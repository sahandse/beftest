import 'dart:convert';
import 'dart:io';

import 'nearby_device.dart';
import 'transfer_models.dart';

class TransferClient {
  Future<Map<String, dynamic>> prepareUpload({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<TransferFile> files,
    String? pin,
  }) async {
    final client = HttpClient();
    try {
      final query = pin == null || pin.isEmpty ? '' : '?pin=${Uri.encodeQueryComponent(pin)}';
      final uri = Uri.parse(
        'http://${device.ip}:${device.port}/api/localsend/v2/prepare-upload$query',
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
          'protocol': 'http',
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
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'http://${device.ip}:${device.port}/api/localsend/v2/upload'
        '?sessionId=${Uri.encodeQueryComponent(sessionId)}'
        '&fileId=${Uri.encodeQueryComponent(file.id)}'
        '&token=${Uri.encodeQueryComponent(token)}',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.binary;
      request.contentLength = file.size;

      var sent = 0;
      await for (final chunk in file.file.openRead()) {
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

  Future<void> cancel({
    required NearbyDevice device,
    required String sessionId,
  }) async {
    if (sessionId.isEmpty) return;
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'http://${device.ip}:${device.port}/api/localsend/v2/cancel'
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
