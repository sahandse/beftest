import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

class GroupedPhotosPickerPage extends StatefulWidget {
  const GroupedPhotosPickerPage({super.key});

  @override
  State<GroupedPhotosPickerPage> createState() =>
      _GroupedPhotosPickerPageState();
}

class _GroupedPhotosPickerPageState extends State<GroupedPhotosPickerPage> {
  final Set<String> _selectedIds = {};
  List<AssetEntity> _assets = const [];
  bool _loading = true;
  bool _limited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );

    if (!permission.hasAccess) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'برای انتخاب عکس باید اجازه دسترسی به عکس‌ها را بدهی.';
      });
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    if (paths.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _limited = permission == PermissionState.limited;
        _assets = const [];
      });
      return;
    }

    final path = paths.first;
    final count = await path.assetCountAsync;
    final assets = await path.getAssetListRange(
      start: 0,
      end: count,
    );

    if (!mounted) return;
    setState(() {
      _assets = assets;
      _limited = permission == PermissionState.limited;
      _loading = false;
    });
  }

  String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  String _dayKey(DateTime date) =>
      '${_monthKey(date)}-${date.day.toString().padLeft(2, '0')}';

  String _monthTitle(DateTime date) {
    const months = [
      'ژانویه',
      'فوریه',
      'مارس',
      'آوریل',
      'مه',
      'ژوئن',
      'ژوئیه',
      'اوت',
      'سپتامبر',
      'اکتبر',
      'نوامبر',
      'دسامبر',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _dayTitle(DateTime date) =>
      '${date.day} / ${date.month} / ${date.year}';

  Map<String, List<AssetEntity>> _groupByMonth() {
    final map = <String, List<AssetEntity>>{};
    for (final asset in _assets) {
      final key = _monthKey(asset.createDateTime);
      map.putIfAbsent(key, () => []).add(asset);
    }
    return map;
  }

  Map<String, List<AssetEntity>> _groupByDay(List<AssetEntity> assets) {
    final map = <String, List<AssetEntity>>{};
    for (final asset in assets) {
      final key = _dayKey(asset.createDateTime);
      map.putIfAbsent(key, () => []).add(asset);
    }
    return map;
  }

  void _toggle(AssetEntity asset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.add(asset.id)) {
        _selectedIds.remove(asset.id);
      }
    });
  }

  void _toggleGroup(List<AssetEntity> assets) {
    HapticFeedback.lightImpact();
    final allSelected =
        assets.every((asset) => _selectedIds.contains(asset.id));
    setState(() {
      if (allSelected) {
        for (final asset in assets) {
          _selectedIds.remove(asset.id);
        }
      } else {
        for (final asset in assets) {
          _selectedIds.add(asset.id);
        }
      }
    });
  }

  Future<void> _reselectLimited() async {
    await PhotoManager.presentLimited(type: RequestType.image);
    if (!mounted) return;
    setState(() {
      _loading = true;
      _assets = const [];
      _selectedIds.clear();
    });
    await _load();
  }

  Future<void> _finish() async {
    if (_selectedIds.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('در حال آماده‌سازی عکس‌ها…')),
            ],
          ),
        ),
      ),
    );

    final paths = <String>[];
    try {
      for (final asset in _assets) {
        if (!_selectedIds.contains(asset.id)) continue;
        final file = await asset.file;
        if (file != null && await file.exists()) {
          paths.add(file.path);
        }
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;
    Navigator.pop(context, paths);
  }

  @override
  Widget build(BuildContext context) {
    final months = _groupByMonth();

    return Scaffold(
      appBar: AppBar(
        title: const Text('عکس‌ها'),
        actions: [
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton.tonal(
                onPressed: _finish,
                child: Text('ارسال ${_selectedIds.length} عکس'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _PermissionError(
                  message: _error!,
                  onSettings: PhotoManager.openSetting,
                )
              : Column(
                  children: [
                    if (_limited)
                      MaterialBanner(
                        content: const Text(
                          'فقط به بخشی از عکس‌ها دسترسی داری.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: _reselectLimited,
                            child: const Text('انتخاب عکس‌های بیشتر'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: months.isEmpty
                          ? const Center(
                              child: Text('عکسی برای نمایش پیدا نشد'),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                              children: [
                                for (final month in months.entries)
                                  _MonthSection(
                                    assets: month.value,
                                    title: _monthTitle(
                                      month.value.first.createDateTime,
                                    ),
                                    selectedIds: _selectedIds,
                                    dayTitle: _dayTitle,
                                    groupByDay: _groupByDay,
                                    onToggleAsset: _toggle,
                                    onToggleGroup: _toggleGroup,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  final List<AssetEntity> assets;
  final String title;
  final Set<String> selectedIds;
  final String Function(DateTime) dayTitle;
  final Map<String, List<AssetEntity>> Function(List<AssetEntity>) groupByDay;
  final ValueChanged<AssetEntity> onToggleAsset;
  final ValueChanged<List<AssetEntity>> onToggleGroup;

  const _MonthSection({
    required this.assets,
    required this.title,
    required this.selectedIds,
    required this.dayTitle,
    required this.groupByDay,
    required this.onToggleAsset,
    required this.onToggleGroup,
  });

  @override
  Widget build(BuildContext context) {
    final days = groupByDay(assets);
    final allSelected =
        assets.every((asset) => selectedIds.contains(asset.id));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${assets.length} عکس'),
        trailing: TextButton.icon(
          onPressed: () => onToggleGroup(assets),
          icon: Icon(
            allSelected
                ? Icons.check_box_rounded
                : Icons.select_all_rounded,
          ),
          label: Text(allSelected ? 'لغو ماه' : 'انتخاب ماه'),
        ),
        children: [
          for (final day in days.entries)
            _DaySection(
              assets: day.value,
              title: dayTitle(day.value.first.createDateTime),
              selectedIds: selectedIds,
              onToggleAsset: onToggleAsset,
              onToggleGroup: onToggleGroup,
            ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  final List<AssetEntity> assets;
  final String title;
  final Set<String> selectedIds;
  final ValueChanged<AssetEntity> onToggleAsset;
  final ValueChanged<List<AssetEntity>> onToggleGroup;

  const _DaySection({
    required this.assets,
    required this.title,
    required this.selectedIds,
    required this.onToggleAsset,
    required this.onToggleGroup,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected =
        assets.every((asset) => selectedIds.contains(asset.id));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => onToggleGroup(assets),
                child: Text(allSelected ? 'لغو روز' : 'انتخاب روز'),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 800
                  ? 8
                  : constraints.maxWidth >= 560
                      ? 6
                      : 4;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: assets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                ),
                itemBuilder: (context, index) {
                  final asset = assets[index];
                  final selected = selectedIds.contains(asset.id);
                  return _AssetTile(
                    asset: asset,
                    selected: selected,
                    onTap: () => onToggleAsset(asset),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                const ThumbnailSize.square(220),
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: const Icon(Icons.image_outlined),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
          ),
          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
          PositionedDirectional(
            top: 5,
            end: 5,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black54,
              child: Icon(
                selected ? Icons.check_rounded : Icons.circle_outlined,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionError extends StatelessWidget {
  final String message;
  final Future<void> Function() onSettings;

  const _PermissionError({
    required this.message,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 56),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: onSettings,
              child: const Text('تنظیمات دسترسی'),
            ),
          ],
        ),
      ),
    );
  }
}
