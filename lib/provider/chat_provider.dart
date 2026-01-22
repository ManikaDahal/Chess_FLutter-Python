import 'dart:async';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:flutter/widgets.dart';

class ChatProvider with ChangeNotifier {
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  int? _currentRoomId;
  int? _currentUserId;

  StreamSubscription? _subscription;

  void init(int roomId, int currentUserId) {
    _currentUserId = currentUserId;
    _currentRoomId = roomId;

    print("ChatProvider: Initializing for user $currentUserId in room $roomId");

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

          // Simple deduplication: don't add if the same message from same user is already last
          if (_messages.isNotEmpty) {
            final last = _messages.last;
            if (last.message == msg.message && last.userId == msg.userId) {
              print("ChatProvider: Skipping duplicate message.");
              return;
            }
          }

          _messages.add(msg);

          bool shouldNotify = false;
          if (msg.userId != _currentUserId) {
            _unreadCount++;
            shouldNotify = true;
          }

          // Ensure we notify listeners safely to avoid build phase conflicts
          scheduleMicrotask(() {
            notifyListeners();
            if (shouldNotify) {
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
    ChatWebsocketService().sendMessage(message, _currentUserId!);

    // REMOVED local _messages.add(msg) to avoid duplication.
    // The server will broadcast it back to us via the WebSocket stream.
    print("ChatProvider: Message sent. Waiting for broadcast reflection.");
  }

  void resetUnreadCount() {
    _unreadCount = 0;
    notifyListeners();
  }
}
