class GameVideo {
  final int id;
  final String title;
  final String description;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? streamUrl;
  final int duration;
  final int fileSize;
  final int views;
  final DateTime createdAt;
  final Map<String, int> reactionCounts;
  final String? userReaction;

  GameVideo({
    required this.id,
    required this.title,
    required this.description,
    this.videoUrl,
    this.thumbnailUrl,
    this.streamUrl,
    required this.duration,
    required this.fileSize,
    required this.views,
    required this.createdAt,
    this.reactionCounts = const {},
    this.userReaction,
  });

  factory GameVideo.fromJson(Map<String, dynamic> json) {
    return GameVideo(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      videoUrl: json['video_url'],
      thumbnailUrl: json['thumbnail_url'],
      streamUrl: json['stream_url'],
      duration: json['duration'] ?? 0,
      fileSize: json['file_size'] ?? 0,
      views: json['views'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      reactionCounts: Map<String, int>.from(json['reaction_counts'] ?? {}),
      userReaction: json['user_reaction'],
    );
  }
}

class VideoComment {
  final int id;
  final int userId;
  final String userName;
  final String text;
  final DateTime createdAt;

  VideoComment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
  });

  factory VideoComment.fromJson(Map<String, dynamic> json) {
    return VideoComment(
      id: json['id'],
      userId: json['user_id'],
      userName: json['user_name'],
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
