import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TransferNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  static Future<void> completed({
    required String peer,
    required int filesCount,
  }) async {
    await initialize();
    await _plugin.show(
      id: 2402,
      title: 'ارسال کامل شد',
      body: '$filesCount فایل برای $peer ارسال شد.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'befrest_complete',
          'انتقال‌های تکمیل‌شده',
          channelDescription: 'اعلان پایان انتقال فایل',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  static Future<void> failed({
    required String peer,
  }) async {
    await initialize();
    await _plugin.show(
      id: 2403,
      title: 'انتقال کامل نشد',
      body: 'برخی فایل‌ها برای $peer ارسال نشدند. امکان ادامه انتقال وجود دارد.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'befrest_errors',
          'خطاهای انتقال',
          channelDescription: 'اعلان خطا و ادامه انتقال',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
