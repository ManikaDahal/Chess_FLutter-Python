import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:chess_game_manika/login.dart';

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
  String? _errorMessage;

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
        // Ensure we start with NO active room so notifications work
        chatProvider.clearActiveRoom();
        chatProvider.init(roomId, userId, setAsActive: false);
      }

      // 3️⃣ Connect user-specific signaling
      await GlobalCallHandler().connectForUser(userId);

      // 4️⃣ Register FCM token for notifications
      await NotificationService.registerToken();

      if (!mounted) return;

      // 4️⃣ Initialize pages
      setState(() {
        _currentUserId = userId;
        _currentRoomId = roomId;
        _loading = false;
        _pages = [
          GameBoard(currentUserId: _currentUserId!, roomId: _currentRoomId!),
          UserList(currentUserId: _currentUserId!),
          ChatPage(
            roomId: _currentRoomId!,
            currentUserId: _currentUserId!,
            showBackButton: false, // Hide back button in Tab View
          ),
          const ProfilePage(),
        ];
      });
    } catch (e, st) {
      debugPrint("Error initializing user: $e\n$st");
      final String errorStr = e.toString().toLowerCase();

      if (errorStr.contains("401") ||
          errorStr.contains("unauthorized") ||
          errorStr.contains("[401]") ||
          errorStr.contains("[403]")) {
        // Token expired and refresh failed, go back to login
        debugPrint("User unauthorized, clearing session and going to login");
        if (mounted) {
          SharedPreferences.getInstance().then((prefs) {
            prefs.clear();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const Login()),
              (route) => false,
            );
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage =
              "App failed to initialize. Please check your internet or try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _errorMessage = null;
                    });
                    _initUser();
                  },
                  child: const Text("Retry"),
                ),
                TextButton(
                  onPressed: () {
                    SharedPreferences.getInstance().then((prefs) {
                      prefs.clear();
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const Login()),
                        (route) => false,
                      );
                    });
                  },
                  child: const Text("Go to Login Page"),
                ),
              ],
            ),
          ),
        ),
      );
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
              print("BottomNavBar: onTap index $index");
              setState(() => _currentIndex = index);
              _pageController.jumpToPage(index);

              // Reset unread count AND ensure we are in the general room if tab 2 is clicked
              if (index == 2) {
                if (_currentRoomId != null) {
                  print(
                    "BottomNavBar: Tab 2 clicked, setting active room to $_currentRoomId",
                  );
                  chatProvider.resetUnreadCount(_currentRoomId!);
                  // Re-init general room if we were previously in a private one
                  print("BottomNavBar: Returning to General Room 1");
                  chatProvider.init(_currentRoomId!, _currentUserId!);
                }
              } else {
                // If leaving the chat tab, clear the active room so notifications can happen
                print(
                  "BottomNavBar: Tab $index clicked (NOT 2), clearing active room",
                );
                chatProvider.clearActiveRoom();
              }
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
                  showBadge: chatProvider.totalUnreadCount > 0,
                  badgeContent: Text(
                    chatProvider.totalUnreadCount.toString(),
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
