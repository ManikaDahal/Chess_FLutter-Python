import 'package:chess_game_manika/core/api/api_services.dart';

class InviteService {
  final ApiService _apiService = ApiService();

  Future<Map<String, dynamic>?> sendInvite(int toUserId, {String gameType = 'chess', int? boardId}) async {
    return await _apiService.sendInvite(toUserId, gameType: gameType, boardId: boardId);
  }

  Future<Map<String, dynamic>> getPendingInvites() async {
    return await _apiService.getPendingInvites();
  }

  Future<int?> acceptInvites(int inviteId) async {
    return await _apiService.acceptInvite(inviteId);
  }

  Future<void> declineInvite(int inviteId) async {
    await _apiService.declineInvite(inviteId);
  }

  Future<void> cancelInvite(int inviteId) async {
    await _apiService.cancelInvite(inviteId);
  }
}
