enum DeviceType { mobile, desktop, tablet, unknown }

class NearbyDevice {
  final String alias;
  final String ip;
  final int port;
  final DeviceType type;
  final String fingerprint;

  const NearbyDevice({
    required this.alias,
    required this.ip,
    required this.port,
    required this.type,
    required this.fingerprint,
  });
}
