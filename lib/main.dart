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

import 'package:chess_game_manika/services/sticky_notification_service.dart';

// Background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("FCM: Handling a background message: ${message.messageId}");

  // Only show local notification if it's a data-only message
  // AND it's explicitly typed as a chat message.
  if (message.notification == null && message.data.isNotEmpty) {
    final data = message.data;

    // Type Check: Only show manual notification if it's a chat message
    if (data['type'] == 'chat_message') {
      final String title = data['sender_name'] ?? 'New Message';
      final String body = data['message'] ?? 'You have a new message';

      await NotificationService.showNotification(
        title: title,
        body: body,
        payload: Map<String, dynamic>.from(data),
      );
    } else {
      print(
        "FCM: Background handler ignoring non-chat data message: ${data['type']}",
      );
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Sticky Notification Service
  await StickyNotificationService.initService();

  // Initialize Firebase
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Start global call listener
  GlobalCallHandler().init();

  // Initialize notification service
  await NotificationService.init(navKey: Constants.navigatorKey);

  // Load saved login state
  final prefs = await SharedPreferences.getInstance();
  final bool loggedIn = prefs.getBool('loggedIn') ?? false;
  final int? userId = prefs.getInt('userId');

  // DO NOT await this here, as it might block the UI/runApp

  runApp(MyApp(autoLogin: loggedIn && userId != null));

  // Check for initial message (terminated state navigation)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    NotificationService.checkForInitialMessage();
    // Start sticky notification after UI is up
    await StickyNotificationService.startService();
  });
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
