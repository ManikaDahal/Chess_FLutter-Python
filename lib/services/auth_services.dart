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
  // CHANGE: Now throws exceptions with specific error messages from backend
  Future<bool> signup(String username, String password, String email) async {
    // CHANGE: Using apiBaseUrl for REST API (Vercel)
    final url = Uri.parse("${Constants.apiBaseUrl}/api/signup/");
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

      // Parse error message from backend
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['error'] != null) {
          throw Exception(errorData['error']);
        }
      } catch (e) {
        // If parsing fails, check for common error patterns
        if (response.body.contains('Username already exists')) {
          throw Exception('Username already exists');
        } else if (response.body.contains('Email already registered')) {
          throw Exception('Email already registered');
        }
      }

      throw Exception('Signup failed. Please try again.');
    }
  }

  //Login
  // CHANGE: Now throws exceptions with specific error messages
  Future<bool> login(String username, String password) async {
    final response = await http.post(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse("${Constants.apiBaseUrl}/api/token/"),
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
        throw Exception('Login failed. Please try again.');
      }
    } else {
      print("Login failed: ${response.body}");

      // Parse error message from backend
      final errorData = jsonDecode(response.body);
      if (errorData['detail'] != null) {
        throw Exception(errorData['detail']);
      }

      // Default error message for invalid credentials
      throw Exception('Invalid username or password');
    }
  }

  //Refresh token
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    final response = await http.post(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/token/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      print("Access token refreshed ${data['access']}");
      return true;
    }

    print("Refresh failed: ${response.body}");
    return false;
  }

  //Logout
  // Future<void> logout() async {
  //   await _storage.deleteAll();

  // }

  //Forgot Password
  Future<bool> forgotPassword({String? email, String? phone}) async {
    final body = <String, String>{};
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    final response = await http.post(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/forgot-password/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
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
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/verify-otp/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'otp': otp.trim()}),
    );

    print("VERIFY OTP RESPONSE: ${response.body}");

    return response.statusCode == 200;
  }

  //Reset Password
  Future<bool> resetPassword(
    String email,
    String new_password,
    String otp,
  ) async {
    final response = await http.post(
      // CHANGE: Using apiBaseUrl for REST API (Vercel)
      Uri.parse('${Constants.apiBaseUrl}/api/reset-password/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'new_password': new_password,
        'otp': otp,
      }),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      print("Password Reset failed ");
      return false;
    }
  }
}
