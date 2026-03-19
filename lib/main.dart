import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/login.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:chess_game_manika/core/permission/permission_service.dart';
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:chess_game_manika/core/ads/ad_service.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui';

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
  try {
    print("--- APP STARTING ---");
    // 1. Must ensure bindings are ready for plugins
    WidgetsFlutterBinding.ensureInitialized();
    print("1. WidgetsFlutterBinding initialized");

    // Initialize Mobile Ads
    await AdService().initialize();
    print("Ads initialized");

    // 2. Initialize Firebase early
    await Firebase.initializeApp();
    print("2. Firebase initialized");
    
    // Initialize Crashlytics only on supported platforms
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        print("3. Initializing Crashlytics...");
        FlutterError.onError = (details) {
          print("Crashlytics catch: FlutterError.onError");
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        };
        
        PlatformDispatcher.instance.onError = (error, stack) {
          print("Crashlytics catch: PlatformDispatcher.instance.onError - $error");
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      } catch (crashError) {
        print("!!! Crashlytics failed to initialize: $crashError !!!");
      }
    } else {
      print("3. SKIPPING Crashlytics (unsupported platform)");
    }
    
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print("4. Firebase Messaging setup done");

    // 3. Request permissions synchronously before service start
    await PermissionService.requestPermissionsOnce();
    print("5. Permissions requested");

    // 4. Initialize singletons
    // (GlobalCallHandler init removed here to prevent startup lag; now handled in BottomNavBar)
    print("6. GlobalCallHandler initialized");
    await NotificationService.init(navKey: Constants.navigatorKey);
    print("7. NotificationService initialized");

    // 6. Load user data
    final prefs = await SharedPreferences.getInstance();
    final bool loggedIn = prefs.getBool('loggedIn') ?? false;
    final int? userId = prefs.getInt('userId');
    print("8. User data loaded: loggedIn=$loggedIn, userId=$userId");

    print("9. Calling runApp...");
    runApp(
      ProviderScope(
        child: MyApp(autoLogin: loggedIn && userId != null),
      ),
    );

  } catch (e, stack) {

    print("!!! CONFIGURATION ERROR IN main(): $e !!!");
    print(stack);
    // Even if config fails, try to show something so it doesn't just go black
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Error starting app: $e")))));
  }
}

class MyApp extends StatelessWidget {
  final bool autoLogin;
  const MyApp({super.key, required this.autoLogin});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
    );

  }
}
