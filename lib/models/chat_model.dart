class ChatMessage {
  final int userId;
  final String message;
  final int roomId;
  ChatMessage({required this.message, required this.userId, required this.roomId});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(message: json['message'], userId: json['user_id'], roomId: json['room_id']);
  }

  
}
