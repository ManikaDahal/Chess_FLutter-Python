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
        'username': 'username',
        'password': 'password',
        'email': 'email',
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
    final url = Uri.parse('${Constants.baseUrl}/api/token/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'username', 'password': 'password'}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      await _storage.saveRefreshToken(data['refresh']);
      return true;
    } else {
      print("Login Failed:${response.body}");
      return false;
    }
  }

  //Refresh token
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    final url = Uri.parse('${Constants.baseUrl}/api/token/refresh/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'applicatio/json'},
      body: jsonEncode({'refresh': refresh}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      return true;
    } else {
      return false;
    }
  }



  //Logout
  Future<void> logout() async{
    await _storage.deleteAll();
  }
}
