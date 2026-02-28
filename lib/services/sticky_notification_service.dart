import 'master_foreground_service.dart';

class StickyNotificationService {
  static Future<void> initService() async {
    await MasterForegroundService.initService();
  }

  static Future<void> startService() async {
    await MasterForegroundService.startService();
  }

  static Future<void> stopService() async {
    await MasterForegroundService.stopService();
  }

  static Future<void> setRecordingState(bool isRecording) async {
    await MasterForegroundService.updateState(isRecording: isRecording);
  }
}
