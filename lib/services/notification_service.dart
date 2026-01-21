import 'dart:convert';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          final payload = jsonDecode(details.payload!);
          final roomId = payload['room_id'];
          final userId = payload['user_id'];

          // Navigate to chat page using navigatorKey
          navigatorKey?.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ChatPage(roomId: roomId, currentUserId: userId),
            ),
          );
        }
      },
    );
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
      msg.userId, // notification id
      "New Message",
      msg.message,
      platformDetails,
      payload: jsonEncode({
        "room_id": msg.roomId,
        "user_id": msg.userId,
        "message": msg.message,
      }),
    );
  }
}
