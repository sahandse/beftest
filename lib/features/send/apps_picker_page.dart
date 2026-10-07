import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

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
    final visible = query.isEmpty
        ? _apps
        : _apps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(query) ||
                  app.packageName.toLowerCase().contains(query),
            )
            .toList(growable: false);

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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
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
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${app.versionName} • ${app.packageName}',
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
