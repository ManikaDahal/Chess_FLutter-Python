import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/login.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'bottom_navbar.dart'; // Make sure you import your main page

// Background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("FCM: Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Foreground Service for MQTT
  // await ForegroundServiceManager.init();

  // Start global call listener
  GlobalCallHandler().init();

  // Initialize notification service
  await NotificationService.init(navKey: Constants.navigatorKey);

  // Load saved login state
  final prefs = await SharedPreferences.getInstance();
  final bool loggedIn = prefs.getBool('loggedIn') ?? false;
  final int? userId = prefs.getInt('userId');

  // If user is logged in, start foreground MQTT service
  /*
  if (loggedIn && userId != null) {
    // DO NOT await this here, as it might block the UI/runApp
    ForegroundServiceManager.start(userId).catchError((e) {
      print("Error starting foreground service in main: $e");
    });
  }
  */

  runApp(MyApp(autoLogin: loggedIn && userId != null));
}

class MyApp extends StatelessWidget {
  final bool autoLogin;
  const MyApp({super.key, required this.autoLogin});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ChatProvider())],
      child: MaterialApp(
        navigatorKey: Constants.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Chess App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        // Auto-login: skip Login page if already logged in
        home: autoLogin
            ? BottomNavBarWrapper() // Main page
            : Login(), // Show login page
      ),
    );
  }
}
