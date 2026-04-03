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

  Completer<void>? _connectionReady;

  bool get isLocal => Constants.localHostIp != null;

  Timer? _reconnectTimer;
  Timer? _pingTimer;

  bool _preventReconnect = false;

  Future<void> connect(int roomId, {bool forceReconnect = false}) async {
    if (!forceReconnect && _isConnected && _currentRoomId == roomId) {
      print("GameWebsocketService [Room $roomId]: Already connected.");
      return;
    }

    if (_isConnected || _channel != null) {
      print("GameWebsocketService: Cleaning up existing connection before connecting to $roomId...");
      disconnect();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _preventReconnect = false;
    _currentRoomId = roomId;

    final url = isLocal
        ? Constants.wsBaseUrl 
        : "${Constants.wsBaseUrl}/ws/game/$roomId";
    
    _reconnectTimer?.cancel();

    // Connection Retry Loop (3 attempts)
    int retryCount = 0;
    while (retryCount < 3) {
      try {
        final uri = Uri.parse(url);
        print("GameWebsocketService: Connecting to $uri (Attempt ${retryCount + 1})...");
        
        _channel = WebSocketChannel.connect(uri);
        _connectionReady = Completer<void>();

        if (!isLocal) {
          // Online mode: set connected optimistically
          _isConnected = true;
          if (!_connectionController.isClosed) {
            _connectionController.add(true);
          }
          _connectionReady?.complete();
        }
        
        // Listen to the stream immediately to catch the handshake
        _channel!.stream.listen(
          (message) {
            _lastMessageTime = DateTime.timestamp();
            try {
              final data = jsonDecode(message);

              // Handshake logic: If we receive valid JSON, the relay is active
              if (!_isConnected) {
                _isConnected = true;
                if (!_connectionController.isClosed) {
                  _connectionController.add(true);
                }
                if (!(_connectionReady?.isCompleted ?? true)) {
                  _connectionReady?.complete();
                }
                _startHeartbeat(roomId);
              }

              if (!_controller.isClosed) {
                _controller.add(data);
              }
              if (isLocal) {
                print("[GAME SYNC] Received local move/msg: $data");
              }
            } catch (e) {
              print("Error decoding Game WebSocket message: $e\nMessage: $message");
            }
          },
          onDone: () {
            print("Game WebSocket [Room $roomId] onDone. Cleaning up...");
            _cleanup();
            _scheduleReconnect(roomId);
          },
          onError: (error) {
            print("Game WebSocket [Room $roomId] Error: $error");
            _cleanup();
            _scheduleReconnect(roomId);
          },
        );

        // If we reached here without error, we break the retry loop
        break; 

      } catch (e) {
        retryCount++;
        print("GameWebsocketService: Connect failed: $e. Retrying in 500ms...");
        if (retryCount >= 3) {
          print("GameWebsocketService: Max retries reached.");
          _cleanup();
          _scheduleReconnect(roomId);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _scheduleReconnect(int roomId) {
    if (_preventReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      print("GameWebsocketService: Attempting auto-reconnect...");
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
        if (_lastMessageTime != null && now.difference(_lastMessageTime!).inSeconds > 60) {
          print("GameWebsocketService: Connection stale. reconnecting...");
          _cleanup();
          connect(roomId);
        } else {
          _channel!.sink.add(jsonEncode({"type": "ping"}));
        }
      } else {
        timer.cancel();
      }
    });
  }

  void sendMove(int roomId, int senderUserId, int fromRow, int fromCol, int toRow, int toCol) async {
    if (isLocal && _connectionReady != null) {
      await _connectionReady!.future.timeout(const Duration(seconds: 2)).catchError((_) => null);
    }

    if (_channel == null || !_isConnected) {
      print("GameWebsocketService: Cannot send move, not connected!");
      return;
    }

    final data = {
      "type": "move",
      "room_id": roomId,
      "sender_id": senderUserId,
      "from_row": fromRow,
      "from_col": fromCol,
      "to_row": toRow,
      "to_col": toCol,
    };
    if (isLocal) print("[GAME SYNC] Sending local move: $data");
    _channel!.sink.add(jsonEncode(data));
  }

  void sendJoin(int roomId, int userId) async {
    if (isLocal && _connectionReady != null) {
      await _connectionReady!.future.timeout(const Duration(seconds: 2)).catchError((_) => null);
      await Future.delayed(const Duration(milliseconds: 100)); 
    }
    if (_channel == null || !_isConnected) return;
    if (isLocal) print("[GAME SYNC] Sending local join: $userId");
    _channel!.sink.add(jsonEncode({"type": "join", "room_id": roomId, "user_id": userId}));
  }

  void sendLeave(int roomId, int userId) {
    if (_channel == null || !_isConnected) return;
    _channel!.sink.add(jsonEncode({"type": "user_left", "room_id": roomId, "user_id": userId}));
  }

  void resetGame(int roomId) {
    if (_channel == null || !_isConnected) return;
    _channel!.sink.add(jsonEncode({"type": "reset", "room_id": roomId}));
  }

  void disconnect() {
    print("GameWebsocketService: Manually disconnecting...");
    _preventReconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _cleanup();
  }

  void _cleanup() {
    _isConnected = false;
    _currentRoomId = null;
    _channel = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }
}
