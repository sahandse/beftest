import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/direct_mode_service.dart';

enum DirectModeRole { sender, receiver }

class DirectModePage extends StatefulWidget {
  final DirectModeRole role;
  final Future<void> Function()? onConnected;

  const DirectModePage({
    super.key,
    required this.role,
    this.onConnected,
  });

  @override
  State<DirectModePage> createState() => _DirectModePageState();
}

class _DirectModePageState extends State<DirectModePage> {
  final _service = DirectModeService();
  bool _loading = true;
  bool _connecting = false;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  List<DirectPeer> _peers = const [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _permissionPermanentlyDenied = false;
      _message = null;
    });

    final status = await _service.requestPermissionStatus();
    if (!mounted) return;

    if (!status.isGranted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
        _permissionPermanentlyDenied = status.isPermanentlyDenied ||
            status.isRestricted;
      });
      return;
    }

    if (widget.role == DirectModeRole.receiver) {
      await _startReceiver();
    } else {
      await _discover();
    }
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _message = 'در حال پیدا کردن گوشی‌های نزدیک…';
    });
    try {
      final peers = await _service.discoverPeers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _loading = false;
        _message = peers.isEmpty
            ? 'هنوز دستگاهی پیدا نشده؛ Direct Mode را روی گوشی دوم باز کن.'
            : null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = error.message ?? 'جستجوی مستقیم انجام نشد.';
      });
    }
  }

  Future<void> _startReceiver() async {
    setState(() {
      _loading = true;
      _message = 'در حال ساخت اتصال مستقیم…';
    });

    try {
      await _service.removeGroup();
      await _service.createGroup();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'آماده اتصال مستقیم • روی گوشی فرستنده Direct Mode را باز کن.';
      });

      final info = await _service.waitForConnection(
        timeout: const Duration(minutes: 2),
      );
      if (!mounted || info == null) return;
      HapticFeedback.mediumImpact();
      await widget.onConnected?.call();
      if (!mounted) return;
      setState(() => _message = 'اتصال مستقیم برقرار شد ✓');
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = error.message ?? 'ساخت اتصال مستقیم انجام نشد.';
      });
    }
  }

  Future<void> _connect(DirectPeer peer) async {
    if (_connecting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _connecting = true;
      _message = 'در حال اتصال به ${peer.name}…';
    });

    try {
      await _service.connect(peer);
      final info = await _service.waitForConnection();
      if (!mounted) return;

      if (info == null) {
        setState(() {
          _connecting = false;
          _message = 'اتصال کامل نشد؛ دوباره تلاش کن.';
        });
        return;
      }

      HapticFeedback.mediumImpact();
      await widget.onConnected?.call();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _message = 'متصل شد ✓ حالا به صفحه ارسال برگرد.';
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _message = error.message ?? 'اتصال مستقیم انجام نشد.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sender = widget.role == DirectModeRole.sender;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('اتصال مستقیم')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: sender
                    ? cs.tertiaryContainer
                    : cs.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  Icon(
                    sender
                        ? Icons.wifi_tethering_rounded
                        : Icons.router_rounded,
                    size: 56,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    sender
                        ? 'اتصال بدون Wi‑Fi مشترک'
                        : 'گوشی را آماده اتصال مستقیم کن',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sender
                        ? 'با Wi‑Fi Direct مستقیماً به گوشی مقصد وصل شو؛ اینترنت لازم نیست.'
                        : 'بفرست یک گروه Wi‑Fi Direct می‌سازد تا گوشی فرستنده مستقیم وصل شود.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_permissionDenied)
              _PermissionCard(
                permanentlyDenied: _permissionPermanentlyDenied,
                onRetry: _start,
              )
            else ...[
              if (_message != null)
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if (_loading) ...[
                const SizedBox(height: 22),
                const Center(child: CircularProgressIndicator()),
              ],
              if (sender && !_loading) ...[
                const SizedBox(height: 16),
                if (_peers.isEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _discover,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('جستجوی دوباره'),
                  )
                else ...[
                  const Text(
                    'دستگاه‌های Wi‑Fi Direct',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._peers.map(
                    (peer) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(22),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: const Icon(Icons.smartphone_rounded),
                          title: Text(
                            peer.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: const Text('اتصال مستقیم آماده است'),
                          trailing: _connecting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.link_rounded),
                          onTap: _connecting ? null : () => _connect(peer),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.tonalIcon(
                    onPressed: _connecting ? null : _discover,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('جستجوی دوباره'),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final bool permanentlyDenied;
  final Future<void> Function() onRetry;

  const _PermissionCard({
    required this.permanentlyDenied,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_lock_rounded, size: 42),
          const SizedBox(height: 10),
          const Text(
            'دسترسی Wi‑Fi نزدیک لازم است',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            permanentlyDenied
                ? 'این دسترسی از تنظیمات خاموش شده. برای استفاده از اتصال مستقیم، آن را از تنظیمات برنامه فعال کن.'
                : 'این دسترسی فقط وقتی Direct Mode را باز می‌کنی درخواست می‌شود و برای پیدا کردن گوشی نزدیک است.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: permanentlyDenied
                ? () async => openAppSettings()
                : onRetry,
            icon: Icon(
              permanentlyDenied
                  ? Icons.settings_rounded
                  : Icons.wifi_rounded,
            ),
            label: Text(
              permanentlyDenied ? 'باز کردن تنظیمات' : 'اجازه بده',
            ),
          ),
        ],
      ),
    );
  }
}
