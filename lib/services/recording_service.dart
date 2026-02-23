import 'dart:async';
import 'dart:io';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/utils/const.dart';
import 'token_storage.dart';
import 'package:path/path.dart' as p;
import 'sticky_notification_service.dart';

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
    if (!_isRecording || _isStopping) {
      debugPrint(
        'RecordingService: stopRecording skipped. Recording: $_isRecording, Stopping: $_isStopping',
      );
      return;
    }

    try {
      _isStopping = true;
      debugPrint('STOPPING RECORDING...');
      _isRecording = false;

      // Force stop via plugin - this is what clears the "Screen is being recorded" notification
      final String path = await FlutterScreenRecording.stopRecordScreen;
      _lastRecordingPath = path;
      debugPrint('✅ Recording stopped. Resulting Path: $path');

      // Small delay to ensure file is flushed
      await Future.delayed(const Duration(milliseconds: 500));

      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint('📄 Recording file size: $size bytes');

          // Upload if we have a path and room ID
          if (_currentRoomId != null) {
            _uploadRecording(path, _currentRoomId!);
          }
        } else {
          debugPrint('⚠️ Recording file does not exist at path: $path');
        }
      }
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
    } finally {
      _isRecording = false;
      _isStopping = false;
    }
  }

  Future<void> _uploadRecording(String filePath, String roomId) async {
    try {
      // Delay to ensure file is completely written and closed by OS/Plugin
      debugPrint('Waiting 2 seconds before upload to ensure file stability...');
      await Future.delayed(const Duration(seconds: 2));

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
