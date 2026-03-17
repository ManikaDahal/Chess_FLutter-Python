import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:chess_game_manika/core/utils/otp_args.dart';
import 'package:chess_game_manika/core/utils/resetPassword_args.dart';
import 'package:chess_game_manika/core/utils/room_args.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/forgot_password.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/login.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/otp_page.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/reset_password.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/sign_up.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/self_chat_screen.dart';
import 'package:chess_game_manika/features/game/presentation/screens/chess_board.dart';
import 'package:chess_game_manika/features/snake_game/models/snake_board.dart';
import 'package:chess_game_manika/features/snake_game/presentation/screens/board_selection_screen.dart';
import 'package:chess_game_manika/features/snake_game/presentation/screens/snake_game_screen.dart';

import 'package:flutter/material.dart';

class RouteGenerator {
  static navigateToPage(
    BuildContext context,
    String route, {
    dynamic arguments,
  }) {
    Navigator.push(
      context,
      generateRoute(RouteSettings(name: route, arguments: arguments)),
    );
  }

  static navigateToPageWithoutStack(
    BuildContext context,
    String route, {
    dynamic arguments,
  }) {
    Navigator.pushAndRemoveUntil(
      context,
      generateRoute(RouteSettings(name: route, arguments: arguments)),
      (route) => false,
    );
  }

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.signupRoute:
        return MaterialPageRoute(builder: (_) => const Signup());
      case Routes.loginRoute:
        return MaterialPageRoute(builder: (_) => const Login());
      case Routes.forgotPasswordRoute:
        return MaterialPageRoute(builder: (_) => const ForgotPassword());
      case Routes.bottomNavBarRoute:
        return MaterialPageRoute(builder: (_) => const BottomNavBarWrapper());
      // case Routes.enterOTPRoute:
      // return MaterialPageRoute(builder: (_) => const OtpPage());
      case Routes.enterOTPRoute:
        final args = settings.arguments as OtpArguments;

        return MaterialPageRoute(
          builder: (_) => OtpPage(contact: args.contact),
        );

      case Routes.resetPasswordRoute:
        final args = settings.arguments as ResetPasswordArguments;

        return MaterialPageRoute(
          builder: (_) => ResetPassword(contact: args.contact, otp: args.otp),
        );
      case Routes.gameRoomRoute:
        final args = settings.arguments as RoomArguments;

        return MaterialPageRoute(
          builder: (_) =>
              GameBoard(roomId: args.roomId, currentUserId: args.userId),
        );

      // case Routes.bottomNavBarRoute:
      //   return MaterialPageRoute(builder: (_) => const BottomnavBar());
      // case Routes.profileRoute:
      //   return MaterialPageRoute(builder: (_) => const ProfilePage());

      case Routes.selfChatRoute:
        return MaterialPageRoute(builder: (_) => const SelfChatScreen());

      case Routes.snakeBoardSelectionRoute:
        return MaterialPageRoute(builder: (_) => const BoardSelectionScreen());

      case Routes.snakeGameRoute:
        final board = settings.arguments as SnakeBoard;
        return MaterialPageRoute(builder: (_) => SnakeGameScreen(board: board));

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
