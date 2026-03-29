import 'dart:async';

import 'package:chess_game_manika/features/chat/data/models/chat_model.dart';
import 'package:chess_game_manika/features/chat/services/chat_websocket_service.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatState {
  final Map<int, List<ChatMessage>> roomMessages;
  final Map<int, int> unreadCounts;
  final Map<int, bool> loadingRooms;
  final Map<int, String> roomParticipants;
  final int? currentUserId;
  final String? currentUserName;
  final int? activeRoomId;
 
  const ChatState({
    this.roomMessages = const {},
    this.unreadCounts = const {},
    this.loadingRooms = const {},
    this.roomParticipants = const {},
    this.currentUserId,
    this.currentUserName,
    this.activeRoomId,
  });

  int get totalUnreadCount => unreadCounts.values.fold(0, (sum, count) => sum + count);
  List<ChatMessage> getMessages(int roomId) => roomMessages[roomId] ?? [];
  int getUnreadCount(int roomId) => unreadCounts[roomId] ?? 0;

  ChatState copyWith({
    Map<int, List<ChatMessage>>? roomMessages,
    Map<int, int>? unreadCounts,
    Map<int, bool>? loadingRooms,
    Map<int, String>? roomParticipants,
    int? currentUserId,
    String? currentUserName,
    int? activeRoomId,
    bool clearActiveRoom = false,
  }) {
    return ChatState(
      roomMessages: roomMessages ?? this.roomMessages,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      loadingRooms: loadingRooms ?? this.loadingRooms,
      roomParticipants: roomParticipants ?? this.roomParticipants,
      currentUserId: currentUserId ?? this.currentUserId,
      currentUserName: currentUserName ?? this.currentUserName,
      activeRoomId: clearActiveRoom ? null : (activeRoomId ?? this.activeRoomId),
    );
  }
}

class ChatNotifier extends Notifier<ChatState> with WidgetsBindingObserver {
  static ChatNotifier? instance;
  final String instanceId = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  StreamSubscription? _subscription;
  static int? currentActiveRoomId;

  @override
  ChatState build() {
    instance = this;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
    });
    return const ChatState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    _lifecycleState = appState;
  }

  void init(int roomId, int currentUserId, {bool setAsActive = true}) {
    if (state.currentUserId == currentUserId &&
        state.activeRoomId == roomId &&
        setAsActive &&
        _subscription != null) {
      return;
    }

    ChatNotifier.currentActiveRoomId = setAsActive ? roomId : state.activeRoomId;

    SharedPreferences.getInstance().then((prefs) {
      final username = prefs.getString("username") ?? "Unknown";
      state = state.copyWith(currentUserName: username);
    });

    final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);
    if (!newRoomMsgs.containsKey(roomId)) {
      newRoomMsgs[roomId] = [];
    }

    final newLoadingRooms = Map<int, bool>.from(state.loadingRooms);
    newLoadingRooms[roomId] = true;
 
    state = state.copyWith(
      currentUserId: currentUserId,
      activeRoomId: setAsActive ? roomId : state.activeRoomId,
      roomMessages: newRoomMsgs,
      loadingRooms: newLoadingRooms,
    );
 
    if (_subscription == null) {
      _listenToStream();
    }
 
    if (ChatWebsocketService().isRoomConnected(roomId)) {
      ChatWebsocketService().requestHistory(roomId);
    } else {
      ChatWebsocketService().connect(roomId, currentUserId);
    }
  }

  void _listenToStream() {
    _subscription?.cancel();
    _subscription = ChatWebsocketService().stream.listen((data) {
      processIncomingPayload(data);
    }, onError: (error) => print("ChatNotifier: Stream error: $error"));
  }

  void processIncomingPayload(Map<String, dynamic> data) {
    try {
      if (data['type'] == 'history') {
        final List<dynamic> historyData = data['messages'] ?? [];
        final int msgRoomId = int.tryParse(data['room_id']?.toString() ?? '0') ?? 0;

        final historyMsgs = historyData.map((e) => ChatMessage.fromJson(e)).toList();
        final currentMsgs = state.roomMessages[msgRoomId] ?? [];

        final Map<int, ChatMessage> idMap = {};
        final List<ChatMessage> optimisticMsgs = [];

        for (var m in currentMsgs) {
          if (m.id != null) idMap[m.id!] = m;
          else optimisticMsgs.add(m);
        }

        for (var m in historyMsgs) {
          if (m.id != null) idMap[m.id!] = m;
        }
 
        // Update room participant name if found in history
        String? otherName;
        for (var m in historyMsgs) {
          if (m.userId != state.currentUserId) {
            otherName = m.senderName;
            break;
          }
        }
 
        final newRoomParticipants = Map<int, String>.from(state.roomParticipants);
        if (otherName != null) {
          newRoomParticipants[msgRoomId] = otherName;
        }
 
        final List<ChatMessage> merged = idMap.values.toList();
        merged.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
 
        for (var optMsg in optimisticMsgs) {
          bool matched = historyMsgs.any((h) => h.message == optMsg.message && h.userId == optMsg.userId);
          if (!matched) merged.add(optMsg);
        }
 
        final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);
        newRoomMsgs[msgRoomId] = merged;
 
        final newLoadingRooms = Map<int, bool>.from(state.loadingRooms);
        newLoadingRooms[msgRoomId] = false;
 
        state = state.copyWith(
          roomMessages: newRoomMsgs,
          loadingRooms: newLoadingRooms,
          roomParticipants: newRoomParticipants,
        );
      } else if (data['type'] == 'chess_invite' || data['type'] == 'snake_invite') {
        if (_lifecycleState == AppLifecycleState.resumed) {
          final String title = data['type'] == 'snake_invite' ? "Snake & Ladder Invite" : "Chess Invite";
          NotificationService.showNotification(
            title: title,
            body: data['message'] ?? "You have been invited to play!",
            payload: Map<String, dynamic>.from(data),
          );
        }
      } else if (data['type'] == 'message_status') {
        final int msgId = int.tryParse(data['message_id']?.toString() ?? '0') ?? 0;
        final String status = data['status'] ?? 'sent';
        _updateMessageStatus(msgId, status);
      } else {
        if (data['type'] == 'chat_message' || data.containsKey('message')) {
          final msg = ChatMessage.fromJson(data);
          _processIncomingMessage(msg, trackingId: data['trackingId']?.toString());
        }
      }
    } catch (e, st) {
      print("ChatNotifier: Error $e\n$st");
    }
  }

  void _updateMessageStatus(int msgId, String status) {
    bool found = false;
    final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);

    for (var roomId in newRoomMsgs.keys) {
      final messages = List<ChatMessage>.from(newRoomMsgs[roomId]!);
      for (int i = 0; i < messages.length; i++) {
        if (messages[i].id == msgId) {
          messages[i] = ChatMessage(
            id: messages[i].id,
            message: messages[i].message,
            userId: messages[i].userId,
            roomId: messages[i].roomId,
            senderName: messages[i].senderName,
            timestamp: messages[i].timestamp,
            status: status,
          );
          found = true;
          break;
        }
      }
      if (found) {
        newRoomMsgs[roomId] = messages;
        break;
      }
    }

    if (found) {
      state = state.copyWith(roomMessages: newRoomMsgs);
    }
  }

  void _processIncomingMessage(ChatMessage msg, {String? trackingId}) {
    if (msg.message.trim().isEmpty) return;

    final int msgRoomId = msg.roomId;
    if (msgRoomId == 0) return;

    final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);
    if (!newRoomMsgs.containsKey(msgRoomId)) newRoomMsgs[msgRoomId] = [];
    final currentMsgs = List<ChatMessage>.from(newRoomMsgs[msgRoomId]!);

    if (msg.id != null && currentMsgs.any((m) => m.id == msg.id)) return;

    bool replaced = false;
    if (msg.userId == state.currentUserId) {
      for (int i = currentMsgs.length - 1; i >= 0; i--) {
        final m = currentMsgs[i];
        if (m.id == null && m.message == msg.message) {
          currentMsgs[i] = msg;
          replaced = true;
          break;
        }
      }
    }

    if (!replaced) {
      currentMsgs.add(msg);
    }
    newRoomMsgs[msgRoomId] = currentMsgs;

    final newUnreadCounts = Map<int, int>.from(state.unreadCounts);
    if (msgRoomId != state.activeRoomId) {
      newUnreadCounts[msgRoomId] = (newUnreadCounts[msgRoomId] ?? 0) + 1;
    }

    state = state.copyWith(roomMessages: newRoomMsgs, unreadCounts: newUnreadCounts);

    final bool isVisible = msgRoomId == state.activeRoomId;
    final bool fromMe = msg.userId == state.currentUserId;
    final bool isForeground = _lifecycleState == AppLifecycleState.resumed;

    if (!fromMe && !isVisible && isForeground) {
      NotificationService.showNotification(
        title: msg.senderName,
        body: msg.message,
        payload: {
          "room_id": msgRoomId,
          "user_id": msg.userId,
          "message": msg.message,
          "sender_name": msg.senderName,
          "status": "delivered", // Mark as delivered when showing notification
          if (trackingId != null) "trackingId": trackingId,
        },
      );
    }
  }

  void send(int roomId, String message) {
    if (state.currentUserId == null) return;

    final optimisticMsg = ChatMessage(
      message: message,
      userId: state.currentUserId!,
      roomId: roomId,
      senderName: state.currentUserName ?? "Unknown",
    );

    final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);
    final currentMsgs = List<ChatMessage>.from(newRoomMsgs[roomId] ?? []);
    currentMsgs.add(optimisticMsg);
    newRoomMsgs[roomId] = currentMsgs;

    state = state.copyWith(roomMessages: newRoomMsgs);

    ChatWebsocketService().connect(roomId, state.currentUserId!).then((_) {
      ChatWebsocketService().sendMessage(
        roomId,
        message,
        state.currentUserId!,
        state.currentUserName ?? "Unknown",
      );
    });
  }

  void resetUnreadCount(int roomId) {
    final newUnreadCounts = Map<int, int>.from(state.unreadCounts);
    newUnreadCounts[roomId] = 0;
    ChatNotifier.currentActiveRoomId = roomId;
    state = state.copyWith(unreadCounts: newUnreadCounts, activeRoomId: roomId);
  }

  /// Pre-seeds the display name for [roomId] so the header shows
  /// the correct name immediately without waiting for message history.
  void setRoomParticipant(int roomId, String name) {
    final updated = Map<int, String>.from(state.roomParticipants);
    updated[roomId] = name;
    state = state.copyWith(roomParticipants: updated);
  }

  void clearActiveRoom() {
    ChatNotifier.currentActiveRoomId = null;
    state = state.copyWith(clearActiveRoom: true);
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    ChatWebsocketService().disconnectAll();
    state = const ChatState();
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});
