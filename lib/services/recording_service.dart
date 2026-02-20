import 'dart:async';
import 'dart:io';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/utils/const.dart';
import 'token_storage.dart';
import 'package:path/path.dart' as p;

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
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'chess_call_$timestamp';

      debugPrint('STARTING RECORDING: $fileName');

      // flutter_screen_recording API
      bool started = await FlutterScreenRecording.startRecordScreenAndAudio(
        fileName,
      );

      if (started) {
        _isRecording = true;
        debugPrint('Recording started for room: $roomId');
      } else {
        debugPrint('Failed to start recording');
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _isRecording = false;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      debugPrint('STOPPING RECORDING');
      final String path = await FlutterScreenRecording.stopRecordScreen;
      _isRecording = false;
      _lastRecordingPath = path;
      debugPrint('Recording stopped locally. Path: $path');

      // Upload if we have a path
      if (_lastRecordingPath != null && _currentRoomId != null) {
        // flutter_screen_recording usually returns the full path,
        // but let's double check if it exists
        _uploadRecording(_lastRecordingPath!, _currentRoomId!);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
    }
  }

  Future<void> _uploadRecording(String filePath, String roomId) async {
    try {
      // Delay slightly to ensure file is closed by recorder
      await Future.delayed(const Duration(seconds: 2));

      final File file = File(filePath);
      if (!await file.exists()) {
        debugPrint('Recording file not found at $filePath');
        return;
      }

      final String? token = await _storage.getAccessToken();
      if (token == null) {
        debugPrint('No access token found for upload');
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

      debugPrint('Uploading recording to $uri for room $roomId');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        debugPrint('Recording uploaded successfully');
      } else {
        debugPrint('Upload failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error uploading recording: $e');
    }
  }
}
