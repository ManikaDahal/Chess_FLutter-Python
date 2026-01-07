
import 'package:chess_python/bottom_navbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/forgot_password.dart';
import 'package:chess_python/login.dart';
import 'package:chess_python/sign_up.dart';
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
        return MaterialPageRoute(builder: (_) => const BottomnavBar());
      // case Routes.enterOTPRoute:
      //   final args = settings.arguments as OtpArguments;

      //   return MaterialPageRoute(
      //     builder: (_) => OtpPage(
      //       isEmail: args.isEmail,
      //       contact: args.contact,
      //       verificationId: args.verificationId,
      //     ),
      //   );

      // case Routes.resetPasswordRoute:
      //   final args = settings.arguments as ResetPasswordArguments;

      //   return MaterialPageRoute(
      //     builder: (_) =>
      //         ResetPassword(isEmail: args.isEmail, contact: args.contact),
      //   );
      // case Routes.gameBoardRoute:
      //   return MaterialPageRoute(builder: (_) => const GameBoard());
      // case Routes.bottomNavBarRoute:
      //   return MaterialPageRoute(builder: (_) => const BottomnavBar());
      // case Routes.profileRoute:
      //   return MaterialPageRoute(builder: (_) => const ProfilePage());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
