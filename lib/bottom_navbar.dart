import 'package:chess_game_manika/features/auth/presentation/screens/login.dart';
import 'package:chess_game_manika/features/call/presentation/screens/video_gallery_screen.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/chat_page.dart';
import 'package:chess_game_manika/features/game/presentation/screens/chess_board.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:chess_game_manika/features/profile/presentation/screens/profile_page.dart';
import 'package:chess_game_manika/features/home/presentation/screens/landing_page.dart';
import 'package:chess_game_manika/features/users/presentation/screens/user_list.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;

import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:chess_game_manika/core/api/api_services.dart';


class BottomNavBarWrapper extends StatefulWidget {
  const BottomNavBarWrapper({super.key});

  @override
  State<BottomNavBarWrapper> createState() => _BottomNavBarWrapperState();
}

class _BottomNavBarWrapperState extends State<BottomNavBarWrapper>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;
  int? _currentUserId;
  int? _currentRoomId;
  bool _loading = true;
  String? _errorMessage;

  List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _initUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initUser() async {
    try {
      print("BottomNavBar: Starting optimized initialization...");
      final startTime = DateTime.now();

      // 1. Fetch profile - this is the ONLY critical path task
      final profile = await ApiService().getProfile();
      final int? userId = profile['id'];
      final int roomId = profile['current_room_id'] ?? 1;

      if (userId == null) throw Exception("User ID not found");

      // 2. Launch background services asynchronously (NON-BLOCKING)
      _initializeBackgroundServices(userId, roomId);

      final endTime = DateTime.now();
      print(
        "BottomNavBar: Critical path initialization completed in ${endTime.difference(startTime).inMilliseconds}ms",
      );

      if (!mounted) return;

      // Initialize pages and stop loading IMMEDIATELY
      setState(() {
        _currentUserId = userId;
        _currentRoomId = roomId;
        _loading = false;
        _pages = [
          LandingPage(onTabChange: (index) {
            setState(() => _currentIndex = index);
            _pageController.jumpToPage(index);
          }),
          UserList(currentUserId: _currentUserId!),
          const VideoGalleryScreen(),
          ChatPage(
            roomId: _currentRoomId!,
            currentUserId: _currentUserId!,
            showBackButton: false,
          ),
          const ProfilePage(),
        ];
      });
    } catch (e, st) {
      debugPrint("Error initializing user: $e\n$st");
      // Fallback handling remains the same...
      if (mounted) {
        _handleInitializationError(e);
      }
    }
  }

  /// Non-blocking initialization of background services
  Future<void> _initializeBackgroundServices(int userId, int roomId) async {
    print("BottomNavBar: Initializing background services...");
    
    // a. Signaling (Background)
    GlobalCallHandler().connectForUser(userId).catchError((e) {
      print("Signaling init error: $e");
    });

    // b. FCM Token registration (Background)
    NotificationService.registerToken().catchError((e) {
      print("FCM registration error: $e");
    });

    // c. Probe Render server early (Background)
    ApiService().probe(ApiBase.render).catchError((e) {
      print("Render probe error: $e");
    });

    // d. Initialize ChatProvider (Background)
    if (mounted) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      chatProvider.clearActiveRoom();
      try {
        chatProvider.init(roomId, userId, setAsActive: false);
      } catch (e) {
        print("ChatProvider init error: $e");
      }
    }
  }

  void _handleInitializationError(Object e) {
    final String errorStr = e.toString().toLowerCase();

    if (errorStr.contains("401") ||
        errorStr.contains("unauthorized") ||
        errorStr.contains("[401]") ||
        errorStr.contains("[403]")) {
      debugPrint("User unauthorized, clearing session and going to login");
      SharedPreferences.getInstance().then((prefs) {
        prefs.clear();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const Login()),
          (route) => false,
        );
      });
      return;
    }

    setState(() {
      _loading = false;
      _errorMessage =
          "App failed to initialize. Please check your internet or try again.";
    });
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

    // Ensure index is within bounds before building BottomNavigationBar
    if (_currentIndex >= _pages.length) {
      _currentIndex = 0;
    }

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
            currentIndex: (_currentIndex >= _pages.length) ? 0 : _currentIndex,
            backgroundColor: foregroundColor, // Premium dark background
            selectedItemColor: primaryYellow,
            unselectedItemColor: Colors.white38,
            showSelectedLabels: true, // Show labels for clarity
            showUnselectedLabels: false,
            selectedFontSize: 12,
            onTap: (index) {
              print("BottomNavBar: onTap index $index");
              setState(() => _currentIndex = index);
              _pageController.jumpToPage(index);

              // Reset unread count AND ensure we are in the general room if Chat tab (now index 3) is clicked
              if (index == 3) {
                if (_currentRoomId != null) {
                  print(
                    "BottomNavBar: Tab 3 (Chat) clicked, setting active room to $_currentRoomId",
                  );
                  chatProvider.resetUnreadCount(_currentRoomId!);
                  // Re-init general room if we were previously in a private one
                  print("BottomNavBar: Returning to General Room 1");
                  chatProvider.init(_currentRoomId!, _currentUserId!);
                }
              } else {
                // If leaving the chat tab, clear the active room so notifications can happen
                print(
                  "BottomNavBar: Tab $index clicked (NOT Chat), clearing active room",
                );
                chatProvider.clearActiveRoom();
              }
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: "Home",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: "Players",
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.video_library), // Video Gallery Icon
                label: "Videos",
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
