
import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/transfer_history_store.dart';
import 'trusted_devices_page.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function() onNetworkRestart;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onNetworkRestart,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _alias;
  late final TextEditingController _pin;

  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(text: widget.settings.alias);
    _pin = TextEditingController(text: widget.settings.pin);
  }

  @override
  void dispose() {
    _alias.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _saveAlias() async {
    await widget.settings.setAlias(_alias.text);
    await widget.onNetworkRestart();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('نام دستگاه ذخیره شد')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تنظیمات')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextField(
              controller: _alias,
              decoration: InputDecoration(
                labelText: 'نام دستگاه',
                hintText: 'مثلاً گوشی سهند',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onSubmitted: (_) => _saveAlias(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saveAlias,
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره نام دستگاه'),
            ),
            const SizedBox(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PIN برای دریافت'),
              subtitle: const Text('فرستنده برای شروع انتقال باید کد را وارد کند.'),
              value: widget.settings.pinEnabled,
              onChanged: (value) async {
                await widget.settings.setPinEnabled(value);
                if (mounted) setState(() {});
                await widget.onNetworkRestart();
              },
            ),
            if (widget.settings.pinEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'PIN شش‌رقمی',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onChanged: (value) async {
                  await widget.settings.setPin(value);
                  await widget.onNetworkRestart();
                },
              ),
            ],
            const SizedBox(height: 28),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('دستگاه‌های مورداعتماد'),
              subtitle: const Text('مدیریت دستگاه‌هایی که بدون تأیید دریافت می‌شوند.'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TrustedDevicesPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('پاک‌کردن تاریخچه انتقال'),
              subtitle: const Text('فایل‌های دریافتی حذف نمی‌شوند.'),
              onTap: () async {
                await TransferHistoryStore().clear();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تاریخچه پاک شد')),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'بفرست فقط داخل شبکه محلی کار می‌کند و برای انتقال فایل به سرور اینترنتی وابسته نیست.',
              style: TextStyle(height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}
