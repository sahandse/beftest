import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/transfer_session_controller.dart';
import '../../core/app_inventory_service.dart';
import '../../network/nearby_device.dart';
import '../../network/transfer_models.dart';
import 'qr_scanner_page.dart';

typedef CheckAppUpdates = Future<List<PeerAppUpdate>> Function(
  NearbyDevice device,
);

typedef ReceiveAppUpdates = Future<void> Function(
  NearbyDevice device,
  List<PeerAppUpdate> updates,
  void Function(PeerAppUpdate update, int received, int? total) onProgress,
);

typedef PickSendCategory = Future<List<String>> Function(
  SendCategory category,
);

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
  final Set<String> trustedFingerprints;
  final VoidCallback? onOpenHistory;
  final CheckAppUpdates? onCheckAppUpdates;
  final ReceiveAppUpdates? onReceiveAppUpdates;
  final PickSendCategory? onPickCategory;
  final VoidCallback? onOpenReceive;
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
    this.trustedFingerprints = const <String>{},
    this.onOpenHistory,
    this.onCheckAppUpdates,
    this.onReceiveAppUpdates,
    this.onPickCategory,
    this.onOpenReceive,
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
  List<String> _selectedPaths = const [];
  bool _pickingCategory = false;
  bool _queueExpanded = false;
  final Map<String, List<PeerAppUpdate>> _appUpdates = {};
  final Set<String> _checkedUpdatePeers = {};
  final Set<String> _checkingUpdatePeers = {};
  final Set<String> _receivingUpdatePeers = {};

  @override
  void initState() {
    super.initState();
    _devices = widget.devices.toList();
    if (widget.sharedPaths.isNotEmpty) {
      _selectedCategory = SendCategory.files;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final device in _devices) {
        if (device.supportsAppUpdates &&
            widget.trustedFingerprints.contains(device.fingerprint)) {
          _checkUpdates(device, silent: true);
        }
      }
    });
  }

  Future<void> _checkUpdates(
    NearbyDevice device, {
    bool silent = false,
  }) async {
    final callback = widget.onCheckAppUpdates;
    if (callback == null ||
        _checkingUpdatePeers.contains(device.fingerprint)) {
      return;
    }

    setState(() => _checkingUpdatePeers.add(device.fingerprint));
    try {
      final updates = await callback(device);
      if (!mounted) return;
      setState(() {
        _appUpdates[device.fingerprint] = updates;
        _checkedUpdatePeers.add(device.fingerprint);
      });
      if (!silent && updates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.alias} بروزرسانی جدیدی ندارد.')),
        );
      }
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('بررسی بروزرسانی‌های ${device.alias} انجام نشد.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingUpdatePeers.remove(device.fingerprint));
      }
    }
  }

  Future<void> _showAppUpdates(
    NearbyDevice device,
    List<PeerAppUpdate> updates,
  ) async {
    final receiver = widget.onReceiveAppUpdates;
    if (receiver == null || updates.isEmpty) return;

    final selected = <String>{
      for (final item in updates) item.packageName,
    };
    final progress = <String, double>{};
    var receiving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  4,
                  18,
                  18 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'بروزرسانی برنامه‌ها',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text('${updates.length} مورد'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'نسخه‌های جدیدتر از ${device.alias}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: updates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final update = updates[index];
                            final value = progress[update.packageName];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  CheckboxListTile(
                                    value: selected.contains(update.packageName),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    onChanged: receiving
                                        ? null
                                        : (checked) {
                                            setSheetState(() {
                                              if (checked == true) {
                                                selected.add(update.packageName);
                                              } else {
                                                selected.remove(
                                                  update.packageName,
                                                );
                                              }
                                            });
                                          },
                                    title: Text(
                                      update.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${update.currentVersion} ← ${update.remoteVersion}',
                                      textDirection: TextDirection.ltr,
                                    ),
                                  ),
                                  if (value != null) ...[
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(value: value),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: receiving || selected.isEmpty
                              ? null
                              : () async {
                                  final chosen = updates
                                      .where(
                                        (item) => selected.contains(
                                          item.packageName,
                                        ),
                                      )
                                      .toList(growable: false);
                                  setSheetState(() => receiving = true);
                                  setState(
                                    () => _receivingUpdatePeers
                                        .add(device.fingerprint),
                                  );
                                  try {
                                    await receiver(
                                      device,
                                      chosen,
                                      (update, received, total) {
                                        final fraction = total == null ||
                                                total <= 0
                                            ? null
                                            : (received / total)
                                                .clamp(0.0, 1.0)
                                                .toDouble();
                                        if (!sheetContext.mounted) return;
                                        setSheetState(() {
                                          if (fraction != null) {
                                            progress[update.packageName] =
                                                fraction;
                                          }
                                        });
                                      },
                                    );
                                    if (!sheetContext.mounted) return;
                                    Navigator.pop(sheetContext);
                                    if (mounted) {
                                      HapticFeedback.mediumImpact();
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${chosen.length} بروزرسانی دریافت شد.',
                                          ),
                                        ),
                                      );
                                      _checkUpdates(device, silent: true);
                                    }
                                  } catch (error) {
                                    if (!sheetContext.mounted) return;
                                    setSheetState(() => receiving = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(this.context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'دریافت بروزرسانی‌ها کامل نشد.',
                                          ),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _receivingUpdatePeers
                                            .remove(device.fingerprint),
                                      );
                                    }
                                  }
                                },
                          icon: receiving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.download_rounded),
                          label: Text(
                            receiving
                                ? 'در حال دریافت…'
                                : 'دریافت ${selected.length} بروزرسانی',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _scanQr() async {
    HapticFeedback.lightImpact();
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

  Future<void> _pickCategory(SendCategory category) async {
    final picker = widget.onPickCategory;
    if (picker == null || _pickingCategory || widget.sessionController.isActive) {
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _pickingCategory = true;
      _selectedCategory = category;
      _selectedPaths = const [];
    });

    try {
      final paths = await picker(category);
      if (!mounted) return;
      setState(() {
        _selectedPaths = paths;
        if (paths.isEmpty) {
          _selectedCategory = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _pickingCategory = false);
      }
    }
  }

  Future<void> _sendToDevice(NearbyDevice device) async {
    if (widget.sessionController.isActive) return;

    HapticFeedback.mediumImpact();

    if (widget.sharedPaths.isNotEmpty && widget.onSendShared != null) {
      await widget.onSendShared!(device, widget.sharedPaths);
      return;
    }

    final category = _selectedCategory;
    if (category == null || _selectedPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اول نوع فایل یا محتوا را انتخاب کن.'),
        ),
      );
      return;
    }

    if (widget.onSendShared != null) {
      final paths = List<String>.from(_selectedPaths);
      await widget.onSendShared!(device, paths);
      if (mounted) {
        setState(() {
          _selectedPaths = const [];
          _selectedCategory = null;
        });
      }
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

  void _openPhoneMigration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: _PhoneMigrationPage(
            devices: _devices,
            onPickCategory: widget.onPickCategory,
            onSendShared: widget.onSendShared,
            onOpenReceive: widget.onOpenReceive,
          ),
        ),
      ),
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final gridCount = width >= 900 ? 6 : width >= 600 ? 5 : 4;

    return AnimatedBuilder(
      animation: widget.sessionController,
      builder: (context, _) {
        final session = widget.sessionController;

        return Scaffold(
          appBar: AppBar(title: const Text('ارسال')),
          bottomNavigationBar: session.items.isEmpty
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: _FloatingTransferCard(
                    controller: session,
                    expanded: _queueExpanded,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      setState(() => _queueExpanded = !_queueExpanded);
                    },
                    formatSpeed: _formatSpeed,
                    formatEta: _formatEta,
                    statusText: _statusText,
                    statusIcon: _statusIcon,
                    onOpenHistory: widget.onOpenHistory,
                  ),
                ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
              children: [
                const Text(
                  'چی می‌خوای بفرستی؟',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'محتوا را انتخاب کن و بعد روی دستگاه مقصد بزن',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: SendCategory.values.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: width >= 600 ? 1.15 : .92,
                  ),
                  itemBuilder: (context, index) {
                    final category = SendCategory.values[index];
                    return _CategoryCard(
                      icon: _iconFor(category),
                      label: _labelFor(category),
                      selected: _selectedCategory == category,
                      onTap: session.isActive || _pickingCategory
                          ? null
                          : () => _pickCategory(category),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _PhoneMigrationCard(
                  onTap: session.isActive ? null : _openPhoneMigration,
                ),
                if (_selectedPaths.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: cs.primaryContainer,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            '${_selectedPaths.length} مورد آماده ارسال • حالا دستگاه مقصد را انتخاب کن',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'پاک کردن انتخاب',
                          onPressed: () => setState(() {
                            _selectedPaths = const [];
                            _selectedCategory = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.sharedPaths.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: cs.secondaryContainer,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.ios_share_rounded),
                        const SizedBox(width: 11),
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
                const SizedBox(height: 26),
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
                    IconButton.filledTonal(
                      tooltip: 'اسکن QR',
                      onPressed: session.isActive ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_devices.isEmpty)
                  const _DevicesEmptyState()
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _devices
                        .map(
                          (device) => _DeviceBubble(
                            device: device,
                            trusted: widget.trustedFingerprints
                                .contains(device.fingerprint),
                            disabled: session.isActive,
                            onTap: () => _sendToDevice(device),
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (_devices.any((device) => device.supportsAppUpdates) &&
                    widget.onCheckAppUpdates != null) ...[
                  const SizedBox(height: 24),
                  _AppUpdatesSection(
                    devices: _devices
                        .where((device) => device.supportsAppUpdates)
                        .toList(growable: false),
                    trustedFingerprints: widget.trustedFingerprints,
                    updates: _appUpdates,
                    checkedPeers: _checkedUpdatePeers,
                    checkingPeers: _checkingUpdatePeers,
                    receivingPeers: _receivingUpdatePeers,
                    onCheck: (device) => _checkUpdates(device),
                    onOpen: _showAppUpdates,
                  ),
                ],
                if (session.items.isNotEmpty)
                  const SizedBox(height: 112),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppUpdatesSection extends StatelessWidget {
  final List<NearbyDevice> devices;
  final Set<String> trustedFingerprints;
  final Map<String, List<PeerAppUpdate>> updates;
  final Set<String> checkedPeers;
  final Set<String> checkingPeers;
  final Set<String> receivingPeers;
  final ValueChanged<NearbyDevice> onCheck;
  final void Function(
    NearbyDevice device,
    List<PeerAppUpdate> updates,
  ) onOpen;

  const _AppUpdatesSection({
    required this.devices,
    required this.trustedFingerprints,
    required this.updates,
    required this.checkedPeers,
    required this.checkingPeers,
    required this.receivingPeers,
    required this.onCheck,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.system_update_alt_rounded),
              SizedBox(width: 9),
              Text(
                'بروزرسانی برنامه‌ها',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'نسخه برنامه‌های مشترک بین دو گوشی را مقایسه کن.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ...devices.map((device) {
            final peerUpdates =
                updates[device.fingerprint] ?? const <PeerAppUpdate>[];
            final checked = checkedPeers.contains(device.fingerprint);
            final checking = checkingPeers.contains(device.fingerprint);
            final receiving = receivingPeers.contains(device.fingerprint);
            final trusted =
                trustedFingerprints.contains(device.fingerprint);

            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: checking || receiving
                      ? null
                      : peerUpdates.isNotEmpty
                          ? () => onOpen(device, peerUpdates)
                          : () => onCheck(device),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: peerUpdates.isNotEmpty
                                ? cs.tertiaryContainer
                                : cs.primaryContainer,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            peerUpdates.isNotEmpty
                                ? Icons.download_for_offline_rounded
                                : Icons.system_update_rounded,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      device.alias,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (trusted) ...[
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                checking
                                    ? 'در حال بررسی…'
                                    : receiving
                                        ? 'در حال دریافت…'
                                        : peerUpdates.isNotEmpty
                                            ? '${peerUpdates.length} بروزرسانی موجود'
                                            : checked
                                                ? 'همه برنامه‌های مشترک بروزند'
                                                : trusted
                                                    ? 'بررسی خودکار'
                                                    : 'برای بررسی بزن',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (checking || receiving)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                            ),
                          )
                        else if (peerUpdates.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${peerUpdates.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        else
                          const Icon(Icons.chevron_left_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
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

    return AnimatedScale(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutBack,
      scale: selected ? 1.035 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(selected ? 28 : 22),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(selected ? 28 : 22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(selected ? 28 : 22),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? 42 : 36,
                  height: selected ? 42 : 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.onPrimaryContainer.withValues(alpha: .09)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: selected ? cs.onPrimaryContainer : null,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? cs.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceBubble extends StatelessWidget {
  final NearbyDevice device;
  final bool trusted;
  final bool disabled;
  final VoidCallback onTap;

  const _DeviceBubble({
    required this.device,
    required this.trusted,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deviceIcon = device.type == DeviceType.desktop
        ? Icons.laptop_rounded
        : Icons.smartphone_rounded;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: disabled ? .48 : 1,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(26),
          child: Container(
            width: 154,
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(deviceIcon),
                    ),
                    if (trusted)
                      PositionedDirectional(
                        start: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            size: 13,
                          ),
                        ),
                      ),
                    if (device.supportsResume)
                      PositionedDirectional(
                        end: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            size: 13,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  device.alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trusted
                      ? 'مورداعتماد'
                      : device.supportsResume
                          ? 'اتصال سریع'
                          : 'دستگاه نزدیک',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevicesEmptyState extends StatelessWidget {
  const _DevicesEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer.withValues(alpha: .45),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer,
                ),
                child: const Icon(Icons.radar_rounded, size: 30),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'هنوز دستگاهی پیدا نشده',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'بفرست را روی دستگاه دوم باز کن و مطمئن شو هر دو روی یک شبکه هستند.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FloatingTransferCard extends StatelessWidget {
  final TransferSessionController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final String Function(double value) formatSpeed;
  final String Function(Duration? value) formatEta;
  final String Function(TransferStatus status) statusText;
  final IconData Function(TransferStatus status) statusIcon;
  final VoidCallback? onOpenHistory;

  const _FloatingTransferCard({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.formatSpeed,
    required this.formatEta,
    required this.statusText,
    required this.statusIcon,
    this.onOpenHistory,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (controller.overallProgress * 100).round();
    final done = !controller.isActive &&
        controller.items.isNotEmpty &&
        controller.items.every(
          (item) => item.status == TransferStatus.completed,
        );

    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .18),
      color: done ? cs.secondaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        done
                            ? Icons.check_circle_rounded
                            : controller.isPaused
                                ? Icons.pause_circle_filled_rounded
                                : Icons.send_rounded,
                        key: ValueKey('$done-${controller.isPaused}'),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            done
                                ? 'انتقال کامل شد'
                                : 'ارسال به ${controller.peer}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            done
                                ? '${controller.items.length} فایل'
                                : '${formatSpeed(controller.totalSpeed)} • ${formatEta(controller.overallEta)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$percent٪',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 7),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: controller.overallProgress,
                    minHeight: 6,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: 13),
                  if (controller.isActive)
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
                    )
                  else if (controller.items.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: controller.clear,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('فایل بیشتر'),
                          ),
                        ),
                        if (onOpenHistory != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onOpenHistory,
                              icon: const Icon(Icons.history_rounded),
                              label: const Text('تاریخچه'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: SingleChildScrollView(
                      child: Column(
                        children: controller.items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Icon(statusIcon(item.status), size: 20),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: item.progress,
                                            minHeight: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      statusText(item.status),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _PhoneMigrationCard extends StatelessWidget {
  final VoidCallback? onTap;

  const _PhoneMigrationCard({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PositionedDirectional(
                      start: 0,
                      child: Transform.rotate(
                        angle: -.08,
                        child: Container(
                          width: 42,
                          height: 62,
                          decoration: BoxDecoration(
                            color: cs.onSecondaryContainer.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: cs.onSecondaryContainer.withValues(alpha: .16),
                            ),
                          ),
                          child: const Icon(Icons.smartphone_rounded, size: 23),
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      child: Transform.rotate(
                        angle: .08,
                        child: Container(
                          width: 42,
                          height: 62,
                          decoration: BoxDecoration(
                            color: cs.onSecondaryContainer.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: cs.onSecondaryContainer.withValues(alpha: .20),
                            ),
                          ),
                          child: const Icon(Icons.smartphone_rounded, size: 23),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'گوشی قدیمی → گوشی جدید',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'عکس، ویدیو، فایل، موسیقی، پوشه و برنامه‌ها را یکجا جابه‌جا کن',
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

class _PhoneMigrationPage extends StatefulWidget {
  final List<NearbyDevice> devices;
  final PickSendCategory? onPickCategory;
  final Future<void> Function(
    NearbyDevice device,
    List<String> paths,
  )? onSendShared;
  final VoidCallback? onOpenReceive;

  const _PhoneMigrationPage({
    required this.devices,
    required this.onPickCategory,
    required this.onSendShared,
    required this.onOpenReceive,
  });

  @override
  State<_PhoneMigrationPage> createState() => _PhoneMigrationPageState();
}

class _PhoneMigrationPageState extends State<_PhoneMigrationPage> {
  bool _oldPhone = true;
  bool _preparing = false;
  bool _sending = false;
  final Set<SendCategory> _selected = {
    SendCategory.photos,
    SendCategory.videos,
    SendCategory.music,
    SendCategory.documents,
    SendCategory.files,
    SendCategory.apps,
    SendCategory.folders,
  };
  List<String> _preparedPaths = const [];

  List<SendCategory> get _transferable => const [
        SendCategory.photos,
        SendCategory.videos,
        SendCategory.music,
        SendCategory.documents,
        SendCategory.files,
        SendCategory.apps,
        SendCategory.folders,
      ];

  String _label(SendCategory category) {
    switch (category) {
      case SendCategory.photos:
        return 'عکس‌ها';
      case SendCategory.videos:
        return 'ویدیوها';
      case SendCategory.music:
        return 'موسیقی';
      case SendCategory.documents:
        return 'اسناد';
      case SendCategory.files:
        return 'فایل‌ها';
      case SendCategory.apps:
        return 'برنامه‌ها';
      case SendCategory.folders:
        return 'پوشه‌ها';
      case SendCategory.text:
        return 'متن';
    }
  }

  IconData _icon(SendCategory category) {
    switch (category) {
      case SendCategory.photos:
        return Icons.photo_library_rounded;
      case SendCategory.videos:
        return Icons.video_library_rounded;
      case SendCategory.music:
        return Icons.library_music_rounded;
      case SendCategory.documents:
        return Icons.description_rounded;
      case SendCategory.files:
        return Icons.folder_copy_rounded;
      case SendCategory.apps:
        return Icons.android_rounded;
      case SendCategory.folders:
        return Icons.folder_rounded;
      case SendCategory.text:
        return Icons.text_snippet_rounded;
    }
  }

  Future<void> _prepare() async {
    final picker = widget.onPickCategory;
    if (picker == null || _selected.isEmpty || _preparing) return;

    setState(() {
      _preparing = true;
      _preparedPaths = const [];
    });

    final collected = <String>[];
    try {
      for (final category in _transferable) {
        if (!_selected.contains(category)) continue;
        final paths = await picker(category);
        collected.addAll(paths);
        if (!mounted) return;
        setState(() => _preparedPaths = List<String>.from(collected));
      }
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
  }

  Future<void> _send(NearbyDevice device) async {
    final sender = widget.onSendShared;
    if (sender == null || _preparedPaths.isEmpty || _sending) return;

    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    try {
      await sender(device, _preparedPaths);
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('انتقال گوشی')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Column(
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 50),
                  const SizedBox(height: 10),
                  const Text(
                    'از گوشی قدیمی به گوشی جدید',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'بدون اینترنت، روی شبکه محلی؛ محتوا را مرحله‌به‌مرحله انتخاب و منتقل کن.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.upload_rounded),
                  label: Text('گوشی قدیمی'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.download_rounded),
                  label: Text('گوشی جدید'),
                ),
              ],
              selected: {_oldPhone},
              onSelectionChanged: (value) {
                HapticFeedback.selectionClick();
                setState(() => _oldPhone = value.first);
              },
            ),
            const SizedBox(height: 18),
            if (_oldPhone) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'چه چیزهایی منتقل شود؟',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _preparing
                        ? null
                        : () {
                            setState(() {
                              if (_selected.length == _transferable.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(_transferable);
                              }
                            });
                          },
                    child: Text(
                      _selected.length == _transferable.length
                          ? 'لغو همه'
                          : 'همه موارد',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _transferable.map((category) {
                  final selected = _selected.contains(category);
                  return FilterChip(
                    avatar: Icon(_icon(category), size: 18),
                    label: Text(_label(category)),
                    selected: selected,
                    onSelected: _preparing
                        ? null
                        : (_) {
                            setState(() {
                              if (!_selected.add(category)) {
                                _selected.remove(category);
                              }
                            });
                          },
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'برنامه‌ها به‌صورت فایل APK منتقل می‌شوند. اطلاعات داخل برنامه‌ها، حساب‌های واردشده و تنظیمات سیستمی Android قابل کپی مستقیم نیستند.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _preparing || _selected.isEmpty ? null : _prepare,
                  icon: _preparing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    _preparing
                        ? 'در حال آماده‌سازی…'
                        : 'آماده‌سازی محتوا',
                  ),
                ),
              ),
              if (_preparedPaths.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '${_preparedPaths.length} مورد آماده انتقال',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.devices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      'هنوز گوشی جدید پیدا نشده. روی گوشی جدید بفرست را باز کن و حالت «گوشی جدید» را بزن.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...widget.devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: _sending ? null : () => _send(device),
                        icon: const Icon(Icons.smartphone_rounded),
                        label: Text(
                          _sending
                              ? 'در حال انتقال…'
                              : 'ارسال به ${device.alias}',
                        ),
                      ),
                    ),
                  ),
              ],
            ] else ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.download_for_offline_rounded, size: 54),
                    const SizedBox(height: 12),
                    const Text(
                      'گوشی جدید را آماده دریافت کن',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'هر دو گوشی را روی یک Wi‑Fi یا Hotspot مشترک بگذار. سپس دریافت را روشن کن تا گوشی قدیمی بتواند محتوا را بفرستد.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: widget.onOpenReceive == null
                          ? null
                          : () {
                              Navigator.pop(context);
                              widget.onOpenReceive!();
                            },
                      icon: const Icon(Icons.south_west_rounded),
                      label: const Text('آماده دریافت'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
