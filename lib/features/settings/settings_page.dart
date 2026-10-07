import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    HapticFeedback.selectionClick();
    await widget.settings.setAlias(_alias.text);
    await widget.onNetworkRestart();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('نام دستگاه ذخیره شد')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تنظیمات')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
            children: [
              _SettingsSection(
                title: 'هویت دستگاه',
                child: Column(
                  children: [
                    TextField(
                      controller: _alias,
                      decoration: const InputDecoration(
                        labelText: 'نام دستگاه',
                        hintText: 'مثلاً گوشی من',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      onSubmitted: (_) => _saveAlias(),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _saveAlias,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('ذخیره نام دستگاه'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'امنیت دریافت',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.lock_outline_rounded),
                      ),
                      title: const Text(
                        'PIN برای دریافت',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: const Text(
                        'فرستنده برای شروع انتقال باید کد را وارد کند.',
                      ),
                      value: widget.settings.pinEnabled,
                      onChanged: (value) async {
                        HapticFeedback.selectionClick();
                        await widget.settings.setPinEnabled(value);
                        if (mounted) setState(() {});
                        await widget.onNetworkRestart();
                      },
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 220),
                      crossFadeState: widget.settings.pinEnabled
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox(width: double.infinity),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: _pin,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'PIN شش‌رقمی',
                            prefixIcon: Icon(Icons.password_rounded),
                          ),
                          onChanged: (value) async {
                            await widget.settings.setPin(value);
                            await widget.onNetworkRestart();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'مدیریت',
                child: Column(
                  children: [
                    _SettingsAction(
                      icon: Icons.verified_user_outlined,
                      title: 'دستگاه‌های مورداعتماد',
                      subtitle: 'مدیریت دستگاه‌هایی که سریع پذیرفته می‌شوند',
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
                    _SettingsAction(
                      icon: Icons.delete_sweep_outlined,
                      title: 'پاک‌کردن تاریخچه انتقال',
                      subtitle: 'فایل‌های دریافتی حذف نمی‌شوند',
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        await TransferHistoryStore().clear();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تاریخچه پاک شد')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.wifi_tethering_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'بفرست فقط داخل شبکه محلی کار می‌کند و برای انتقال فایل به سرور اینترنتی وابسته نیست.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.7,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
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
