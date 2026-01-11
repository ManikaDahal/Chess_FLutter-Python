import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'package:chess_python/services/api_services.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/services/token_storage.dart';

class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  final AuthServices _authServices = AuthServices();
  final TokenStorage _tokenStorage = TokenStorage();
  final ApiService _apiService = ApiService();

  bool _isAuthenticating = false;

  Future<bool> authenticate() async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;

    try {
      bool authenticated = await _auth.authenticate(
        localizedReason: "Scan fingerprint to login",

        biometricOnly: true,
      );
      return authenticated;
    } on PlatformException catch (e) {
      print("Biometric error: $e");
      return false;
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<bool> loginWithBiometrics() async {
  bool authenticated = await authenticate();
  if (!authenticated) return false;

  String? token = await _tokenStorage.getAccessToken();
  if (token == null) {
    print("Access token is null. Please login manually first.");
    return false;
  }

  try {
    await _apiService.getProfile(); // uses stored token internally
    return true;
  } catch (e) {
    print("Profile fetch failed during biometric login: $e");

    // Try refreshing token
    bool refreshed = await _authServices.refreshToken();
    if (refreshed) {
      token = await _tokenStorage.getAccessToken();
      if (token != null) {
        await _apiService.getProfile();
        return true;
      }
    }
    return false;
  }
}


}
