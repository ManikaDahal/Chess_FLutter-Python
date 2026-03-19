import 'dart:async';
import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  Timer? _pingTimer;

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
    // REMOVE TRIALING SLASH: Some proxies/servers (like Render/Daphne) are sensitive to this
    final url = "${Constants.wsBaseUrl}/ws/game/$roomId";
    print("GameWebsocketService: Connecting to $url...");
    print("DEBUG: Final WebSocket URL: $url");

    _reconnectTimer?.cancel();

    try {
      // Wake up the server before connecting
      await ApiService().probe(ApiBase.vercel);

      var uri = Uri.parse(url);
      // Fix: Use proper default ports if not explicitly set (avoids :0 issues on some platforms)
      if (uri.port == 0) {
        uri = uri.replace(port: uri.scheme == 'wss' ? 443 : 80);
      }
      _channel = WebSocketChannel.connect(uri);

      // Optimisticaly set connected as soon as we start listening
      // This allows the UI to attempt sending moves without waiting for a heartbeat
      _isConnected = true;
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }
      _startHeartbeat(roomId);

      _channel!.stream.listen(
        (message) {
          _lastMessageTime = DateTime.timestamp();
          try {
            final data = jsonDecode(message);

            // If we receive ANY valid JSON, we are definitely connected
            if (!_isConnected) {
              _isConnected = true;
              if (!_connectionController.isClosed) {
                _connectionController.add(true);
              }
              _startHeartbeat(roomId);
            }

            if (!_controller.isClosed) {
              _controller.add(data);
            }
            print("Game message received [Room $roomId]: $data");
          } catch (e) {
            print(
              "Error decoding Game WebSocket message: $e\nMessage: $message",
            );
          }
        },
        onDone: () {
          print("Game WebSocket [Room $roomId] onDone. Cleaning up...");
          _cleanup();
          _scheduleReconnect(roomId);
        },
        onError: (error, stackTrace) {
          print(
            "Game WebSocket FATAL ERROR [Room $roomId]: $error\n$stackTrace",
          );
          _cleanup();
          _scheduleReconnect(roomId);
        },
      );
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

  DateTime? _lastMessageTime;

  void _startHeartbeat(int roomId) {
    _pingTimer?.cancel();
    _lastMessageTime = DateTime.timestamp();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_isConnected && _channel != null) {
        final now = DateTime.timestamp();
        if (_lastMessageTime != null &&
            now.difference(_lastMessageTime!).inSeconds > 60) {
          print(
            "GameWebsocketService [Room $roomId]: Zombie connection detected. Reconnecting...",
          );
          _channel?.sink.close();
          _cleanup();
          _scheduleReconnect(roomId);
          return;
        }
        _channel!.sink.add(jsonEncode({"type": "ping", "room_id": roomId}));
      } else {
        timer.cancel();
      }
    });
  }

  void _cleanup() {
    bool wasConnected = _isConnected;
    _pingTimer?.cancel();
    _isConnected = false;
    _currentRoomId = null;
    _channel = null;
    if (wasConnected) {
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
    }
  }

  void sendMove(
    int roomId,
    int senderUserId,
    int fromRow,
    int fromCol,
    int toRow,
    int toCol,
  ) {
    if (_channel == null || !_isConnected) {
      print(
        "GameWebsocketService: Cannot send move, not connected! (Room: $roomId)",
      );
      return;
    }

    final data = {
      "type": "move",
      "room_id": roomId, // Explicitly include for backend/client parity
      "sender_id": senderUserId,
      "from_row": fromRow,
      "from_col": fromCol,
      "to_row": toRow,
      "to_col": toCol,
    };
    _channel!.sink.add(jsonEncode(data));
  }

  void sendLeave(int roomId, int userId) {
    if (_channel == null || !_isConnected) return;
    _channel!.sink.add(
      jsonEncode({"type": "user_left", "room_id": roomId, "user_id": userId}),
    );
  }

  void resetGame(int roomId) {
    if (_channel == null || !_isConnected) return;
    _channel!.sink.add(jsonEncode({"type": "reset", "room_id": roomId}));
  }

  void disconnect() {
    print("GameWebsocketService: Manually disconnecting...");
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _cleanup();
  }
}
