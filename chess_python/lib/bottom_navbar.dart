import 'package:chess_python/profile_page.dart';
import 'package:chess_python/ui/chess_board.dart';
import 'package:flutter/material.dart';
import 'package:chess_python/core/utils/color_utils.dart';



class BottomnavBar extends StatefulWidget {

  const BottomnavBar({super.key,});

  @override
  State<BottomnavBar> createState() => _BottomnavBarState();
}

class _BottomnavBarState extends State<BottomnavBar> {
    
  PageController _pageController = PageController();
  int index = 0;

  List<BottomNavigationBarItem> bottomNavItemList = [
    const BottomNavigationBarItem(icon: Icon(Icons.home), label: ""),
    const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: ""),
  ];
 

  List<Widget> widgets = [const GameBoard(), const ProfilePage()];
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
