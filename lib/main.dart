import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/login.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // final int currentUserId = await getCurrentUserId();
  // Start global call listener
  GlobalCallHandler().init();
  await NotificationService.init(navKey: Constants.navigatorKey);
  runApp(MyApp());
}

// Future<int> getCurrentUserId() async {
//   final prefs = await SharedPreferences.getInstance();
//   return prefs.getInt('userId') ?? 0; // fallback if not saved
// }

// Future<void> setCurrentUserId(int id) async {
//   final prefs = await SharedPreferences.getInstance();
//   await prefs.setInt('userId', id);
//}

class MyApp extends StatelessWidget {
  // final GlobalCallHandler _callHandler = GlobalCallHandler();
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Initialize the global call listener
    // _callHandler.init();

    return MultiProvider(
       providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MaterialApp(
        navigatorKey: Constants.navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: Login(),
      ),
    );
  }
}
