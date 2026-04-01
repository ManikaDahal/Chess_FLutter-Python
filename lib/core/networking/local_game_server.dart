import 'dart:io';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LocalGameServer {
  HttpServer? _server;
  final List<WebSocketChannel> _clients = [];

  Future<int> start() async {
    final handler = webSocketHandler((dynamic socket) {
      print("[LocalServer] New client connected!");
      
      // We cast to dynamic to bypass version-specific type conflicts
      final clientsocket = socket;
      _clients.add(clientsocket);

      clientsocket.stream.listen((message) {
        print("[LocalServer] Received from client: $message");
        // Broadcast the move/message to all other connected players
        for (var client in _clients) {
          if (client != clientsocket) {
            client.sink.add(message);
          }
        }
      }, onDone: () {
        print("[LocalServer] Client disconnected.");
        _clients.remove(clientsocket);
      });
    });

    try {
      // Start server on all interfaces (0.0.0.0) at port 0 (OS picks a free port)
      _server = await io.serve(handler, InternetAddress.anyIPv4, 0);
      print("[LocalServer] Running on ${_server!.address.address}:${_server!.port}");
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
    print("[LocalServer] Server stopped.");
  }
}
