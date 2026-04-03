import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LocalGameServer {
  HttpServer? _server;
  final List<WebSocketChannel> _clients = [];

  /// Called when the first joiner connects.
  VoidCallback? onClientConnected;

  bool _hasNotifiedHost = false;

  Future<int> start({VoidCallback? onClientConnected}) async {
    this.onClientConnected = onClientConnected;
    _hasNotifiedHost = false;

    // shelf_web_socket ^2.x requires two-param callback: (WebSocketChannel, String?)
    final handler = webSocketHandler((WebSocketChannel clientSocket, String? protocol) {
      print('[LocalServer] New TCP connection received. Waiting for join handshake...');
      _clients.add(clientSocket);

      clientSocket.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            print('[LocalServer] Received: $data');

            // Trigger host navigation ONLY when we receive a real join message.
            // This prevents port probes / NSD health checks / ghost reconnects
            // from accidentally firing onClientConnected on bare connection.
            if (!_hasNotifiedHost && data['type'] == 'join') {
              _hasNotifiedHost = true;
              print('[LocalServer] Valid join handshake received — notifying host!');
              this.onClientConnected?.call();
            }

            // Broadcast to all OTHER connected clients (move relay)
            for (final client in List<WebSocketChannel>.from(_clients)) {
              if (client != clientSocket) {
                client.sink.add(message);
              }
            }
          } catch (e) {
            print('[LocalServer] Ignoring non-JSON message: $e');
          }
        },
        onDone: () {
          print('[LocalServer] A client disconnected.');
          _clients.remove(clientSocket);
          // Tell remaining clients their opponent left so their board reacts
          if (_clients.isNotEmpty) {
            final leaveMsg = jsonEncode({'type': 'user_left', 'user_id': null});
            for (final client in List<WebSocketChannel>.from(_clients)) {
              try { client.sink.add(leaveMsg); } catch (_) {}
            }
            print('[LocalServer] Broadcasted user_left to ${_clients.length} remaining client(s).');
          }
        },
        onError: (e) {
          print('[LocalServer] Client error: $e');
          _clients.remove(clientSocket);
        },
      );
    });

    try {
      _server = await io.serve(
        handler,
        InternetAddress.anyIPv4,
        8080,
        shared: true,
      );
      print('[LocalServer] Running on ${_server!.address.address}:${_server!.port}');
      return _server!.port;
    } catch (e) {
      print('[LocalServer] Error starting server: $e');
      rethrow;
    }
  }

  void stop() {
    _server?.close(force: true);
    for (var client in List<WebSocketChannel>.from(_clients)) {
      client.sink.close();
    }
    _clients.clear();
    _hasNotifiedHost = false;
    print('[LocalServer] Server stopped.');
  }
}

// Typedef so we don't need to import flutter just for VoidCallback
typedef VoidCallback = void Function();
