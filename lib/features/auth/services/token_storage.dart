import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  // Singleton pattern
  static final TokenStorage _instance = TokenStorage._internal();
  factory TokenStorage() => _instance;
  TokenStorage._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Memory cache
  String? _accessToken;
  String? _refreshToken;

  Future<void> saveAccessToken(String token) async {
    _accessToken = token;
    await _storage.write(key: 'access_token', value: token);
    print("Saved access token to storage and cache");
  }

  Future<String?> getAccessToken() async {
    // Return from cache if available
    if (_accessToken != null) {
      return _accessToken;
    }

    // Otherwise read from secure storage
    final token = await _storage.read(key: 'access_token');
    _accessToken = token;
    print(
      "Read access token from storage: ${token != null ? 'Found' : 'Not Found'}",
    );
    return token;
  }

  Future<void> saveRefreshToken(String token) async {
    _refreshToken = token;
    await _storage.write(key: 'refresh_token', value: token);
    print("Saved refresh token to storage and cache");
  }

  Future<String?> getRefreshToken() async {
    // Return from cache if available
    if (_refreshToken != null) {
      return _refreshToken;
    }

    final token = await _storage.read(key: 'refresh_token');
    _refreshToken = token;
    return token;
  }

  // Persistent Biometric Credentials
  Future<void> saveBiometricAuth(String email, String password) async {
    await _storage.write(key: 'bio_email', value: email);
    await _storage.write(key: 'bio_password', value: password);
    print("Persistent biometric credentials saved");
  }

  Future<Map<String, String>?> getBiometricAuth() async {
    final email = await _storage.read(key: 'bio_email');
    final password = await _storage.read(key: 'bio_password');
    if (email != null && password != null) {
      return {'email': email, 'password': password};
    }
    return null;
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    print("Cleared session tokens from storage and cache");
  }

  Future<void> deleteAll() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.deleteAll();
    print("Cleared EVERYTHING from secure storage");
  }
}
