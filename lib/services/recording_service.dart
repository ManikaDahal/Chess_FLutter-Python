import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import '../core/utils/const.dart';
import 'notification_service.dart';
import 'token_storage.dart';

enum RecordingStatus { idle, starting, recording, stopping, saved, failed }

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final TokenStorage _storage = TokenStorage();

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
      // --- 1️⃣ Update sticky notification to recording state ---
      // await StickyNotificationService.setRecordingState(true);

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
        // await StickyNotificationService.setRecordingState(false);
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

      debugPrint('RecordingService: stopRecordScreen returned path: "$path"');

      if (path.isNotEmpty) {
        statusNotifier.value = RecordingStatus.saved;
        debugPrint('RecordingService: SUCCESS! File saved at $path');

        // Show recording saved notification
        NotificationService.showNotification(
          title: "Recording Saved",
          body: "Your call recording has been saved.",
          payload: {'room_id': _currentRoomId ?? '0'},
        );

        // Upload recording in background
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
      // Reset flag so subsequent calls can show the recording prompt
      hasShownRecordingPopup = false;

      // --- 4️⃣ Revert sticky notification state ---
      // await StickyNotificationService.setRecordingState(false);
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
      if (!await file.exists()) return;

      final String? token = await _storage.getAccessToken();
      if (token == null) return;

      final uri = Uri.parse('${Constants.videoBaseUrl}/api/call/upload/');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['room_id'] = roomId
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: p.basename(filePath),
          ),
        );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Upload successful');
      } else {
        debugPrint(
          '❌ Upload failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Upload error: $e');
    }
  }
}
