import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/services/auth_services.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';

import 'package:http/http.dart' as http;

class ApiService {
  final TokenStorage _storage = TokenStorage();

  /// Authenticated GET with automatic token refresh
  Future<http.Response> _authenticatedGet(Uri uri) async {
    final token = await _storage.getAccessToken();
    var response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 401) {
      print("ApiService: 401 Unauthorized. Attempting token refresh...");
      final refreshed = await AuthServices().refreshToken();
      if (refreshed) {
        final newToken = await _storage.getAccessToken();
        print("ApiService: Token refreshed. Retrying request...");
        response = await http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $newToken',
          },
        );
      }
    }
    return response;
  }

  /// Authenticated POST with automatic token refresh
  Future<http.Response> _authenticatedPost(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final token = await _storage.getAccessToken();
    var response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      print(
        "ApiService: 401 Unauthorized on POST. Attempting token refresh...",
      );
      final refreshed = await AuthServices().refreshToken();
      if (refreshed) {
        final newToken = await _storage.getAccessToken();
        print("ApiService: Token refreshed. Retrying POST...");
        response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $newToken',
          },
          body: jsonEncode(body),
        );
      }
    }
    return response;
  }

  /// PROFILE
  Future<Map<String, dynamic>> getProfile() async {
    final response = await _authenticatedGet(
      Uri.parse('${Constants.apiBaseUrl}/api/profile/'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Profile failed [${response.statusCode}]");
    }
  }

  Future<List<dynamic>> getUsers() async {
    final response = await _authenticatedGet(
      Uri.parse('${Constants.apiBaseUrl}/api/users/'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch users [${response.statusCode}]");
    }
  }

  Future<List<dynamic>> getChatMessages(int roomId) async {
    // Note: Using the Render server URL but with https (not wss) for REST
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );
    final response = await _authenticatedGet(
      Uri.parse('$renderUrl/api/chat/history/$roomId/'),
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

    final response = await _authenticatedPost(
      Uri.parse('$renderUrl/api/chat/get_or_create_room/'),
      {"user1_id": user1Id, "user2_id": user2Id},
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
    final response = await _authenticatedPost(
      Uri.parse('${Constants.apiBaseUrl}/api/register-fcm-token/'),
      {"token": token},
    );

    if (response.statusCode == 200) {
      print("FCM Dashboard: Token registered successfully on backend (Vercel)");
    } else {
      print(
        "FCM Dashboard: Failed to register token: ${response.statusCode} - ${response.body}",
      );
    }
  }

  Future<void> updateNotificationStatus(String messageId, String status) async {
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );
    final response = await _authenticatedPost(
      Uri.parse('$renderUrl/api/notifications/update-status/'),
      {"message_id": messageId, "status": status},
    );

    if (response.statusCode == 200) {
      print("FCM: Notification status updated to $status");
    } else {
      print(
        "FCM ERROR: Failed to update notification status: ${response.body}",
      );
    }
  }
}
