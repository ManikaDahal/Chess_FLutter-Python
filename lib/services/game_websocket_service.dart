import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class GameWebsocketService {
  static final GameWebsocketService _instance =
      GameWebsocketService._internal();
  factory GameWebsocketService() => _instance;
  GameWebsocketService._internal();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect(int roomId) async {
    if (_isConnected) return;

    final url = "wss://chess-websocket-dor6.onrender.com/ws/game/$roomId/";
    print("GameWebsocketService: Connecting to $url");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          _controller.add(data);
          print("Game message received: $data");
        },
        onDone: () {
          print("Game WebSocket disconnected");
          _isConnected = false;
        },
        onError: (error) {
          print("Game WebSocket error: $error");
          _isConnected = false;
        },
      );
    } catch (e) {
      print("Failed to connect Game WebSocket: $e");
      _isConnected = false;
    }
  }

  void sendMove(int roomId, int fromRow, int fromCol, int toRow, int toCol) {
    if (_channel == null || !_isConnected) {
      print("GameWebsocketService: Cannot send move, not connected!");
      return;
    }

    final data = {
      "type": "move",
      "from_row": fromRow,
      "from_col": fromCol,
      "to_row": toRow,
      "to_col": toCol,
    };
    _channel!.sink.add(jsonEncode(data));
  }

  void resetGame(int roomId) {
    if (_channel == null || !_isConnected) return;
    _channel!.sink.add(jsonEncode({"type": "reset"}));
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
