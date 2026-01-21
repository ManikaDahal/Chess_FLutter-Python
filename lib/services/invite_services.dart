import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:http/http.dart' as http;

class InviteService {
  final TokenStorage _storage = TokenStorage();

  Future<bool> sendInvite(int toUserId) async {
    final token = await _storage.getAccessToken();
    final res = await http.post(
      Uri.parse("${Constants.wsBaseUrl}/api/send-invite/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"to_user": toUserId}),
    );
    return res.statusCode == 200;
  }

  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    final token = await _storage.getAccessToken();
    final res = await http.get(
      Uri.parse("${Constants.wsBaseUrl}/api/pending-invites/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
    );
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  Future<int?> acceptInvites(int inviteId) async {
    final token = await _storage.getAccessToken();
    final res = await http.post(
      Uri.parse("${Constants.wsBaseUrl}/api/accept-invite/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"invite_id": inviteId}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body)["room_id"];
    }
    return null;
  }

  Future<void> declineInvite(int inviteId) async {
    final token = await _storage.getAccessToken();
    await http.post(
      Uri.parse("${Constants.wsBaseUrl}/api/decline-invite/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"invite_id": inviteId}),
    );
  }
}
