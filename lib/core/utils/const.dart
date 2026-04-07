import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class Constants {
  // REST API endpoint (Hugging Face) - handles login, signup, profile, users, etc.
  static String get apiBaseUrl =>
      dotenv.get('API_BASE_URL', fallback: 'https://fallback-auth.example.com');

  // FCM API endpoint for notifications
  // static String get apiFCMBaseUrl =>
  //     dotenv.get('API_FCM_BASE_URL', fallback: 'https://fallback-fcm.example.com');

  // Support dynamic WebSocket URL for Hotspot Mode
  static String? localHostIp;
  static int localPort = 8080;

  // WebSocket endpoint (Hugging Face) - handles call signaling only
  static String get wsBaseUrl {
    if (localHostIp != null) {
      return "ws://$localHostIp:$localPort";
    }
    return dotenv.get('WS_BASE_URL', fallback: 'wss://fallback-ws.example.com');
  }

  // HTTP endpoint for Video service (same as WebSocket but with https)
  static String get videoBaseUrl {
    if (localHostIp != null) {
      return "http://$localHostIp:$localPort";
    }
    return dotenv.get('VIDEO_BASE_URL', fallback: 'https://fallback-ws.example.com');
  }

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
