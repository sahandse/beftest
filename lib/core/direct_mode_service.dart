import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DirectPeer {
  final String name;
  final String deviceAddress;
  final int status;

  const DirectPeer({
    required this.name,
    required this.deviceAddress,
    required this.status,
  });

  factory DirectPeer.fromMap(Map<dynamic, dynamic> map) {
    return DirectPeer(
      name: (map['name'] ?? 'Android').toString(),
      deviceAddress: (map['deviceAddress'] ?? '').toString(),
      status: int.tryParse('${map['status'] ?? 0}') ?? 0,
    );
  }
}

class DirectConnectionInfo {
  final bool groupFormed;
  final bool isGroupOwner;
  final String groupOwnerAddress;

  const DirectConnectionInfo({
    required this.groupFormed,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });

  factory DirectConnectionInfo.fromMap(Map<dynamic, dynamic> map) {
    return DirectConnectionInfo(
      groupFormed: map['groupFormed'] == true,
      isGroupOwner: map['isGroupOwner'] == true,
      groupOwnerAddress: (map['groupOwnerAddress'] ?? '').toString(),
    );
  }
}

class DirectModeService {
  static const MethodChannel _channel =
      MethodChannel('ir.befrest/direct_mode');

  Future<bool> requestPermission() async {
    final sdk = await _channel.invokeMethod<int>('sdkInt') ?? 0;
    if (sdk >= 33) {
      final status = await Permission.nearbyWifiDevices.request();
      return status.isGranted;
    }

    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  Future<List<DirectPeer>> discoverPeers() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('discoverPeers') ??
        const <dynamic>[];
    return raw
        .whereType<Map>()
        .map(DirectPeer.fromMap)
        .where((peer) => peer.deviceAddress.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> createGroup() async {
    await _channel.invokeMethod<bool>('createGroup');
  }

  Future<void> connect(DirectPeer peer) async {
    await _channel.invokeMethod<bool>(
      'connectPeer',
      {'deviceAddress': peer.deviceAddress},
    );
  }

  Future<DirectConnectionInfo> connectionInfo() async {
    final raw =
        await _channel.invokeMethod<Map<dynamic, dynamic>>('connectionInfo') ??
            const <dynamic, dynamic>{};
    return DirectConnectionInfo.fromMap(raw);
  }

  Future<DirectConnectionInfo?> waitForConnection({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final info = await connectionInfo();
      if (info.groupFormed) return info;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  Future<void> removeGroup() async {
    try {
      await _channel.invokeMethod<bool>('removeGroup');
    } catch (_) {}
  }
}
