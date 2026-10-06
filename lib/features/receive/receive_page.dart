import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_settings.dart';

Future<String?> _localIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      final ip = address.address;
      if (ip.startsWith('169.254.')) continue;
      return ip;
    }
  }
  return null;
}

class ReceivePage extends StatefulWidget {
  final AppSettings settings;

  const ReceivePage({
    super.key,
    required this.settings,
  });

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  late Future<String> _qrPayload;

  @override
  void initState() {
    super.initState();
    _refreshQr();
  }

  void _refreshQr() {
    _qrPayload = Future<String>(() async {
      final ip = await _localIpv4();
      return jsonEncode({
        'app': 'befrest',
        'alias': widget.settings.alias,
        'fingerprint': widget.settings.fingerprint,
        'ip': ip ?? '',
        'port': 53317,
        'protocol': 'https',
        'version': '2.2',
        'features': const ['resume-v1', 'queue-v1'],
      });
    });
  }

  Future<void> _toggleQuickReceive() async {
    if (widget.settings.isQuickReceiveActive) {
      await widget.settings.disableQuickReceive();
    } else {
      await widget.settings.enableQuickReceive();
    }
    if (!mounted) return;
    setState(() {});
  }

  String _quickReceiveSubtitle() {
    final until = widget.settings.quickReceiveUntil;
    if (!widget.settings.isQuickReceiveActive || until == null) {
      return 'برای ۵ دقیقه درخواست‌های شبکه محلی را سریع بپذیر.';
    }

    final remaining = until.difference(DateTime.now());
    final minutes = remaining.inMinutes.clamp(0, 5);
    final seconds = remaining.inSeconds.remainder(60);
    return 'فعال • حدود $minutes:${seconds.toString().padLeft(2, '0')} باقی مانده';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quick = widget.settings.isQuickReceiveActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دریافت'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: quick
                    ? cs.secondaryContainer
                    : cs.primaryContainer,
              ),
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surface,
                    ),
                    child: Icon(
                      quick
                          ? Icons.bolt_rounded
                          : Icons.south_west_rounded,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    quick ? 'دریافت سریع فعال' : 'آماده دریافت',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.settings.alias,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    quick
                        ? 'درخواست‌های شبکه محلی تا پایان زمان سریع پذیرفته می‌شوند.'
                        : 'دستگاه فرستنده باید روی همین شبکه محلی باشد.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _toggleQuickReceive,
              icon: Icon(
                quick ? Icons.flash_off_rounded : Icons.bolt_rounded,
              ),
              label: Text(
                quick ? 'خاموش‌کردن دریافت سریع' : 'دریافت سریع برای ۵ دقیقه',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _quickReceiveSubtitle(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: cs.surfaceContainerLow,
              ),
              child: Column(
                children: [
                  const Text(
                    'اتصال با QR',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: FutureBuilder<String>(
                        future: _qrPayload,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const SizedBox(
                              width: 210,
                              height: 210,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return QrImageView(
                            data: snapshot.data!,
                            size: 210,
                            backgroundColor: Colors.white,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'در دستگاه فرستنده روی «اسکن QR» بزن.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _StatusTile(
              icon: Icons.wifi_rounded,
              title: 'شبکه محلی',
              subtitle: 'انتقال بدون نیاز به اینترنت',
            ),
            const SizedBox(height: 10),
            _StatusTile(
              icon: widget.settings.pinEnabled
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              title: widget.settings.pinEnabled ? 'PIN فعال' : 'PIN غیرفعال',
              subtitle: widget.settings.pinEnabled
                  ? 'ارسال‌کننده باید PIN را وارد کند.'
                  : 'می‌توانی از تنظیمات PIN را فعال کنی.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
