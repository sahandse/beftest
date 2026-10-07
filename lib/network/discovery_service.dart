import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'nearby_device.dart';
import '../core/tls_identity.dart';

class DiscoveryService {
  static const String multicastAddress = '224.0.0.167';
  static const int port = 53317;

  static const MethodChannel _networkChannel =
      MethodChannel('ir.befrest/network');

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  final _devices = <String, NearbyDevice>{};
  final _lastSeen = <String, DateTime>{};
  final _controller = StreamController<List<NearbyDevice>>.broadcast();

  Stream<List<NearbyDevice>> get devicesStream => _controller.stream;

  Future<void> start({
    required String alias,
    required String fingerprint,
    required TlsIdentity identity,
  }) async {
    if (_socket != null) {
      _announce(alias: alias, fingerprint: fingerprint);
      return;
    }

    await _networkChannel.invokeMethod<bool>('acquireMulticastLock');

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: false,
    );

    _socket!.broadcastEnabled = true;
    _socket!.joinMulticast(InternetAddress(multicastAddress));
    _socket!.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;

      try {
        final data = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
        final remoteFingerprint = (data['fingerprint'] ?? '').toString();
        if (remoteFingerprint.isEmpty || remoteFingerprint == fingerprint) return;

        final remote = NearbyDevice(
          alias: (data['alias'] ?? 'دستگاه ناشناس').toString(),
          ip: datagram.address.address,
          port: int.tryParse('${data['port'] ?? port}') ?? port,
          type: _parseType((data['deviceType'] ?? '').toString()),
          fingerprint: remoteFingerprint,
          supportsResume: ((data['features'] as List?) ?? const [])
              .map((e) => e.toString())
              .contains('resume-v1'),
          supportsAppUpdates: ((data['features'] as List?) ?? const [])
              .map((e) => e.toString())
              .contains('app-updates-v1'),
        );
        _devices[remoteFingerprint] = remote;
        _lastSeen[remoteFingerprint] = DateTime.now();
        _publishDevices();

        if (data['announce'] == true) {
          await _registerTo(remote, alias, fingerprint, identity);
          _sendMulticastResponse(alias: alias, fingerprint: fingerprint);
        }
      } catch (_) {}
    });

    _announce(alias: alias, fingerprint: fingerprint);
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        _announce(alias: alias, fingerprint: fingerprint);
        _pruneStale();
      },
    );
  }

  void _announce({
    required String alias,
    required String fingerprint,
  }) {
    _sendPacket(alias: alias, fingerprint: fingerprint, announce: true);
  }

  void _sendMulticastResponse({
    required String alias,
    required String fingerprint,
  }) {
    _sendPacket(alias: alias, fingerprint: fingerprint, announce: false);
  }

  void _sendPacket({
    required String alias,
    required String fingerprint,
    required bool announce,
  }) {
    final payload = utf8.encode(jsonEncode({
      'alias': alias,
      'version': '2.2',
      'deviceModel': Platform.operatingSystem,
      'deviceType': 'mobile',
      'fingerprint': fingerprint,
      'port': port,
      'protocol': 'https',
      'download': false,
      'announce': announce,
      'app': 'befrest',
      'features': const ['resume-v1', 'queue-v1', 'app-updates-v1'],
    }));
    try {
      _socket?.send(payload, InternetAddress(multicastAddress), port);
    } catch (_) {}

    try {
      _socket?.send(payload, InternetAddress('255.255.255.255'), port);
    } catch (_) {}
  }

  Future<void> _registerTo(
    NearbyDevice device,
    String alias,
    String fingerprint,
    TlsIdentity identity,
  ) async {
    final client = HttpClient(context: identity.createClientContext());
    client.badCertificateCallback = (certificate, host, port) {
      final actual =
          TlsIdentityStore.fingerprintFromCertificate(certificate);
      return actual == device.fingerprint.toUpperCase();
    };
    try {
      final uri = Uri.parse(
        'https://${device.ip}:${device.port}/api/localsend/v2/register',
      );
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 2));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'alias': alias,
        'version': '2.2',
        'deviceModel': Platform.operatingSystem,
        'deviceType': 'mobile',
        'fingerprint': fingerprint,
        'port': port,
        'protocol': 'https',
        'download': false,
        'app': 'befrest',
        'features': const ['resume-v1', 'queue-v1', 'app-updates-v1'],
      }));
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  void _publishDevices() {
    _controller.add(
      _devices.values.toList(growable: false)
        ..sort((a, b) => a.alias.compareTo(b.alias)),
    );
  }

  void _pruneStale() {
    final now = DateTime.now();
    final stale = _lastSeen.entries
        .where(
          (entry) =>
              now.difference(entry.value) > const Duration(seconds: 8),
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    if (stale.isEmpty) return;

    for (final fingerprint in stale) {
      _lastSeen.remove(fingerprint);
      _devices.remove(fingerprint);
    }
    _publishDevices();
  }

  DeviceType _parseType(String value) {
    switch (value) {
      case 'desktop':
        return DeviceType.desktop;
      case 'tablet':
        return DeviceType.tablet;
      case 'mobile':
        return DeviceType.mobile;
      default:
        return DeviceType.unknown;
    }
  }

  Future<void> dispose() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    _lastSeen.clear();
    try {
      await _networkChannel.invokeMethod<bool>('releaseMulticastLock');
    } catch (_) {}
    await _controller.close();
  }
}
