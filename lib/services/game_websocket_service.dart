import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/utils/const.dart';

class GameWebsocketService {
  static final GameWebsocketService _instance =
      GameWebsocketService._internal();
  factory GameWebsocketService() => _instance;
  GameWebsocketService._internal();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  int? _currentRoomId;
  int? get currentRoomId => _currentRoomId;

  Timer? _reconnectTimer;

  Future<void> connect(int roomId) async {
    // If it's already the same room, do nothing
    if (_isConnected && _currentRoomId == roomId) {
      print("GameWebsocketService [Room $roomId]: Already connected.");
      return;
    }

    // Force disconnect if switching rooms
    if (_isConnected || _channel != null) {
      print(
        "GameWebsocketService: Switching from $_currentRoomId to $roomId. Cleaning up...",
      );
      disconnect();
      // Small pause to allow socket cleanup
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _currentRoomId = roomId;
    final url = "${Constants.wsBaseUrl}/ws/game/$roomId/";
    print("GameWebsocketService: Connecting to $url...");
    print("DEBUG: Final WebSocket URL: $url");

    _reconnectTimer?.cancel();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          // In case we haven't already marked as connected
          if (!_isConnected) {
            _isConnected = true;
            _connectionController.add(true);
          }
          final data = jsonDecode(message);
          _controller.add(data);
          print("Game message received [Room $roomId]: $data");
        },
        onDone: () {
          print("Game WebSocket [Room $roomId] onDone. Cleaning up...");
          _cleanup();
          _scheduleReconnect(roomId);
        },
        onError: (error, stackTrace) {
          print("Game WebSocket [Room $roomId] onError: $error\n$stackTrace");
          _cleanup();
          _scheduleReconnect(roomId);
        },
      );

      // OPTIMISM: Mark as connected while we wait for the first message.
      // If the URL is wrong or server is down, onError will trigger.
      _isConnected = true;
      _connectionController.add(true);
    } catch (e) {
      print("Failed to connect Game WebSocket [Room $roomId]: $e");
      _cleanup();
      _scheduleReconnect(roomId);
    }
  }

  void _scheduleReconnect(int roomId) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      print(
        "GameWebsocketService: Attempting auto-reconnect for room $roomId...",
      );
      connect(roomId);
    });
  }

  void _cleanup() {
    bool wasConnected = _isConnected;
    _isConnected = false;
    _currentRoomId = null;
    _channel = null;
    if (wasConnected) {
      _connectionController.add(false);
    }
  }

  void sendMove(int roomId, int fromRow, int fromCol, int toRow, int toCol) {
    if (_channel == null || !_isConnected) {
      print(
        "GameWebsocketService: Cannot send move, not connected! (Room: $roomId)",
      );
      return;
    }

    final data = {
      "type": "move",
      "room_id": roomId, // Explicitly include for backend/client parity
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
    print("GameWebsocketService: Manually disconnecting...");
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _cleanup();
  }
}
