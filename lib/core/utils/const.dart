import 'package:flutter/material.dart';

class Constants {
  // CHANGE: Split into two URLs for dual deployment architecture
  // REST API endpoint (Hugging Face) - handles login, signup, profile, users, etc.
  static const String apiBaseUrl = "https://manikadahal-chess-auth-backend-manika-dahal.hf.space";
  //For testing FCM in new branch
  static const String apiFCMBaseUrl =
      "https://chess-backend-git-manika-dev-fcm-manikadahals-projects.vercel.app";

  // WebSocket endpoint (Hugging Face) - handles call signaling only
  static const String wsBaseUrl = "wss://manikadahal-chess-websocket-backend-manika-dahal.hf.space";
  // HTTP endpoint for Video service (same as WebSocket but with https)
  static const String videoBaseUrl =
      "https://manikadahal-chess-websocket-backend-manika-dahal.hf.space";

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}
