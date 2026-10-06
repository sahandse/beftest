import 'package:flutter/material.dart';

import '../../core/trusted_devices_store.dart';

class TrustedDevicesPage extends StatefulWidget {
  const TrustedDevicesPage({super.key});

  @override
  State<TrustedDevicesPage> createState() => _TrustedDevicesPageState();
}

class _TrustedDevicesPageState extends State<TrustedDevicesPage> {
  final _store = TrustedDevicesStore();
  List<TrustedDevice> _devices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devices = await _store.load();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _revoke(TrustedDevice device) async {
    await _store.revoke(device.fingerprint);
    await _load();
  }

  Future<void> _clear() async {
    await _store.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دستگاه‌های مورداعتماد'),
        actions: [
          if (_devices.isNotEmpty)
            IconButton(
              tooltip: 'پاک‌کردن همه',
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 56),
                        SizedBox(height: 14),
                        Text(
                          'هنوز دستگاه مورداعتمادی نداری',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'هنگام دریافت فایل می‌توانی «اعتماد و دریافت» را انتخاب کنی.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(18),
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.verified_user_outlined),
                        ),
                        title: Text(device.alias),
                        subtitle: Text(
                          device.fingerprint.length > 14
                              ? '${device.fingerprint.substring(0, 14)}…'
                              : device.fingerprint,
                          textDirection: TextDirection.ltr,
                        ),
                        trailing: IconButton(
                          tooltip: 'لغو اعتماد',
                          onPressed: () => _revoke(device),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
