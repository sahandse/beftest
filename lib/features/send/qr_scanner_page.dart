import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../network/nearby_device.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _handled = false;
  bool _checkingPermission = true;
  bool _cameraGranted = false;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _requestCameraForScanner();
  }

  Future<void> _requestCameraForScanner() async {
    if (!mounted) return;
    setState(() => _checkingPermission = true);

    final status = await Permission.camera.request();
    if (!mounted) return;

    setState(() {
      _checkingPermission = false;
      _cameraGranted = status.isGranted;
      _permanentlyDenied = status.isPermanentlyDenied;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['app'] != 'befrest') {
        _showInvalid();
        return;
      }

      final ip = (data['ip'] ?? '').toString();
      final fingerprint = (data['fingerprint'] ?? '').toString();
      if (ip.isEmpty || fingerprint.isEmpty) {
        _showInvalid();
        return;
      }

      _handled = true;
      final features = ((data['features'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false);

      final device = NearbyDevice(
        alias: (data['alias'] ?? 'دستگاه بفرست').toString(),
        ip: ip,
        port: int.tryParse('${data['port'] ?? 53317}') ?? 53317,
        type: DeviceType.mobile,
        fingerprint: fingerprint,
        supportsResume: features.contains('resume-v1'),
        supportsAppUpdates: features.contains('app-updates-v1'),
      );

      Navigator.pop(context, device);
    } catch (_) {
      _showInvalid();
    }
  }

  void _showInvalid() {
    if (_handled) return;
    _handled = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('این QR مربوط به بفرست نیست یا ناقص است.')),
    );
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _handled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اسکن QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _checkingPermission
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : !_cameraGranted
              ? _CameraPermissionState(
                  permanentlyDenied: _permanentlyDenied,
                  onRetry: _requestCameraForScanner,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      onDetect: _onDetect,
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 24,
                      right: 24,
                      bottom: 42,
                      child: Text(
                        'QR دستگاه مقصد را داخل کادر بگیر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}


class _CameraPermissionState extends StatelessWidget {
  final bool permanentlyDenied;
  final Future<void> Function() onRetry;

  const _CameraPermissionState({
    required this.permanentlyDenied,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 58,
            ),
            const SizedBox(height: 16),
            const Text(
              'برای اسکن QR به دوربین نیاز است',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              permanentlyDenied
                  ? 'دسترسی دوربین خاموش شده؛ از تنظیمات برنامه آن را فعال کن.'
                  : 'فقط هنگام اسکن QR از دوربین استفاده می‌شود.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: permanentlyDenied
                  ? () async => openAppSettings()
                  : onRetry,
              icon: Icon(
                permanentlyDenied
                    ? Icons.settings_rounded
                    : Icons.camera_alt_rounded,
              ),
              label: Text(
                permanentlyDenied ? 'باز کردن تنظیمات' : 'اجازه دوربین',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
