import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

// The callback function for the foreground task service.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(StickyTaskHandler());
}

class StickyTaskHandler extends TaskHandler {
  int _currentTipIndex = 0;

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

  static String _getCurrentTime() {
    final now = DateTime.now();
    return DateFormat('h:mm a').format(now);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print("StickyTaskHandler: Started");
    _updateNotification();
  }

  void _updateNotification() {
    final String currentTip = _chessTips[_currentTipIndex];
    final String currentTime = _getCurrentTime();

    FlutterForegroundTask.updateService(
      notificationTitle: '🕐 $currentTime • Chess Daily',
      notificationText: currentTip,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _currentTipIndex = (_currentTipIndex + 1) % _chessTips.length;
    _updateNotification();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print("StickyTaskHandler: Destroyed");
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp("/");
    print("StickyTaskHandler: Notification pressed");
  }
}

class StickyNotificationService {
  static bool _isInitialized = false;

  static Future<void> initService() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sticky_chess_channel',
        channelName: 'Chess Daily',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(120000), // 2 minutes
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  static Future<void> startService() async {
    print("StickyNotificationService: Attempting to start service...");
    await initService();

    // Check permissions again before starting
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      // Optional: request to ignore battery optimizations
    }

    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      print(
        "StickyNotificationService: Notification permission not granted: $notificationPermissionStatus",
      );
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      print("StickyNotificationService: Service is already running");
      // Optional: Update existing service if needed
      return;
    }

    print(
      "StickyNotificationService: Calling FlutterForegroundTask.startService...",
    );
    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle:
            '🕐 ${DateFormat('h:mm a').format(DateTime.now())} • Chess Daily',
        notificationText: "Starting chess tips...",
        callback: startCallback,
      );

      print("StickyNotificationService: Start service result: $result");
    } catch (e, stack) {
      print("StickyNotificationService: Exception in startService: $e");
      print("StickyNotificationService: Stack trace: $stack");
    }
  }

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
    print("StickyNotificationService: Service stopped");
  }
}
