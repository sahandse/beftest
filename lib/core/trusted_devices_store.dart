import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrustedDevice {
  final String fingerprint;
  final String alias;

  const TrustedDevice({
    required this.fingerprint,
    required this.alias,
  });

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'alias': alias,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        fingerprint: (json['fingerprint'] ?? '').toString(),
        alias: (json['alias'] ?? 'دستگاه مورداعتماد').toString(),
      );
}

class TrustedDevicesStore {
  static const _key = 'trusted_devices_v1';

  Future<List<TrustedDevice>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((item) {
          try {
            return TrustedDevice.fromJson(
              jsonDecode(item) as Map<String, dynamic>,
            );
          } catch (_) {
            return const TrustedDevice(
              fingerprint: '',
              alias: 'دستگاه مورداعتماد',
            );
          }
        })
        .where((device) => device.fingerprint.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> contains(String fingerprint) async {
    final devices = await load();
    return devices.any((device) => device.fingerprint == fingerprint);
  }

  Future<void> trust({
    required String fingerprint,
    required String alias,
  }) async {
    if (fingerprint.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final devices = (await load()).toList();
    devices.removeWhere((device) => device.fingerprint == fingerprint);
    devices.insert(
      0,
      TrustedDevice(
        fingerprint: fingerprint,
        alias: alias.trim().isEmpty ? 'دستگاه مورداعتماد' : alias.trim(),
      ),
    );
    await prefs.setStringList(
      _key,
      devices.map((device) => jsonEncode(device.toJson())).toList(),
    );
  }

  Future<void> revoke(String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = (await load()).toList()
      ..removeWhere((device) => device.fingerprint == fingerprint);
    await prefs.setStringList(
      _key,
      devices.map((device) => jsonEncode(device.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
