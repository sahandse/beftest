import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_settings.dart';
import '../direct/direct_mode_page.dart';

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
  final Future<void> Function()? onNetworkRestart;

  const ReceivePage({
    super.key,
    required this.settings,
    this.onNetworkRestart,
  });

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage>
    with SingleTickerProviderStateMixin {
  late Future<String> _qrPayload;
  late final AnimationController _radarController;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    _refreshQr();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
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
        'features': const ['resume-v1', 'queue-v1', 'app-updates-v1'],
      });
    });
  }

  Future<void> _toggleQuickReceive() async {
    HapticFeedback.selectionClick();
    if (widget.settings.isQuickReceiveActive) {
      await widget.settings.disableQuickReceive();
    } else {
      await widget.settings.enableQuickReceive();
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openDirectMode() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: DirectModePage(
            role: DirectModeRole.receiver,
            onConnected: widget.onNetworkRestart,
          ),
        ),
      ),
    );
    if (mounted) {
      _refreshQr();
      setState(() {});
    }
  }

  void _toggleQr() {
    HapticFeedback.lightImpact();
    setState(() => _showQr = !_showQr);
  }

  String _quickReceiveSubtitle() {
    final until = widget.settings.quickReceiveUntil;
    if (!widget.settings.isQuickReceiveActive || until == null) {
      return 'درخواست‌های شبکه محلی را برای ۵ دقیقه سریع بپذیر';
    }

    final remaining = until.difference(DateTime.now());
    final minutes = remaining.inMinutes.clamp(0, 5);
    final seconds = remaining.inSeconds.remainder(60);
    return 'فعال • حدود $minutes:${seconds.toString().padLeft(2, '0')} باقی مانده';
  }

  @override
  Widget build(BuildContext context) {
    final quick = widget.settings.isQuickReceiveActive;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final radar = _ReceiveRadar(
      animation: _radarController,
      active: quick,
      alias: widget.settings.alias,
    );

    final controls = Column(
      children: [
        _QuickReceiveCard(
          active: quick,
          subtitle: _quickReceiveSubtitle(),
          onTap: _toggleQuickReceive,
        ),
        const SizedBox(height: 12),
        _ConnectionCard(
          showQr: _showQr,
          qrPayload: _qrPayload,
          onToggleQr: _toggleQr,
          onDirectMode: _openDirectMode,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: _InfoPill(
                icon: Icons.wifi_rounded,
                title: 'شبکه محلی',
                subtitle: 'بدون اینترنت',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoPill(
                icon: widget.settings.pinEnabled
                    ? Icons.lock_outline_rounded
                    : Icons.lock_open_rounded,
                title: widget.settings.pinEnabled ? 'PIN فعال' : 'PIN غیرفعال',
                subtitle: widget.settings.pinEnabled
                    ? 'محافظت روشن'
                    : 'دریافت ساده',
              ),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('دریافت'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: radar,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: ListView(
                        children: [controls],
                      ),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    SizedBox(height: 370, child: radar),
                    const SizedBox(height: 14),
                    controls,
                  ],
                ),
        ),
      ),
    );
  }
}

class _ReceiveRadar extends StatelessWidget {
  final Animation<double> animation;
  final bool active;
  final String alias;

  const _ReceiveRadar({
    required this.animation,
    required this.active,
    required this.alias,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onSecondaryContainer : cs.onPrimaryContainer;
    final bg = active ? cs.secondaryContainer : cs.primaryContainer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(44),
          topLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
          bottomLeft: Radius.circular(44),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (index) {
                  final phase = (animation.value + index / 3) % 1;
                  final size = 92 + (phase * 190);
                  return Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: fg.withValues(
                          alpha: (1 - phase) * .18,
                        ),
                        width: 2,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: .10),
            ),
            child: Icon(
              active ? Icons.bolt_rounded : Icons.south_west_rounded,
              size: 50,
              color: fg,
            ),
          ),
          Positioned(
            left: 26,
            right: 26,
            bottom: 28,
            child: Column(
              children: [
                Text(
                  active ? 'دریافت سریع روشن است' : 'آماده دریافت',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  alias,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: .72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReceiveCard extends StatelessWidget {
  final bool active;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickReceiveCard({
    required this.active,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: active ? cs.secondaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: active
                      ? cs.onSecondaryContainer.withValues(alpha: .10)
                      : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  active ? Icons.flash_off_rounded : Icons.bolt_rounded,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'خاموش کردن دریافت سریع' : 'دریافت سریع',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final bool showQr;
  final Future<String> qrPayload;
  final VoidCallback onToggleQr;
  final VoidCallback onDirectMode;

  const _ConnectionCard({
    required this.showQr,
    required this.qrPayload,
    required this.onToggleQr,
    required this.onDirectMode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'روش اتصال',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.qr_code_2_rounded),
                label: Text('QR'),
              ),
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.wifi_tethering_rounded),
                label: Text('مستقیم'),
              ),
            ],
            selected: {showQr},
            showSelectedIcon: false,
            onSelectionChanged: (value) {
              final next = value.first;
              if (next != showQr) onToggleQr();
            },
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showQr
                ? Column(
                    key: const ValueKey('qr'),
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: FutureBuilder<String>(
                            future: qrPayload,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const SizedBox(
                                  width: 190,
                                  height: 190,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return QrImageView(
                                data: snapshot.data!,
                                size: 190,
                                backgroundColor: Colors.white,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'در دستگاه فرستنده «اسکن QR» را بزن',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('direct'),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.wifi_tethering_rounded, size: 38),
                            SizedBox(height: 8),
                            Text(
                              'بدون Wi‑Fi مشترک',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'گوشی فرستنده مستقیماً با Wi‑Fi Direct وصل می‌شود.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onDirectMode,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('شروع اتصال مستقیم'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoPill({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
