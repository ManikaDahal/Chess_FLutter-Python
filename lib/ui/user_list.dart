import 'package:chess_python/bottom_navbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:flutter/material.dart';
import 'package:chess_python/services/api_services.dart';
import 'package:chess_python/ui/call_screen.dart';
import 'package:chess_python/core/utils/color_utils.dart';

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

              // For now, we use a simple room ID based on the user's ID or similar.
              // In a real app, this would be more secure.
              final roomId = "call_${user['id']}";

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
