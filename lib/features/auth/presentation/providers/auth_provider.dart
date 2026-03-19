import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';

class AuthState {
  final bool isAuthenticated;
  final int? userId;
  final String? email;
  final int? roomId;

  const AuthState({this.isAuthenticated = false, this.userId, this.email, this.roomId});
  
  AuthState copyWith({bool? isAuthenticated, int? userId, String? email, int? roomId}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      roomId: roomId ?? this.roomId,
    );
  }
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    return await _checkAuthStatus();
  }

  Future<AuthState> _checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('loggedIn') ?? false;
      final cachedUserId = prefs.getInt('userId');
      final email = prefs.getString('email');

      if (loggedIn && cachedUserId != null) {
        // Try to fetch profile to ensure session is valid
        try {
          final profile = await ApiService().getProfile();
          final int userId = profile['id'] ?? cachedUserId;
          final int roomId = profile['current_room_id'] ?? 1;
          // Update cached user ID if it was missing/wrong
          if (userId != cachedUserId) {
            await prefs.setInt('userId', userId);
          }
          return AuthState(isAuthenticated: true, userId: userId, email: email, roomId: roomId);
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
            // Token expired or invalid
            await logout();
            return const AuthState(isAuthenticated: false);
          }
          // Network error or other - assume logged in for now and let other services handle retry
          return AuthState(isAuthenticated: true, userId: cachedUserId, email: email, roomId: 1);
        }
      }
    } catch (e, st) {
      debugPrint("Auth check error: $e\n$st");
    }
    
    return const AuthState(isAuthenticated: false);
  }

  Future<void> login(int userId, String email, {int roomId = 1}) async {
    state = const AsyncValue.loading();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', true);
    await prefs.setInt('userId', userId);
    await prefs.setString('email', email);
    
    state = AsyncValue.data(AuthState(isAuthenticated: true, userId: userId, email: email, roomId: roomId));
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedIn');
    await prefs.remove('userId');
    await prefs.remove('email');
    
    state = const AsyncValue.data(AuthState(isAuthenticated: false));
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
