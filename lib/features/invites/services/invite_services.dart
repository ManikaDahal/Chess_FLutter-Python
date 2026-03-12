import 'package:chess_game_manika/core/api/api_services.dart';

class InviteService {
  final ApiService _apiService = ApiService();

  Future<int?> sendInvite(int toUserId) async {
    return await _apiService.sendInvite(toUserId);
  }

  Future<List<Map<String, dynamic>>> getPendingInvites() async {
    return await _apiService.getPendingInvites();
  }

  Future<int?> acceptInvites(int inviteId) async {
    return await _apiService.acceptInvite(inviteId);
  }

  Future<void> declineInvite(int inviteId) async {
    await _apiService.declineInvite(inviteId);
  }
}
