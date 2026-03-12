import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

enum ApiBase { vercel, render }

class ApiService {
  final TokenStorage _storage = TokenStorage();

  String _getBaseUrl(ApiBase base) {
    switch (base) {
      case ApiBase.render:
        return Constants.videoBaseUrl;
      case ApiBase.vercel:
      default:
        return Constants.apiBaseUrl;
    }
  }

  /// Core GET implementation with automatic token refresh
  Future<http.Response> get(String endpoint, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final uri = Uri.parse('${_getBaseUrl(base)}$endpoint');
    final headers = {'Content-Type': 'application/json'};
    
    if (authenticated) {
      final token = await _storage.getAccessToken();
      headers['Authorization'] = 'Bearer $token';
    }

    var response = await http.get(uri, headers: headers);

    if (authenticated && response.statusCode == 401) {
      print("ApiService: 401 Unauthorized. Attempting token refresh...");
      final refreshed = await refreshToken();
      if (refreshed) {
        final newToken = await _storage.getAccessToken();
        headers['Authorization'] = 'Bearer $newToken';
        print("ApiService: Token refreshed. Retrying GET...");
        response = await http.get(uri, headers: headers);
      }
    }
    return response;
  }

  /// Core POST implementation with automatic token refresh
  Future<http.Response> post(String endpoint, Map<String, dynamic> body, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final uri = Uri.parse('${_getBaseUrl(base)}$endpoint');
    final headers = {'Content-Type': 'application/json'};
    
    if (authenticated) {
      final token = await _storage.getAccessToken();
      headers['Authorization'] = 'Bearer $token';
    }

    var response = await http.post(uri, headers: headers, body: jsonEncode(body));

    if (authenticated && response.statusCode == 401) {
      print("ApiService: 401 Unauthorized. Attempting token refresh...");
      final refreshed = await refreshToken();
      if (refreshed) {
        final newToken = await _storage.getAccessToken();
        headers['Authorization'] = 'Bearer $newToken';
        print("ApiService: Token refreshed. Retrying POST...");
        response = await http.post(uri, headers: headers, body: jsonEncode(body));
      }
    }
    return response;
  }

  /// Core DELETE implementation
  Future<http.Response> delete(String endpoint, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final uri = Uri.parse('${_getBaseUrl(base)}$endpoint');
    final headers = {'Content-Type': 'application/json'};
    
    if (authenticated) {
      final token = await _storage.getAccessToken();
      headers['Authorization'] = 'Bearer $token';
    }

    var response = await http.delete(uri, headers: headers);

    if (authenticated && response.statusCode == 401) {
      print("ApiService: 401 Unauthorized on DELETE. Attempting token refresh...");
      final refreshed = await refreshToken();
      if (refreshed) {
        final newToken = await _storage.getAccessToken();
        headers['Authorization'] = 'Bearer $newToken';
        print("ApiService: Token refreshed. Retrying DELETE...");
        response = await http.delete(uri, headers: headers);
      }
    }
    return response;
  }

  /// Multipart POST implementation for file uploads
  Future<http.Response> multipartPost(
    String endpoint, 
    {
      List<String>? filePaths, 
      String filePath = '', // Backward compatibility
      String fileKey = 'file',
      Map<String, String>? fields, 
      ApiBase base = ApiBase.vercel, 
      bool authenticated = true
    }
  ) async {
    final uri = Uri.parse('${_getBaseUrl(base)}$endpoint');
    final request = http.MultipartRequest('POST', uri);
    
    if (authenticated) {
      final token = await _storage.getAccessToken();
      request.headers['Authorization'] = 'Bearer $token';
    }

    if (fields != null) request.fields.addAll(fields);
    
    final paths = filePaths ?? (filePath.isNotEmpty ? [filePath] : []);
    for (var path in paths) {
      request.files.add(await http.MultipartFile.fromPath(
        fileKey, 
        path, 
        filename: p.basename(path)
      ));
    }

    final streamed = await request.send();
    var response = await http.Response.fromStream(streamed);

    if (authenticated && response.statusCode == 401) {
      print("ApiService: 401 Unauthorized on Multipart. Attempting token refresh...");
      final refreshed = await refreshToken();
      if (refreshed) {
        return await multipartPost(
          endpoint, 
          filePaths: filePaths, 
          filePath: filePath, 
          fileKey: fileKey, 
          fields: fields, 
          base: base, 
          authenticated: authenticated
        );
      }
    }
    return response;
  }

  /// Probe method to wake up servers
  Future<void> probe(ApiBase base) async {
    try {
      final uri = Uri.parse(_getBaseUrl(base));
      await http.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      print("ApiService: Probe for $base failed: $e");
    }
  }

  /// AUTHENTICATION
  
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    final response = await http.post(
      Uri.parse('${Constants.apiBaseUrl}/api/token/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.saveAccessToken(data['access']);
      print("ApiService: Access token refreshed successfully");
      return true;
    }

    print("ApiService: Refresh failed: ${response.body}");
    return false;
  }

  Future<http.Response> login(String email, String password) async {
    return await post('/api/token/', {'email': email, 'password': password}, authenticated: false);
  }

  Future<http.Response> signup(String username, String password, String email) async {
    return await post('/api/signup/', {
      'username': username,
      'password': password,
      'email': email,
    }, authenticated: false);
  }

  Future<bool> forgotPassword({String? email, String? phone}) async {
    final body = <String, String>{};
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    final response = await post('/api/forgot-password/', body, authenticated: false);
    return response.statusCode == 200;
  }

  Future<bool> verifyOtp(String email, String otp) async {
    final response = await post('/api/verify-otp/', {
      'email': email.trim(), 
      'otp': otp.trim()
    }, authenticated: false);
    return response.statusCode == 200;
  }

  Future<bool> resetPassword(String email, String newPassword, String otp) async {
    final response = await post('/api/reset-password/', {
      'email': email,
      'new_password': newPassword,
      'otp': otp,
    }, authenticated: false);
    return response.statusCode == 200;
  }

  /// PROFILE & USERS
  
  Future<Map<String, dynamic>> getProfile() async {
    final response = await get('/api/profile/');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Profile failed [${response.statusCode}]");
    }
  }

  Future<List<dynamic>> getUsers() async {
    final response = await get('/api/users/');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to fetch users [${response.statusCode}]");
    }
  }

  /// CHAT & MESSAGING
  
  Future<List<dynamic>> getChatMessages(int roomId) async {
    final response = await get('/api/chat/history/$roomId/', base: ApiBase.render);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print("Failed to fetch chat history: ${response.body}");
      return [];
    }
  }

  Future<int?> getOrCreateChatRoom(int user1Id, int user2Id) async {
    final response = await post('/api/chat/get_or_create_room/', {
      "user1_id": user1Id, 
      "user2_id": user2Id
    }, base: ApiBase.render);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['room_id'];
    } else {
      print("Failed to get/create chat room: ${response.body}");
      return null;
    }
  }

  /// INVITES
  
  Future<int?> sendInvite(int toUserId) async {
    final response = await post('/api/send-invite/', {"to_user": toUserId}, base: ApiBase.render);
    if (response.statusCode == 201) {
      return jsonDecode(response.body)['room_id'];
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    final response = await get('/api/pending-invites/', base: ApiBase.render);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    return [];
  }

  Future<int?> acceptInvite(int inviteId) async {
    final response = await post('/api/accept-invite/', {"invite_id": inviteId}, base: ApiBase.render);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)["room_id"];
    }
    return null;
  }

  Future<void> declineInvite(int inviteId) async {
    await post('/api/decline-invite/', {"invite_id": inviteId}, base: ApiBase.render);
  }

  /// NOTIFICATIONS
  
  Future<void> registerFcmToken(String token) async {
    final response = await post('/api/register-fcm-token/', {"token": token});
    if (response.statusCode == 200) {
      print("FCM: Token registered successfully");
    } else {
      print("FCM Error: ${response.statusCode} - ${response.body}");
    }
  }

  Future<void> updateNotificationStatus(String messageId, String status) async {
    final response = await post('/api/notifications/update-status/', {
      "message_id": messageId, 
      "status": status
    }, base: ApiBase.render);

    if (response.statusCode == 200) {
      print("FCM: Notification status updated to $status");
    } else {
      print("FCM ERROR: Failed to update status: ${response.body}");
    }
  }

  String getStreamUrl(int videoId) {
    return '${Constants.videoBaseUrl}/api/videos/$videoId/stream/';
  }
}
