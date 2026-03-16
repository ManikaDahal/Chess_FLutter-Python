import 'dart:convert';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthServices {
  final ApiService _apiService = ApiService();
  final TokenStorage _storage = TokenStorage();

  //Signup
  Future<bool> signup(String username, String password, String email) async {
    final response = await _apiService.signup(username, password, email);

    if (response.statusCode == 201) {
      final data = response.data;
      await _storage.saveAccessToken(data['access']);
      await _storage.saveRefreshToken(data['refresh']);

      // Register FCM token
      _registerFCM();

      return true;
    } else {
      print("Signup Failed:${response.data}");

      // Parse error message from backend
      try {
        final errorData = response.data;
        if (errorData['error'] != null) {
          throw Exception(errorData['error']);
        }
      } catch (e) {
        final bodyString = response.data.toString();
        if (bodyString.contains('Username already exists')) {
          throw Exception('Username already exists');
        } else if (bodyString.contains('Email already registered')) {
          throw Exception('Email already registered');
        }
      }

      throw Exception('Signup failed. Please try again.');
    }
  }

  //Login
  Future<bool> login(String email, String password) async {
    final response = await _apiService.login(email, password);

    if (response.statusCode == 200) {
      final data = response.data;
      if (data['access'] != null && data['refresh'] != null) {
        print("Login response successful");

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString("email", email);

        await _storage.saveAccessToken(data['access']);
        await _storage.saveRefreshToken(data['refresh']);

        // Persist for Biometrics (survives logout)
        await _storage.saveBiometricAuth(email, password);

        // Register FCM token
        _registerFCM();

        return true;
      } else {
        print("Login api didnot return token");
        throw Exception('Login failed. Please try again.');
      }
    } else {
      print("Login failed: ${response.data}");

      final errorData = response.data;
      if (errorData['detail'] != null) {
        throw Exception(errorData['detail']);
      }

      throw Exception('Invalid email or password');
    }
  }

  //Refresh token
  Future<bool> refreshToken() async {
    return await _apiService.refreshToken();
  }

  //Forgot Password
  Future<bool> forgotPassword({String? email, String? phone}) async {
    return await _apiService.forgotPassword(email: email, phone: phone);
  }

  //Verify OTP
  Future<bool> verifyOtp(String email, String otp) async {
    return await _apiService.verifyOtp(email, otp);
  }

  //Reset Password
  Future<bool> resetPassword(
    String email,
    String new_password,
    String otp,
  ) async {
    return await _apiService.resetPassword(email, new_password, otp);
  }

  Future<void> logout() async {
    // 1. Clear Session Tokens (Preserve Biometric Credentials)
    await _storage.clearSession();

    // 2. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);
    await prefs.remove('userId');
    await prefs.remove('email');
    await prefs.remove('username');
    await prefs.remove('roomId');
    
    // 3. Clear "Remember Me" data as well on explicit logout
    await prefs.setBool('rememberMe', false);
    await prefs.remove('savedEmail');
    await prefs.remove('savedPassword');
    
    print("AuthServices: Logout complete. All session and credential data cleared.");
  }

  Future<void> _registerFCM() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      print("TOKEN: $token");
      if (token != null) {
        await _apiService.registerFcmToken(token);
      }
    } catch (e) {
      print("FCM: Failed to get/register token: $e");
    }
  }
}
