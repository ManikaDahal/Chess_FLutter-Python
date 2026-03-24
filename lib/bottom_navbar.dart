import 'package:chess_game_manika/features/call/presentation/screens/video_gallery_screen.dart';
import 'package:chess_game_manika/features/call/presentation/providers/call_provider.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/chat_page.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:chess_game_manika/features/profile/presentation/screens/profile_page.dart';
import 'package:chess_game_manika/features/home/presentation/screens/landing_page.dart';
import 'package:chess_game_manika/features/users/presentation/screens/friend_list.dart';

import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:badges/badges.dart' as badges;

import 'package:chess_game_manika/core/utils/color_utils.dart';

import 'package:chess_game_manika/core/api/api_services.dart';

import 'package:chess_game_manika/core/widgets/connectivity_banner.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';

class BottomNavBarWrapper extends ConsumerStatefulWidget {
  const BottomNavBarWrapper({super.key});

  @override
  ConsumerState<BottomNavBarWrapper> createState() => _BottomNavBarWrapperState();
}

class _BottomNavBarWrapperState extends ConsumerState<BottomNavBarWrapper>
    with WidgetsBindingObserver {

  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startServices();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  void _startServices() {
    final authState = ref.read(authProvider).value;
    if (authState != null && authState.isAuthenticated && authState.userId != null) {
      _initializeBackgroundServices(authState.userId!, authState.roomId ?? 1);
    }
  }

  /// Non-blocking initialization of background services (Staggered to prevent frame skips)
  Future<void> _initializeBackgroundServices(int userId, int roomId) async {
    print("BottomNavBar: Initializing background services (Staggered)...");

    // 1. Give the UI a moment to be responsive first
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // 2. Signaling (User-specific) - PRIORITY
    ref.read(callProvider.notifier).connectForUser(userId).catchError((e) {
      print("Signaling user connect error: $e");
    });

    // 3. Signaling (General/Home room) - 1s stagger
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    ref.read(callProvider.notifier).init();

    // 4. FCM Token registration - 1s stagger
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    NotificationService.registerToken().catchError((e) {
      print("FCM registration error: $e");
    });

    // 5. Probe Render server - 1s stagger
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    ApiService().probe(ApiBase.render).catchError((e) {
      print("Render probe error: $e");
    });

    // 6. Initialize ChatProvider - Final stagger
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      ref.read(chatProvider.notifier).clearActiveRoom();
      ref.read(chatProvider.notifier).init(roomId, userId, setAsActive: false);
    } catch (e) {
      print("ChatProvider init error: $e");
    }

  }

  @override
  Widget build(BuildContext context) {
    // Read from auth provider synchronously to ensure we have the ID to render pages
    final authState = ref.watch(authProvider).value;
    
    if (authState == null || !authState.isAuthenticated || authState.userId == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final currentUserId = authState.userId!;
    final currentRoomId = authState.roomId ?? 1;

    final pages = [
      LandingPage(
        onTabChange: (index) {
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        },
      ),
      FriendListScreen(currentUserId: currentUserId),
      const VideoGalleryScreen(),
      ChatPage(
        roomId: currentRoomId,
        currentUserId: currentUserId,
        showBackButton: false,
      ),
      const ProfilePage(),
    ];

    // Ensure index is within bounds before building BottomNavigationBar
    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    return ConnectivityBanner(
      child: Consumer(
        builder: (context, ref, _) {
          final chatProviderRef = ref.watch(chatProvider);
          return Scaffold(

            body: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: pages,
            ),
            bottomNavigationBar: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: (_currentIndex >= pages.length)
                  ? 0
                  : _currentIndex,
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
                  print(
                    "BottomNavBar: Tab 3 (Chat) clicked, setting active room to $currentRoomId",
                  );
                  ref.read(chatProvider.notifier).resetUnreadCount(currentRoomId);
                  // Re-init general room if we were previously in a private one
                  print("BottomNavBar: Returning to General Room 1");
                  ref.read(chatProvider.notifier).init(currentRoomId, currentUserId);
                } else {
                  // If leaving the chat tab, clear the active room so notifications can happen
                  print(
                    "BottomNavBar: Tab $index clicked (NOT Chat), clearing active room",
                  );
                  ref.read(chatProvider.notifier).clearActiveRoom();

                }
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: "Home",
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt_rounded),
                  label: "Social",
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.video_library), // Video Gallery Icon
                  label: "Videos",
                ),
                BottomNavigationBarItem(
                  icon: badges.Badge(
                    showBadge: chatProviderRef.totalUnreadCount > 0,
                    badgeContent: Text(
                      chatProviderRef.totalUnreadCount.toString(),
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
      ),
    );
  }
}
