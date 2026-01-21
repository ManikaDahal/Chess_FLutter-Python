import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool get isConnected => _channel != null;

  void connect(String roomId) {
    final url = "wss://chess-websocket-dor6.onrender.com/ws/call/$roomId/";

    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        _controller.add(data);
      },
      onError: (error) {
        print("WebSocket Error: $error");
      },
      onDone: () {
        print("WebSocket Disconnected");
      },
    );
  }

  void sendMove(String move, int userId) {
    if (_channel == null) return;

    final data = {
      "type": "move",
      "move": move,
      "user_id": userId,
    };

    _channel!.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
