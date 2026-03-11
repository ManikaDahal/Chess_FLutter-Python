import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionService {
  static const String _permissionRequestedKey =
      'notification_permission_requested';

  static Future<void> requestPermissionsOnce() async {
    if (!Platform.isAndroid) return;

    final prefs = await SharedPreferences.getInstance();
    final bool alreadyRequested =
        prefs.getBool(_permissionRequestedKey) ?? false;

    if (alreadyRequested) {
      print(
        "PermissionService: Permissions already requested in a previous session. Skipping.",
      );
      return;
    }

    print("PermissionService: Requesting permissions for the first time.");

    // Check battery optimization
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      print("PermissionService: Requesting battery optimization ignore");
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // Check notification permission
    final NotificationPermission notificationPermissionStatus =
        await FlutterForegroundTask.checkNotificationPermission();

    if (notificationPermissionStatus != NotificationPermission.granted) {
      print("PermissionService: Requesting notification permission");
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Mark as requested so it doesn't bother the user again
    await prefs.setBool(_permissionRequestedKey, true);
  }

  static Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await FlutterForegroundTask.checkNotificationPermission();
    return status == NotificationPermission.granted;
  }
}
