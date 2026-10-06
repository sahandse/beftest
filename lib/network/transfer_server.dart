import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class IncomingRequestFile {
  final String id;
  final String fileName;
  final int size;
  final String fileType;

  const IncomingRequestFile({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
  });
}

class IncomingRequest {
  final String senderAlias;
  final String sourceIp;
  final List<IncomingRequestFile> files;

  const IncomingRequest({
    required this.senderAlias,
    required this.sourceIp,
    required this.files,
  });

  int get totalSize => files.fold(0, (sum, file) => sum + file.size);
}

class IncomingFileEvent {
  final String senderAlias;
  final String fileName;
  final int size;
  final bool success;

  const IncomingFileEvent({
    required this.senderAlias,
    required this.fileName,
    required this.size,
    required this.success,
  });
}

class TransferServer {
  HttpServer? _server;
  final Map<String, _Session> _sessions = {};
  String? _pin;

  Future<bool> Function(IncomingRequest request)? onIncomingRequest;
  void Function(IncomingFileEvent event)? onIncomingComplete;

  Future<void> start({
    required String alias,
    required String fingerprint,
    String? pin,
    int port = 53317,
  }) async {
    await stop();
    _pin = (pin ?? '').isEmpty ? null : pin;

    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    _server!.listen((request) async {
      try {
        final path = request.uri.path;
        if (path == '/api/localsend/v2/register' &&
            request.method == 'POST') {
          await _handleRegister(request, alias, fingerprint, port);
        } else if (path == '/api/localsend/v2/prepare-upload' &&
            request.method == 'POST') {
          await _handlePrepare(request);
        } else if (path == '/api/localsend/v2/upload' &&
            request.method == 'POST') {
          await _handleUpload(request);
        } else if (path == '/api/localsend/v2/cancel' &&
            request.method == 'POST') {
          await _handleCancel(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> _handleRegister(
    HttpRequest request,
    String alias,
    String fingerprint,
    int port,
  ) async {
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'alias': alias,
      'version': '2.2',
      'deviceModel': Platform.operatingSystem,
      'deviceType': 'mobile',
      'fingerprint': fingerprint,
      'download': false,
      'port': port,
      'protocol': 'http',
    }));
    await request.response.close();
  }

  Future<void> _handlePrepare(HttpRequest request) async {
    if (_pin != null && request.uri.queryParameters['pin'] != _pin) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final info = (data['info'] as Map?)?.cast<String, dynamic>() ?? {};
    final senderAlias = (info['alias'] ?? 'دستگاه ناشناس').toString();
    final files = (data['files'] as Map?)?.cast<String, dynamic>() ?? {};

    if (files.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final sourceIp = request.connectionInfo?.remoteAddress.address ?? '';
    final requestFiles = <IncomingRequestFile>[];

    for (final entry in files.entries) {
      final meta = (entry.value as Map).cast<String, dynamic>();
      requestFiles.add(
        IncomingRequestFile(
          id: entry.key,
          fileName: (meta['fileName'] ?? entry.key).toString(),
          size: int.tryParse('${meta['size']}') ?? 0,
          fileType: (meta['fileType'] ?? 'application/octet-stream').toString(),
        ),
      );
    }

    final decision = onIncomingRequest == null
        ? true
        : await onIncomingRequest!(
            IncomingRequest(
              senderAlias: senderAlias,
              sourceIp: sourceIp,
              files: requestFiles,
            ),
          );

    if (!decision) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final sessionId = _randomToken(24);
    final tokens = <String, String>{};
    final expected = <String, _ExpectedFile>{};

    for (final entry in files.entries) {
      final meta = (entry.value as Map).cast<String, dynamic>();
      final token = _randomToken(32);
      tokens[entry.key] = token;
      expected[entry.key] = _ExpectedFile(
        id: entry.key,
        token: token,
        fileName: (meta['fileName'] ?? entry.key).toString(),
        size: int.tryParse('${meta['size']}') ?? 0,
        sha256: meta['sha256']?.toString(),
      );
    }

    _sessions[sessionId] = _Session(
      senderAlias: senderAlias,
      sourceIp: sourceIp,
      files: expected,
    );

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'sessionId': sessionId,
      'files': tokens,
    }));
    await request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    final fileId = request.uri.queryParameters['fileId'];
    final token = request.uri.queryParameters['token'];

    if (sessionId == null || fileId == null || token == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final session = _sessions[sessionId];
    final expected = session?.files[fileId];
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';

    if (session == null ||
        expected == null ||
        expected.token != token ||
        session.sourceIp != remoteIp) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final downloads = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeName = expected.fileName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '_');
    final target = File('${downloads.path}/$safeName');
    final temp = File('${target.path}.befrest-part');

    final sink = temp.openWrite();
    final digestSink = AccumulatorSink<Digest>();
    final converter = sha256.startChunkedConversion(digestSink);

    var received = 0;
    await for (final chunk in request) {
      sink.add(chunk);
      converter.add(chunk);
      received += chunk.length;
    }
    await sink.flush();
    await sink.close();
    converter.close();

    final hash = digestSink.events.single.toString();
    var success = true;

    if (expected.size > 0 && received != expected.size) {
      success = false;
    }
    if (expected.sha256 != null &&
        expected.sha256!.isNotEmpty &&
        expected.sha256 != hash) {
      success = false;
    }

    if (!success) {
      if (await temp.exists()) await temp.delete();
      onIncomingComplete?.call(
        IncomingFileEvent(
          senderAlias: session.senderAlias,
          fileName: expected.fileName,
          size: received,
          success: false,
        ),
      );
      request.response.statusCode = 422;
      await request.response.close();
      return;
    }

    if (await target.exists()) {
      final dot = safeName.lastIndexOf('.');
      final stem = dot > 0 ? safeName.substring(0, dot) : safeName;
      final ext = dot > 0 ? safeName.substring(dot) : '';
      await temp.rename(
        '${downloads.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext',
      );
    } else {
      await temp.rename(target.path);
    }

    onIncomingComplete?.call(
      IncomingFileEvent(
        senderAlias: session.senderAlias,
        fileName: expected.fileName,
        size: received,
        success: true,
      ),
    );

    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  Future<void> _handleCancel(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    if (sessionId != null) _sessions.remove(sessionId);
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }

  String _randomToken(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
  }
}

class _Session {
  final String senderAlias;
  final String sourceIp;
  final Map<String, _ExpectedFile> files;

  _Session({
    required this.senderAlias,
    required this.sourceIp,
    required this.files,
  });
}

class _ExpectedFile {
  final String id;
  final String token;
  final String fileName;
  final int size;
  final String? sha256;

  _ExpectedFile({
    required this.id,
    required this.token,
    required this.fileName,
    required this.size,
    required this.sha256,
  });
}
