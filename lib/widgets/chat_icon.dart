import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChatIcon extends StatelessWidget {
  final int roomId;
  final int currentUserId;

  const ChatIcon({required this.roomId, required this.currentUserId, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (_, provider, __) {
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(roomId: roomId, currentUserId: currentUserId),
                  ),
                );
              },
            ),
            if (provider.unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  child: Text(
                    "${provider.unreadCount}",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              )
          ],
        );
      },
    );
  }
}
