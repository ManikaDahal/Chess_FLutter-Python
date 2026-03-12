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
    // 1. Session Validation: Check if we even have tokens to use
    final accessToken = await _storage.getAccessToken();
    print("AuthBiometrics: accessToken=${accessToken != null ? 'Present' : 'NULL'}");
    
    if (accessToken == null) {
      print("AuthBiometrics: Login Failure: No session found. Please login manually first.");
      return false;
    }

    // 2. Local Authentication
    bool authenticated = await authenticate();
    if (!authenticated) {
      print("AuthBiometrics: authenticate() failed or was cancelled");
      return false;
    }

    // 3. API validation
    try {
      print("AuthBiometrics: Verifying session with backend profile...");
      await _apiService.getProfile(); 
      print("AuthBiometrics: Profile verified successfully");
      return true;
    } catch (e) {
      print("AuthBiometrics: Initial profile fetch failed, trying refresh... Error: $e");
      
      bool refreshed = await _authServices.refreshToken();
      if (!refreshed) {
        print("AuthBiometrics: Token refresh failed. User must login manually.");
        return false;
      }

      try {
        await _apiService.getProfile();
        print("AuthBiometrics: Profile fetch successful after refresh.");
        return true;
      } catch (e2) {
        print("AuthBiometrics: Profile fetch failed even after refresh: $e2");
        return false;
      }
    }
  }
}
