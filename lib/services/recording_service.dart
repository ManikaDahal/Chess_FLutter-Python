import 'dart:async';
import 'dart:io';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/utils/const.dart';
import 'token_storage.dart';
import 'package:path/path.dart' as p;
import 'notification_service.dart';

class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  final TokenStorage _storage = TokenStorage();
  bool _isRecording = false;
  String? _lastRecordingPath;
  String? _currentRoomId;

  bool get isRecording => _isRecording;
  String? get lastRecordingPath => _lastRecordingPath;

  Future<void> startRecording(String roomId, {int? width, int? height}) async {
    if (_isRecording) return;
    _currentRoomId = roomId;

    try {
      // Use a more unique filename with room ID and milliseconds
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'chess_${roomId}_$timestamp';

      final Directory? appDocDir = await getApplicationDocumentsDirectory();
      debugPrint('STARTING RECORDING: $fileName');
      if (appDocDir != null) {
        debugPrint(
          'Target Directory for internal reference: ${appDocDir.path}',
        );
      }

      // flutter_screen_recording API
      // Note: Passing fileName only; plugin saves to a default location usually.
      bool started = await FlutterScreenRecording.startRecordScreenAndAudio(
        fileName,
      );

      if (started) {
        _isRecording = true;
        debugPrint('✅ Recording started for room: $roomId');
      } else {
        debugPrint('❌ Failed to start recording');
      }
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      _isRecording = false;
    }
  }

  bool _isStopping = false;

  Future<void> stopRecording() async {
    if (!_isRecording) {
      debugPrint('RecordingService: stopRecording skipped. Not recording.');
      return;
    }
    if (_isStopping) {
      debugPrint('RecordingService: stopRecording skipped. Already stopping.');
      return;
    }

    try {
      _isStopping = true;
      debugPrint('🔴 [RECORDING] Requesting stop from plugin...');

      // Stop the plugin. This triggers the native stop and returns the path.
      final String path = await FlutterScreenRecording.stopRecordScreen;
      _lastRecordingPath = path;
      _isRecording = false; // Set to false only after native stop returns

      debugPrint('✅ [RECORDING] native stop returned. Path: $path');

      if (path.isNotEmpty) {
        // Show recording stop notification
        try {
          NotificationService.showNotification(
            title: "Recording Saved",
            body: "Your call recording has been saved and is being uploaded.",
            payload: {'room_id': _currentRoomId ?? '0'},
          );
        } catch (e) {
          debugPrint('⚠️ Error showing recording notification: $e');
        }

        // Small delay to ensure OS file handles are released
        await Future.delayed(const Duration(milliseconds: 1000));

        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint('📄 [RECORDING] File size finalized: $size bytes');

          if (_currentRoomId != null) {
            debugPrint(
              '⬆️ [RECORDING] Scheduling upload for room: $_currentRoomId',
            );
            _uploadRecording(path, _currentRoomId!);
          }
        } else {
          debugPrint(
            '⚠️ [RECORDING] WARNING: File missing after stop at $path',
          );
        }
      } else {
        debugPrint('⚠️ [RECORDING] WARNING: Plugin returned empty path');
      }
    } catch (e, st) {
      debugPrint('❌ [RECORDING] FATAL STOP ERROR: $e\n$st');
    } finally {
      debugPrint('🏁 [RECORDING] Stop logic completed.');
      _isRecording = false;
      _isStopping = false;
    }
  }

  Future<void> _uploadRecording(String filePath, String roomId) async {
    try {
      // Delay to ensure file is completely written and closed by OS/Plugin
      debugPrint('Waiting 5 seconds before upload to ensure file stability...');
      await Future.delayed(const Duration(seconds: 5));

      final File file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ Upload failed: File not found at $filePath');
        return;
      }

      final String? token = await _storage.getAccessToken();
      if (token == null) {
        debugPrint('❌ Upload failed: No access token found');
        return;
      }

      final uri = Uri.parse('${Constants.videoBaseUrl}/api/call/upload/');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['room_id'] = roomId;

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: p.basename(filePath),
        ),
      );

      debugPrint('⬆️ Uploading ${p.basename(filePath)} to $uri');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ Recording uploaded successfully');
        // Optional: delete local file after success
        // await file.delete();
      } else {
        debugPrint(
          '❌ Upload failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error during upload: $e');
    }
  }
}
