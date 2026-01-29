class ChatMessage {
  final int? id; // Optional for optimistic messages
  final int userId;
  final String message;
  final int roomId;
  final String senderName;
  final String? timestamp;

  ChatMessage({
    this.id,
    required this.message,
    required this.userId,
    required this.roomId,
    required this.senderName,
    this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? ''),
      message: json['message'] ?? "",
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      roomId: int.tryParse(json['room_id']?.toString() ?? '0') ?? 0,
      senderName: json['sender_name'] ?? "Unknown",
      timestamp: json['timestamp'],
    );
  }
}
