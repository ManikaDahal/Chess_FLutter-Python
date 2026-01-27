import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class ChatWebsocketService {
  static final ChatWebsocketService _instance =
      ChatWebsocketService._internal();
  factory ChatWebsocketService() => _instance;
  ChatWebsocketService._internal();

  final Map<int, WebSocketChannel> _channels = {};
  final Map<int, Timer> _heartbeatTimers = {};
  final Map<int, Timer> _reconnectTimers = {};
  final Map<int, int> _retryAttempts = {};

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  // Connection state stream for UI feedback
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  bool isRoomConnected(int roomId) => _channels.containsKey(roomId);

  Future<void> connect(int roomId) async {
    if (_channels.containsKey(roomId)) {
      print("ChatWebsocketService: Already connected to room $roomId.");
      return;
    }

    _retryAttempts[roomId] = 0;
    await _connectWithRetry(roomId);
  }

  Future<void> _connectWithRetry(int roomId) async {
    final baseUrl = "wss://chess-websocket-dor6.onrender.com";
    // STICT SANITIZATION: Strip trailing #, / or whitespace
    final cleanBaseUrl = baseUrl.trim().replaceAll(RegExp(r'[#/]+$'), '');
    final url = "$cleanBaseUrl/ws/chat/$roomId/";

    print(
      "ChatWebsocketService: Connecting to $url (Attempt ${_retryAttempts[roomId]! + 1})",
    );

    try {
      _connectionStateController.add(ConnectionState.connecting);
      final uri = Uri.parse(url);
      print(
        "ChatWebsocketService: URI: scheme=${uri.scheme}, host=${uri.host}, port=${uri.port}",
      );

      final channel = WebSocketChannel.connect(uri);
      _channels[roomId] = channel;
      print("ChatWebsocketService: WebSocket channel created for room $roomId");

      // Reset retry attempts on successful connection
      _retryAttempts[roomId] = 0;
      _connectionStateController.add(ConnectionState.connected);

      // Start heartbeat
      _startHeartbeat(roomId);

      channel.stream.listen(
        (message) {
          final data = jsonDecode(message);

          // Handle pong response
          if (data['type'] == 'pong') {
            print("ChatWebsocketService: Received pong from room $roomId");
            return;
          }

          // Ensure room_id is in the data so listeners know where it came from
          if (!data.containsKey('room_id')) {
            data['room_id'] = roomId;
          }
          _controller.add(data);
          print("Message received from room $roomId: $data");
        },
        onDone: () {
          print("WebSocket for room $roomId disconnected");
          _handleDisconnect(roomId);
        },
        onError: (error) {
          print("WebSocket error in room $roomId: $error");
          _handleDisconnect(roomId);
        },
      );
    } catch (e) {
      print("Failed to connect WebSocket for room $roomId: $e");
      _handleDisconnect(roomId);
    }
  }

  void _startHeartbeat(int roomId) {
    _heartbeatTimers[roomId]?.cancel();
    _heartbeatTimers[roomId] = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      final channel = _channels[roomId];
      if (channel != null) {
        try {
          print("ChatWebsocketService: Sending ping to room $roomId");
          channel.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          print("ChatWebsocketService: Error sending ping to room $roomId: $e");
          _handleDisconnect(roomId);
        }
      }
    });
  }

  void _handleDisconnect(int roomId) {
    _channels.remove(roomId);
    _heartbeatTimers[roomId]?.cancel();
    _heartbeatTimers.remove(roomId);

    _connectionStateController.add(ConnectionState.disconnected);

    // Implement exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
    final attempt = _retryAttempts[roomId] ?? 0;
    if (attempt < 10) {
      // Max 10 attempts
      // For first few attempts, use longer delays to give Render server time to wake up
      final delaySeconds = attempt == 0
          ? 5 // First retry: 5s (server might be waking up)
          : attempt == 1
          ? 10 // Second retry: 10s (give more time)
          : (1 << (attempt - 1)).clamp(
              1,
              30,
            ); // Then exponential: 2, 4, 8, 16, 30

      final reason = attempt == 0
          ? "Server might be waking up from sleep..."
          : "Retrying connection...";

      print(
        "ChatWebsocketService: $reason Reconnecting to room $roomId in ${delaySeconds}s (attempt ${attempt + 1}/10)",
      );

      _reconnectTimers[roomId]?.cancel();
      _reconnectTimers[roomId] = Timer(Duration(seconds: delaySeconds), () {
        _retryAttempts[roomId] = attempt + 1;
        _connectWithRetry(roomId);
      });
    } else {
      print(
        "ChatWebsocketService: Max reconnection attempts reached for room $roomId. Server may be down.",
      );
      _connectionStateController.add(ConnectionState.failed);
      _retryAttempts.remove(roomId);
    }
  }

  void sendMessage(int roomId, String message, int userId, String senderName) {
    final channel = _channels[roomId];
    if (channel == null) {
      print(
        "ChatWebsocketService: CANNOT send message, no connection for room $roomId!",
      );
      connect(roomId);
      return;
    }
    try {
      final data = {
        "message": message,
        "user_id": userId,
        "sender_name": senderName,
        "room_id": roomId,
      };
      print("ChatWebsocketService: Sending data to room $roomId: $data");
      channel.sink.add(jsonEncode(data));
    } catch (e) {
      print("ChatWebsocketService: Error sending message to room $roomId: $e");
      _handleDisconnect(roomId);
    }
  }

  void requestHistory(int roomId) {
    final channel = _channels[roomId];
    if (channel == null) return;
    try {
      final data = {"type": "get_history", "room_id": roomId};
      print("ChatWebsocketService: Requesting history for room $roomId");
      channel.sink.add(jsonEncode(data));
    } catch (e) {
      print(
        "ChatWebsocketService: Error requesting history for room $roomId: $e",
      );
    }
  }

  void disconnect(int roomId) {
    _reconnectTimers[roomId]?.cancel();
    _reconnectTimers.remove(roomId);
    _heartbeatTimers[roomId]?.cancel();
    _heartbeatTimers.remove(roomId);
    _retryAttempts.remove(roomId);

    _channels[roomId]?.sink.close();
    _channels.remove(roomId);
  }

  void disconnectAll() {
    for (final roomId in _channels.keys.toList()) {
      disconnect(roomId);
    }
  }
}

enum ConnectionState { connecting, connected, disconnected, failed }
