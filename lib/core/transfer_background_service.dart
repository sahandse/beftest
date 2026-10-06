import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void befrestTransferCallback() {
  FlutterForegroundTask.setTaskHandler(_BefrestTaskHandler());
}

class _BefrestTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

class TransferBackgroundService {
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'befrest_transfer',
        channelName: 'انتقال فایل بفرست',
        channelDescription: 'وضعیت انتقال فایل‌های فعال',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> start({
    required String peer,
    required int filesCount,
  }) async {
    initialize();
    await requestPermission();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'بفرست • انتقال فعال',
        notificationText: '$filesCount فایل برای $peer',
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 2401,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'بفرست • انتقال فعال',
      notificationText: '$filesCount فایل برای $peer',
      callback: befrestTransferCallback,
    );
  }

  static Future<void> updateProgress({
    required String fileName,
    required int sent,
    required int total,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final percent = total <= 0 ? 0 : ((sent / total) * 100).round();
    await FlutterForegroundTask.updateService(
      notificationTitle: 'بفرست • $percent٪',
      notificationText: fileName,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
