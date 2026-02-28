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
import 'package:chess_game_manika/widgets/floating_call_overlay.dart';
import 'package:chess_game_manika/services/permission_service.dart';
import 'package:chess_game_manika/services/sticky_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.notification == null && message.data.isNotEmpty) {
    if (message.data['type'] == 'chat_message') {
      await NotificationService.showNotification(
        title: message.data['sender_name'] ?? 'New Message',
        body: message.data['message'] ?? 'You have a new message',
        payload: Map<String, dynamic>.from(message.data),
      );
    }
  }
}

Future<void> main() async {
  // 1. Must ensure bindings are ready for plugins
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Firebase early
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. Request permissions synchronously before service start
  await PermissionService.requestPermissionsOnce();

  // 4. Initialize and START the Sticky Service before runApp
  // This avoids the 5-second watchdog crash (DidNotStartInTimeException)
  await StickyNotificationService.initService();
  try {
    await StickyNotificationService.startService();
  } catch (e) {
    debugPrint("Service failed to start: $e");
  }

  // 5. Initialize other singleton services
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
          return Stack(
            children: [
              if (child != null) child,
              ValueListenableBuilder<bool>(
                valueListenable: GlobalCallHandler().isMinimized,
                builder: (context, isMinimized, _) {
                  return isMinimized ? const FloatingCallOverlay() : const SizedBox.shrink();
                },
              ),
            ],
          );
        },
        home: autoLogin ? BottomNavBarWrapper() : Login(),
      ),
    );
  }
}