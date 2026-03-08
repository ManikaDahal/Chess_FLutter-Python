enum MessageStatus { sending, sent, delivered, seen }

class MessageReaction {
  final int userId;
  final String emoji;

  MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      emoji: json['emoji'] ?? "",
    );
  }
}

class ChatMessage {
  final int? id;
  final int userId;
  final String message;
  final int roomId;
  final String senderName;
  final String? timestamp;
  final DateTime localTimestamp;
  final MessageStatus status;
  final List<MessageReaction> reactions;
  final String? trackingId;

  ChatMessage({
    this.id,
    required this.message,
    required this.userId,
    required this.roomId,
    required this.senderName,
    this.timestamp,
    DateTime? localTimestamp,
    this.status = MessageStatus.delivered,
    this.reactions = const [],
    this.trackingId,
  }) : localTimestamp = localTimestamp ?? DateTime.now();

  ChatMessage copyWith({
    MessageStatus? status,
    List<MessageReaction>? reactions,
    String? trackingId,
  }) {
    return ChatMessage(
      id: id,
      message: message,
      userId: userId,
      roomId: roomId,
      senderName: senderName,
      timestamp: timestamp,
      localTimestamp: localTimestamp,
      status: status ?? this.status,
      reactions: reactions ?? this.reactions,
      trackingId: trackingId ?? this.trackingId,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? parsedTime;
    final ts = json['timestamp'];
    if (ts != null) {
      parsedTime = DateTime.tryParse(ts.toString())?.toLocal();
    }

    // Map backend statuses to Enum
    MessageStatus status = MessageStatus.sent;
    if (json['is_read'] == true) {
      status = MessageStatus.seen;
    } else if (json['is_delivered'] == true) {
      status = MessageStatus.delivered;
    }

    // Parse reactions
    final List<dynamic> reactionsJson = json['reactions'] ?? [];
    final List<MessageReaction> reactions = reactionsJson
        .map((e) => MessageReaction.fromJson(e))
        .toList();

    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? ''),
      message: json['message'] ?? "",
      userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      roomId: int.tryParse(json['room_id']?.toString() ?? '0') ?? 0,
      senderName: json['sender_name'] ?? "Unknown",
      timestamp: ts?.toString(),
      localTimestamp: parsedTime ?? DateTime.now(),
      status: status,
      reactions: reactions,
      trackingId: json['trackingId']?.toString(),
    );
  }
}
