import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/login.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:chess_game_manika/features/notifications/services/sticky_notification_service.dart';
import 'package:chess_game_manika/core/permission/permission_service.dart';
import 'package:chess_game_manika/core/ads/ad_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
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

    // Initialize Stripe
    Stripe.publishableKey = "pk_test_51TFB8RK6P5b4mTJTc8M593ZOXEJN2voOuMk2MRODYA7DnnwZu4PgnBfGtU0Mzea4Jhrh1qL3r0hndG6LKlyK8pGw00RmxJo9g9";
    await Stripe.instance.applySettings();

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

    // Start sticky notification service (Chess Tips)
    try {
      await StickyNotificationService.initService();
      await StickyNotificationService.startService();
      print("5.1 StickyNotificationService started");
    } catch (e) {
      print("!!! Error starting StickyNotificationService: $e !!!");
    }

    // 4. Initialize singletons
    // Initialized features
    print("6. Services initialized");
    await NotificationService.init(navKey: Constants.navigatorKey);
    print("7. NotificationService initialized");

    // 6. User data initialization is now handled by authProvider

    print("9. Calling runApp...");
    runApp(
      ProviderScope(
        child: const MyApp(),
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
  const MyApp({super.key});

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
      home: const AuthChecker(),
    );
  }
}

class AuthChecker extends ConsumerWidget {
  const AuthChecker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read authProvider to decide routing dynamically
    final authState = ref.watch(authProvider);

    return authState.when(
      data: (state) {
        if (state.isAuthenticated) {
          // BottomNavBarWrapper will now safely assume user exists
          return BottomNavBarWrapper();
        } else {
          return const Login();
        }
      },
      loading: () => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => const Login(),
    );
  }
}
