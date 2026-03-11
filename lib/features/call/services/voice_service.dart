import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';

class VoiceService {
  final TokenStorage _storage = TokenStorage();

  // Use Render base URL for AI Voice endpoints
  String get _baseUrl => Constants.videoBaseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getAccessToken();
    return {'Authorization': 'Bearer $token'};
  }

  /// Check if the user has a trained voice clone
  Future<Map<String, dynamic>> getVoiceStatus() async {
    try {
      final headers = await _headers();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/voice/status/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('DEBUG: [VOICE] Error getting status: $e');
    }
    return {"is_trained": false};
  }

  /// Upload multiple voice samples to train the clone
  Future<bool> uploadVoiceSamples(List<String> filePaths) async {
    try {
      final token = await _storage.getAccessToken();
      final uri = Uri.parse('$_baseUrl/api/voice/upload-samples/');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      for (var path in filePaths) {
        final file = await http.MultipartFile.fromPath(
          'samples',
          path,
          filename: basename(path),
        );
        request.files.add(file);
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamedResponse);

      print('DEBUG: [VOICE] Upload Status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } on TimeoutException {
      print('DEBUG: [VOICE] Upload timed out');
      return false;
    } catch (e) {
      print('DEBUG: [VOICE] Error uploading samples: $e');
      return false;
    }
  }

  /// Send message to AI and receive text + audio reference
  Future<Map<String, dynamic>?> chatWithSelf(String message) async {
    try {
      final token = await _storage.getAccessToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/api/voice/chat-self/'),
        headers: headers,
        body: jsonEncode({"message": message}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('DEBUG: [VOICE] Chat failed: ${response.statusCode}');
        print('DEBUG: [VOICE] Body: ${response.
        body}');
      }
    } catch (e) {
      print('DEBUG: [VOICE] Error in chat: $e');
    }
    return null;
  }

  /// Delete voice profile and all recorded samples
  Future<bool> deleteVoiceProfile() async {
    try {
      final headers = await _headers();
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/voice/delete-profile/'),
        headers: headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      print('DEBUG: [VOICE] Error deleting profile: $e');
      return false;
    }
  }
}
