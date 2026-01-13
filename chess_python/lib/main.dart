import 'package:chess_python/bottom_navbar.dart';
import 'package:chess_python/login.dart';
import 'package:chess_python/services/token_storage.dart';
import 'package:chess_python/sign_up.dart';
import 'package:chess_python/ui/chess_board.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized;
  // final storage=TokenStorage();
  // final access = await storage.getAccessToken();
  // final refresh = await storage.getRefreshToken();
  // print("Access token on start $access");
  // print("Refresh token on start $refresh");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
       
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: GameBoard(),
    );
  }
}

