import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_settings.dart';

class ReceivePage extends StatelessWidget {
  final AppSettings settings;

  const ReceivePage({
    super.key,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qrPayload = jsonEncode({
      'app': 'befrest',
      'alias': settings.alias,
      'fingerprint': settings.fingerprint,
      'port': 53317,
      'protocol': 'http',
      'version': '2.2',
    });

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
                color: cs.primaryContainer,
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
                    child: const Icon(
                      Icons.south_west_rounded,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'آماده دریافت',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    settings.alias,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'دستگاه فرستنده باید روی همین شبکه محلی باشد.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
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
                      child: QrImageView(
                        data: qrPayload,
                        size: 210,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'QR شامل اطلاعات اتصال محلی همین دستگاه است.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _StatusTile(
              icon: Icons.wifi_rounded,
              title: 'شبکه محلی',
              subtitle: 'بدون نیاز به اینترنت',
            ),
            const SizedBox(height: 10),
            _StatusTile(
              icon: settings.pinEnabled
                  ? Icons.lock_outline_rounded
                  : Icons.lock_open_rounded,
              title: settings.pinEnabled ? 'PIN فعال' : 'PIN غیرفعال',
              subtitle: settings.pinEnabled
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
