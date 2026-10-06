import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'nearby_device.dart';

class DiscoveryService {
  static const String multicastAddress = '224.0.0.167';
  static const int port = 53317;

  RawDatagramSocket? _socket;
  final _devices = <String, NearbyDevice>{};
  final _controller = StreamController<List<NearbyDevice>>.broadcast();

  Stream<List<NearbyDevice>> get devicesStream => _controller.stream;

  Future<void> start({
    required String alias,
    required String fingerprint,
  }) async {
    if (_socket != null) {
      _announce(alias: alias, fingerprint: fingerprint);
      return;
    }

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: false,
    );

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
        );
        _devices[remoteFingerprint] = remote;
        _controller.add(_devices.values.toList(growable: false));

        if (data['announce'] == true) {
          await _registerTo(remote, alias, fingerprint);
          _sendMulticastResponse(alias: alias, fingerprint: fingerprint);
        }
      } catch (_) {}
    });

    _announce(alias: alias, fingerprint: fingerprint);
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
      'protocol': 'http',
      'download': false,
      'announce': announce,
    }));
    _socket?.send(payload, InternetAddress(multicastAddress), port);
  }

  Future<void> _registerTo(
    NearbyDevice device,
    String alias,
    String fingerprint,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'http://${device.ip}:${device.port}/api/localsend/v2/register',
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
        'protocol': 'http',
        'download': false,
      }));
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
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
    _socket?.close();
    _socket = null;
    await _controller.close();
  }
}
