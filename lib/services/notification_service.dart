import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/invite_services.dart';
import 'package:chess_game_manika/services/notification_preference_service.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:chess_game_manika/ui/chess_board.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationController {
  /// Use this method to detect when a new notification or a schedule is created
  @pragma("vm:entry-point")
  static Future<void> onNotificationCreatedMethod(
    ReceivedNotification receivedNotification,
  ) async {}

  /// Use this method to detect every time that a new notification is displayed
  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(
    ReceivedNotification receivedNotification,
  ) async {}

  /// Use this method to detect if the user dismissed a notification
  @pragma("vm:entry-point")
  static Future<void> onDismissActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    final payload = receivedAction.payload;
    if (payload != null) {
      final String? trackingId = payload['trackingId'] ?? payload['id'];
      if (trackingId != null && trackingId.isNotEmpty) {
        print(
          "FCM [AwesomeNotification]: Swiped away. Reporting 'closed' for ID: $trackingId",
        );
        ApiService().updateNotificationStatus(trackingId, 'closed');
      }
    }
  }

  /// Use this method to detect when the user taps on a notification or action button
  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(
    ReceivedAction receivedAction,
  ) async {
    final payload = receivedAction.payload;
    if (payload != null) {
      final String? trackingId = payload['trackingId'] ?? payload['id'];
      if (trackingId != null && trackingId.isNotEmpty) {
        print(
          "FCM [AwesomeNotification]: Notification Tapped. Reporting 'opened' for ID: $trackingId",
        );
        ApiService().updateNotificationStatus(trackingId, 'opened');
      }

      NotificationService._handleFcmPayload(Map<String, dynamic>.from(payload));
    }
  }
}

class NotificationService extends WidgetsBindingObserver {
  /// Keep a navigator key to allow navigation from anywhere
  static GlobalKey<NavigatorState>? navigatorKey;
  static bool _isLocalInit = false;
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;
  NotificationService._internal();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print(
        "FCM [Lifecycle]: App resumed. Triggering permission sync after short delay...",
      );
      // Delay 1.5s to allow Android to finalize channel status after returning from Settings
      Future.delayed(const Duration(milliseconds: 1500), () {
        checkAndReportPermission();
      });
    }
  }

  static Future<void> _initLocal() async {
    if (_isLocalInit) return;

    // Fetch categories from backend to create dynamic channels
    List<NotificationCategoryPreference> categories = [];
    try {
      categories = await NotificationPreferenceService.fetchPreferences();
    } catch (e) {
      print("FCM: Could not fetch preferences for initialization: $e");
    }

    List<NotificationChannel> channels = [];

    if (categories.isEmpty) {
      // Default fallback channels
      channels = [
        NotificationChannel(
          channelKey: 'chat_channel',
          channelName: 'Chat Messages',
          channelDescription: 'Receive new chat messages',
          defaultColor: const Color(0xFF9D50BB),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          onlyAlertOnce: true,
          playSound: true,
          criticalAlerts: true,
        ),
        NotificationChannel(
          channelKey: 'invitation_channel',
          channelName: 'Game Invitations',
          channelDescription: 'Receive chess game invitations',
          defaultColor: const Color(0xFF9D50BB),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          onlyAlertOnce: true,
          playSound: true,
          criticalAlerts: true,
        ),
      ];
    } else {
      for (var pref in categories) {
        channels.add(
          NotificationChannel(
            channelKey: pref.category == 'message'
                ? 'chat_channel'
                : '${pref.category}_channel',
            channelName: pref.label,
            channelDescription: 'Notifications for ${pref.label}',
            defaultColor: const Color(0xFF9D50BB),
            ledColor: Colors.white,
            importance: NotificationImportance.Max,
            channelShowBadge: true,
            onlyAlertOnce: true,
            playSound: true,
            criticalAlerts: true,
          ),
        );
      }
    }

    await AwesomeNotifications().initialize(
      null, // default icon
      channels,
      debug: true,
    );

    // Set up listeners
    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: NotificationController.onActionReceivedMethod,
      onNotificationCreatedMethod:
          NotificationController.onNotificationCreatedMethod,
      onNotificationDisplayedMethod:
          NotificationController.onNotificationDisplayedMethod,
      onDismissActionReceivedMethod:
          NotificationController.onDismissActionReceivedMethod,
    );

    _isLocalInit = true;
  }

  static Future<void> init({required GlobalKey<NavigatorState> navKey}) async {
    navigatorKey = navKey;
    await _initLocal();

    // Register as lifecycle observer
    WidgetsBinding.instance.addObserver(_instance);

    // Request permissions for AwesomeNotifications
    await AwesomeNotifications().isNotificationAllowed().then((isAllowed) {
      if (!isAllowed) {
        AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });

    // FCM Setup
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions for Firebase
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Initial check and report
    await checkAndReportPermission();

    // Pre-load notification category preferences from backend
    NotificationPreferenceService.fetchPreferences();

    // Handle foreground messages

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('FCM: Got a foreground message. Data: ${message.data}');

      // Check if this notification's category is blocked by the user
      final String? category = message.data['category'] as String?;
      if (category != null &&
          await NotificationPreferenceService.isCategoryBlocked(category)) {
        print(
          'FCM [onMessage]: Category "$category" is blocked by user. Dropping notification.',
        );
        return;
      }

      // Update status - prefer FCM messageId for tracking
      final String? trackingId = message.messageId ?? message.data['id'];
      if (trackingId != null && trackingId.isNotEmpty) {
        // PROACTIVE CHECK: Determine if we should report 'delivered' or 'blocked'
        final bool isBlockedLocally =
            category != null &&
            await NotificationPreferenceService.isCategoryBlockedLocally(
              category,
            );

        if (isBlockedLocally) {
          print(
            "FCM [onMessage]: Category '$category' is blocked locally. Reporting 'blocked' for ID: $trackingId",
          );
          ApiService().updateNotificationStatus(trackingId, 'blocked');
          return; // Drop if blocked locally
        } else {
          ApiService().updateNotificationStatus(trackingId, 'delivered');
        }
      }

      // Forward to ChatProvider for unified processing (deduplication, unread counts, alerts)
      Map<String, dynamic> dataPayload = Map<String, dynamic>.from(
        message.data,
      );
      if (trackingId != null) {
        dataPayload['trackingId'] = trackingId;
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

  /// Checks if notification permissions are denied and reports 'blocked' to backend
  /// This also ensures the backend is aware of the user's focus on our app's settings.
  static Future<void> checkAndReportPermission() async {
    try {
      // 1. Check Global Permission (FCM)
      NotificationSettings settings = await FirebaseMessaging.instance
          .getNotificationSettings();

      print(
        'FCM: Current authorization status: ${settings.authorizationStatus}',
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print(
          'FCM: Notification permission blocked by user globally. Reporting to backend.',
        );
        ApiService().updateNotificationStatus('permission_blocked', 'blocked');

        // Block all to be safe if global is off
        NotificationPreferenceService.updatePreference('message', true);
        NotificationPreferenceService.updatePreference('invitation', true);
        return;
      }

      // 2. Check individual channels and sync to backend
      print("FCM [Sync]: Fetching preferences from backend...");
      var categories = await NotificationPreferenceService.fetchPreferences();
      print("FCM [Sync]: Got ${categories.length} preferences from backend.");

      // Ensure we always sync at least 'message' and 'invitation' if missing from backend
      final mandatoryCategories = ['message', 'invitation'];
      for (var cat in mandatoryCategories) {
        if (!categories.any((p) => p.category == cat)) {
          print(
            "FCM [Sync]: Category '$cat' missing from backend list. Adding mandatory placeholder.",
          );
          categories.add(
            NotificationCategoryPreference(
              category: cat,
              label: cat == 'message' ? 'Chat Message' : 'Game Invitation',
              isBlocked: false,
            ),
          );
        }
      }

      print("FCM [Sync]: Checking category permissions individually...");

      for (var pref in categories) {
        final String channelKey = pref.category == 'message'
            ? 'chat_channel'
            : '${pref.category}_channel';

        print(
          "FCM [Sync]: Checking status for category '${pref.category}' (Key: $channelKey)",
        );

        print(
          "FCM [Sync]: Probing permission for category '${pref.category}' (Key: $channelKey)",
        );

        bool shouldBeBlocked = false;
        try {
          // Check if the specific channel has ANY permission.
          // Using checkPermissionList (plural) as verified for 0.10.x.
          final List<dynamic> permissions =
              await (AwesomeNotifications() as dynamic).checkPermissionList(
                channelKey: channelKey,
                permissions: [
                  NotificationPermission.Alert,
                  NotificationPermission.Sound,
                  NotificationPermission.Badge,
                  NotificationPermission.Vibration,
                  NotificationPermission.Light,
                ],
              );

          // If the list is empty, it means the channel is effectively blocked or disabled
          shouldBeBlocked = permissions.isEmpty;

          print(
            "FCM [Sync]: Channel $channelKey permissions: $permissions. Blocked (empty): $shouldBeBlocked",
          );
        } catch (e) {
          print(
            "FCM [Sync] ERROR: Could not check permission for $channelKey: $e",
          );
          // If the backend says blocked and we can't read OS status,
          // assume unblocked to avoid keeping user locked out.
          // This prevents a stuck 'blocked' state due to API incompatibility.
          if (pref.isBlocked) {
            print(
              "FCM [Sync]: Backend says blocked but can't verify. Assuming UNBLOCKED for $channelKey to avoid lockout.",
            );
            shouldBeBlocked = false;
          } else {
            continue; // already unblocked — safe to skip
          }
        }

        // Only update if it changed from what the backend thinks
        if (pref.isBlocked != shouldBeBlocked) {
          print(
            'FCM [Sync]: STATUS MISMATCH for ${pref.category}! Backend: ${pref.isBlocked}, OS: $shouldBeBlocked. UPDATING BACKEND...',
          );
          final success = await NotificationPreferenceService.updatePreference(
            pref.category,
            shouldBeBlocked,
          );
          // Also update local cache immediately so foreground checks use fresh data
          await NotificationPreferenceService.updateLocalBlock(
            pref.category,
            shouldBeBlocked,
          );
          print(
            "FCM [Sync]: Backend update for ${pref.category} success: $success",
          );
        } else {
          print(
            "FCM [Sync]: ${pref.category} already in sync (Blocked: $shouldBeBlocked).",
          );
        }
      }
    } catch (e) {
      print('FCM: Error checking notification permissions: $e');
    }
  }

  /// This should be called once the main UI is built to handle terminated state navigation
  static Future<void> checkForInitialMessage() async {
    // Also check permissions when app starts/resumes
    await checkAndReportPermission();

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
        "FCM [invite_accepted]: Receiver accepted. Inviter should stay on current board.",
      );
      _showStatusDialog(data, "Invitation Accepted", Colors.green);
      return;
    }

    if (data['type'] == 'invite_declined') {
      print("FCM [invite_declined]: Receiver declined.");
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
                Navigator.pop(context);
                final int? acceptedRoomId = await InviteService().acceptInvites(
                  inviteId,
                );
                if (acceptedRoomId != null) {
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
                      ),
                    ),
                  );
                }
              },
              child: const Text("Accept"),
            ),
          ],
        );
      },
    );
  }

  /// Show local notification using AwesomeNotifications
  static Future<void> showNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    await _initLocal();

    // Map the category to the correct channel key
    String? category = payload['category']?.toString();
    if (category == null) {
      // Fallback for older payloads
      category = payload['type'] == 'chess_invite' ? 'invitation' : 'message';
    }

    final String channelKey = category == 'message'
        ? 'chat_channel'
        : '${category}_channel';

    int id = int.tryParse(payload['room_id']?.toString() ?? '0') ?? 0;

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: channelKey,
          title: title,
          body: body,
          payload: payload.map((key, value) => MapEntry(key, value.toString())),
          notificationLayout: NotificationLayout.Default,
        ),
      );
    } catch (e) {
      if (e.toString().contains('disabled') ||
          e.toString().contains('INSUFFICIENT_PERMISSIONS')) {
        print(
          "FCM [showNotification]: Catching channel disabled error for $channelKey. Reporting 'blocked'...",
        );
        final String? trackingId = payload['trackingId'] ?? payload['id'];
        if (trackingId != null) {
          ApiService().updateNotificationStatus(trackingId, 'blocked');
        }
        // Trigger a background sync to flip the preference if we just found out it's blocked
        NotificationService.checkAndReportPermission();
      } else {
        print("FCM [showNotification]: Error creating notification: $e");
      }
    }
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
