import 'package:flutter/material.dart';

class Constants {
  // CHANGE: Split into two URLs for dual deployment architecture
  // REST API endpoint (Vercel) - handles login, signup, profile, users, etc.
  static const String apiBaseUrl = "https://chess-backend-ochre.vercel.app";

  // WebSocket endpoint (Render) - handles call signaling only
  static const String wsBaseUrl = "wss://chess-websocket-dor6.onrender.com";

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
