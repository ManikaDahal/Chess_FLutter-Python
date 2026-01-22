class ChatMessage {
  final int userId;
  final String message;
  final int roomId;
  final String senderName;

  ChatMessage({
    required this.message,
    required this.userId,
    required this.roomId,
    this.senderName = "Unknown",
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      message: json['message'] ?? "",
      userId: json['user_id'] ?? 0,
      roomId: json['room_id'] ?? 0,
      senderName: json['username'] ?? "Unknown",
    );
  }
}
