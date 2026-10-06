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
  final String senderFingerprint;
  final String sourceIp;
  final List<IncomingRequestFile> files;

  const IncomingRequest({
    required this.senderAlias,
    required this.senderFingerprint,
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
        } else if (path == '/api/befrest/v1/resume/status' &&
            request.method == 'GET') {
          await _handleResumeStatus(request);
        } else if (path == '/api/befrest/v1/resume/upload' &&
            request.method == 'POST') {
          await _handleResumeUpload(request);
        } else if (path == '/api/befrest/v1/session/add' &&
            request.method == 'POST') {
          await _handleSessionAdd(request);
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
    final senderFingerprint = (info['fingerprint'] ?? '').toString();
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
              senderFingerprint: senderFingerprint,
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
        relativePath: meta['relativePath']?.toString(),
      );
    }

    _sessions[sessionId] = _Session(
      senderAlias: senderAlias,
      sourceIp: sourceIp,
      files: expected,
      touchedAt: DateTime.now(),
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
    final target = await _finalTarget(expected);
    final temp = File('${target.path}.befrest-part');
    await temp.parent.create(recursive: true);

    final sink = temp.openWrite();
    var received = 0;
    await for (final chunk in request) {
      sink.add(chunk);
      received += chunk.length;
    }
    await sink.flush();
    await sink.close();

    final hash = (await sha256.bind(temp.openRead()).first).toString();
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

    session.files.remove(fileId);
    session.touchedAt = DateTime.now();

    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }


  Future<File> _resumeTempFile(
    String sessionId,
    _ExpectedFile expected,
  ) async {
    final downloads = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeId = expected.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${downloads.path}/.befrest-$sessionId-$safeId.part');
  }


  String? _safeRelativePath(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.contains(':')) return null;

    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.any((part) => part == '.' || part == '..')) {
      return null;
    }

    return parts
        .map(
          (part) => part
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
              .replaceAll('..', '_'),
        )
        .join(Platform.pathSeparator);
  }

  Future<File> _finalTarget(_ExpectedFile expected) async {
    final downloads = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final safeName = expected.fileName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '_');
    final relative = _safeRelativePath(expected.relativePath);
    final base = relative == null
        ? File('${downloads.path}/$safeName')
        : File('${downloads.path}/$relative');
    await base.parent.create(recursive: true);
    if (!await base.exists()) return base;

    final dot = safeName.lastIndexOf('.');
    final stem = dot > 0 ? safeName.substring(0, dot) : safeName;
    final ext = dot > 0 ? safeName.substring(dot) : '';
    return File(
      '${downloads.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext',
    );
  }

  bool _authorizedResume(
    HttpRequest request,
    _Session? session,
    _ExpectedFile? expected,
    String? token,
  ) {
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    return session != null &&
        expected != null &&
        token != null &&
        expected.token == token &&
        session.sourceIp == remoteIp;
  }

  Future<void> _handleResumeStatus(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    final fileId = request.uri.queryParameters['fileId'];
    final token = request.uri.queryParameters['token'];

    if (sessionId == null || fileId == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final session = _sessions[sessionId];
    final expected = session?.files[fileId];
    if (!_authorizedResume(request, session, expected, token)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final temp = await _resumeTempFile(sessionId, expected!);
    final offset = await temp.exists() ? await temp.length() : 0;

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'offset': offset}));
    await request.response.close();
  }

  Future<void> _handleResumeUpload(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    final fileId = request.uri.queryParameters['fileId'];
    final token = request.uri.queryParameters['token'];
    final requestedOffset =
        int.tryParse(request.uri.queryParameters['offset'] ?? '');

    if (sessionId == null || fileId == null || requestedOffset == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final session = _sessions[sessionId];
    final expected = session?.files[fileId];
    if (!_authorizedResume(request, session, expected, token)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    final temp = await _resumeTempFile(sessionId, expected!);
    final actualOffset = await temp.exists() ? await temp.length() : 0;

    if (requestedOffset != actualOffset) {
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'offset': actualOffset}));
      await request.response.close();
      return;
    }

    final sink = temp.openWrite(
      mode: requestedOffset == 0 ? FileMode.write : FileMode.append,
    );

    try {
      await for (final chunk in request) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final received = await temp.length();

    if (received < expected.size) {
      request.response.statusCode = HttpStatus.permanentRedirect;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'offset': received}));
      await request.response.close();
      return;
    }

    if (received > expected.size) {
      await temp.delete();
      request.response.statusCode = 422;
      await request.response.close();
      return;
    }

    final hash = (await sha256.bind(temp.openRead()).first).toString();
    if (expected.sha256 != null &&
        expected.sha256!.isNotEmpty &&
        expected.sha256 != hash) {
      await temp.delete();
      onIncomingComplete?.call(
        IncomingFileEvent(
          senderAlias: session!.senderAlias,
          fileName: expected.fileName,
          size: received,
          success: false,
        ),
      );
      request.response.statusCode = 422;
      await request.response.close();
      return;
    }

    final target = await _finalTarget(expected);
    await temp.rename(target.path);

    session!.files.remove(fileId);
    onIncomingComplete?.call(
      IncomingFileEvent(
        senderAlias: session.senderAlias,
        fileName: expected.fileName,
        size: received,
        success: true,
      ),
    );

    session.touchedAt = DateTime.now();

    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }


  Future<void> _handleSessionAdd(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['sessionId'];
    if (sessionId == null || sessionId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final session = _sessions[sessionId];
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';
    if (session == null ||
        session.sourceIp != remoteIp ||
        DateTime.now().difference(session.touchedAt) >
            const Duration(minutes: 10)) {
      _sessions.remove(sessionId);
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final body = await utf8.decoder.bind(request).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final files = (data['files'] as Map?)?.cast<String, dynamic>() ?? {};
    if (files.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final tokens = <String, String>{};
    for (final entry in files.entries) {
      final meta = (entry.value as Map).cast<String, dynamic>();
      final token = _randomToken(32);
      tokens[entry.key] = token;
      session.files[entry.key] = _ExpectedFile(
        id: entry.key,
        token: token,
        fileName: (meta['fileName'] ?? entry.key).toString(),
        size: int.tryParse('${meta['size']}') ?? 0,
        sha256: meta['sha256']?.toString(),
        relativePath: meta['relativePath']?.toString(),
      );
    }

    session.touchedAt = DateTime.now();
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'sessionId': sessionId,
      'files': tokens,
    }));
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
  DateTime touchedAt;

  _Session({
    required this.senderAlias,
    required this.sourceIp,
    required this.files,
    required this.touchedAt,
  });
}

class _ExpectedFile {
  final String id;
  final String token;
  final String fileName;
  final int size;
  final String? sha256;
  final String? relativePath;

  _ExpectedFile({
    required this.id,
    required this.token,
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.relativePath,
  });
}
