import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_settings.dart';
import '../../core/transfer_history_store.dart';
import '../../network/discovery_service.dart';
import '../../network/nearby_device.dart';
import '../../network/transfer_server.dart';
import '../../network/transfer_service.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  final AppSettings settings;

  const HomePage({
    super.key,
    required this.settings,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _discovery = DiscoveryService();
  final _server = TransferServer();
  final _transfer = TransferService();
  final _historyStore = TransferHistoryStore();
  final _uuid = const Uuid();

  List<NearbyDevice> _devices = const [];
  List<HistoryItem> _history = const [];
  bool _discovering = true;
  bool _sending = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _discovery.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _discovering = false;
      });
    });
    _loadHistory();
    _startNetwork();
  }

  Future<void> _loadHistory() async {
    final items = await _historyStore.load();
    if (mounted) setState(() => _history = items);
  }

  Future<void> _startNetwork() async {
    try {
      _server.onIncomingRequest = (incoming) async {
        if (!mounted) return false;
        final decision = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.move_to_inbox_rounded),
            title: Text('دریافت از ${incoming.senderAlias}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${incoming.files.length} فایل'),
                const SizedBox(height: 6),
                Text('حجم کل: ${_sizeText(incoming.totalSize)}'),
                const SizedBox(height: 14),
                ...incoming.files.take(3).map(
                  (file) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• ${file.fileName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (incoming.files.length > 3)
                  Text('و ${incoming.files.length - 3} فایل دیگر'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('رد'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.download_rounded),
                label: const Text('دریافت'),
              ),
            ],
          ),
        );
        return decision ?? false;
      };

      _server.onIncomingComplete = (event) async {
        await _historyStore.add(
          HistoryItem(
            id: _uuid.v4(),
            peer: event.senderAlias,
            fileName: event.fileName,
            size: event.size,
            sent: false,
            success: event.success,
            createdAt: DateTime.now(),
          ),
        );
        await _loadHistory();
      };

      await _server.start(
        alias: widget.settings.alias,
        fingerprint: widget.settings.fingerprint,
        pin: widget.settings.pinEnabled ? widget.settings.pin : null,
      );
      await _discovery.start(
        alias: widget.settings.alias,
        fingerprint: widget.settings.fingerprint,
      );
    } catch (_) {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _restartNetwork() async {
    await _server.stop();
    await _startNetwork();
  }

  Future<String?> _askForPin() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN دستگاه'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'کد را وارد کن',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _sendTo(NearbyDevice device, {String? pin}) async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    final paths = picked?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) return;

    setState(() {
      _sending = true;
      _progress = 0;
    });

    try {
      final files = await _transfer.buildFiles(paths);
      final total = files.fold<int>(0, (sum, item) => sum + item.size);
      final sentById = <String, int>{};

      await _transfer.send(
        device: device,
        alias: widget.settings.alias,
        fingerprint: widget.settings.fingerprint,
        files: files,
        pin: pin,
        onProgress: (id, sent, fileTotal) {
          sentById[id] = sent;
          final sentAll = sentById.values.fold<int>(0, (a, b) => a + b);
          if (mounted) {
            setState(() => _progress = total == 0 ? 0 : sentAll / total);
          }
        },
      );

      for (final file in files) {
        await _historyStore.add(
          HistoryItem(
            id: _uuid.v4(),
            peer: device.alias,
            fileName: file.fileName,
            size: file.size,
            sent: true,
            success: true,
            createdAt: DateTime.now(),
          ),
        );
      }
      await _loadHistory();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ارسال به ${device.alias} کامل شد')),
      );
    } catch (e) {
      final text = e.toString();
      if (text.contains('PIN_REQUIRED') && mounted) {
        setState(() {
          _sending = false;
          _progress = 0;
        });
        final entered = await _askForPin();
        if (entered != null && entered.isNotEmpty) {
          await _sendTo(device, pin: entered);
        }
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ارسال انجام نشد. اتصال یا PIN را بررسی کن.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = 0;
        });
      }
    }
  }

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _discovery.dispose();
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('بفرست', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'تنظیمات',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    settings: widget.settings,
                    onNetworkRestart: _restartNetwork,
                  ),
                ),
              );
              await _loadHistory();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _discovery.start(
          alias: widget.settings.alias,
          fingerprint: widget.settings.fingerprint,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [cs.primaryContainer, cs.secondaryContainer],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.near_me_rounded, size: 36),
                  const SizedBox(height: 16),
                  Text(
                    widget.settings.alias,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.settings.pinEnabled
                        ? 'دریافت با PIN فعال است'
                        : 'آماده ارسال و دریافت روی شبکه محلی',
                    style: const TextStyle(height: 1.7),
                  ),
                  if (_sending) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 8),
                    Text('${(_progress * 100).round()}٪ در حال ارسال'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'دستگاه‌های نزدیک',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_discovering && _devices.isEmpty)
              const _InfoCard(
                icon: Icons.radar_rounded,
                title: 'در حال جستجو',
                subtitle: 'دستگاه‌های روی همین شبکه را پیدا می‌کنم.',
              )
            else if (_devices.isEmpty)
              const _InfoCard(
                icon: Icons.devices_other_rounded,
                title: 'دستگاهی پیدا نشد',
                subtitle: 'بفرست یا LocalSend را روی دستگاه دوم باز کن.',
              )
            else
              ..._devices.map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _sending ? null : () => _sendTo(device),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 25,
                              child: Icon(
                                device.type == DeviceType.desktop
                                    ? Icons.laptop_rounded
                                    : Icons.smartphone_rounded,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.alias,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    device.ip,
                                    textDirection: TextDirection.ltr,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.send_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'فعالیت اخیر',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                if (_history.isNotEmpty)
                  Text('${_history.length} مورد'),
              ],
            ),
            const SizedBox(height: 10),
            if (_history.isEmpty)
              const _InfoCard(
                icon: Icons.history_rounded,
                title: 'هنوز انتقالی ثبت نشده',
                subtitle: 'ارسال‌ها و دریافت‌های واقعی اینجا می‌آیند.',
              )
            else
              ..._history.take(12).map(
                (item) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    child: Icon(item.sent
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded),
                  ),
                  title: Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${item.peer} • ${_sizeText(item.size)}'),
                  trailing: Icon(
                    item.success
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
