import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/services/auth_services.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:chess_game_manika/features/call/data/models/video_model.dart';
import 'package:http/http.dart' as http;

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

  /// Authenticated GET with automatic token refresh
  Future<http.Response> _authenticatedGet(Uri uri) async {
    final headers = await _headers();
    var response = await http.get(uri, headers: headers);

    if (response.statusCode == 401) {
      print("VideoService: 401 Unauthorized. Attempting token refresh...");
      final refreshed = await AuthServices().refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        print("VideoService: Token refreshed. Retrying request...");
        response = await http.get(uri, headers: newHeaders);
      }
    }
    return response;
  }

  /// Authenticated POST with automatic token refresh
  Future<http.Response> _authenticatedPost(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final headers = await _headers();
    var response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 401) {
      print(
        "VideoService: 401 Unauthorized on POST. Attempting token refresh...",
      );
      final refreshed = await AuthServices().refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        print("VideoService: Token refreshed. Retrying POST...");
        response = await http.post(
          uri,
          headers: newHeaders,
          body: jsonEncode(body),
        );
      }
    }
    return response;
  }

  List<GameVideo>? _cachedVideos;

  Future<List<GameVideo>> getVideos({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedVideos != null) {
      return _cachedVideos!;
    }
    try {
      final response = await _authenticatedGet(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
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
      final response = await _authenticatedGet(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/comments/'),
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
      final response = await _authenticatedPost(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/comments/'),
        {'text': text},
      );

      if (response.statusCode == 201) {
        return VideoComment.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)),
        );
      } else {
        print(
          'DEBUG: [SERVICE] Post comment failed. Status: ${response.statusCode}, Body: ${response.body}',
        );
      }
    } catch (e) {
      print('Error posting comment: $e');
    }
    return null;
  }

  Future<GameVideo?> toggleReaction(int videoId, String reactionType) async {
    try {
      final response = await _authenticatedPost(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/$videoId/react/'),
        {'reaction_type': reactionType},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['video'] != null) {
          return GameVideo.fromJson(data['video']);
        }
      } else {
        print(
          'DEBUG: [SERVICE] Toggle reaction failed. Status: ${response.statusCode}, Body: ${response.body}',
        );
      }
      return null;
    } catch (e) {
      print('Error toggling reaction: $e');
      return null;
    }
  }

  String getStreamUrl(int videoId) {
    return '${Constants.videoBaseUrl}/api/videos/$videoId/stream/';
  }
}
