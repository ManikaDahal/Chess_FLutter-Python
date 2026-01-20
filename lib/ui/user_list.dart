import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/ui/call_screen.dart';
import 'package:flutter/material.dart';


class UserList extends StatefulWidget {
  const UserList({super.key});

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends State<UserList> {
  final ApiService _apiService = ApiService();
  late Future<List<dynamic>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _apiService.getUsers();
  }
//   void _startChessGame(int friendId){
// String roomId="game_${DateTime.now().millisecondsSinceEpoch}";
// GlobalCallHandler().sendToGeneral({
//   "type":"game_invite",
//   "to":friendId,
//   "room":roomId,
//   });
//   RouteGenerator.navigateToPage(context, Routes.gameRoomRoute, arguments: RoomArguments(roomId: roomId));
//   }

  void _startCall(String roomId, bool isVideo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          roomId: roomId,
          isIncomingCall: false,
          isInitialVideo: isVideo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: whiteColor),
          onPressed: () {
            RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
          },
        ),
        title: const Text("Users"),
        backgroundColor: backgroundColor,
        foregroundColor: whiteColor,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No users found"));
          }

          final users = snapshot.data!;
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final user = users[index];
              final username = user['username'] ?? "Unknown User";
              final email = user['email'] ?? "";

              // CHANGE: Using 'user_' prefix to call the target user's personal room
              // This ensures only the specific user receives the call notification
              // Format: user_{targetUserId}
              final roomId = "user_${user['id']}";

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: foregroundColor,
                  child: Text(
                    username[0].toUpperCase(),
                    style: const TextStyle(color: whiteColor),
                  ),
                ),
                title: Text(username),
                subtitle: Text(email),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.phone, color: Colors.green),
                      onPressed: () => _startCall(roomId, false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.videocam, color: Colors.blue),
                      onPressed: () => _startCall(roomId, true),
                    ),
                    // IconButton(onPressed:() =>_startChessGame(user.id),
                    //  icon:Icon(Icons.group,color: Colors.blue) )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
