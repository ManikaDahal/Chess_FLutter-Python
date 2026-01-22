import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class ChatWebsocketService {
  static final ChatWebsocketService _instance =
      ChatWebsocketService._internal();
  factory ChatWebsocketService() => _instance;
  ChatWebsocketService._internal();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get isConnected => _channel != null;

  int? _lastRoomId;

  Future<void> connect(int roomId) async {
    if (_channel != null && _lastRoomId == roomId) {
      print(
        "ChatWebsocketService: Already connected to room $roomId, skipping.",
      );
      return;
    }

    if (_channel != null) {
      print(
        "ChatWebsocketService: Switching from $_lastRoomId to $roomId. Closing old connection.",
      );
      await _channel!.sink.close();
      _channel = null;
    }

    _lastRoomId = roomId;
    final url =
        "wss://chess-websocket-dor6.onrender.com/ws/chat/$roomId/"; // Added trailing slash
    print("ChatWebsocketService: Attempting connection to $url");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      print("ChatWebsocketService: WebSocket channel created for room $roomId");

      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _controller.add(data);
          print("Message received: $data");
        },
        onDone: () {
          print("WebSocket disconnected");
          _channel = null;
        },
        onError: (error) {
          print("WebSocket error: $error");
          _channel = null;
        },
      );
    } catch (e) {
      print("Failed to connect WebSocket: $e");
      _channel = null;
    }
  }

  void sendMessage(String message, int userId) {
    if (_channel == null) {
      print("ChatWebsocketService: CANNOT send message, channel is null!");
      if (_lastRoomId != null) {
        print(
          "ChatWebsocketService: Attempting emergency reconnect to room $_lastRoomId...",
        );
        connect(_lastRoomId!);
      }
      return;
    }
    try {
      final data = {"message": message, "user_id": userId};
      print("ChatWebsocketService: Sending data: $data");
      _channel!.sink.add(jsonEncode(data));
      print("ChatWebsocketService: Data added to sink.");
    } catch (e) {
      print("ChatWebsocketService: Error sending message: $e");
      _channel = null;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
