import 'dart:async';
import 'dart:io';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:chess_game_manika/features/notifications/services/sticky_notification_service.dart';
import 'package:permission_handler/permission_handler.dart';



enum RecordingStatus { idle, starting, recording, stopping, saved, failed, uploading }

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final ApiService _apiService = ApiService();

  bool _isRecording = false;
  bool _isStopping = false;
  String? _lastRecordingPath;
  String? _currentRoomId;

  final ValueNotifier<RecordingStatus> statusNotifier =
      ValueNotifier<RecordingStatus>(RecordingStatus.idle);
  bool hasShownRecordingPopup = false;
  bool get isRecording => _isRecording;
  String? get lastRecordingPath => _lastRecordingPath;

  /// Start recording
  Future<void> startRecording(String roomId, {int? width, int? height}) async {
    if (_isRecording) return;

    _currentRoomId = roomId;
    statusNotifier.value = RecordingStatus.starting;

    try {
      debugPrint('RecordingService: Starting recording for room $roomId...');
      
      // --- 1️⃣ STOP sticky notification to avoid double notification during call ---
     await StickyNotificationService.setRecordingState(true);

      // --- 2️⃣ Request permissions ---
      if (Platform.isAndroid) {
        debugPrint('RecordingService: Requesting Android permissions...');
        await _requestAndroidPermissions();
      }

      // --- 3️⃣ Start screen + audio recording ---
      final String fileName = 'rec_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint(
        'RecordingService: Calling FlutterScreenRecording.startRecordScreenAndAudio with fileName: $fileName',
      );

      final bool started =
          await FlutterScreenRecording.startRecordScreenAndAudio(
            fileName,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint(
                'RecordingService: startRecordScreenAndAudio TIMED OUT',
              );
              return false;
            },
          );

      if (started) {
        _isRecording = true;
        statusNotifier.value = RecordingStatus.recording;
        debugPrint(
          '🔴 RecordingService: SUCCESS! Started recording: $fileName',
        );
      } else {
        statusNotifier.value = RecordingStatus.failed;
        debugPrint(
          '❌ RecordingService: FAILED! FlutterScreenRecording returned false',
        );
        // Revert sticky notification on failure
        await StickyNotificationService.setRecordingState(false);
      }
    } catch (e, st) {
      debugPrint('❌ RecordingService: ERROR in startRecording: $e\n$st');
      statusNotifier.value = RecordingStatus.failed;
      // await StickyNotificationService.setRecordingState(false);
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording || _isStopping) return;

    _isStopping = true;
    statusNotifier.value = RecordingStatus.stopping;

    try {
      debugPrint('RecordingService: Stopping recording...');
      final String path = await FlutterScreenRecording.stopRecordScreen;
      _lastRecordingPath = path;
      _isRecording = false;

      // --- 4️⃣ Restart sticky notification command immediately ---
      try {
        await StickyNotificationService.setRecordingState(false);
      } catch (e) {
        debugPrint('⚠️ RecordingService: Error resetting sticky notification: $e');
      }

      if (path.isNotEmpty) {
        statusNotifier.value = RecordingStatus.saved;
        debugPrint('RecordingService: SUCCESS! File saved at $path');

        // Initiate upload in background
        debugPrint('RecordingService: Initiating upload for $path');
        _uploadRecording(path, _currentRoomId ?? '0');
      } else {
        statusNotifier.value = RecordingStatus.failed;
        debugPrint('❌ RecordingService: FAILED! path is empty');
        _showFailureNotification("Recording failed: No file produced.");
      }
    } catch (e, st) {
      debugPrint('❌ RecordingService: ERROR in stopRecording: $e\n$st');
      statusNotifier.value = RecordingStatus.failed;
      _showFailureNotification("Recording failed due to error.");
    } finally {
      _isStopping = false;
      _isRecording = false;
      if (statusNotifier.value != RecordingStatus.saved) {
        statusNotifier.value = RecordingStatus.idle;
      }
      hasShownRecordingPopup = false;
      
      // Fallback reset
      try {
        await StickyNotificationService.setRecordingState(false);
      } catch (_) {}
    }
  }

  /// Request Android permissions safely
  Future<void> _requestAndroidPermissions() async {
    debugPrint('Requesting microphone & media permissions...');
    await Permission.microphone.request();
    if (!await Permission.microphone.isGranted) {
      throw Exception('Microphone permission denied');
    }

    if (await Permission.videos.isDenied || await Permission.audio.isDenied) {
      await [Permission.videos, Permission.audio].request();
    }

    await Permission.storage.request();
    await Future.delayed(
      const Duration(milliseconds: 300),
    ); // brief safety wait
    debugPrint('Permissions granted ✅');
  }

  /// Show failure notification
  void _showFailureNotification(String body) {
    try {
      NotificationService.showNotification(
        title: "Recording Failed",
        body: body,
        payload: {'room_id': _currentRoomId ?? '0', 'error': 'true'},
      );
    } catch (e) {
      debugPrint('⚠️ Error showing failure notification: $e');
    }
  }

  /// Upload recording without blocking main thread
  Future<void> _uploadRecording(String filePath, String roomId) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ Upload error: File not found at $filePath');
        return;
      }

      statusNotifier.value = RecordingStatus.uploading;
      debugPrint('RecordingService: Uploading $filePath to room $roomId...');

      final response = await _apiService.multipartPost(
        '/api/call/upload/',
        filePath: filePath,
        fields: {'room_id': roomId},
        base: ApiBase.render,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Upload successful');
        statusNotifier.value = RecordingStatus.saved;
        
        // Show success snackbar if possible via global context or just log
        // The UI listener will handle the success message
      } else {
        debugPrint(
          '❌ Upload failed: ${response.statusCode} - ${response.data}',
        );
        statusNotifier.value = RecordingStatus.failed;
      }
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      statusNotifier.value = RecordingStatus.failed;
    }
  }
}
