import 'dart:convert';
import 'package:chess_game_manika/core/api/api_services.dart';

class VoiceService {
  final ApiService _apiService = ApiService();

  /// Check if the user has a trained voice clone
  Future<Map<String, dynamic>> getVoiceStatus() async {
    try {
      final response = await _apiService.get('/api/voice/status/', base: ApiBase.render);

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
      final response = await _apiService.multipartPost(
        '/api/voice/upload-samples/', 
        filePaths: filePaths, 
        fileKey: 'samples',
        base: ApiBase.render
      );

      print('DEBUG: [VOICE] Upload Status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('DEBUG: [VOICE] Error uploading samples: $e');
      return false;
    }
  }

  /// Send message to AI and receive text + audio reference
  Future<Map<String, dynamic>?> chatWithSelf(String message) async {
    try {
      final response = await _apiService.post(
        '/api/voice/chat-self/', 
        {"message": message}, 
        base: ApiBase.render
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('DEBUG: [VOICE] Error in chat: $e');
    }
    return null;
  }

  /// Delete voice profile and all recorded samples
  Future<bool> deleteVoiceProfile() async {
    try {
      final response = await _apiService.delete('/api/voice/delete-profile/', base: ApiBase.render);
      return response.statusCode == 200;
    } catch (e) {
      print('DEBUG: [VOICE] Error deleting profile: $e');
      return false;
    }
  }
}
