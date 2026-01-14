import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:chess_python/ui/call_screen.dart';
import 'package:chess_python/services/signaling_service.dart';
import 'package:chess_python/core/utils/const.dart';

class GlobalCallHandler {
  static final GlobalCallHandler _instance = GlobalCallHandler._internal();
  factory GlobalCallHandler() => _instance;
  GlobalCallHandler._internal();

  final SignalingService signalingService = SignalingService();

  void init() {
    // Only assign listener once
    signalingService.onIncomingCall = () {
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        _showIncomingCallDialog(context, "chess_room_1");
      }
    };
  }

  void _showIncomingCallDialog(BuildContext context, String roomId) {
    FlutterRingtonePlayer().playRingtone(looping: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Incoming Call"),
        content: Text("You have an incoming call in room: $roomId"),
        actions: [
          TextButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Navigator.pop(context);
              signalingService.disconnect(); // Decline call
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Navigator.pop(context);
              Constants.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) =>
                      CallScreen(roomId: roomId, isIncomingCall: true),
                ),
              );
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }
}
