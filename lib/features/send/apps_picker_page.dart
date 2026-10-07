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
  String? _exportingPackage;

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

  Future<void> _select(AppInfo app) async {
    if (_exportingPackage != null) return;
    setState(() => _exportingPackage = app.packageName);

    try {
      final path = await _channel.invokeMethod<String>(
        'exportApk',
        {
          'packageName': app.packageName,
          'label': app.name,
          'version': app.versionName,
        },
      );

      if (!mounted) return;
      if (path == null || path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل APK این برنامه قابل خواندن نیست.')),
        );
        return;
      }

      Navigator.pop(context, path);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('آماده‌سازی APK انجام نشد.')),
      );
    } finally {
      if (mounted) setState(() => _exportingPackage = null);
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
      appBar: AppBar(title: const Text('برنامه‌ها')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: TextField(
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
                            final exporting =
                                _exportingPackage == app.packageName;
                            final cs = Theme.of(context).colorScheme;
                            return Material(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                onTap: exporting
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        _select(app);
                                      },
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
                                      if (exporting)
                                        const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: cs.primaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(15),
                                          ),
                                          child: const Icon(
                                            Icons.north_east_rounded,
                                            size: 20,
                                          ),
                                        ),
                                    ],
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
