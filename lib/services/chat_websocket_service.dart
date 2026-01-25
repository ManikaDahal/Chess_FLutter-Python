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
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool isRoomConnected(int roomId) => _channels.containsKey(roomId);

  Future<void> connect(int roomId) async {
    if (_channels.containsKey(roomId)) {
      print("ChatWebsocketService: Already connected to room $roomId.");
      return;
    }

    final url = "wss://chess-websocket-dor6.onrender.com/ws/chat/$roomId/";
    print("ChatWebsocketService: Connecting to $url");

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channels[roomId] = channel;
      print("ChatWebsocketService: WebSocket channel created for room $roomId");

      channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          // Ensure room_id is in the data so listeners know where it came from
          if (!data.containsKey('room_id')) {
            data['room_id'] = roomId;
          }
          _controller.add(data);
          print("Message received from room $roomId: $data");
        },
        onDone: () {
          print("WebSocket for room $roomId disconnected");
          _channels.remove(roomId);
        },
        onError: (error) {
          print("WebSocket error in room $roomId: $error");
          _channels.remove(roomId);
        },
      );
    } catch (e) {
      print("Failed to connect WebSocket for room $roomId: $e");
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
      _channels.remove(roomId);
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
    _channels[roomId]?.sink.close();
    _channels.remove(roomId);
  }

  void disconnectAll() {
    for (final channel in _channels.values) {
      channel.sink.close();
    }
    _channels.clear();
  }
}
