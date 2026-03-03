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
import 'bottom_navbar.dart';
import 'package:chess_game_manika/services/permission_service.dart';
import 'package:chess_game_manika/core/utils/logger.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.notification == null && message.data.isNotEmpty) {
    if (message.data['type'] == 'chat_message') {
      Map<String, dynamic> payload = Map<String, dynamic>.from(message.data);
      if (message.messageId != null) {
        payload['trackingId'] = message.messageId;
      }
      await NotificationService.showNotification(
        title: message.data['sender_name'] ?? 'New Message',
        body: message.data['message'] ?? 'You have a new message',
        payload: payload,
      );
    }
  }
}

Future<void> main() async {
  // 1. Must ensure bindings are ready for plugins
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Logger first
  AppLogger.init();

  // 2. Initialize Firebase early
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. Request permissions synchronously before service start
  await PermissionService.requestPermissionsOnce();

  // 4. Initialize singletons
  GlobalCallHandler().init();
  await NotificationService.init(navKey: Constants.navigatorKey);

  // 6. Load user data
  final prefs = await SharedPreferences.getInstance();
  final bool loggedIn = prefs.getBool('loggedIn') ?? false;
  final int? userId = prefs.getInt('userId');

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
        builder: (context, child) {
          return child ?? const SizedBox.shrink();
        },
        home: autoLogin ? BottomNavBarWrapper() : Login(),
      ),
    );
  }
}
