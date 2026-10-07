import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import 'nearby_device.dart';
import 'transfer_client.dart';
import 'transfer_models.dart';
import '../core/tls_identity.dart';
import '../core/app_inventory_service.dart';

class TransferService {
  final TransferClient _client;

  TransferService({
    required TlsIdentity identity,
  }) : _client = TransferClient(identity: identity);
  final _uuid = const Uuid();
  final AppInventoryService _appInventory = AppInventoryService();
  final Map<String, _ReusableSession> _sessions = {};

  Future<List<TransferFile>> buildFiles(
    List<String> paths, {
    Map<String, String> relativePaths = const {},
  }) async {
    final result = <TransferFile>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final stat = await file.stat();
      final hash = await sha256.bind(file.openRead()).first;
      result.add(
        TransferFile(
          id: _uuid.v4(),
          file: file,
          fileName: path.split(Platform.pathSeparator).last,
          size: stat.size,
          mimeType: lookupMimeType(path) ?? 'application/octet-stream',
          sha256: hash.toString(),
          relativePath: relativePaths[path],
        ),
      );
    }
    return result;
  }


  Future<List<PeerAppUpdate>> checkAppUpdates({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
  }) async {
    final apps = await _appInventory.loadInstalledVersions();
    return _client.compareAppUpdates(
      device: device,
      alias: alias,
      fingerprint: fingerprint,
      localApps: apps,
    );
  }

  Future<List<File>> receiveAppUpdates({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<PeerAppUpdate> updates,
    void Function(
      PeerAppUpdate update,
      int received,
      int? total,
    )? onProgress,
  }) async {
    if (updates.isEmpty) return const [];

    final tokens = await _client.prepareAppUpdates(
      device: device,
      alias: alias,
      fingerprint: fingerprint,
      updates: updates,
    );

    final downloads = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final appDir = Directory(
      '${downloads.path}${Platform.pathSeparator}Befrest Apps',
    );
    await appDir.create(recursive: true);

    final receivedFiles = <File>[];
    for (final update in updates) {
      final token = tokens[update.packageName];
      if (token == null || token.isEmpty) continue;

      final safeName = update.name
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll('..', '_')
          .trim();
      final safeVersion = update.remoteVersion
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final target = File(
        '${appDir.path}${Platform.pathSeparator}'
        '${safeName.isEmpty ? update.packageName : safeName}'
        '${safeVersion.isEmpty ? '' : '-$safeVersion'}.apk',
      );

      await _client.downloadAppUpdate(
        device: device,
        packageName: update.packageName,
        token: token,
        target: target,
        onProgress: (received, total) {
          onProgress?.call(update, received, total);
        },
      );
      receivedFiles.add(target);
    }

    return receivedFiles;
  }

  Future<void> send({
    required NearbyDevice device,
    required String alias,
    required String fingerprint,
    required List<TransferFile> files,
    String? pin,
    required void Function(String fileId, int sent, int total) onProgress,
    void Function(String fileId, TransferStatus status)? onStatus,
    TransferRuntimeControl? control,
  }) async {
    Map<String, dynamic> prepared;
    final reusable = _sessions[device.fingerprint];
    final canReuse = device.supportsResume &&
        reusable != null &&
        DateTime.now().difference(reusable.updatedAt) <
            const Duration(minutes: 9);

    if (canReuse) {
      try {
        prepared = await _client.addToSession(
          device: device,
          sessionId: reusable.sessionId,
          files: files,
        );
      } catch (_) {
        _sessions.remove(device.fingerprint);
        prepared = await _client.prepareUpload(
          device: device,
          alias: alias,
          fingerprint: fingerprint,
          files: files,
          pin: pin,
        );
      }
    } else {
      prepared = await _client.prepareUpload(
        device: device,
        alias: alias,
        fingerprint: fingerprint,
        files: files,
        pin: pin,
      );
    }

    final sessionId = prepared['sessionId']?.toString() ?? '';
    final tokens =
        (prepared['files'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    if (sessionId.isEmpty) return;

    if (device.supportsResume) {
      _sessions[device.fingerprint] = _ReusableSession(
        sessionId: sessionId,
        updatedAt: DateTime.now(),
      );
    }

    try {
      Object? firstError;

      for (final file in files) {
        final token = tokens[file.id]?.toString();
        if (token == null || token.isEmpty) {
          onStatus?.call(file.id, TransferStatus.failed);
          firstError ??= StateError('Missing upload token for ${file.id}');
          continue;
        }

        onStatus?.call(file.id, TransferStatus.transferring);

        try {
          if (device.supportsResume) {
            await _client.uploadFileResumable(
              device: device,
              sessionId: sessionId,
              file: file,
              token: token,
              onProgress: (sent, total) => onProgress(file.id, sent, total),
              control: control,
            );
          } else {
            await _client.uploadFile(
              device: device,
              sessionId: sessionId,
              file: file,
              token: token,
              onProgress: (sent, total) => onProgress(file.id, sent, total),
              control: control,
            );
          }
          onStatus?.call(file.id, TransferStatus.completed);
        } catch (error) {
          firstError ??= error;
          onStatus?.call(file.id, TransferStatus.failed);
        }
      }

      if (device.supportsResume && _sessions.containsKey(device.fingerprint)) {
        _sessions[device.fingerprint] = _ReusableSession(
          sessionId: sessionId,
          updatedAt: DateTime.now(),
        );
      }

      if (firstError != null) {
        throw firstError;
      }
    } catch (error) {
      if (control?.isCancelled == true) {
        _sessions.remove(device.fingerprint);
        await _client.cancel(device: device, sessionId: sessionId);
      }
      rethrow;
    }
  }
}


class _ReusableSession {
  final String sessionId;
  final DateTime updatedAt;

  const _ReusableSession({
    required this.sessionId,
    required this.updatedAt,
  });
}
