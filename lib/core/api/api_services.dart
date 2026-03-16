import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/auth/services/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

enum ApiBase { vercel, render }

class ApiService {
  late final Dio _dio;
  final TokenStorage _storage = TokenStorage();

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ));
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.addAll([
      // 1. Authorization Interceptor
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final isAuthRequired = options.extra['authenticated'] ?? true;
          if (isAuthRequired) {
            final token = await _storage.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
      ),

      // 2. Token Refresh Interceptor
      InterceptorsWrapper(
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401 && e.requestOptions.extra['authenticated'] != false) {
            print("ApiService Interceptor: 401 error detected. Refreshing token...");
            final success = await refreshToken();
            if (success) {
              print("ApiService Interceptor: Token refreshed. Retrying original request...");
              final token = await _storage.getAccessToken();
              final opts = e.requestOptions;
              opts.headers['Authorization'] = 'Bearer $token';

              // Create a special retry instance to avoid infinite loops if it fails again
              final retryDio = Dio();
              try {
                final response = await retryDio.request(
                  opts.path,
                  data: opts.data,
                  queryParameters: opts.queryParameters,
                  options: Options(
                    method: opts.method,
                    headers: opts.headers,
                  ),
                );
                return handler.resolve(response);
              } catch (retryError) {
                return handler.next(e);
              }
            }
          }
          return handler.next(e);
        },
      ),

      // 3. Simple Logging Interceptor
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    ]);
  }

  String _getBaseUrl(ApiBase base) {
    switch (base) {
      case ApiBase.render:
        return Constants.videoBaseUrl;
      case ApiBase.vercel:
      default:
        return Constants.apiBaseUrl;
    }
  }

  /// Wrapper to make GET requests
  Future<Response> get(String endpoint, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final url = '${_getBaseUrl(base)}$endpoint';
    return await _dio.get(
      url,
      options: Options(extra: {'authenticated': authenticated}),
    );
  }

  /// Wrapper to make POST requests
  Future<Response> post(String endpoint, dynamic body, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final url = '${_getBaseUrl(base)}$endpoint';
    return await _dio.post(
      url,
      data: body,
      options: Options(extra: {'authenticated': authenticated}),
    );
  }

  /// Wrapper to make DELETE requests
  Future<Response> delete(String endpoint, {ApiBase base = ApiBase.vercel, bool authenticated = true}) async {
    final url = '${_getBaseUrl(base)}$endpoint';
    return await _dio.delete(
      url,
      options: Options(extra: {'authenticated': authenticated}),
    );
  }

  /// Wrapper for multipart POST requests
  Future<Response> multipartPost(
    String endpoint, 
    {
      List<String>? filePaths, 
      String filePath = '', 
      String fileKey = 'file',
      Map<String, String>? fields, 
      ApiBase base = ApiBase.vercel, 
      bool authenticated = true
    }
  ) async {
    final url = '${_getBaseUrl(base)}$endpoint';
    final formData = FormData();
    
    if (fields != null) formData.fields.addAll(fields.entries.map((e) => MapEntry(e.key, e.value)));
    
    final paths = filePaths ?? (filePath.isNotEmpty ? [filePath] : []);
    for (var path in paths) {
      formData.files.add(MapEntry(
        fileKey,
        await MultipartFile.fromFile(path, filename: p.basename(path)),
      ));
    }

    return await _dio.post(
      url,
      data: formData,
      options: Options(extra: {'authenticated': authenticated}),
    );
  }

  /// Probe method to wake up servers
  Future<void> probe(ApiBase base) async {
    try {
      final url = _getBaseUrl(base);
      await _dio.get(url, options: Options(extra: {'authenticated': false}))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print("ApiService: Probe for $base failed: $e");
    }
  }

  /// AUTHENTICATION
  
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null) return false;

    try {
      final dio = Dio(); // Use new instance to avoid interceptor recursion
      final response = await dio.post(
        '${Constants.apiBaseUrl}/api/token/refresh/',
        data: {'refresh': refresh},
      );

      if (response.statusCode == 200) {
        await _storage.saveAccessToken(response.data['access']);
        print("ApiService: Access token refreshed successfully");
        return true;
      }
    } catch (e) {
      print("ApiService: Refresh failed: $e");
    }
    return false;
  }

  Future<Response> login(String email, String password) async {
    return await post('/api/token/', {'email': email, 'password': password}, authenticated: false);
  }

  Future<Response> signup(String username, String password, String email) async {
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
      return response.data;
    } else {
      throw Exception("Profile failed [${response.statusCode}]");
    }
  }

  Future<List<dynamic>> getUsers() async {
    final response = await get('/api/users/');
    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception("Failed to fetch users [${response.statusCode}]");
    }
  }

  /// CHAT & MESSAGING
  
  Future<List<dynamic>> getChatMessages(int roomId) async {
    final response = await get('/api/chat/history/$roomId/', base: ApiBase.render);
    if (response.statusCode == 200) {
      return response.data;
    } else {
      print("Failed to fetch chat history: ${response.data}");
      return [];
    }
  }

  Future<int?> getOrCreateChatRoom(int user1Id, int user2Id) async {
    final response = await post('/api/chat/get_or_create_room/', {
      "user1_id": user1Id, 
      "user2_id": user2Id
    }, base: ApiBase.render);

    if (response.statusCode == 200) {
      return response.data['room_id'];
    } else {
      print("Failed to get/create chat room: ${response.data}");
      return null;
    }
  }

  /// INVITES
  
  Future<int?> sendInvite(int toUserId) async {
    final response = await post('/api/send-invite/', {"to_user": toUserId}, base: ApiBase.render);
    if (response.statusCode == 201) {
      return response.data['room_id'];
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    final response = await get('/api/pending-invites/', base: ApiBase.render);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(response.data);
    }
    return [];
  }

  Future<int?> acceptInvite(int inviteId) async {
    final response = await post('/api/accept-invite/', {"invite_id": inviteId}, base: ApiBase.render);
    if (response.statusCode == 200) {
      return response.data["room_id"];
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
      print("FCM Error: ${response.statusCode} - ${response.data}");
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
      print("FCM ERROR: Failed to update status: ${response.data}");
    }
  }

  String getStreamUrl(int videoId) {
    return '${Constants.videoBaseUrl}/api/videos/$videoId/stream/';
  }
}
