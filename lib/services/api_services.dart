import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:http/http.dart' as http;

class ApiService {
  final TokenStorage _storage = TokenStorage();

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getAccessToken();
    print('Token before profile call: $token');

    if (token == null) throw Exception('Access token missing');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// PROFILE
  Future<Map<String, dynamic>> getProfile() async {
    final token = await _storage.getAccessToken();

    print("Token used for profile: $token");

    final response = await http.get(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/profile/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    print("Profile status: ${response.statusCode}");
    print("Profile raw body: ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Profile failed");
    }
  }

  Future<List<dynamic>> getUsers() async {
    final token = await _storage.getAccessToken();
    final response = await http.get(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/users/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch users");
    }
  }

  Future<List<dynamic>> getChatMessages(int roomId) async {
    // Note: Using the Render server URL but with https (not wss) for REST
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );
    final response = await http.get(
      Uri.parse('$renderUrl/api/chat/history/$roomId/'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print("Failed to fetch chat history: ${response.body}");
      return []; // Return empty list on failure to avoid crashing
    }
  }

  Future<int?> getOrCreateChatRoom(int user1Id, int user2Id) async {
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );
    final response = await http.post(
      Uri.parse('$renderUrl/api/chat/get_or_create_room/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"user1_id": user1Id, "user2_id": user2Id}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['room_id'];
    } else {
      print("Failed to get/create chat room: ${response.body}");
      return null;
    }
  }

  Future<void> registerFcmToken(String token) async {
    final headers = await _headers();
    final response = await http.post(
      Uri.parse('${Constants.apiBaseUrl}/api/register-fcm-token/'),
      headers: headers,
      body: jsonEncode({"token": token}),
    );

    if (response.statusCode == 200) {
      print("FCM: Token registered successfully on backend");
    } else {
      print("FCM: Failed to register token: ${response.body}");
    }
  }
}
