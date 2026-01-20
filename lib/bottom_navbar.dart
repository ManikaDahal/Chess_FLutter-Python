import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/profile_page.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/services/signaling_service.dart';
import 'package:chess_game_manika/ui/chess_board.dart';
import 'package:chess_game_manika/ui/user_list.dart';
import 'package:flutter/material.dart';


class BottomnavBar extends StatefulWidget {
  const BottomnavBar({super.key});

  @override
  State<BottomnavBar> createState() => _BottomnavBarState();
}

class _BottomnavBarState extends State<BottomnavBar> {
  PageController _pageController = PageController();
  int index = 0;
  final SignalingService _signalingService = SignalingService();

  @override
  void initState() {
    super.initState();
    // CHANGE: Initialize user-specific signaling for targeted calls
    _initUserSignaling();
  }

  // CHANGE: Added _initUserSignaling() to connect user to their personal room
  // This allows them to receive calls targeted specifically at them from the user list
  // Note: General chess_room_1 is already connected in GlobalCallHandler.init()
  Future<void> _initUserSignaling() async {
    try {
      final apiService = ApiService();
      final profile = await apiService.getProfile();
      final int? userId = profile['id'];

      if (userId != null) {
        debugPrint('🚀 Initializing user-specific signaling for user: $userId');
        // Connect to user's personal room: user_{userId}
        await GlobalCallHandler().connectForUser(userId);
      } else {
        debugPrint(
          '⚠️ Could not find user ID in profile for user-specific signaling',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ Error initializing user-specific signaling in BottomnavBar: $e',
      );
    }
  }

  List<BottomNavigationBarItem> bottomNavItemList = [
    const BottomNavigationBarItem(icon: Icon(Icons.home), label: ""),
    const BottomNavigationBarItem(icon: Icon(Icons.people), label: ""),
    const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: ""),
  ];

  List<Widget> widgets = [
    const GameBoard(),
    const UserList(),
    const ProfilePage(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        children: widgets,
        onPageChanged: (value) {
          setState(() {
            index = value;
          });
        },
      ),
      bottomNavigationBar: Theme(
        data: ThemeData(splashFactory: NoSplash.splashFactory),

        child: BottomNavigationBar(
          items: bottomNavItemList,
          currentIndex: index,
          backgroundColor: whiteColor,
          unselectedItemColor: foregroundColor,
          selectedItemColor: backgroundColor,
          type: BottomNavigationBarType.fixed,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          onTap: (value) {
            setState(() {
              index = value;
              _pageController.jumpToPage(value);
            });
          },
        ),
      ),
    );
  }
}
