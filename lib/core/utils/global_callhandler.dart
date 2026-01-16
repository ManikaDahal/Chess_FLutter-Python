import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:chess_python/ui/call_screen.dart';
import 'package:vibration/vibration.dart';
import 'package:chess_python/services/signaling_service.dart';
import 'package:chess_python/core/utils/const.dart';

// class GlobalCallHandler {
//   static final GlobalCallHandler _instance = GlobalCallHandler._internal();
//   factory GlobalCallHandler() => _instance;
//   GlobalCallHandler._internal();

//   final SignalingService signalingService = SignalingService();

//   void init() {
//     // Only assign listener once
//     signalingService.onIncomingCall = () {
//       final context = Constants.navigatorKey.currentContext;
//       if (context != null) {
//         _showIncomingCallDialog(context, "chess_room_1");
//       }
//     };
//   }

//   void _showIncomingCallDialog(BuildContext context, String roomId) {
//     FlutterRingtonePlayer().playRingtone(looping: true);
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (_) => AlertDialog(
//         title: const Text("Incoming Call"),
//         content: Text("You have an incoming call in room: $roomId"),
//         actions: [
//           TextButton(
//             onPressed: () {
//               FlutterRingtonePlayer().stop();
//               Navigator.pop(context);
//               signalingService.disconnect(); // Decline call
//             },
//             child: const Text("Decline", style: TextStyle(color: Colors.red)),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               FlutterRingtonePlayer().stop();
//               Navigator.pop(context);
//               Constants.navigatorKey.currentState?.push(
//                 MaterialPageRoute(
//                   builder: (_) =>
//                       CallScreen(roomId: roomId, isIncomingCall: true),
//                 ),
//               );
//             },
//             child: const Text("Accept"),
//           ),
//         ],
//       ),
//     );
//   }
// }
class GlobalCallHandler {
  static final GlobalCallHandler _instance = GlobalCallHandler._internal();
  factory GlobalCallHandler() => _instance;
  GlobalCallHandler._internal();

  final SignalingService signalingService = SignalingService();
  bool _initialized = false;

  void init() async {
    if (_initialized) return;
    _initialized = true;

    const roomId = "chess_room_1";

    String wsUrl;
    if (Constants.baseUrl.startsWith("https")) {
      wsUrl = Constants.baseUrl.replaceAll("https://", "wss://");
    } else {
      wsUrl = Constants.baseUrl.replaceAll("http://", "ws://");
    }

    // Listen for incoming calls
    signalingService.onIncomingCall = () {
      debugPrint('🔔 Incoming call received in GlobalCallHandler');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = signalingService.pendingMediaType == 'video';
        _showIncomingCallDialog(context, roomId, isVideo: isVideo);
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    };

    // ✅ START SIGNALING
    try {
      debugPrint('🌐 Connecting to signaling: $wsUrl');
      await signalingService.connect(wsUrl, roomId);
      debugPrint('✅ Connected to signaling');
    } catch (e) {
      debugPrint('❌ Failed to connect to signaling: $e');
    }
  }

  void _showIncomingCallDialog(
    BuildContext context,
    String roomId, {
    bool isVideo = true,
  }) {
    FlutterRingtonePlayer().playRingtone(looping: true);
    Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text("Incoming ${isVideo ? 'Video' : 'Audio'} Call"),
        content: Text(
          "You have an incoming ${isVideo ? 'video' : 'audio'} call",
        ),
        actions: [
          TextButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Vibration.cancel();
              Navigator.pop(context);
              signalingService.disconnect(); // Decline
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Vibration.cancel();
              Navigator.pop(context);
              Constants.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    roomId: roomId,
                    isIncomingCall: true,
                    isInitialVideo: isVideo,
                  ),
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
