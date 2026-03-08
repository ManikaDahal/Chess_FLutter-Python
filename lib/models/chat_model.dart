enum MessageStatus { sending, sent, delivered }

class ChatMessage {
  final int? id;
  final int userId;
  final String message;
  final int roomId;
  final String senderName;
  final String? timestamp;
  final DateTime localTimestamp;
  final MessageStatus status;

  ChatMessage({
    this.id,
    required this.message,
    required this.userId,
    required this.roomId,
    required this.senderName,
    this.timestamp,
    DateTime? localTimestamp,
    this.status = MessageStatus.delivered,
  }) : localTimestamp = localTimestamp ?? DateTime.now();

  ChatMessage copyWith({MessageStatus? status}) {
    return ChatMessage(
      id: id,
      message: message,
      userId: userId,
      roomId: roomId,
      senderName: senderName,
      timestamp: timestamp,
      localTimestamp: localTimestamp,
      status: status ?? this.status,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parsedTime;
    final ts = json['timestamp'];
    if (ts != null) {
      parsedTime = DateTime.tryParse(ts.toString());
    }
    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? ''),
      message: json['message'] ?? "",
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      roomId: int.tryParse(json['room_id']?.toString() ?? '0') ?? 0,
      senderName: json['sender_name'] ?? "Unknown",
      timestamp: ts?.toString(),
      localTimestamp: parsedTime ?? DateTime.now(),
      status: MessageStatus.delivered,
    );
  }
}
