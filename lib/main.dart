import 'package:chess_python/bottom_navbar.dart';
import 'package:chess_python/core/utils/const.dart';
import 'package:chess_python/core/utils/global_callhandler.dart';
import 'package:chess_python/login.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Start global call listener
  GlobalCallHandler().init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // final GlobalCallHandler _callHandler = GlobalCallHandler();
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Initialize the global call listener
    // _callHandler.init();

    return MaterialApp(
      navigatorKey: Constants.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Login(),
    );
  }

  
}
