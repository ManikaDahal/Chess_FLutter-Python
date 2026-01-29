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

  // Static accessor for other services
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
      print("ChatProvider [$instanceId]: Raw stream data: $data");
      try {
        if (data['type'] == 'history') {
          final List<dynamic> historyData = data['messages'] ?? [];
          final int msgRoomId = data['room_id'] ?? 0;
          print(
            "ChatProvider [$instanceId]: Processing history for room $msgRoomId. Count: ${historyData.length}",
          );

          final historyMsgs = historyData
              .map((e) => ChatMessage.fromJson(e))
              .toList();

          final currentMsgs = _roomMessages[msgRoomId] ?? [];

          // ROBUST MERGE STRATEGY:
          // Use a Map by ID to ensure we don't drop any server-verified messages
          // but also don't duplicate them.
          final Map<int, ChatMessage> idMap = {};
          final List<ChatMessage> optimisticMsgs = [];

          // 1. Add existing messages (to keep older history not in the new batch)
          for (var m in currentMsgs) {
            if (m.id != null)
              idMap[m.id!] = m;
            else
              optimisticMsgs.add(m);
          }

          // 2. Add new history batch (overwrites/updates existing by ID)
          for (var m in historyMsgs) {
            if (m.id != null) idMap[m.id!] = m;
          }

          // 3. Rebuild sorted list
          final List<ChatMessage> merged = idMap.values.toList();
          merged.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

          // 4. Append optimistic messages (which have id == null)
          // (Removing any that have been echoed back in historyMsgs)
          for (var optMsg in optimisticMsgs) {
            bool matched = historyMsgs.any(
              (h) => h.message == optMsg.message && h.userId == optMsg.userId,
            );
            if (!matched) {
              merged.add(optMsg);
            }
          }

          _roomMessages[msgRoomId] = merged;
          print(
            "ChatProvider [$instanceId]: Final merged count for room $msgRoomId: ${merged.length}",
          );
          notifyListeners();
          return;
        }

        // --- SINGLE MESSAGE LOGIC ---
        final msg = ChatMessage.fromJson(data);
        final int msgRoomId = msg.roomId;
        if (msgRoomId == 0) {
          print("ChatProvider ERROR: Message has room_id=0 ($data)");
          return;
        }

        final currentMsgs = _roomMessages[msgRoomId] ?? [];

        // 1. If this message ID already exists, it's a duplicate
        if (msg.id != null && currentMsgs.any((m) => m.id == msg.id)) {
          print("ChatProvider: Ignoring duplicate ID: ${msg.id}");
          return;
        }

        // 2. If it's from US, try to replace the optimistic entry
        bool replaced = false;
        if (msg.userId == _currentUserId) {
          print(
            "ChatProvider: Message is from current user. Looking for optimistic entry to replace...",
          );
          for (int i = currentMsgs.length - 1; i >= 0; i--) {
            final m = currentMsgs[i];
            if (m.id == null && m.message == msg.message) {
              currentMsgs[i] = msg;
              replaced = true;
              print(
                "ChatProvider: Replaced optimistic message with server ID: ${msg.id}",
              );
              break;
            }
          }
        }

        if (replaced) {
          notifyListeners();
          return;
        }

        // 3. New message (either from others or a fresh one from us)
        print(
          "ChatProvider: Adding new message to list. Room: $msgRoomId, From: ${msg.senderName}",
        );
        if (!_roomMessages.containsKey(msgRoomId)) {
          _roomMessages[msgRoomId] = [];
        }
        _roomMessages[msgRoomId]!.add(msg);

        // Update unread count if not active
        if (msgRoomId != _activeRoomId) {
          _unreadCounts[msgRoomId] = (_unreadCounts[msgRoomId] ?? 0) + 1;
        }

        notifyListeners();

        // 4. Notification Logic: Only for others' messages in non-active rooms
        final bool isVisible = msgRoomId == _activeRoomId;
        final bool fromMe = msg.userId == _currentUserId;

        print("ChatProvider NotifyCheck: roomMatch=$isVisible, isMe=$fromMe");

        if (!fromMe && !isVisible) {
          print(
            "ChatProvider: Triggering local notification for Room $msgRoomId",
          );
          NotificationService.showNotification(
            title: msg.senderName,
            body: msg.message,
            payload: {
              "room_id": msgRoomId,
              "user_id": msg.userId,
              "message": msg.message,
              "sender_name": msg.senderName,
            },
          );
        }
      } catch (e, st) {
        print("ChatProvider: Error processing message: $e\n$st");
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
