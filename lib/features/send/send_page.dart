import 'package:flutter/material.dart';

import '../../core/transfer_session_controller.dart';
import '../../network/nearby_device.dart';
import '../../network/transfer_models.dart';
import 'qr_scanner_page.dart';

enum SendCategory {
  photos,
  videos,
  music,
  documents,
  files,
  apps,
  folders,
  text,
}

class SendPage extends StatefulWidget {
  final List<NearbyDevice> devices;
  final TransferSessionController sessionController;
  final Future<void> Function(
    NearbyDevice device,
    SendCategory category,
  ) onSend;
  final List<String> sharedPaths;
  final Future<void> Function(
    NearbyDevice device,
    List<String> paths,
  )? onSendShared;

  const SendPage({
    super.key,
    required this.devices,
    required this.sessionController,
    required this.onSend,
    this.sharedPaths = const [],
    this.onSendShared,
  });

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late List<NearbyDevice> _devices;
  SendCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _devices = widget.devices.toList();
    if (widget.sharedPaths.isNotEmpty) {
      _selectedCategory = SendCategory.files;
    }
  }

  Future<void> _scanQr() async {
    final device = await Navigator.push<NearbyDevice>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(),
      ),
    );

    if (device == null || !mounted) return;

    setState(() {
      _devices.removeWhere(
        (item) => item.fingerprint == device.fingerprint,
      );
      _devices.insert(0, device);
    });
  }

  Future<void> _sendToDevice(NearbyDevice device) async {
    if (widget.sessionController.isActive) return;

    if (widget.sharedPaths.isNotEmpty && widget.onSendShared != null) {
      await widget.onSendShared!(device, widget.sharedPaths);
      return;
    }

    final category = _selectedCategory;
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اول نوع فایل یا محتوا را انتخاب کن.'),
        ),
      );
      return;
    }

    await widget.onSend(device, category);
  }

  IconData _iconFor(SendCategory category) {
    switch (category) {
      case SendCategory.photos:
        return Icons.photo_library_outlined;
      case SendCategory.videos:
        return Icons.video_library_outlined;
      case SendCategory.music:
        return Icons.library_music_outlined;
      case SendCategory.documents:
        return Icons.description_outlined;
      case SendCategory.files:
        return Icons.folder_copy_outlined;
      case SendCategory.apps:
        return Icons.android_rounded;
      case SendCategory.folders:
        return Icons.folder_open_rounded;
      case SendCategory.text:
        return Icons.text_snippet_outlined;
    }
  }

  String _labelFor(SendCategory category) {
    switch (category) {
      case SendCategory.photos:
        return 'عکس';
      case SendCategory.videos:
        return 'ویدیو';
      case SendCategory.music:
        return 'موسیقی';
      case SendCategory.documents:
        return 'اسناد';
      case SendCategory.files:
        return 'فایل‌ها';
      case SendCategory.apps:
        return 'برنامه‌ها';
      case SendCategory.folders:
        return 'پوشه';
      case SendCategory.text:
        return 'متن و لینک';
    }
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '—';
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    if (bytesPerSecond < 1024 * 1024 * 1024) {
      return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024 / 1024 / 1024).toStringAsFixed(1)} GB/s';
  }

  String _formatEta(Duration? duration) {
    if (duration == null) return '—';
    if (duration.inSeconds < 60) return '${duration.inSeconds} ثانیه';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _statusText(TransferStatus status) {
    switch (status) {
      case TransferStatus.waiting:
        return 'در صف';
      case TransferStatus.transferring:
        return 'در حال ارسال';
      case TransferStatus.completed:
        return 'تمام شد';
      case TransferStatus.failed:
        return 'ناموفق';
      case TransferStatus.cancelled:
        return 'لغو شد';
    }
  }

  IconData _statusIcon(TransferStatus status) {
    switch (status) {
      case TransferStatus.waiting:
        return Icons.schedule_rounded;
      case TransferStatus.transferring:
        return Icons.sync_rounded;
      case TransferStatus.completed:
        return Icons.check_circle_outline_rounded;
      case TransferStatus.failed:
        return Icons.error_outline_rounded;
      case TransferStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: widget.sessionController,
      builder: (context, _) {
        final session = widget.sessionController;

        return Scaffold(
          appBar: AppBar(title: const Text('ارسال')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'چی می‌خوای بفرستی؟',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('نوع محتوا را انتخاب کن و بعد دستگاه مقصد را بزن.'),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: SendCategory.values.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .92,
                  ),
                  itemBuilder: (context, index) {
                    final category = SendCategory.values[index];
                    return _CategoryCard(
                      icon: _iconFor(category),
                      label: _labelFor(category),
                      selected: _selectedCategory == category,
                      onTap: session.isActive
                          ? null
                          : () {
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                    );
                  },
                ),
                if (widget.sharedPaths.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: cs.secondaryContainer,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.ios_share_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${widget.sharedPaths.length} فایل از Share آماده ارسال است',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'دستگاه‌های نزدیک',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: session.isActive ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('اسکن QR'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_devices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: cs.surfaceContainerLow,
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.radar_rounded, size: 38),
                        SizedBox(height: 10),
                        Text(
                          'دستگاهی پیدا نشد',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'دستگاه دوم باید روی همین شبکه باشد. می‌توانی QR را هم اسکن کنی.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ..._devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DeviceCard(
                        device: device,
                        disabled: session.isActive,
                        onTap: () => _sendToDevice(device),
                      ),
                    ),
                  ),
                if (session.items.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _TransferQueuePanel(
                    controller: session,
                    formatSpeed: _formatSpeed,
                    formatEta: _formatEta,
                    statusText: _statusText,
                    statusIcon: _statusIcon,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: selected ? cs.onPrimaryContainer : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? cs.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final NearbyDevice device;
  final bool disabled;
  final VoidCallback onTap;

  const _DeviceCard({
    required this.device,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Icon(
                  device.type == DeviceType.desktop
                      ? Icons.laptop_rounded
                      : Icons.smartphone_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.alias,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.supportsResume
                          ? 'ادامه انتقال پشتیبانی می‌شود'
                          : device.ip,
                      textDirection: device.supportsResume
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferQueuePanel extends StatelessWidget {
  final TransferSessionController controller;
  final String Function(double value) formatSpeed;
  final String Function(Duration? value) formatEta;
  final String Function(TransferStatus status) statusText;
  final IconData Function(TransferStatus status) statusIcon;

  const _TransferQueuePanel({
    required this.controller,
    required this.formatSpeed,
    required this.formatEta,
    required this.statusText,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (controller.overallProgress * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.isActive
                      ? 'ارسال به ${controller.peer}'
                      : 'آخرین انتقال',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text('$percent٪'),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: controller.overallProgress),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  icon: Icons.speed_rounded,
                  value: formatSpeed(controller.totalSpeed),
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.timer_outlined,
                  value: formatEta(controller.overallEta),
                ),
              ),
            ],
          ),
          if (controller.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.isPaused
                        ? controller.resume
                        : controller.pause,
                    icon: Icon(
                      controller.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    label: Text(
                      controller.isPaused ? 'ادامه' : 'توقف موقت',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'لغو انتقال',
                  onPressed: controller.cancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ] else if (controller.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: controller.clear,
              icon: const Icon(Icons.add_rounded),
              label: const Text('فایل بیشتری بفرست'),
            ),
          ],
          const SizedBox(height: 12),
          ...controller.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(statusIcon(item.status), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: item.progress),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 72,
                    child: Text(
                      statusText(item.status),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _Metric({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(value)),
      ],
    );
  }
}
