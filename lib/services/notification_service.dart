import 'dart:convert';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Keep a navigator key to allow navigation from anywhere
  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> init({required GlobalKey<NavigatorState> navKey}) async {
    navigatorKey = navKey;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final payload = jsonDecode(details.payload!);
            _handleFcmPayload(Map<String, dynamic>.from(payload));
          } catch (e) {
            print("Error parsing notification payload: $e");
          }
        }
      },
    );

    // Explicitly request permission for Android 13+
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    // FCM Setup
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions for iOS/Android 13+
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('FCM: User granted permission: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCM: Got a message whilst in the foreground!');
      print('FCM: Message data: ${message.data}');

      if (message.notification != null) {
        print(
          'FCM: Message also contained a notification: ${message.notification}',
        );

        final data = message.data;
        if (data.containsKey('room_id')) {
          final int roomId =
              int.tryParse(data['room_id']?.toString() ?? '1') ?? 1;
          final msg = ChatMessage(
            message: message.notification?.body ?? '',
            senderName: message.notification?.title ?? 'New Message',
            userId: int.tryParse(data['user_id']?.toString() ?? '0') ?? 0,
            roomId: roomId,
          );

          // Suppression logic: don't show if user is in the room
          if (roomId != ChatProvider.currentActiveRoomId) {
            showNotification(msg: msg, roomId: roomId);
          }
        }
      }
    });

    // Handle notification click when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: Notification clicked!');
      _handleFcmPayload(message.data);
    });

    // Handle notification click when app is terminated
    messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('FCM: App opened from terminated state via notification');
        _handleFcmPayload(message.data);
      }
    });
  }

  static void _handleFcmPayload(Map<String, dynamic> data) {
    if (data.containsKey('room_id')) {
      final int roomId = int.tryParse(data['room_id'].toString()) ?? 1;
      final int senderUserId = int.tryParse(data['user_id'].toString()) ?? 0;

      SharedPreferences.getInstance().then((prefs) {
        final currentUserId = prefs.getInt('userId') ?? senderUserId;
        navigatorKey?.currentState?.push(
          MaterialPageRoute(
            builder: (_) =>
                ChatPage(roomId: roomId, currentUserId: currentUserId),
          ),
        );
      });
    }
  }

  /// Show local notification
  static Future<void> showNotification({
    required ChatMessage msg,
    required int roomId,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          "chat_channel",
          "Chat Messages",
          channelDescription: "Receive new chat messages",
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      id: roomId,
      title: msg.senderName,
      body: msg.message,
      notificationDetails: platformDetails,
      payload: jsonEncode({
        "room_id": roomId,
        "user_id": msg.userId,
        "message": msg.message,
      }),
    );
  }
}
