import 'dart:convert';
import 'package:chess_python/core/utils/const.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class AuthServices {
  final TokenStorage _storage = TokenStorage();

  //Signup
  Future<bool> signup(String username, String password, String email) async {
    final url = Uri.parse("${Constants.baseUrl}/api/signup/");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'email': email,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      await _storage.saveRefreshToken(data['refresh']);
      return true;
    } else {
      print("Signup Failed:${response.body}");
      return false;
    }
  }

  //Login
  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse("${Constants.baseUrl}/api/token/"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['access'] != null && data['refresh'] != null) {
        print("Login response : $response");

        await _storage.saveAccessToken(data['access']);
        await _storage.saveRefreshToken(data['refresh']);

        print("Access token saved: ${data['access']}");
        String? token = await _storage.getAccessToken();
        print("Stored token after login: $token");
        final access = await _storage.getAccessToken();
        final refresh = await _storage.getRefreshToken();
        print("Access token read immediately after saving: $access");
        print("Refresh token read immediately after saving: $refresh");

        return true;
      } else {
        print("Login api didnot return token");
      }
    } else {
      print("Login failed: ${response.body}");
      return false;
    }
    return false;
  }

  //Refresh token
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    final response = await http.post(
      Uri.parse('${Constants.baseUrl}/api/token/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      return true;
    }

    print("Refresh failed: ${response.body}");
    return false;
  }

  //Logout
  Future<void> logout() async {
    await _storage.deleteAll();
  }

  //Forgot Password
  Future<bool> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('${Constants.baseUrl}/api/forgot-password/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      print("OTP sending failed : ${response.body}");
      return false;
    }
  }

  //Verify OTP
  Future<bool> verifyOtp(String email, String otp) async {
    final response = await http.post(
      Uri.parse('${Constants.baseUrl}/api/verify-otp/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'otp': otp}),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      print("OTP verification failed : ${response.body}");
      return false;
    }
  }

  //Reset Password
  Future<bool> resetPassword(String email, String password) async {
    final response = await http.post(
      Uri.parse('${Constants.baseUrl}/api/reset-password/'),
      headers: {'Content-Type': 'applicatio/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      print("Password Reset failed ");
      return false;
    }
  }
}
