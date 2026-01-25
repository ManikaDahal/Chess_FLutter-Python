import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:chess_game_manika/services/mqtt_service.dart';
import 'package:chess_game_manika/services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The callback function should be a top-level function or a static function.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MqttForegroundHandler());
}

class MqttForegroundHandler extends TaskHandler {
  SendPort? _sendPort;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;

    // Retrieve user ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final int userId = prefs.getInt('userId') ?? 0;

    if (userId != 0) {
      print('Foreground Service: Connecting global MQTT for user $userId');
      await MqttService().connect(userId);
    } else {
      print('Foreground Service: User ID not found, MQTT not connected');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    final mqtt = MqttService();
    if (!mqtt.isConnected) {
      print(
        'Foreground Service: MQTT disconnected, attempting reconnection...',
      );
      final prefs = await SharedPreferences.getInstance();
      final int userId = prefs.getInt('userId') ?? 0;
      if (userId != 0) {
        await mqtt.connect(userId);
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    MqttService().disconnect();
    print('Foreground Service: Destroyed and MQTT disconnected');
  }

  @override
  void onNotificationPressed() {
    // Handle notification click if needed
    FlutterForegroundTask.launchApp();
  }
}

class ForegroundServiceManager {
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mqtt_foreground_service',
        channelName: 'MQTT Message Service',
        channelDescription:
            'Maintains MQTT connection for real-time notifications',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start(int userId) async {
    // Ensure permissions are requested once
    await PermissionService.requestPermissionsOnce();

    // Save userId to prefs so the background task can access it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', userId);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Chess App Online',
        notificationText: 'Waiting for messages...',
        callback: startCallback,
      );
    }
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
