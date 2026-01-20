import 'package:chess_game_manika/services/game_socket_service.dart';
import 'package:flutter/cupertino.dart';

class Gamescreen extends StatefulWidget {
  final String roomId;
  const Gamescreen({super.key, required this. roomId});

  @override
  State<Gamescreen> createState() => _GamescreenState();
}

class _GamescreenState extends State<Gamescreen> {
  final GameSocketService socket=GameSocketService();

  @override
  void initState(){
    super.initState();
    socket.onMessage=(data){
      if(data["type"]=="move"){

      }
    };
    socket.connect(widget.roomId);
  }
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}