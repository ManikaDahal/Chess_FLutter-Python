import 'package:chess_python/profile_page.dart';
import 'package:chess_python/ui/chess_board.dart';
import 'package:chess_python/ui/user_list.dart';
import 'package:flutter/material.dart';
import 'package:chess_python/core/utils/color_utils.dart';
import 'package:chess_python/services/signaling_service.dart';
import 'package:chess_python/core/utils/const.dart';

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
    // _initSignaling();
  }

  // void _initSignaling() {
  //   // For now using the same hardcoded roomId as in GameBoard
  //   // In a real app, this might be a user-specific room or a list of rooms.
  //   const roomId = "chess_room_1";

  //   String wsUrl;
  //   if (Constants.baseUrl.startsWith("https")) {
  //     wsUrl = Constants.baseUrl.replaceAll("https://", "wss://");
  //   } else {
  //     wsUrl = Constants.baseUrl.replaceAll("http://", "ws://");
  //   }

  //   // Connect to signaling
  //   _signalingService.connect(wsUrl, roomId);
  // }

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
