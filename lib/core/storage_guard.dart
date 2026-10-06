import 'dart:math' as math;

import 'package:disk_space_2/disk_space_2.dart';

class StorageGuard {
  static Future<StorageCheck> checkForIncoming(int incomingBytes) async {
    try {
      final freeMb = await DiskSpace.getFreeDiskSpace;
      if (freeMb == null) {
        return const StorageCheck.unknown();
      }

      final freeBytes = (freeMb * 1024 * 1024).floor();
      final reserve = math.max(
        100 * 1024 * 1024,
        (incomingBytes * 0.10).ceil(),
      );
      final required = incomingBytes + reserve;

      return StorageCheck(
        known: true,
        enough: freeBytes >= required,
        freeBytes: freeBytes,
        requiredBytes: required,
      );
    } catch (_) {
      return const StorageCheck.unknown();
    }
  }
}

class StorageCheck {
  final bool known;
  final bool enough;
  final int freeBytes;
  final int requiredBytes;

  const StorageCheck({
    required this.known,
    required this.enough,
    required this.freeBytes,
    required this.requiredBytes,
  });

  const StorageCheck.unknown()
      : known = false,
        enough = true,
        freeBytes = 0,
        requiredBytes = 0;
}
