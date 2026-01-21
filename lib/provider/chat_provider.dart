import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:flutter/widgets.dart';

class ChatProvider with ChangeNotifier{
  final List<ChatMessage> _messages=[];
  List<ChatMessage> get messages=>_messages;
  int _unreadCount = 0;
  int get unreadCount=>_unreadCount;

  int? _currentRoomId;
  int? _currentUserId;

void init(int roomId, int currentUserId) {
  _currentUserId = currentUserId;
  _currentRoomId = roomId;

  // Only connect if not already connected
  if (!ChatWebsocketService().isConnected) {
    print("Connecting to WebSocket...");
    ChatWebsocketService().connect(roomId); // no await
  }

  // Listen to messages once
  ChatWebsocketService().stream.listen((data) {
    final msg = ChatMessage.fromJson(data);
    _messages.add(msg);
    notifyListeners();

    if (msg.userId != currentUserId) {
      _unreadCount++;
      notifyListeners();
      NotificationService.showNotification(msg, roomId);
    }
  });
}


   void send(String message){
      if(_currentUserId==null) return;
      ChatWebsocketService().sendMessage(message,_currentUserId!);
      final msg= ChatMessage(message: message, userId: _currentUserId!, roomId: _currentRoomId!);
      _messages.add(msg);
      notifyListeners();

    }

    void resetUnreadCount(){
      _unreadCount=0;
      notifyListeners();
    }
}