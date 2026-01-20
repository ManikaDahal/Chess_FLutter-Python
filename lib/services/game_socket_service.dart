import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class GameSocketService {
  WebSocketChannel? _channel;
  late Function(Map<String, dynamic>) onMessage;

  void connect(String roomID) {
    _channel = WebSocketChannel.connect(
      Uri.parse("wss://chess-websocket-dor6.onrender.com/ws/game/$roomID/"),
    );

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      onMessage(data);
    });
  }

  void sendMove(String from, String to){
    final move = {
      "type":"move",
      "from":from,
      "to":to,
    };

    _channel?.sink.add(jsonEncode(move));
  }

  void dispose(){
    _channel?.sink.close();
  }
}
