import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
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

    // Use shelf_web_socket to create the core WebSocket logic
    final wsHandler = webSocketHandler((WebSocketChannel clientSocket, String? protocol) {
      final clientId = clientSocket.hashCode;
      _clients.add(clientSocket);
      
      // Notify the client that they are connected to the relay pool.
      final ack = jsonEncode({'type': 'connected', 'status': 'ok', 'client_id': clientId});
      clientSocket.sink.add(ack);
      
      print('[LocalServer] New WebSocket client ($clientId). Total: ${_clients.length}');

      clientSocket.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            print('[LocalServer] Received: $data');

            if (!_hasNotifiedHost && data['type'] == 'join') {
              // We could potentially check data['user_id'] here, but for local mode,
              // the first join message is the trigger.
              _hasNotifiedHost = true;
              print('[LocalServer] Valid join handshake received — notifying host!');
              this.onClientConnected?.call();
            }

            // Broadcast to all OTHER connected clients (move/msg relay)
            final otherClients = _clients.where((c) => c != clientSocket).toList();
            if (otherClients.isNotEmpty) {
              print('[LocalServer] Relaying message from $clientId to ${otherClients.length} peer(s)');
              for (final client in otherClients) {
                try {
                  client.sink.add(message);
                } catch (e) {
                  print('[LocalServer] Error relaying from $clientId: $e');
                }
              }
            } else {
              print('[LocalServer] No peers to relay from $clientId. Pool size: ${_clients.length}');
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

    // Wrapper handler to capture the remote IP before upgrading to WebSocket
    final Handler combinedHandler = (Request request) {
      final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final remoteAddr = connectionInfo?.remoteAddress.address;

      print('[LocalServer] Incoming ${request.method} from $remoteAddr');

      // IMMEDIATE TRIGGER: If a REMOTE device (not loopback) connects,
      // notify the host immediately to restore "works first try" behavior.
      if (!_hasNotifiedHost && remoteAddr != null && remoteAddr != '127.0.0.1') {
        _hasNotifiedHost = true;
        print('[LocalServer] Remote client ($remoteAddr) connected — notifying host!');
        this.onClientConnected?.call();
      }

      return wsHandler(request);
    };

    int retryCount = 0;
    while (retryCount < 2) {
      try {
        _server = await io.serve(
          combinedHandler,
          InternetAddress.anyIPv4,
          8080,
          shared: true,
        );
        print('[LocalServer] Successfully running on ${_server!.address.address}:${_server!.port}');
        return _server!.port;
      } catch (e) {
        retryCount++;
        print('[LocalServer] Binding failed (Attempt $retryCount/2): $e');
        if (retryCount >= 2) rethrow;
        // Wait 500ms before retrying to let the OS release port 8080
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    throw Exception("Failed to start server after retries.");
  }

  Future<void> stop() async {
    print('[LocalServer] Stopping server...');
    await _server?.close(force: true);
    _server = null;
    for (var client in List<WebSocketChannel>.from(_clients)) {
      try { client.sink.close(); } catch (_) {}
    }
    _clients.clear();
    _hasNotifiedHost = false;
    print('[LocalServer] Server fully stopped.');
  }
}

// Typedef so we don't need to import flutter just for VoidCallback
typedef VoidCallback = void Function();
