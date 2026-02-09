import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class StickyNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int _stickyNotificationId = 999999;
  static bool _isInitialized = false;

  static Future<void> initService() async {
    print("StickyNotificationService: Initializing...");

    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        print("StickyNotificationService: Notification tapped");
      },
    );

    // Create the sticky notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sticky_chess_channel',
      'Chess Daily',
      description: 'Persistent notification for chess tips',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
      print("StickyNotificationService: Channel created");
    }

    _isInitialized = true;
  }

  static Future<void> startService() async {
    print("StickyNotificationService: Starting sticky notification...");

    await initService();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'sticky_chess_channel',
          'Chess Daily',
          channelDescription: 'Persistent notification for chess tips',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // This makes it sticky
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
          playSound: false,
          enableVibration: false,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: _stickyNotificationId,
      title: 'Chess Daily',
      body: 'Ready for a game? Tap to play!',
      notificationDetails: platformDetails,
    );

    print("StickyNotificationService: Sticky notification shown");
  }

  static Future<void> updateNotification(String title, String message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'sticky_chess_channel',
          'Chess Daily',
          channelDescription: 'Persistent notification for chess tips',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
          playSound: false,
          enableVibration: false,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: _stickyNotificationId,
      title: title,
      body: message,
      notificationDetails: platformDetails,
    );
  }

  static Future<void> stopService() async {
    print("StickyNotificationService: Stopping sticky notification...");
    await _notificationsPlugin.cancel(id: _stickyNotificationId);
  }
}
