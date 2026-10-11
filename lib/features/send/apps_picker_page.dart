import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

enum _AppFilter { all, recent, large, selected }

class AppsPickerPage extends StatefulWidget {
  const AppsPickerPage({super.key});

  @override
  State<AppsPickerPage> createState() => _AppsPickerPageState();
}

class _AppsPickerPageState extends State<AppsPickerPage> {
  static const _channel = MethodChannel('ir.befrest/app_export');

  List<AppInfo> _apps = const [];
  bool _loading = true;
  String _query = '';
  final Set<String> _selectedPackages = <String>{};
  bool _exporting = false;
  int _exportedCount = 0;
  _AppFilter _filter = _AppFilter.all;
  final Map<String, int> _apkSizes = <String, int>{};
  bool _showSelectedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      excludeNonLaunchableApps: true,
      withIcon: true,
    );

    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
    await _loadApkSizes(apps);
  }

  Future<void> _loadApkSizes(List<AppInfo> apps) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getApkSizes',
        {
          'packages': apps.map((app) => app.packageName).toList(growable: false),
        },
      );
      if (!mounted || raw == null) return;
      setState(() {
        _apkSizes
          ..clear()
          ..addEntries(
            raw.entries.map(
              (entry) => MapEntry(
                entry.key.toString(),
                (entry.value as num?)?.toInt() ?? 0,
              ),
            ),
          );
      });
    } catch (_) {}
  }

  String _sizeText(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  void _toggle(AppInfo app) {
    if (_exporting) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedPackages.add(app.packageName)) {
        _selectedPackages.remove(app.packageName);
      }
    });
  }

  void _selectVisible(List<AppInfo> visible) {
    if (_exporting || visible.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final allSelected = visible.every(
        (app) => _selectedPackages.contains(app.packageName),
      );
      if (allSelected) {
        for (final app in visible) {
          _selectedPackages.remove(app.packageName);
        }
      } else {
        for (final app in visible) {
          _selectedPackages.add(app.packageName);
        }
      }
    });
  }

  Future<void> _finish() async {
    if (_selectedPackages.isEmpty || _exporting) return;

    final selected = _apps
        .where((app) => _selectedPackages.contains(app.packageName))
        .toList(growable: false);

    setState(() {
      _exporting = true;
      _exportedCount = 0;
    });

    final paths = <String>[];
    try {
      for (final app in selected) {
        final path = await _channel.invokeMethod<String>(
          'exportApk',
          {
            'packageName': app.packageName,
            'label': app.name,
            'version': app.versionName,
          },
        );
        if (path != null && path.isNotEmpty) {
          paths.add(path);
        }
        if (mounted) {
          setState(() => _exportedCount++);
        }
      }

      if (!mounted) return;
      if (paths.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('APK برنامه‌های انتخاب‌شده قابل آماده‌سازی نبود.'),
          ),
        );
        return;
      }
      Navigator.pop(context, paths);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('آماده‌سازی بعضی برنامه‌ها انجام نشد.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final searched = query.isEmpty
        ? _apps
        : _apps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(query) ||
                  app.packageName.toLowerCase().contains(query),
            )
            .toList(growable: false);
    final visible = _showSelectedOnly
        ? searched
            .where(
              (app) => _selectedPackages.contains(app.packageName),
            )
            .toList(growable: false)
        : searched;

    return Scaffold(
      appBar: AppBar(
        title: const Text('برنامه‌ها'),
        actions: [
          if (_selectedPackages.isNotEmpty && !_exporting)
            TextButton(
              onPressed: () => setState(_selectedPackages.clear),
              child: const Text('پاک کردن'),
            ),
        ],
      ),
      bottomNavigationBar: _selectedPackages.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.icon(
                onPressed: _exporting ? null : _finish,
                icon: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _exporting
                      ? 'آماده‌سازی $_exportedCount از ${_selectedPackages.length}'
                      : 'انتخاب ${_selectedPackages.length} برنامه',
                ),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: TextField(
                enabled: !_exporting,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'جستجوی برنامه',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('همه'),
                    selected: !_showSelectedOnly,
                    onSelected: _exporting
                        ? null
                        : (_) => setState(() => _showSelectedOnly = false),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'انتخاب‌شده‌ها (${_selectedPackages.length})',
                    ),
                    selected: _showSelectedOnly,
                    onSelected: _exporting
                        ? null
                        : (_) => setState(() => _showSelectedOnly = true),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _exporting || _apps.isEmpty
                        ? null
                        : () => setState(() {
                              _selectedPackages
                                ..clear()
                                ..addAll(
                                  _apps.map((app) => app.packageName),
                                );
                              _showSelectedOnly = true;
                            }),
                    child: const Text('انتخاب همه'),
                  ),
                ],
              ),
            ),
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _AppFilterChip(
                            label: 'همه',
                            selected: _filter == _AppFilter.all,
                            onTap: () => setState(() => _filter = _AppFilter.all),
                          ),
                          const SizedBox(width: 7),
                          _AppFilterChip(
                            label: 'جدیدها',
                            selected: _filter == _AppFilter.recent,
                            onTap: () =>
                                setState(() => _filter = _AppFilter.recent),
                          ),
                          const SizedBox(width: 7),
                          _AppFilterChip(
                            label: 'حجم بالا',
                            selected: _filter == _AppFilter.large,
                            onTap: () => setState(() => _filter = _AppFilter.large),
                          ),
                          const SizedBox(width: 7),
                          _AppFilterChip(
                            label: 'انتخاب‌شده',
                            selected: _filter == _AppFilter.selected,
                            onTap: () =>
                                setState(() => _filter = _AppFilter.selected),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${visible.length} برنامه',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: visible.isEmpty || _exporting
                              ? null
                              : () => _selectVisible(visible),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: Text(
                            visible.isNotEmpty &&
                                    visible.every(
                                      (app) => _selectedPackages
                                          .contains(app.packageName),
                                    )
                                ? 'لغو انتخاب همه'
                                : 'انتخاب همه',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? const Center(
                          child: Text('برنامه‌ای برای نمایش پیدا نشد'),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final app = visible[index];
                            final selected =
                                _selectedPackages.contains(app.packageName);
                            final cs = Theme.of(context).colorScheme;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: selected
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                                child: InkWell(
                                onTap: _exporting ? null : () => _toggle(app),
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      _AppIcon(bytes: app.icon),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              app.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'نسخه ${app.versionName} • ${_sizeText(_apkSizes[app.packageName] ?? 0)}\n${app.packageName}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textDirection:
                                                  TextDirection.ltr,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.circle_outlined,
                                        color: selected ? cs.primary : null,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final Uint8List? bytes;

  const _AppIcon({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final data = bytes;
    if (data == null || data.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.android_rounded));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        data,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const CircleAvatar(child: Icon(Icons.android_rounded)),
      ),
    );
  }
}


class _AppFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AppFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
    );
  }
}
