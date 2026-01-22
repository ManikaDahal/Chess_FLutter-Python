import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;

import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/ui/chess_board.dart';
import 'package:chess_game_manika/ui/user_list.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:chess_game_manika/profile_page.dart';
import 'package:chess_game_manika/services/foreground_service_manager.dart';

class BottomNavBarWrapper extends StatefulWidget {
  const BottomNavBarWrapper({super.key});

  @override
  State<BottomNavBarWrapper> createState() => _BottomNavBarWrapperState();
}

class _BottomNavBarWrapperState extends State<BottomNavBarWrapper> {
  int _currentIndex = 0;
  late final PageController _pageController;
  int? _currentUserId;
  int? _currentRoomId;
  bool _loading = true;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initUser();
  }

  Future<void> _initUser() async {
    try {
      // 1️⃣ Fetch profile
      final profile = await ApiService().getProfile();
      final int? userId = profile['id'];
      final int roomId = profile['current_room_id'] ?? 1;

      if (userId == null) throw Exception("User ID not found");

      // 2️⃣ Initialize ChatProvider once
      if (mounted) {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        chatProvider.init(roomId, userId);
      }

      // 3️⃣ Connect user-specific signaling
      await GlobalCallHandler().connectForUser(userId);

      // 3.5 Start MQTT Foreground Service
      await ForegroundServiceManager.start(userId);

      if (!mounted) return;

      // 4️⃣ Initialize pages
      setState(() {
        _currentUserId = userId;
        _currentRoomId = roomId;
        _loading = false;
        _pages = [
          GameBoard(currentUserId: _currentUserId!, roomId: _currentRoomId!),
          const UserList(),
          ChatPage(roomId: _currentRoomId!, currentUserId: _currentUserId!),
          const ProfilePage(),
        ];
      });
    } catch (e, st) {
      debugPrint("Error initializing user: $e\n$st");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 5️⃣ User the global ChatProvider provided in main.dart
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        return Scaffold(
          body: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _currentIndex,
            backgroundColor: whiteColor,
            selectedItemColor: backgroundColor,
            unselectedItemColor: foregroundColor,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            onTap: (index) {
              setState(() => _currentIndex = index);
              _pageController.jumpToPage(index);

              // Reset unread count if chat tab opened
              if (index == 2) chatProvider.resetUnreadCount();
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: "Board",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: "Players",
              ),
              BottomNavigationBarItem(
                icon: badges.Badge(
                  showBadge: chatProvider.unreadCount > 0,
                  badgeContent: Text(
                    chatProvider.unreadCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  child: const Icon(Icons.chat),
                ),
                label: "Chat",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                label: "Profile",
              ),
            ],
          ),
        );
      },
    );
  }
}
