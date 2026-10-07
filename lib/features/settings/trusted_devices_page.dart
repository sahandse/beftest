import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    HapticFeedback.selectionClick();
    await _store.revoke(device.fingerprint);
    await _load();
  }

  Future<void> _clear() async {
    HapticFeedback.mediumImpact();
    await _store.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('دستگاه‌های مورداعتماد'),
        actions: [
          if (_devices.isNotEmpty)
            IconButton(
              tooltip: 'پاک کردن همه',
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(34),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: const Icon(
                            Icons.verified_user_outlined,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'هنوز دستگاه مورداعتمادی نداری',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'هنگام دریافت فایل «اعتماد و دریافت» را بزن تا دستگاه اینجا ذخیره شود.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.verified_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.alias,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  device.fingerprint.length > 14
                                      ? '${device.fingerprint.substring(0, 14)}…'
                                      : device.fingerprint,
                                  textDirection: TextDirection.ltr,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'لغو اعتماد',
                            onPressed: () => _revoke(device),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
