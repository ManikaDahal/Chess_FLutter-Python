import 'dart:convert';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
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
          final payload = jsonDecode(details.payload!);
          final int roomId = payload['room_id'] ?? 1;
          final int senderUserId = payload['user_id'] ?? 0;

          // Retrieve current user ID from SharedPreferences
          SharedPreferences.getInstance().then((prefs) {
            final currentUserId = prefs.getInt('userId') ?? senderUserId;

            // Navigate to chat page using navigatorKey
            navigatorKey?.currentState?.push(
              MaterialPageRoute(
                builder: (_) =>
                    ChatPage(roomId: roomId, currentUserId: currentUserId),
              ),
            );
          });
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
  }

  /// Show local notification
  static Future<void> showNotification(ChatMessage msg, int roomId) async {
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
  title: msg.senderName ?? 'New Message',
  body: msg.message ?? '',
  notificationDetails: platformDetails,
  payload: jsonEncode({
    "room_id": roomId,
    "user_id": msg.userId ?? 0,
    "message": msg.message ?? '',
  }),
);

  }
}
