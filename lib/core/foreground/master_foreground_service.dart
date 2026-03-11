import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

@pragma('vm:entry-point')
void masterStartCallback() {
  FlutterForegroundTask.setTaskHandler(MasterTaskHandler());
}

class MasterTaskHandler extends TaskHandler {
  int _currentTipIndex = 0;
  bool _isRecording = false;

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
    print("MasterTaskHandler: Started");
    _updateNotification();
  }

  void _updateNotification() {
    final String currentTime = _getCurrentTime();

    if (_isRecording) {
      FlutterForegroundTask.updateService(
        notificationTitle: '🔴 Recording in Progress',
        notificationText: 'Your screen and audio are being recorded.',
      );
    } else {
      final String currentTip = _chessTips[_currentTipIndex];
      FlutterForegroundTask.updateService(
        notificationTitle: '🕐 $currentTime • Chess Daily',
        notificationText: currentTip,
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_isRecording) {
      _currentTipIndex = (_currentTipIndex + 1) % _chessTips.length;
    }
    _updateNotification();
  }

  @override
  void onReceiveData(Object data) {
    if (data is bool) {
      _isRecording = data;
      _updateNotification();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print("MasterTaskHandler: Destroyed");
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp("/");
  }
}

class MasterForegroundService {
  static bool _isInitialized = false;

  static Future<void> initService() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'master_foreground_service',
        channelName: 'Chess App Service',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
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
    if (await FlutterForegroundTask.isRunningService) return;

    await initService();

    // Check permissions
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermissionStatus != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceTypes: [
        ForegroundServiceTypes.microphone,
        ForegroundServiceTypes.mediaProjection,
      ],
      notificationTitle: 'Chess App',
      notificationText: 'Service is running',
      callback: masterStartCallback,
    );
  }

  static Future<void> updateState({required bool isRecording}) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(isRecording);
    } else if (!isRecording) {
      // If we want to start normal tips and it's not running
      await startService();
    }
  }

  static Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }
}
