import 'dart:io';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LocalGameServer {
  HttpServer? _server;
  final List<WebSocketChannel> _clients = [];

  /// Called when the first client (joiner) connects.
  /// This signals the host that a player is ready to play.
  VoidCallback? onClientConnected;

  bool _hasNotifiedHost = false;

  Future<int> start({VoidCallback? onClientConnected}) async {
    this.onClientConnected = onClientConnected;
    _hasNotifiedHost = false;

    final handler = webSocketHandler((dynamic socket) {
      print("[LocalServer] New client connected!");

      final clientsocket = socket as WebSocketChannel;
      _clients.add(clientsocket);

      // Notify host when the first joiner connects
      if (!_hasNotifiedHost) {
        _hasNotifiedHost = true;
        print("[LocalServer] First client connected — notifying host.");
        this.onClientConnected?.call();
      }

      clientsocket.stream.listen(
        (message) {
          print("[LocalServer] Received from client: $message");
          // Broadcast the move/message to all OTHER connected players
          for (var client in _clients) {
            if (client != clientsocket) {
              client.sink.add(message);
            }
          }
        },
        onDone: () {
          print("[LocalServer] Client disconnected.");
          _clients.remove(clientsocket);
        },
        onError: (e) {
          print("[LocalServer] Client error: $e");
          _clients.remove(clientsocket);
        },
      );
    });

    try {
      // Use a fixed port (8080) so that manual IP connection is possible
      // if mDNS is blocked by the Android Hotspot.
      _server = await io.serve(
        handler,
        InternetAddress.anyIPv4,
        8080,
        shared: true,
      );
      print(
        "[LocalServer] Running on ${_server!.address.address}:${_server!.port}",
      );
      return _server!.port;
    } catch (e) {
      print("[LocalServer] Error starting server: $e");
      rethrow;
    }
  }

  void stop() {
    _server?.close();
    for (var client in _clients) {
      client.sink.close();
    }
    _clients.clear();
    _hasNotifiedHost = false;
    print("[LocalServer] Server stopped.");
  }
}

// Typedef so we don't need to import flutter just for VoidCallback
typedef VoidCallback = void Function();
