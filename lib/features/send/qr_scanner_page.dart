import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../network/nearby_device.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _handled = false;

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
      body: Stack(
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
