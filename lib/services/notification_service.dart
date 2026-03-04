import 'dart:convert';
import 'dart:async';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/invite_services.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:chess_game_manika/ui/chess_board.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/services/signaling_service.dart';
import 'package:chess_game_manika/core/utils/const.dart';
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

  // Stream to broadcast FCM events to the UI
  static final StreamController<Map<String, dynamic>> _fcmEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get fcmEventStream =>
      _fcmEventController.stream;

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
            final payloadMap = Map<String, dynamic>.from(payload);

            // Extract trackingId and update backend status to "opened"
            final String? trackingId =
                payloadMap['trackingId']?.toString() ??
                payloadMap['id']?.toString();
            if (trackingId != null && trackingId.isNotEmpty) {
              print(
                "FCM [LocalNotification]: Marking status as opened for ID: $trackingId",
              );
              ApiService().updateNotificationStatus(trackingId, 'opened');
            }

            _handleFcmPayload(payloadMap);
          } catch (e) {
            print("Error parsing notification payload: $e");
          }
        }
      },
    );

    // Create the notification channel explicitly for Android 8.0+
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'chat_channel', // id
      'Chat Messages', // title
      description: 'Receive new chat messages', // description
      importance: Importance.max,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
      print("FCM: Notification Channel 'chat_channel' created.");
    }

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

      // Update status to delivered - prefer FCM messageId for tracking
      final String? trackingId = message.messageId ?? message.data['id'];
      if (trackingId != null && trackingId.isNotEmpty) {
        ApiService().updateNotificationStatus(trackingId, 'delivered');
      }

      // Forward to ChatProvider for unified processing (deduplication, unread counts, alerts)
      Map<String, dynamic> dataPayload = Map<String, dynamic>.from(
        message.data,
      );
      if (trackingId != null) {
        dataPayload['trackingId'] = trackingId;
      }

      // If it is a game response, we want to handle the transition immediately in the foreground
      if (dataPayload['type'] == 'invite_accepted' ||
          dataPayload['type'] == 'invite_declined') {
        _handleFcmPayload(dataPayload);
      }

      ChatProvider.instance?.processIncomingPayload(dataPayload);
    });

    // Handle notification click when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: Notification clicked!');

      // Update status to opened - prefer FCM messageId for tracking
      final String? trackingId = message.messageId ?? message.data['id'];
      if (trackingId != null && trackingId.isNotEmpty) {
        ApiService().updateNotificationStatus(trackingId, 'opened');
      }

      _handleFcmPayload(message.data);
    });

    // Handle notification click when app is terminated
    // We only LOG here, handle navigation in checkForInitialMessage
    messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print(
          'FCM: App opened from terminated state via notification. Delaying navigation.',
        );

        // Update status to opened - prefer FCM messageId for tracking
        final String? trackingId = message.messageId ?? message.data['id'];
        if (trackingId != null && trackingId.isNotEmpty) {
          ApiService().updateNotificationStatus(trackingId, 'opened');
        }
      }
    });
  }

  /// This should be called once the main UI is built to handle terminated state navigation
  static Future<void> checkForInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();

    if (initialMessage != null) {
      print("FCM [ColdStart]: Found initial message, processing navigation...");
      // Add a longer delay for cold starts to ensure Navigator and Provider are ready
      await Future.delayed(const Duration(milliseconds: 1500));
      _handleFcmPayload(initialMessage.data);
    }
  }

  static void _handleFcmPayload(Map<String, dynamic> data) async {
    print("FCM: Handling payload details: $data");

    if (data['type'] == 'chess_invite') {
      _showInviteDialog(data);
      return;
    }

    if (data['type'] == 'invite_accepted') {
      print(
        "FCM [invite_accepted]: Receiver accepted. Inviter should enter the board.",
      );
      // Broadcast the event so the waiting screen can handle it smoothly
      _fcmEventController.add(data);
      return;
    }

    if (data['type'] == 'invite_declined') {
      print("FCM [invite_declined]: Receiver declined.");
      // Broadcast the event
      _fcmEventController.add(data);

      _showStatusDialog(data, "Invitation Declined", Colors.red);
      return;
    }

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

  static void _showInviteDialog(Map<String, dynamic> data) async {
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    final String senderName = data['sender_name'] ?? "Someone";
    final int senderId = int.tryParse(data['user_id']?.toString() ?? "0") ?? 0;
    final String inviteIdStr =
        data['id']?.toString().replaceAll("invite_", "") ?? "0";
    final int inviteId = int.tryParse(inviteIdStr) ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Game Invitation"),
          content: Text("$senderName invited you to play a chess game!"),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await InviteService().declineInvite(inviteId);
              },
              child: const Text("Decline", style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // Close invite dialog

                // Show progress dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 20),
                        Text("Connecting to call..."),
                      ],
                    ),
                  ),
                );

                final int? acceptedRoomId = await InviteService().acceptInvites(
                  inviteId,
                );

                if (acceptedRoomId != null) {
                  final String callRoomId = "game_call_$acceptedRoomId";
                  final SignalingService sigService = SignalingService();

                  try {
                    // Connect to signaling
                    await sigService.connect(Constants.wsBaseUrl, callRoomId);

                    // Wait for incoming call (as Invitee/Black)
                    // We expect White to call immediately
                    bool callEstablished = false;
                    int handshakeRetries = 0;

                    final sub = sigService.onIncomingCallStream.listen((_) {
                      sigService.acceptCall(isVideo: false);
                    });

                    // Poll for remote stream
                    while (!callEstablished && handshakeRetries < 20) {
                      await Future.delayed(const Duration(milliseconds: 500));
                      if (sigService.remoteStreamNotifier.value != null) {
                        callEstablished = true;
                      }
                      handshakeRetries++;
                    }
                    sub.cancel();

                    if (context.mounted)
                      Navigator.pop(context); // Close progress dialog

                    final SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    final int currentUserId = prefs.getInt('userId') ?? 0;

                    // Navigator navigate to Chess Board
                    navigatorKey?.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => GameBoard(
                          roomId: acceptedRoomId,
                          currentUserId: currentUserId,
                          isMultiplayer: true,
                          amIWhite: false, // Receiver is always Black
                          opponentId: senderId,
                          showLeaveButton: true,
                          signalingService: sigService,
                        ),
                      ),
                    );
                  } catch (e) {
                    if (context.mounted) Navigator.pop(context);
                    debugPrint("[NOTIF SERVICE] Signaling error: $e");
                  }
                } else {
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text("Accept"),
            ),
          ],
        );
      },
    );
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
      print("FCM [DEBUG]: Requesting token from Firebase...");
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        print("FCM [DEBUG]: Token generated: $token");
        print("FCM [DEBUG]: Sending token to backend (ApiService)...");
        await ApiService().registerFcmToken(token);
      } else {
        print("FCM [DEBUG]: FAILED to get FCM token (token is null)");
      }
    } catch (e) {
      print("FCM [DEBUG]: Error during registerToken: $e");
    }
  }

  static void _showStatusDialog(
    Map<String, dynamic> data,
    String title,
    Color color,
  ) {
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    final String message = data['message'] ?? "";
    final int roomId = int.tryParse(data['room_id']?.toString() ?? "0") ?? 0;
    final int senderId = int.tryParse(data['user_id']?.toString() ?? "0") ?? 0;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title, style: TextStyle(color: color)),
          content: Text(message),
          actions: [
            if (title == "Invitation Accepted")
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  final int currentUserId = prefs.getInt('userId') ?? 0;

                  navigatorKey?.currentState?.push(
                    MaterialPageRoute(
                      builder: (_) => GameBoard(
                        roomId: roomId,
                        currentUserId: currentUserId,
                        isMultiplayer: true,
                        amIWhite: true, // Inviter is always White
                        opponentId: senderId,
                        showLeaveButton: true,
                      ),
                    ),
                  );
                },
                child: const Text("Play Now"),
              ),
            if (title == "Invitation Declined")
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  // Trigger re-invite if sender chooses
                  final SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  final int currentUserId = prefs.getInt('userId') ?? 0;

                  navigatorKey?.currentState?.pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => GameBoard(
                        roomId: roomId,
                        currentUserId: currentUserId,
                        isMultiplayer: true,
                        amIWhite: true, // Inviter stays White
                        opponentId: senderId,
                        showLeaveButton: true,
                      ),
                    ),
                  );
                  // Call sendInvite again
                  await InviteService().sendInvite(senderId);
                },
                child: const Text("Send Again"),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }
}
