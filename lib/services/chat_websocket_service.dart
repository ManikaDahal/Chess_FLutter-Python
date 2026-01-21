import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

class ChatWebsocketService {
static final ChatWebsocketService _instance = ChatWebsocketService();
factory ChatWebsocketService()=>_instance;
ChatWebsocketService._internal();

WebSocketChannel? _channel;
final _controller = StreamController<Map<String , dynamic>>.broadcast();
Stream<Map<String, dynamic>> get stream =>_controller.stream;
bool get isConnected => _channel!=null;

Future<void> connect(int roomId) async {
  if (_channel != null) return; // Already connected

  final url = "wss://chess-websocket-dor6.onrender.com/ws/chat/$roomId";

  try {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    print("WebSocket channel created for room $roomId");

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      _controller.add(data);
      print("Message received: $data");
    }, onDone: () {
      print("WebSocket disconnected");
      _channel = null;
    }, onError: (error) {
      print("WebSocket error: $error");
      _channel = null;
    });
  } catch (e) {
    print("Failed to connect WebSocket: $e");
    _channel = null;
  }
}


void sendMessage(String message, int userId){
  if(_channel==null)return;
  final data ={"message":message,"user_id":userId};
  _channel!.sink.add(jsonEncode(data));
}

void disconnect(){
  _channel?.sink.close();
  _channel=null;
}

}