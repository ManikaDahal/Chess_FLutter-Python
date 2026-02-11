import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/const.dart';
import '../models/video_model.dart';

class VideoService {
  // Singleton pattern
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  Future<List<GameVideo>> getVideos() async {
    try {
      final response = await http.get(
        Uri.parse('${Constants.videoBaseUrl}/api/videos/'),
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

  String getStreamUrl(int videoId) {
    return '${Constants.videoBaseUrl}/api/videos/$videoId/stream/';
  }
}
