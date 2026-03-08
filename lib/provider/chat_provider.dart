import 'dart:async';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/services/notification_preference_service.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatProvider with ChangeNotifier, WidgetsBindingObserver {
  static ChatProvider? instance;

  final String instanceId = DateTime.now().millisecondsSinceEpoch
      .toString()
      .substring(8);

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  ChatProvider() {
    instance = this;
    WidgetsBinding.instance.addObserver(this);
  }

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
    if (_currentUserId == currentUserId &&
        _activeRoomId == roomId &&
        setAsActive &&
        _subscription != null) {
      print(
        "ChatProvider [$instanceId]: Already initialized for room $roomId. Skipping.",
      );
      return;
    }

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
        _currentUserId = prefs.getInt(
          'userId',
        ); // Set _currentUserId from prefs
        _currentUserName = prefs.getString("username") ?? "Unknown";
        print(
          "ChatProvider [$instanceId]: Retrieved username: $_currentUserName, userId: $_currentUserId",
        );
      });
    }

    // If we already have messages for this room, don't show empty screen while loading
    if (!_roomMessages.containsKey(roomId)) {
      _roomMessages[roomId] = [];
    }

    // Ensure listener is active BEFORE connecting or requesting history
    if (_subscription == null) {
      print("ChatProvider [$instanceId]: Starting stream listener");
      _listenToStream();
    }

    // Connect or request history if already connected
    if (ChatWebsocketService().isRoomConnected(roomId)) {
      print(
        "ChatProvider [$instanceId]: Room $roomId already connected, requesting history",
      );
      ChatWebsocketService().requestHistory(roomId);
    } else {
      print(
        "ChatProvider [$instanceId]: Room $roomId NOT connected, initiating connection",
      );
      ChatWebsocketService().connect(roomId, _currentUserId!);
    }
  }

  void _listenToStream() {
    _subscription?.cancel();
    _subscription = ChatWebsocketService().stream.listen((data) {
      processIncomingPayload(data);
    }, onError: (error) => print("ChatProvider: Stream error: $error"));
  }

  /// Unified processor for messages from any source (WebSocket or FCM)
  void processIncomingPayload(Map<String, dynamic> data) {
    print("ChatProvider [$instanceId]: Processing incoming payload: $data");
    try {
      if (data['type'] == 'history') {
        final List<dynamic> historyData = data['messages'] ?? [];
        final int msgRoomId =
            int.tryParse(data['room_id']?.toString() ?? '0') ?? 0;
        print(
          "ChatProvider [$instanceId]: Processing history for room $msgRoomId. Count: ${historyData.length}",
        );

        final historyMsgs = historyData
            .map((e) => ChatMessage.fromJson(e))
            .toList();

        final currentMsgs = _roomMessages[msgRoomId] ?? [];

        // ROBUST MERGE STRATEGY:
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
      } else if (data['type'] == 'chess_invite') {
        final bool isForeground = _lifecycleState == AppLifecycleState.resumed;
        if (isForeground) {
          NotificationService.showNotification(
            title: "Chess Invite",
            body: data['message'] ?? "You have been invited to play chess!",
            payload: Map<String, dynamic>.from(data),
          );
        }
      } else if (data['type'] == 'message_status_update') {
        final int msgId =
            int.tryParse(data['message_id']?.toString() ?? '0') ?? 0;
        final int msgRoomId =
            int.tryParse(data['room_id']?.toString() ?? '0') ?? 0;
        final String statusStr = data['status'] ?? "";

        if (msgId != 0 && msgRoomId != 0) {
          final msgs = _roomMessages[msgRoomId] ?? [];
          final index = msgs.indexWhere((m) => m.id == msgId);
          if (index != -1) {
            MessageStatus newStatus = MessageStatus.sent;
            if (statusStr == "read")
              newStatus = MessageStatus.seen;
            else if (statusStr == "delivered")
              newStatus = MessageStatus.delivered;

            msgs[index] = msgs[index].copyWith(status: newStatus);
            notifyListeners();
          }
        }
      } else if (data['type'] == 'message_reaction_update') {
        final int msgId =
            int.tryParse(data['message_id']?.toString() ?? '0') ?? 0;
        final int msgRoomId =
            int.tryParse(data['room_id']?.toString() ?? '0') ?? 0;
        final int reactionUserId =
            int.tryParse(data['user_id']?.toString() ?? '0') ?? 0;
        final String emoji = data['emoji'] ?? "";

        if (msgId != 0 && msgRoomId != 0) {
          final msgs = _roomMessages[msgRoomId] ?? [];
          final index = msgs.indexWhere((m) => m.id == msgId);
          if (index != -1) {
            final List<MessageReaction> currentReactions =
                List<MessageReaction>.from(msgs[index].reactions);
            final int reactionIndex = currentReactions.indexWhere(
              (r) => r.userId == reactionUserId,
            );

            final String action =
                data['action']?.toString() ?? "added"; // Default to added

            if (action == "removed") {
              if (reactionIndex != -1) {
                currentReactions.removeAt(reactionIndex);
              }
            } else {
              // action == "added"
              if (reactionIndex != -1) {
                currentReactions[reactionIndex] = MessageReaction(
                  userId: reactionUserId,
                  emoji: emoji,
                );
              } else {
                currentReactions.add(
                  MessageReaction(userId: reactionUserId, emoji: emoji),
                );
              }
            }

            msgs[index] = msgs[index].copyWith(reactions: currentReactions);
            notifyListeners();
          }
        }
      } else {
        // Only process if it looks like a chat message
        if (data['type'] == 'chat_message' || data.containsKey('message')) {
          final msg = ChatMessage.fromJson(data);
          _processIncomingMessage(
            msg,
            trackingId: data['trackingId']?.toString(),
          );
        } else {
          print(
            "ChatProvider: Ignoring non-chat payload Type: ${data['type']}",
          );
        }
      }
    } catch (e, st) {
      print("ChatProvider: Error processing payload: $e\n$st");
    }
  }

  void _processIncomingMessage(ChatMessage msg, {String? trackingId}) {
    // Sanitization: Ignore empty message bodies
    if (msg.message.trim().isEmpty) {
      print("ChatProvider: Ignoring empty message payload.");
      return;
    }

    final int msgRoomId = msg.roomId;
    if (msgRoomId == 0) {
      print("ChatProvider ERROR: Message has room_id=0");
      return;
    }

    if (!_roomMessages.containsKey(msgRoomId)) {
      _roomMessages[msgRoomId] = [];
    }
    final List<ChatMessage> currentMsgs = _roomMessages[msgRoomId]!;

    // 1. Deduplication
    if (msg.id != null && currentMsgs.any((m) => m.id == msg.id)) {
      print("ChatProvider: Ignoring duplicate ID: ${msg.id}");
      return;
    }

    // 2. Optimistic replacement – upgrade status to `sent` when server confirms
    bool substituted = false;
    if (msg.userId == _currentUserId) {
      for (int i = currentMsgs.length - 1; i >= 0; i--) {
        final m = currentMsgs[i];
        // Match by trackingId if available, else fallback to message content
        bool isMatch = false;
        if (msg.trackingId != null && msg.trackingId!.isNotEmpty) {
          isMatch = (m.id == null && m.trackingId == msg.trackingId);
        } else {
          isMatch = (m.id == null && m.message == msg.message);
        }

        if (isMatch) {
          // Preserve more advanced status if it arrived earlier or exists in payload
          final newStatus = (msg.status == MessageStatus.sending)
              ? MessageStatus.sent
              : msg.status;
          currentMsgs[i] = msg.copyWith(status: newStatus);
          substituted = true;
          print(
            "ChatProvider: Replaced optimistic message with server ID: ${msg.id} (status: sent)",
          );
          break;
        }
      }
    }

    if (!substituted) {
      print(
        "ChatProvider: Adding new message from ${msg.senderName} to Room $msgRoomId",
      );
      currentMsgs.add(msg);
    }

    // ── SEND STATUS RECEIPTS ──
    if (msg.id != null && msg.userId != _currentUserId) {
      // If we received it, it's at least "delivered"
      ChatWebsocketService().sendStatusUpdate(msgRoomId, msg.id!, "delivered");

      // If we are currently IN the room, it's also "read"
      if (msgRoomId == _activeRoomId) {
        ChatWebsocketService().sendStatusUpdate(msgRoomId, msg.id!, "read");
      }
    }

    // 3. Update unread count
    if (msgRoomId != _activeRoomId) {
      final String category = msg.roomId == 1
          ? 'system'
          : 'message'; // Mapping for chat room logic
      NotificationPreferenceService.isCategoryBlockedLocally(category).then((
        isBlocked,
      ) {
        if (!isBlocked) {
          _unreadCounts[msgRoomId] = (_unreadCounts[msgRoomId] ?? 0) + 1;
          notifyListeners();
        } else {
          print(
            "ChatProvider: Suppressing unread count for blocked category '$category' (Live OS status)",
          );
        }
      });
    } else {
      notifyListeners();
    }

    // 4. Unified Notification Alert
    final bool isVisible = msgRoomId == _activeRoomId;
    final bool fromMe = msg.userId == _currentUserId;

    // CRITICAL: Only show manual notification if APP IS IN FOREGROUND.
    // If the app is in background/paused, the OS handles the FCM notification automatically.
    final bool isForeground = _lifecycleState == AppLifecycleState.resumed;

    print(
      "ChatProvider NotifyCheck: roomMatch=$isVisible, isMe=$fromMe, isFG=$isForeground",
    );

    if (!fromMe && !isVisible && isForeground) {
      print(
        "ChatProvider: Triggering manual foreground notification alert (Tracking ID: $trackingId)",
      );
      NotificationService.showNotification(
        title: msg.senderName,
        body: msg.message,
        payload: {
          "room_id": msgRoomId,
          "user_id": msg.userId,
          "message": msg.message,
          "sender_name": msg.senderName,
          if (trackingId != null) "trackingId": trackingId,
        },
      );
    } else if (!isForeground) {
      print(
        "ChatProvider: Suppressing manual alert (OS handles background FCM)",
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("ChatProvider: Lifecycle state changed to $state");
    _lifecycleState = state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> send(int roomId, String message) async {
    if (_currentUserId == null) return;

    final String trackingId =
        "t_${DateTime.now().millisecondsSinceEpoch}_${roomId}_$message".hashCode
            .toString();

    final optimisticMsg = ChatMessage(
      message: message,
      userId: _currentUserId!,
      roomId: roomId,
      senderName: _currentUserName ?? "Me",
      status: MessageStatus.sending,
      trackingId: trackingId,
    );

    // 1. Add optimistical message locally
    _roomMessages[roomId] = List.from(_roomMessages[roomId] ?? [])
      ..add(optimisticMsg);
    notifyListeners();

    // 2. Transmit via WebSockets
    try {
      await ChatWebsocketService().connect(roomId, _currentUserId!);
      ChatWebsocketService().sendMessage(
        roomId,
        message,
        _currentUserId!,
        _currentUserName ?? "Me",
        trackingId: trackingId,
      );
    } catch (e) {
      print("ChatProvider: Error sending message: $e");
    }
  }

  void resetUnreadCount(int roomId) {
    print("ChatProvider: resetUnreadCount $roomId");
    _unreadCounts[roomId] = 0;
    _activeRoomId = roomId;
    currentActiveRoomId = roomId;

    // Send read receipts for all messages in the room that we haven't read yet
    final msgs = _roomMessages[roomId] ?? [];
    for (var m in msgs) {
      if (m.id != null &&
          m.userId != _currentUserId &&
          m.status != MessageStatus.seen) {
        ChatWebsocketService().sendStatusUpdate(roomId, m.id!, "read");
      }
    }

    notifyListeners();
  }

  void toggleReaction(int roomId, int messageId, String emoji) {
    // Optimistic toggle
    final msgs = _roomMessages[roomId] ?? [];
    final index = msgs.indexWhere((m) => m.id == messageId);
    if (index != -1 && _currentUserId != null) {
      final currentReactions = List<MessageReaction>.from(
        msgs[index].reactions,
      );
      final reactionIndex = currentReactions.indexWhere(
        (r) => r.userId == _currentUserId,
      );

      if (reactionIndex != -1) {
        if (currentReactions[reactionIndex].emoji == emoji) {
          currentReactions.removeAt(reactionIndex);
        } else {
          currentReactions[reactionIndex] = MessageReaction(
            userId: _currentUserId!,
            emoji: emoji,
          );
        }
      } else {
        currentReactions.add(
          MessageReaction(userId: _currentUserId!, emoji: emoji),
        );
      }

      msgs[index] = msgs[index].copyWith(reactions: currentReactions);
      notifyListeners();

      // Sync with server
      ChatWebsocketService().sendReaction(roomId, messageId, emoji);
    }
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
