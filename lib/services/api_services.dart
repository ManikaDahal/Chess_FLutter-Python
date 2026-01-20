import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/auth_services.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:http/http.dart' as http;

class ApiService {
  final TokenStorage _storage = TokenStorage();
  final AuthServices _authService = AuthServices();

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
}
