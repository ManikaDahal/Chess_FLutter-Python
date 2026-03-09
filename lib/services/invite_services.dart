import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:http/http.dart' as http;

class InviteService {
  final TokenStorage _storage = TokenStorage();

  Future<int?> sendInvite(int toUserId) async {
    final token = await _storage.getAccessToken();
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );

    final res = await http.post(
      Uri.parse("$renderUrl/api/send-invite/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"to_user": toUserId}),
    );
    print("SendInvite status: ${res.statusCode} body: ${res.body}");
    if (res.statusCode == 201) {
      return jsonDecode(res.body)['room_id'];
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    final token = await _storage.getAccessToken();
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );

    final res = await http.get(
      Uri.parse("$renderUrl/api/pending-invites/"),
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
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );

    final res = await http.post(
      Uri.parse("$renderUrl/api/accept-invite/"),
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
    final String renderUrl = Constants.wsBaseUrl.replaceFirst(
      "wss://",
      "https://",
    );

    await http.post(
      Uri.parse("$renderUrl/api/decline-invite/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({"invite_id": inviteId}),
    );
  }
}
