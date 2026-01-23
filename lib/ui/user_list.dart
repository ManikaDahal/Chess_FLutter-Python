import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/ui/call_screen.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UserList extends StatefulWidget {
  final int currentUserId;
  const UserList({super.key, required this.currentUserId});

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

  void _startChat(int targetUserId) async {
    // Show a loading indicator if necessary, but keep it simple for now
    final int? roomId = await _apiService.getOrCreateChatRoom(
      widget.currentUserId,
      targetUserId,
    );

    if (roomId != null && mounted) {
      // Initialize the chat provider for this specific room
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.clear(); // Clear previous room data
      chatProvider.init(roomId, widget.currentUserId);

      // Navigate to ChatPage
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatPage(roomId: roomId, currentUserId: widget.currentUserId),
        ),
      );
    }
  }

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
        centerTitle: true,
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
          // Remove ourselves from the list
          final otherUsers = users
              .where((u) => u['id'] != widget.currentUserId)
              .toList();

          return ListView.separated(
            itemCount: otherUsers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final user = otherUsers[index];
              final username = user['username'] ?? "Unknown User";
              final email = user['email'] ?? "";
              final targetUserId = user['id'];

              // Format: user_{targetUserId}
              final callRoomId = "user_$targetUserId";

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
                      icon: const Icon(Icons.chat, color: Colors.blue),
                      onPressed: () => _startChat(targetUserId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.phone, color: Colors.green),
                      onPressed: () => _startCall(callRoomId, false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.videocam, color: Colors.blue),
                      onPressed: () => _startCall(callRoomId, true),
                    ),
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
