import 'dart:async';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/services/notification_service.dart';
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
  int? _activeRoomId; // Track current viewing room

  // Static accessor for other services (like MqttService)
  static int? currentActiveRoomId;

  StreamSubscription? _subscription;

  // Get messages for a specific room
  List<ChatMessage> getMessages(int roomId) => _roomMessages[roomId] ?? [];

  // Get unread count for a specific room
  int getUnreadCount(int roomId) => _unreadCounts[roomId] ?? 0;

  // Total unread count for the bottom bar badge
  int get totalUnreadCount =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  void init(int roomId, int currentUserId, {bool setAsActive = true}) {
    print(
      "ChatProvider [$instanceId]: init for user $currentUserId in room $roomId (active: $setAsActive)",
    );
    _currentUserId = currentUserId;
    if (setAsActive) {
      _activeRoomId = roomId;
      currentActiveRoomId = roomId;
    }

    // Retrieve username if not set or "Unknown"
    if (_currentUserName == null || _currentUserName == "Unknown") {
      SharedPreferences.getInstance().then((prefs) {
        _currentUserName = prefs.getString("username") ?? "Unknown";
        print("ChatProvider: Retrieved username: $_currentUserName");
      });
    }

    // If we already have messages for this room, don't show empty screen while loading
    if (!_roomMessages.containsKey(roomId)) {
      _roomMessages[roomId] = [];
    }

    // Ensure listener is active BEFORE connecting or requesting history
    if (_subscription == null) {
      _listenToStream();
    }

    // Connect or request history if already connected
    if (ChatWebsocketService().isRoomConnected(roomId)) {
      ChatWebsocketService().requestHistory(roomId);
    } else {
      ChatWebsocketService().connect(roomId);
    }
  }

  void _listenToStream() {
    _subscription?.cancel();
    _subscription = ChatWebsocketService().stream.listen((data) {
      print("ChatProvider: Received data: $data");
      try {
        if (data['type'] == 'history') {
          final List<dynamic> historyData = data['messages'] ?? [];
          final int msgRoomId = data['room_id'];
          final historyMsgs = historyData
              .map((e) => ChatMessage.fromJson(e))
              .toList();

          final currentMsgs = _roomMessages[msgRoomId] ?? [];

          // Merge history into current messages, keeping optimistic ones
          final List<ChatMessage> merged = List.from(historyMsgs);
          for (var cm in currentMsgs) {
            if (!historyMsgs.any(
              (hm) => hm.message == cm.message && hm.userId == cm.userId,
            )) {
              merged.add(cm);
            }
          }

          _roomMessages[msgRoomId] = merged;
          notifyListeners();
          print(
            "ChatProvider: History loaded and merged via WebSocket for room $msgRoomId. Total: ${merged.length}",
          );
          return;
        }

        final msg = ChatMessage.fromJson(data);
        final int msgRoomId = msg.roomId;

        // Dedup: Only ignore if it's an ECHO from ourselves and it's most likely the one we just sent
        final currentMsgs = _roomMessages[msgRoomId] ?? [];
        final bool isDuplicateEcho =
            msg.userId == _currentUserId &&
            currentMsgs.reversed
                .take(3)
                .any((m) => m.message == msg.message && m.userId == msg.userId);

        if (isDuplicateEcho) {
          print("ChatProvider: Ignoring duplicate echo for room $msgRoomId");
          return;
        }

        // Increment unread count if message is for a room we aren't "in"
        if (msg.userId != _currentUserId && msgRoomId != _activeRoomId) {
          _unreadCounts[msgRoomId] = (_unreadCounts[msgRoomId] ?? 0) + 1;
        }

        // Add to the correct bucket
        scheduleMicrotask(() {
          _roomMessages[msgRoomId] = List.from(_roomMessages[msgRoomId] ?? [])
            ..add(msg);
          notifyListeners();

          // Only show notification if NOT in this room
          final bool isUserMatch = msg.userId == _currentUserId;
          final bool isRoomMatch = msgRoomId == _activeRoomId;

          print(
            "ChatProvider: Notification Decision - MsgRoom: $msgRoomId, ActiveRoom: $_activeRoomId, IsUserMatch: $isUserMatch, IsRoomMatch: $isRoomMatch",
          );

          if (!isUserMatch && !isRoomMatch) {
            print("ChatProvider: Triggering notification for Room $msgRoomId");
            NotificationService.showNotification(msg: msg, roomId: msgRoomId);
          } else {
            print(
              "ChatProvider: Notification SUPPRESSED. reason: ${isUserMatch ? 'Self-Message' : 'Active Room'}",
            );
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
        roomId,
        message,
        _currentUserId!,
        _currentUserName ?? "Unknown",
      );
    });
  }

  void resetUnreadCount(int roomId) {
    print("ChatProvider: resetUnreadCount $roomId");
    _unreadCounts[roomId] = 0;
    _activeRoomId = roomId;
    currentActiveRoomId = roomId;
    notifyListeners();
  }

  void clearActiveRoom() {
    print("ChatProvider: clearActiveRoom called (Current: $_activeRoomId)");
    _activeRoomId = null;
    currentActiveRoomId = null;
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _roomMessages.clear();
    _unreadCounts.clear();
    ChatWebsocketService().disconnectAll();
    notifyListeners();
  }
}
