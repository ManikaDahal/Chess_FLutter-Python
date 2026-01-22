import 'dart:async';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatProvider with ChangeNotifier {
  final String instanceId = DateTime.now().millisecondsSinceEpoch
      .toString()
      .substring(8);
  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  int? _currentRoomId;
  int? _currentUserId;
  String? _currentUserName;

  StreamSubscription? _subscription;

  void init(int roomId, int currentUserId) {
    print(
      "ChatProvider [$instanceId]: init called for user $currentUserId in room $roomId",
    );
    _currentUserId = currentUserId;
    _currentRoomId = roomId;

    // Retrieve username from SharedPreferences
    _currentUserName = "Unknown";
    SharedPreferences.getInstance().then((prefs) {
      _currentUserName = prefs.getString("username") ?? "Unknown";
      print("ChatProvider: Retrieved username: $_currentUserName");
    });

    print("ChatProvider: Initializing for user $currentUserId in room $roomId");

    // Fetch message history
    ApiService()
        .getChatMessages(roomId)
        .then((history) {
          print(
            "ChatProvider [$instanceId]: Loaded ${history.length} history messages.",
          );
          // Combine history with any existing optimistic messages, avoid duplicates
          final List<ChatMessage> historyMsgs = history
              .map((e) => ChatMessage.fromJson(e))
              .toList();

          // Merge: Keep current messages (which might contain new optimistic ones)
          // but prioritize history for older ones.
          // Simple approach: if history is loaded, it replaces everything
          // BUT we should be careful if messages arrived while loading.
          _messages = historyMsgs;
          notifyListeners();
        })
        .catchError((e) {
          print("ChatProvider [$instanceId]: Error loading history: $e");
        });

    // Only connect if not already connected
    if (!ChatWebsocketService().isConnected) {
      print("ChatProvider: WebSocket not connected, connecting...");
      ChatWebsocketService().connect(roomId);
    }

    // Cancel existing subscription if any to avoid duplicates
    _subscription?.cancel();

    // Listen to messages
    _subscription = ChatWebsocketService().stream.listen(
      (data) {
        print("ChatProvider: Received data: $data");
        try {
          final msg = ChatMessage.fromJson(data);

          // Dedup: Better logic checking last few messages to handle rapid messaging
          final bool isDuplicate = _messages.reversed
              .take(5)
              .any(
                (m) =>
                    m.userId == _currentUserId &&
                    m.userId == msg.userId &&
                    m.message == msg.message,
              );

          if (isDuplicate) {
            print(
              "ChatProvider [$instanceId]: Ignoring server echo (Duplicate found in last 5).",
            );
            return;
          }

          final bool shouldNotify = msg.userId != _currentUserId;
          if (shouldNotify) {
            _unreadCount++;
          }

          // Ensure we notify listeners safely to avoid build phase conflicts
          scheduleMicrotask(() {
            _messages = List.from(_messages)..add(msg);
            notifyListeners();

            // Only show local notification if we are still "active" in this provider
            if (shouldNotify && _currentUserId != null) {
              NotificationService.showNotification(msg, roomId);
            }
          });
        } catch (e) {
          print("ChatProvider: Error parsing message: $e");
        }
      },
      onError: (error) {
        print("ChatProvider: Stream error: $error");
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    print("ChatProvider: Disposed, subscription cancelled.");
    super.dispose();
  }

  void send(String message) {
    if (_currentUserId == null) {
      print("ChatProvider: Cannot send message, current user ID is null.");
      return;
    }
    if (_currentRoomId == null) {
      print("ChatProvider: Cannot send message, current room ID is null.");
      return;
    }
    print(
      "ChatProvider: Attempting to send message: '$message' from user $_currentUserId to room $_currentRoomId",
    );
    // OPTIMISTIC UPDATE: Add message locally first
    final optimisticMsg = ChatMessage(
      message: message,
      userId: _currentUserId!,
      roomId: _currentRoomId!,
      senderName: _currentUserName ?? "Unknown",
    );

    _messages = List.from(_messages)..add(optimisticMsg);
    print(
      "ChatProvider [$instanceId]: Optimistic add. Total messages: ${_messages.length}",
    );
    notifyListeners();

    ChatWebsocketService().sendMessage(
      message,
      _currentUserId!,
      _currentUserName ?? "Unknown",
    );

    print("ChatProvider [$instanceId]: Message sent to WebSocket.");
  }

  void clear() {
    print("ChatProvider [$instanceId]: clear called. Cancelling subscription.");
    _subscription?.cancel();
    _subscription = null;
    _messages.clear();
    _currentUserId = null;
    _currentRoomId = null;
    _unreadCount = 0;
    notifyListeners();
  }

  void resetUnreadCount() {
    _unreadCount = 0;
    notifyListeners();
  }
}
