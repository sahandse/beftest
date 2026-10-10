import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../network/nearby_device.dart';
import '../../core/migration_draft_store.dart';
import '../send/send_page.dart';

class PhoneMigrationPage extends StatefulWidget {
  final List<NearbyDevice> devices;
  final Stream<List<NearbyDevice>>? devicesStream;
  final Future<List<String>> Function(SendCategory category) onPickCategory;
  final Future<bool> Function(
    NearbyDevice device,
    List<String> paths,
  ) onSend;
  final Future<void> Function()? onRefreshDevices;
  final VoidCallback onOpenReceive;

  const PhoneMigrationPage({
    super.key,
    required this.devices,
    this.devicesStream,
    required this.onPickCategory,
    required this.onSend,
    this.onRefreshDevices,
    required this.onOpenReceive,
  });

  @override
  State<PhoneMigrationPage> createState() => _PhoneMigrationPageState();
}

class _PhoneMigrationPageState extends State<PhoneMigrationPage> {
  late List<NearbyDevice> _devices;
  StreamSubscription<List<NearbyDevice>>? _sub;
  final MigrationDraftStore _draftStore = MigrationDraftStore();
  bool _oldPhone = true;
  bool _preparing = false;
  bool _loadingDraft = true;
  MigrationDraft? _draft;
  bool _sending = false;
  int _step = 0;
  final Map<SendCategory, List<String>> _picked = {};
  final Set<SendCategory> _selected = {
    SendCategory.photos,
    SendCategory.videos,
    SendCategory.music,
    SendCategory.documents,
    SendCategory.files,
    SendCategory.apps,
    SendCategory.folders,
  };
  List<String> _prepared = const [];

  static const _categories = [
    SendCategory.photos,
    SendCategory.videos,
    SendCategory.music,
    SendCategory.documents,
    SendCategory.files,
    SendCategory.apps,
    SendCategory.folders,
  ];

  @override
  void initState() {
    super.initState();
    _devices = widget.devices.toList(growable: false);
    _sub = widget.devicesStream?.listen((items) {
      if (!mounted) return;
      setState(() => _devices = items.toList(growable: false));
    });
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final draft = await _draftStore.load();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loadingDraft = false;
    });
  }

  Future<void> _useDraft() async {
    final draft = _draft;
    if (draft == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _prepared = List<String>.from(draft.paths);
      _picked
        ..clear()
        ..[SendCategory.files] = List<String>.from(draft.paths);
      _step = 2;
    });
  }

  Future<void> _discardDraft() async {
    await _draftStore.clear();
    if (!mounted) return;
    setState(() {
      _draft = null;
      _prepared = const [];
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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

  List<String> get _allPickedPaths => _picked.values
      .expand((paths) => paths)
      .toList(growable: false);

  Future<void> _pickOneCategory(SendCategory category) async {
    if (_preparing) return;
    HapticFeedback.selectionClick();
    setState(() => _preparing = true);
    try {
      final paths = await widget.onPickCategory(category);
      if (!mounted) return;
      setState(() {
        if (paths.isEmpty) {
          _picked.remove(category);
        } else {
          _picked[category] = paths;
        }
        _prepared = _allPickedPaths;
      });
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _continueToTransfer() async {
    final paths = _allPickedPaths;
    if (paths.isEmpty) return;
    await _draftStore.save(paths);
    final draft = await _draftStore.load();
    if (!mounted) return;
    setState(() {
      _prepared = paths;
      _draft = draft;
      _step = 2;
    });
  }

  Future<void> _send(NearbyDevice device) async {
    if (_sending || _prepared.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _sending = true);
    try {
      final success = await widget.onSend(device, _prepared);
      if (!mounted) return;
      if (success) {
        await _draftStore.clear();
        if (!mounted) return;
        setState(() => _draft = null);
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'انتقال کامل نشد؛ موارد انتخاب‌شده برای «ادامه انتقال» ذخیره شدند.',
            ),
          ),
        );
      }
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
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(34),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PositionedDirectional(
                          start: 24,
                          child: Transform.rotate(
                            angle: -.08,
                            child: const Icon(
                              Icons.phone_android_rounded,
                              size: 70,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_back_rounded, size: 34),
                        PositionedDirectional(
                          end: 24,
                          child: Transform.rotate(
                            angle: .08,
                            child: const Icon(
                              Icons.phone_android_rounded,
                              size: 70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'گوشی قدیمی → گوشی جدید',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'یک مسیر مستقل برای جابه‌جایی گروهی محتوا، بدون قاطی‌شدن با ارسال و دریافت عادی.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.upload_rounded),
                  label: Text('این گوشی قدیمی است'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.download_rounded),
                  label: Text('این گوشی جدید است'),
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
              _MigrationStepHeader(step: _step),
              const SizedBox(height: 16),
              if (_loadingDraft)
                const LinearProgressIndicator()
              else if (_draft != null && _step == 0) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.restore_rounded, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ادامه انتقال قبلی',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text('${_draft!.paths.length} مورد آماده ادامه انتقال'),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: _discardDraft,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      FilledButton.tonal(
                        onPressed: _useDraft,
                        child: const Text('ادامه'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_step == 0) ...[
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'موارد قابل انتقال',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _preparing
                        ? null
                        : () => setState(() {
                              if (_selected.length == _categories.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(_categories);
                              }
                            }),
                    child: Text(
                      _selected.length == _categories.length
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
                children: _categories.map((category) {
                  final selected = _selected.contains(category);
                  return FilterChip(
                    avatar: Icon(_icon(category), size: 18),
                    label: Text(_label(category)),
                    selected: selected,
                    onSelected: _preparing
                        ? null
                        : (_) => setState(() {
                              if (!_selected.add(category)) {
                                _selected.remove(category);
                              }
                            }),
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'برنامه‌ها به‌صورت APK منتقل می‌شوند. داده داخلی برنامه‌ها، حساب‌های واردشده و تنظیمات سیستمی Android قابل کپی مستقیم نیستند.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(() => _step = 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('ادامه و انتخاب محتوا'),
                ),
              ),
              ],
              if (_step == 1) ...[
                const Text(
                  'محتوای هر دسته را انتخاب کن',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'هر بخش را جدا باز کن؛ دیگر انتخاب‌گرها پشت‌سرهم نمایش داده نمی‌شوند.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ..._categories.where(_selected.contains).map((category) {
                  final count = _picked[category]?.length ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: count > 0
                          ? cs.primaryContainer
                          : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      child: ListTile(
                        leading: Icon(_icon(category)),
                        title: Text(
                          _label(category),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          count == 0
                              ? 'هنوز انتخاب نشده'
                              : '${count} مورد انتخاب شده',
                        ),
                        trailing: Icon(
                          count > 0
                              ? Icons.check_circle_rounded
                              : Icons.chevron_left_rounded,
                        ),
                        onTap: _preparing
                            ? null
                            : () => _pickOneCategory(category),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step = 0),
                        child: const Text('قبلی'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _allPickedPaths.isEmpty
                            ? null
                            : _continueToTransfer,
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: Text(
                          _allPickedPaths.isEmpty
                              ? 'اول محتوا انتخاب کن'
                              : 'ادامه • ${_allPickedPaths.length} مورد',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_step == 2 && _prepared.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '${_prepared.length} مورد آماده انتقال',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (_devices.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'گوشی جدید هنوز پیدا نشده. هر دو گوشی را روی یک Wi‑Fi یا Hotspot مشترک بگذار.',
                          textAlign: TextAlign.center,
                        ),
                        if (widget.onRefreshDevices != null) ...[
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            onPressed: widget.onRefreshDevices,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('جستجوی دوباره'),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  ..._devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: _sending ? null : () => _send(device),
                        icon: const Icon(Icons.smartphone_rounded),
                        label: Text(
                          _sending
                              ? 'در حال انتقال…'
                              : 'انتقال به ${device.alias}',
                        ),
                      ),
                    ),
                  ),
              ],
            ] else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.download_for_offline_rounded, size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      'گوشی جدید را آماده کن',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'این حالت فقط برای مهاجرت است. بعد از آماده‌کردن گوشی جدید، گوشی قدیمی آن را پیدا می‌کند و انتقال گروهی را شروع می‌کند.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenReceive();
                      },
                      icon: const Icon(Icons.south_west_rounded),
                      label: const Text('آماده دریافت'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _MigrationStepHeader extends StatelessWidget {
  final int step;

  const _MigrationStepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const titles = ['دسته‌ها', 'محتوا', 'انتقال'];

    return Row(
      children: List.generate(3, (index) {
        final active = index <= step;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? cs.primary : cs.surfaceContainerHighest,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  titles[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        index == step ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
              if (index < 2)
                Container(
                  width: 12,
                  height: 2,
                  color: active ? cs.primary : cs.outlineVariant,
                ),
            ],
          ),
        );
      }),
    );
  }
}
