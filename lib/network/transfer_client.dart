import 'dart:convert';
import 'dart:io';

import 'nearby_device.dart';
import 'transfer_models.dart';
import '../core/tls_identity.dart';
import '../core/app_inventory_service.dart';

class TransferClient {
  final TlsIdentity identity;

  TransferClient({
    required this.identity,
  });

  HttpClient _clientFor(NearbyDevice device) {
    final client = HttpClient(context: identity.createClientContext())
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 20);
    client.badCertificateCallback = (certificate, host, port) {
      final actual =
          TlsIdentityStore.fingerprintFromCertificate(certificate);
      return actual == device.fingerprint.toUpperCase();
    };
    return client;
  }
  Future<Map<String, dynamic>> prepareUpload({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<TransferFile> files,
    String? pin,
  }) async {
    final client = _clientFor(device);
    try {
      final query = pin == null || pin.isEmpty ? '' : '?pin=${Uri.encodeQueryComponent(pin)}';
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/localsend/v2/prepare-upload$query',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'info': {
          'alias': alias,
          'version': '2.2',
          'deviceModel': Platform.operatingSystem,
          'deviceType': 'mobile',
          'fingerprint': fingerprint,
          'port': 53317,
          'protocol': 'https',
          'download': false,
        },
        'files': {
          for (final file in files)
            file.id: {
              'id': file.id,
              'fileName': file.fileName,
              'size': file.size,
              'fileType': file.mimeType,
              'sha256': file.sha256,
              if (file.relativePath != null)
                'relativePath': file.relativePath,
            },
        },
      }));

      final response = await request.close();
      if (response.statusCode == HttpStatus.noContent) {
        return {'sessionId': '', 'files': <String, String>{}};
      }
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const HttpException('PIN_REQUIRED');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('PREPARE_FAILED_${response.statusCode}');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadFile({
    required NearbyDevice device,
    required String sessionId,
    required TransferFile file,
    required String token,
    required void Function(int sent, int total) onProgress,
    TransferRuntimeControl? control,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/localsend/v2/upload'
        '?sessionId=${Uri.encodeQueryComponent(sessionId)}'
        '&fileId=${Uri.encodeQueryComponent(file.id)}'
        '&token=${Uri.encodeQueryComponent(token)}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.binary;
      request.contentLength = file.size;

      var sent = 0;
      await for (final chunk in file.file.openRead()) {
        if (control != null) {
          await control.waitIfPaused();
          control.throwIfCancelled();
        }
        request.add(chunk);
        sent += chunk.length;
        onProgress(sent, file.size);
      }

      final response = await request.close();
      await response.drain();
      if (response.statusCode == 422) {
        throw const HttpException('CHECKSUM_MISMATCH');
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.noContent) {
        throw HttpException('UPLOAD_FAILED_${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }



  Future<Map<String, dynamic>> addToSession({
    required NearbyDevice device,
    required String sessionId,
    required List<TransferFile> files,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/befrest/v1/session/add'
        '?sessionId=${Uri.encodeQueryComponent(sessionId)}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'files': {
          for (final file in files)
            file.id: {
              'id': file.id,
              'fileName': file.fileName,
              'size': file.size,
              'fileType': file.mimeType,
              'sha256': file.sha256,
              if (file.relativePath != null)
                'relativePath': file.relativePath,
            },
        },
      }));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.forbidden) {
        throw const HttpException('SESSION_EXPIRED');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('SESSION_ADD_${response.statusCode}');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> queryResumeOffset({
    required NearbyDevice device,
    required String sessionId,
    required String fileId,
    required String token,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/befrest/v1/resume/status'
        '?sessionId=${Uri.encodeQueryComponent(sessionId)}'
        '&fileId=${Uri.encodeQueryComponent(fileId)}'
        '&token=${Uri.encodeQueryComponent(token)}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.notFound) return 0;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('RESUME_STATUS_${response.statusCode}');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      return int.tryParse('${data['offset'] ?? 0}') ?? 0;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadFileResumable({
    required NearbyDevice device,
    required String sessionId,
    required TransferFile file,
    required String token,
    required void Function(int sent, int total) onProgress,
    TransferRuntimeControl? control,
    int maxAttempts = 5,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (control != null) {
        await control.waitIfPaused();
        control.throwIfCancelled();
      }
      final client = _clientFor(device);
      try {
        final offset = await queryResumeOffset(
          device: device,
          sessionId: sessionId,
          fileId: file.id,
          token: token,
        );

        if (offset >= file.size) {
          onProgress(file.size, file.size);
          return;
        }

        final uri = Uri.parse(
          'https://${device.ip}:${device.port}/api/befrest/v1/resume/upload'
          '?sessionId=${Uri.encodeQueryComponent(sessionId)}'
          '&fileId=${Uri.encodeQueryComponent(file.id)}'
          '&token=${Uri.encodeQueryComponent(token)}'
          '&offset=$offset',
        );

        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.binary;
        request.contentLength = file.size - offset;

        var sent = offset;
        await for (final chunk in file.file.openRead(offset)) {
          if (control != null) {
            await control.waitIfPaused();
            control.throwIfCancelled();
          }
          request.add(chunk);
          sent += chunk.length;
          onProgress(sent, file.size);
        }

        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();

        if (response.statusCode == HttpStatus.noContent) {
          onProgress(file.size, file.size);
          return;
        }

        if (response.statusCode == HttpStatus.permanentRedirect) {
          final data = body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(body) as Map<String, dynamic>;
          final serverOffset = int.tryParse('${data['offset'] ?? sent}') ?? sent;
          onProgress(serverOffset, file.size);
          continue;
        }

        if (response.statusCode == HttpStatus.conflict) {
          continue;
        }

        if (response.statusCode == 422) {
          throw const HttpException('CHECKSUM_MISMATCH');
        }

        throw HttpException('RESUME_UPLOAD_${response.statusCode}');
      } catch (error) {
        lastError = error;
        if (attempt + 1 >= maxAttempts) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 600 * (attempt + 1)),
        );
      } finally {
        client.close(force: true);
      }
    }

    throw HttpException('RESUME_FAILED: $lastError');
  }


  Future<List<PeerAppUpdate>> compareAppUpdates({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<InstalledAppVersion> localApps,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/befrest/v1/apps/compare',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'info': {
          'alias': alias,
          'fingerprint': fingerprint,
        },
        'apps': [
          for (final app in localApps) app.toJson(),
        ],
      }));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APP_COMPARE_${response.statusCode}');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final updates = (data['updates'] as List?) ?? const [];
      return updates
          .whereType<Map>()
          .map(
            (item) => PeerAppUpdate.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .where((item) => item.packageName.isNotEmpty)
          .toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, String>> prepareAppUpdates({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<PeerAppUpdate> updates,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/befrest/v1/apps/prepare',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'info': {
          'alias': alias,
          'fingerprint': fingerprint,
        },
        'packages': updates.map((item) => item.packageName).toList(),
      }));

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode == HttpStatus.forbidden) {
        throw const HttpException('APP_UPDATE_REJECTED');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APP_PREPARE_${response.statusCode}');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      return ((data['tokens'] as Map?) ?? const {})
          .map(
            (key, value) => MapEntry(
              key.toString(),
              value.toString(),
            ),
          );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAppUpdate({
    required NearbyDevice device,
    required String packageName,
    required String token,
    required File target,
    required void Function(int received, int? total) onProgress,
  }) async {
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/befrest/v1/apps/download'
        '?package=${Uri.encodeQueryComponent(packageName)}'
        '&token=${Uri.encodeQueryComponent(token)}',
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain();
        throw HttpException('APP_DOWNLOAD_${response.statusCode}');
      }

      await target.parent.create(recursive: true);
      final sink = target.openWrite();
      var received = 0;
      final total = response.contentLength >= 0
          ? response.contentLength
          : null;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> cancel({
    required NearbyDevice device,
    required String sessionId,
  }) async {
    if (sessionId.isEmpty) return;
    final client = _clientFor(device);
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/localsend/v2/cancel'
        '?sessionId=${Uri.encodeQueryComponent(sessionId)}',
      );
      final request = await client.postUrl(uri);
      final response = await request.close();
      await response.drain();
    } finally {
      client.close(force: true);
    }
  }
}
