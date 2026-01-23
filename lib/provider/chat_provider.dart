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

  // Isolated Storage: RoomID -> Message List
  final Map<int, List<ChatMessage>> _roomMessages = {};

  // Isolated Unread Counts: RoomID -> Count
  final Map<int, int> _unreadCounts = {};

  int? _currentUserId;
  String? _currentUserName;

  StreamSubscription? _subscription;

  // Get messages for a specific room
  List<ChatMessage> getMessages(int roomId) => _roomMessages[roomId] ?? [];

  // Get unread count for a specific room
  int getUnreadCount(int roomId) => _unreadCounts[roomId] ?? 0;

  // Total unread count for the bottom bar badge
  int get totalUnreadCount =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  void init(int roomId, int currentUserId) {
    print(
      "ChatProvider [$instanceId]: init for user $currentUserId in room $roomId",
    );
    _currentUserId = currentUserId;

    // Retrieve username if not set or "Unknown"
    if (_currentUserName == null || _currentUserName == "Unknown") {
      SharedPreferences.getInstance().then((prefs) {
        _currentUserName = prefs.getString("username") ?? "Unknown";
        print("ChatProvider: Retrieved username: $_currentUserName");
      });
    }

    // Fetch history ONLY for this room
    ApiService()
        .getChatMessages(roomId)
        .then((history) {
          final List<ChatMessage> historyMsgs = history
              .map((e) => ChatMessage.fromJson(e))
              .toList();

          _roomMessages[roomId] = historyMsgs;
          print(
            "ChatProvider: History loaded for room $roomId. Total: ${historyMsgs.length}",
          );
          notifyListeners();
        })
        .catchError((e) {
          print(
            "ChatProvider [$instanceId]: Error loading history for room $roomId: $e",
          );
        });

    // Ensure WebSocket is connected for this room
    ChatWebsocketService().connect(roomId);

    // Cancel existing subscription to avoid duplicate listeners
    _subscription?.cancel();

    // Listen to messages globally, but route them locally
    _subscription = ChatWebsocketService().stream.listen((data) {
      print("ChatProvider: Received data: $data");
      try {
        final msg = ChatMessage.fromJson(data);
        final int msgRoomId = msg.roomId;

        // Dedup
        final currentMsgs = _roomMessages[msgRoomId] ?? [];
        final bool isDuplicate = currentMsgs.reversed
            .take(5)
            .any(
              (m) =>
                  m.userId == _currentUserId &&
                  m.userId == msg.userId &&
                  m.message == msg.message,
            );

        if (isDuplicate) return;

        // Increment unread count if message is for a room we aren't "in" or just globally
        if (msg.userId != _currentUserId) {
          _unreadCounts[msgRoomId] = (_unreadCounts[msgRoomId] ?? 0) + 1;
        }

        // Add to the correct bucket
        scheduleMicrotask(() {
          _roomMessages[msgRoomId] = List.from(_roomMessages[msgRoomId] ?? [])
            ..add(msg);
          notifyListeners();

          if (msg.userId != _currentUserId && _currentUserId != null) {
            NotificationService.showNotification(msg, msgRoomId);
          }
        });
      } catch (e) {
        print("ChatProvider: Error processing message: $e");
      }
    }, onError: (error) => print("ChatProvider: Stream error: $error"));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void send(int roomId, String message) {
    if (_currentUserId == null) return;

    // Optimistic add to the SPECIFIC room list
    final optimisticMsg = ChatMessage(
      message: message,
      userId: _currentUserId!,
      roomId: roomId,
      senderName: _currentUserName ?? "Unknown",
    );

    _roomMessages[roomId] = List.from(_roomMessages[roomId] ?? [])
      ..add(optimisticMsg);
    notifyListeners();

    // Ensure we are connected to the correct room before sending
    ChatWebsocketService().connect(roomId).then((_) {
      ChatWebsocketService().sendMessage(
        message,
        _currentUserId!,
        _currentUserName ?? "Unknown",
      );
    });
  }

  void resetUnreadCount(int roomId) {
    _unreadCounts[roomId] = 0;
    notifyListeners();
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _roomMessages.clear();
    _unreadCounts.clear();
    notifyListeners();
  }
}
