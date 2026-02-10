import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

class StickyNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int _stickyNotificationId = 999999;
  static bool _isInitialized = false;
  static Timer? _updateTimer;
  static int _currentTipIndex = 0;

  static final List<String> _chessTips = [
    "Control the center of the board 🎯",
    "Develop your pieces early ♟️",
    "Don't move the same piece twice in opening 🔄",
    "Castle early to protect your king 🏰",
    "Connect your rooks 🔗",
    "Think before you move ⏱️",
    "Control key squares 📍",
    "Don't bring your queen out too early 👑",
    "Look for tactical opportunities 👀",
    "Always check for checks! ✓",
  ];

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

    // Show initial notification
    await _showNotificationWithTip();

    // Start timer to update notification every 5 minutes (to keep time fresh)
    _updateTimer?.cancel(); // Cancel any existing timer
    _updateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      // Change tip every hour (12 updates = 1 hour)
      if (timer.tick % 12 == 0) {
        _currentTipIndex = (_currentTipIndex + 1) % _chessTips.length;
      }
      _showNotificationWithTip();
    });

    print(
      "StickyNotificationService: Dynamic updates enabled (every 5 minutes)",
    );
  }

  static String _getCurrentTime() {
    final now = DateTime.now();
    return DateFormat('h:mm a').format(now); // e.g., "3:45 PM"
  }

  static Future<void> _showNotificationWithTip() async {
    final String currentTip = _chessTips[_currentTipIndex];
    final String currentTime = _getCurrentTime();

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
      title: '🕐 $currentTime • Chess Daily',
      body: currentTip,
      notificationDetails: platformDetails,
    );
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
    _updateTimer?.cancel();
    _updateTimer = null;
    await _notificationsPlugin.cancel(id: _stickyNotificationId);
  }
}
