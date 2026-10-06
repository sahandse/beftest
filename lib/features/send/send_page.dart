import 'package:flutter/material.dart';

import '../../network/nearby_device.dart';
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
  final bool sending;
  final double progress;
  final Future<void> Function(NearbyDevice device, SendCategory category) onSend;
  final List<String> sharedPaths;
  final Future<void> Function(NearbyDevice device, List<String> paths)? onSendShared;

  const SendPage({
    super.key,
    required this.devices,
    required this.sending,
    required this.progress,
    required this.onSend,
    this.sharedPaths = const [],
    this.onSendShared,
  });

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  late List<NearbyDevice> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.devices.toList();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            const Text('اول نوع محتوا را انتخاب کن، بعد دستگاه مقصد را بزن.'),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: SendCategory.values.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                );
              },
            ),
            if (widget.sharedPaths.isNotEmpty) ...[
              const SizedBox(height: 20),
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
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('اسکن QR'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                if (widget.sending)
                  Text('${(widget.progress * 100).round()}٪'),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: LinearProgressIndicator(value: widget.progress),
              ),
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
                      'دستگاه دوم باید روی همین شبکه باشد و بفرست یا LocalSend باز باشد.',
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
                    disabled: widget.sending,
                    onSend: (category) {
                      if (widget.sharedPaths.isNotEmpty && widget.onSendShared != null) {
                        widget.onSendShared!(device, widget.sharedPaths);
                      } else {
                        widget.onSend(device, category);
                      }
                    },
                    hasSharedFiles: widget.sharedPaths.isNotEmpty,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CategoryCard({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final NearbyDevice device;
  final bool disabled;
  final ValueChanged<SendCategory> onSend;
  final bool hasSharedFiles;

  const _DeviceCard({
    required this.device,
    required this.disabled,
    required this.onSend,
    required this.hasSharedFiles,
  });

  Future<void> _pickCategory(BuildContext context) async {
    final selected = await showModalBottomSheet<SendCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: SendCategory.values
              .map(
                (category) => ListTile(
                  leading: Icon(_icon(category)),
                  title: Text(_label(category)),
                  onTap: () => Navigator.pop(context, category),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      onSend(selected);
    }
  }

  IconData _icon(SendCategory category) {
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

  String _label(SendCategory category) {
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: disabled
            ? null
            : () {
                if (hasSharedFiles) {
                  onSend(SendCategory.files);
                } else {
                  _pickCategory(context);
                }
              },
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.ip,
                      textDirection: TextDirection.ltr,
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
