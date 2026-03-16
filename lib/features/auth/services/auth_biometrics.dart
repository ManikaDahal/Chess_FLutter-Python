import 'package:chess_game_manika/features/auth/services/auth_services.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();
  final AuthServices _authServices = AuthServices();
  final ApiService _apiService = ApiService();
  final TokenStorage _storage = TokenStorage();

  bool _isAuthenticating = false;

  Future<bool> checkBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      print("Biometric Check: canCheck=$canCheck, isSupported=$isSupported");
      return canCheck && isSupported;
    } catch (e) {
      print("Biometric check error: $e");
      return false;
    }
  }

  Future<bool> authenticate() async {
    print("AuthBiometrics: authenticate() called");
    if (_isAuthenticating) {
      print("AuthBiometrics: Already authenticating");
      return false;
    }

    final canAuthenticate = await checkBiometrics();
    if (!canAuthenticate) {
      print("AuthBiometrics: checkBiometrics returned false");
      return false;
    }

    _isAuthenticating = true;
    try {
      final availableBiometrics = await _auth.getAvailableBiometrics();
      print("AuthBiometrics: availableBiometrics=$availableBiometrics");

      if (availableBiometrics.isEmpty) {
        print("AuthBiometrics: No biometrics enrolled");
        return false;
      }

      print("AuthBiometrics: Triggering UI prompt...");
      bool authenticated = await _auth.authenticate(
        localizedReason: "Scan fingerprint to login",
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      print("AuthBiometrics: UI result=$authenticated");
      return authenticated;
    } catch (e) {
      print("AuthBiometrics: General error in authenticate(): $e");
      return false;
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<bool> loginWithBiometrics() async {
    print("AuthBiometrics: loginWithBiometrics() started");
    
    // 1. Local Authentication FIRST (User must prove it's them)
    bool authenticated = await authenticate();
    if (!authenticated) {
      print("AuthBiometrics: Biometric scan failed or cancelled");
      return false;
    }

    // 2. Session Validation: Check if we have active tokens
    final accessToken = await _storage.getAccessToken();
    if (accessToken != null) {
      print("AuthBiometrics: Active session found. Verifying with profile...");
      try {
        await _apiService.getProfile(); 
        print("AuthBiometrics: Session valid");
        return true;
      } catch (e) {
        print("AuthBiometrics: Access token expired, attempting refresh... $e");
        bool refreshed = await _authServices.refreshToken();
        if (refreshed) {
          try {
            await _apiService.getProfile();
            print("AuthBiometrics: Session restored via refresh");
            return true;
          } catch (e2) {
            print("AuthBiometrics: Profile failed even after refresh: $e2");
          }
        }
      }
    }

    // 3. Re-Authentication: If session is missing or invalid, use persistent credentials
    print("AuthBiometrics: No valid session. Searching persistent biometric credentials...");
    final bioCreds = await _storage.getBiometricAuth();
    
    if (bioCreds != null) {
      print("AuthBiometrics: Found persistent credentials for ${bioCreds['email']}. Performing background login...");
      try {
        bool loginOk = await _authServices.login(
          bioCreds['email']!, 
          bioCreds['password']!,
        );
        if (loginOk) {
          print("AuthBiometrics: Background login successful");
          return true;
        }
      } catch (e) {
        print("AuthBiometrics: Background login failed: $e");
      }
    } else {
      print("AuthBiometrics: No persistent credentials found.");
    }

    print("AuthBiometrics: Biometric login flow failed. Manual login required.");
    return false;
  }
}
