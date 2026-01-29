import 'dart:convert';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Keep a navigator key to allow navigation from anywhere
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _isLocalInit = false;

  static Future<void> _initLocal() async {
    if (_isLocalInit) return;

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
    _isLocalInit = true;
  }

  static Future<void> init({required GlobalKey<NavigatorState> navKey}) async {
    navigatorKey = navKey;
    await _initLocal();

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
      print('FCM: Got a foreground message. Data: ${message.data}');

      final data = message.data;
      final int msgRoomId =
          int.tryParse(data['room_id']?.toString() ?? '0') ?? 0;
      final int currentRoomId = ChatProvider.currentActiveRoomId ?? -1;

      // SELECTIVE SUPPRESSION:
      // If we are NOT connected to this room via WebSocket, show the notification.
      // This allows private messages (which use separate rooms) to notify in foreground,
      // while the general room (which is always connected) stays suppressed to avoid duplicates.
      bool isConnected = ChatWebsocketService().isRoomConnected(msgRoomId);
      bool isViewingThisRoom = msgRoomId != 0 && msgRoomId == currentRoomId;

      print(
        "FCM: FG Check - msgRoom: $msgRoomId, isConnected: $isConnected, isViewing: $isViewingThisRoom",
      );

      if (!isConnected && !isViewingThisRoom) {
        print(
          "FCM: Showing foreground notification (room not connected via WS)",
        );
        showNotification(
          title: data['sender_name'] ?? "New Message",
          body:
              data['message'] ??
              message.notification?.body ??
              "New message arrived",
          payload: Map<String, dynamic>.from(data),
        );
      } else {
        print(
          "FCM: Suppressing foreground notification (already handled by WebSocket)",
        );
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

  static void _handleFcmPayload(Map<String, dynamic> data) async {
    print("FCM: Handling payload details: $data");
    if (data.containsKey('room_id')) {
      final int roomId = int.tryParse(data['room_id'].toString()) ?? 1;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int? currentUserId = prefs.getInt('userId');

      print("FCM: Navigating to Room $roomId for User $currentUserId");

      if (currentUserId == null) {
        print(
          "FCM ERROR: Cannot navigate, userId is missing in SharedPreferences",
        );
        return;
      }

      navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) =>
              ChatPage(roomId: roomId, currentUserId: currentUserId),
        ),
      );
    }
  }

  /// Show local notification
  static Future<void> showNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    await _initLocal();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          "chat_channel",
          "Chat Messages",
          channelDescription: "Receive new chat messages",
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          showWhen: true,
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    // Use a unique ID or hash of room_id to avoid overwriting
    int id = int.tryParse(payload['room_id']?.toString() ?? '0') ?? 0;

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: jsonEncode(payload),
    );
  }

  /// Register FCM Token with backend
  static Future<void> registerToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        print("FCM Token: $token");
        await ApiService().registerFcmToken(token);
      }
    } catch (e) {
      print("Error registering FCM token: $e");
    }
  }
}
