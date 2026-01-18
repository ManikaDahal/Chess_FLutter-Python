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

  // CHANGE: Modified init() to connect to general chess_room_1
  // This room is used for chess board calls (everyone can hear)
  void init() async {
    if (_initialized) return;
    _initialized = true;

    const roomId = "chess_room_1";

    // CHANGE: Using wsBaseUrl for WebSocket (Render)
    String wsUrl = Constants.wsBaseUrl;

    // Listen for incoming calls
    signalingService.onIncomingCall = () {
      debugPrint('🔔 Incoming call received in GlobalCallHandler');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = signalingService.pendingMediaType == 'video';
        // CHANGE: Use currentRoomId to determine which room the call is from
        String? currentRoom = signalingService.currentRoomId;
        _showIncomingCallDialog(
          context,
          currentRoom ?? roomId,
          isVideo: isVideo,
        );
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    };

    // ✅ START SIGNALING for general chess room
    try {
      debugPrint('🌐 Connecting to general signaling: $wsUrl (Room: $roomId)');
      await signalingService.connect(wsUrl, roomId);
      debugPrint('✅ Connected to general signaling room: $roomId');
    } catch (e) {
      debugPrint('❌ Failed to connect to general signaling: $e');
    }
  }

  // CHANGE: Added connectForUser() to enable user-specific signaling
  // This allows users to receive calls targeted specifically at them
  // Each user listens on their own room: user_{userId}
  Future<void> connectForUser(int userId) async {
    final roomId = "user_$userId";

    // CHANGE: Using wsBaseUrl for WebSocket (Render)
    String wsUrl = Constants.wsBaseUrl;

    try {
      debugPrint(
        '🌐 Connecting to user-specific signaling: $wsUrl (Room: $roomId)',
      );
      await signalingService.connect(wsUrl, roomId);
      debugPrint('✅ Connected to user-specific signaling room: $roomId');
    } catch (e) {
      debugPrint('❌ Failed to connect to user-specific signaling: $e');
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
