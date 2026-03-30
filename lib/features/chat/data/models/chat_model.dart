class ChatMessage {
  final int? id;
  final int userId;
  final String message;
  final int roomId;
  final String senderName;
  final String? timestamp;
  final String status;
  final bool isDelivered;
  final bool isRead;

  ChatMessage({
    this.id,
    required this.message,
    required this.userId,
    required this.roomId,
    required this.senderName,
    this.timestamp,
    this.status = 'sent',
    this.isDelivered = false,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Map status for UI convenience from backend flags
    final bool delivered = json['is_delivered'] == true || 
                          json['is_delivered'] == 1 || 
                          json['status'] == 'delivered' ||
                          json['status'] == 'read' ||
                          json['status'] == 'seen';
                          
    final bool read = json['is_read'] == true || 
                     json['is_read'] == 1 || 
                     json['status'] == 'read' ||
                     json['status'] == 'seen';

    String mappedStatus = json['status'] ?? 'sent';
    if (read) {
      mappedStatus = 'seen';
    } else if (delivered) {
      mappedStatus = 'delivered';
    }

    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? ''),
      message: json['message'] ?? "",
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      roomId: int.tryParse(json['room_id']?.toString() ?? '0') ?? 0,
      senderName: json['sender_name'] ?? "Unknown",
      timestamp: json['timestamp'],
      status: mappedStatus,
      isDelivered: delivered,
      isRead: read,
    );
  }
}

