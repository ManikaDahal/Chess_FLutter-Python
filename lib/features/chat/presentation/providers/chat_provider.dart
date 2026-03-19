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
  final int? currentUserId;
  final String? currentUserName;
  final int? activeRoomId;

  const ChatState({
    this.roomMessages = const {},
    this.unreadCounts = const {},
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
    int? currentUserId,
    String? currentUserName,
    int? activeRoomId,
    bool clearActiveRoom = false,
  }) {
    return ChatState(
      roomMessages: roomMessages ?? this.roomMessages,
      unreadCounts: unreadCounts ?? this.unreadCounts,
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

    state = state.copyWith(
      currentUserId: currentUserId,
      activeRoomId: setAsActive ? roomId : state.activeRoomId,
      roomMessages: newRoomMsgs,
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

        final List<ChatMessage> merged = idMap.values.toList();
        merged.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

        for (var optMsg in optimisticMsgs) {
          bool matched = historyMsgs.any((h) => h.message == optMsg.message && h.userId == optMsg.userId);
          if (!matched) merged.add(optMsg);
        }

        final newRoomMsgs = Map<int, List<ChatMessage>>.from(state.roomMessages);
        newRoomMsgs[msgRoomId] = merged;

        state = state.copyWith(roomMessages: newRoomMsgs);
      } else if (data['type'] == 'chess_invite') {
        if (_lifecycleState == AppLifecycleState.resumed) {
          NotificationService.showNotification(
            title: "Chess Invite",
            body: data['message'] ?? "You have been invited to play chess!",
            payload: Map<String, dynamic>.from(data),
          );
        }
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
