import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/const.dart';
import '../models/video_model.dart';
import 'token_storage.dart';

class VideoService {
  // Singleton pattern
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final TokenStorage _storage = TokenStorage();

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<GameVideo>> getVideos() async {
    try {
      final headers = await _headers();
      final response = await http.get(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return data.map((json) => GameVideo.fromJson(json)).toList();
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
      final headers = await _headers();
      final response = await http.get(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/comments/'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
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
      final headers = await _headers();
      final response = await http.post(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/comments/'),
        headers: headers,
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 201) {
        return VideoComment.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('Error posting comment: $e');
    }
    return null;
  }

  Future<bool> toggleReaction(int videoId, String reactionType) async {
    try {
      final headers = await _headers();
      final response = await http.post(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/react/'),
        headers: headers,
        body: jsonEncode({'reaction_type': reactionType}),
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Error toggling reaction: $e');
      return false;
    }
  }

  String getStreamUrl(int videoId) {
    return '${Constants.videoBaseUrl}/api/videos/$videoId/stream/';
  }
}
