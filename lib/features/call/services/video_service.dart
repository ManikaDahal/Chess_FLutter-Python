import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/features/call/data/models/video_model.dart';

class VideoService {
  // Singleton pattern
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final ApiService _apiService = ApiService();

  List<GameVideo>? _cachedVideos;

  Future<List<GameVideo>> getVideos({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedVideos != null) {
      return _cachedVideos!;
    }
    try {
      final response = await _apiService.get('/api/videos/', base: ApiBase.render);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _cachedVideos = data.map((json) => GameVideo.fromJson(json)).toList();
        return _cachedVideos!;
      } else {
        throw Exception('Failed to load videos: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching videos: $e');
      throw Exception('Failed to connect to video service');
    }
  }

  Future<List<VideoComment>> getComments(int videoId) async {
    try {
      final response = await _apiService.get('/api/videos/$videoId/comments/', base: ApiBase.render);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((json) => VideoComment.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load comments');
      }
    } catch (e) {
      print('Error fetching comments: $e');
      return [];
    }
  }

  Future<VideoComment?> postComment(int videoId, String text) async {
    try {
      final response = await _apiService.post('/api/videos/$videoId/comments/', {'text': text}, base: ApiBase.render);

      if (response.statusCode == 201) {
        return VideoComment.fromJson(response.data);
      }
    } catch (e) {
      print('Error posting comment: $e');
    }
    return null;
  }

  Future<GameVideo?> toggleReaction(int videoId, String reactionType) async {
    try {
      final response = await _apiService.post('/api/videos/$videoId/react/', {'reaction_type': reactionType}, base: ApiBase.render);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data['video'] != null) {
          return GameVideo.fromJson(data['video']);
        }
      }
      return null;
    } catch (e) {
      print('Error toggling reaction: $e');
      return null;
    }
  }

  String getStreamUrl(int videoId) {
    return _apiService.getStreamUrl(videoId);
  }
}
