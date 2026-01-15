import 'package:flutter/material.dart';

class Constants {
  // NOTE: Vercel does NOT support WebSockets (Django Channels).
  // For production, use Heroku, DigitalOcean, or AWS.
  // For local testing across networks, use ngrok: ngrok http 8000
  static const String baseUrl =
      "https://uncoddled-charita-nonlymphatic.ngrok-free.dev";
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  //https://chess-backend-ochre.vercel.app
}
