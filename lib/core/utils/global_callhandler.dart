// import 'package:flutter/material.dart';
// import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
// import 'package:chess_python/ui/call_screen.dart';
// import 'package:vibration/vibration.dart';
// import 'package:chess_python/services/signaling_service.dart';
// import 'package:chess_python/core/utils/const.dart';

// // class GlobalCallHandler {
// //   static final GlobalCallHandler _instance = GlobalCallHandler._internal();
// //   factory GlobalCallHandler() => _instance;
// //   GlobalCallHandler._internal();

// //   final SignalingService signalingService = SignalingService();

// //   void init() {
// //     // Only assign listener once
// //     signalingService.onIncomingCall = () {
// //       final context = Constants.navigatorKey.currentContext;
// //       if (context != null) {
// //         _showIncomingCallDialog(context, "chess_room_1");
// //       }
// //     };
// //   }

// //   void _showIncomingCallDialog(BuildContext context, String roomId) {
// //     FlutterRingtonePlayer().playRingtone(looping: true);
// //     showDialog(
// //       context: context,
// //       barrierDismissible: false,
// //       builder: (_) => AlertDialog(
// //         title: const Text("Incoming Call"),
// //         content: Text("You have an incoming call in room: $roomId"),
// //         actions: [
// //           TextButton(
// //             onPressed: () {
// //               FlutterRingtonePlayer().stop();
// //               Navigator.pop(context);
// //               signalingService.disconnect(); // Decline call
// //             },
// //             child: const Text("Decline", style: TextStyle(color: Colors.red)),
// //           ),
// //           ElevatedButton(
// //             onPressed: () {
// //               FlutterRingtonePlayer().stop();
// //               Navigator.pop(context);
// //               Constants.navigatorKey.currentState?.push(
// //                 MaterialPageRoute(
// //                   builder: (_) =>
// //                       CallScreen(roomId: roomId, isIncomingCall: true),
// //                 ),
// //               );
// //             },
// //             child: const Text("Accept"),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }
// class GlobalCallHandler {
//   static final GlobalCallHandler _instance = GlobalCallHandler._internal();
//   factory GlobalCallHandler() => _instance;
//   GlobalCallHandler._internal();

//   final SignalingService signalingService = SignalingService();
//   bool _initialized = false;

//   // CHANGE: Modified init() to connect to general chess_room_1
//   // This room is used for chess board calls (everyone can hear)
//   void init() async {
//     if (_initialized) return;
//     _initialized = true;

//     const roomId = "chess_room_1";

//     // CHANGE: Using wsBaseUrl for WebSocket (Render)
//     String wsUrl = Constants.wsBaseUrl;

//     // Listen for incoming calls
//     signalingService.onIncomingCall = () {
//       debugPrint('🔔 Incoming call received in GlobalCallHandler');
//       final context = Constants.navigatorKey.currentContext;
//       if (context != null) {
//         bool isVideo = signalingService.pendingMediaType == 'video';
//         // CHANGE: Use currentRoomId to determine which room the call is from
//         String? currentRoom = signalingService.currentRoomId;
//         _showIncomingCallDialog(
//           context,
//           currentRoom ?? roomId,
//           isVideo: isVideo,
//         );
//       } else {
//         debugPrint('❌ Cannot show incoming call dialog: context is null');
//       }
//     };

//     // ✅ START SIGNALING for general chess room
//     try {
//       debugPrint('🌐 Connecting to general signaling: $wsUrl (Room: $roomId)');
//       await signalingService.connect(wsUrl, roomId);
//       debugPrint('✅ Connected to general signaling room: $roomId');
//     } catch (e) {
//       debugPrint('❌ Failed to connect to general signaling: $e');
//     }
//   }

//   // CHANGE: Added connectForUser() to enable user-specific signaling
//   // This allows users to receive calls targeted specifically at them
//   // Each user listens on their own room: user_{userId}
//   Future<void> connectForUser(int userId) async {
//     final roomId = "user_$userId";

//     // CHANGE: Using wsBaseUrl for WebSocket (Render)
//     String wsUrl = Constants.wsBaseUrl;

//     try {
//       debugPrint(
//         '🌐 Connecting to user-specific signaling: $wsUrl (Room: $roomId)',
//       );
//       await signalingService.connect(wsUrl, roomId);
//       debugPrint('✅ Connected to user-specific signaling room: $roomId');
//     } catch (e) {
//       debugPrint('❌ Failed to connect to user-specific signaling: $e');
//     }
//   }

//   void _showIncomingCallDialog(
//     BuildContext context,
//     String roomId, {
//     bool isVideo = true,
//   }) {
//     FlutterRingtonePlayer().playRingtone(looping: true);
//     Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);

//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (_) => AlertDialog(
//         title: Text("Incoming ${isVideo ? 'Video' : 'Audio'} Call"),
//         content: Text(
//           "You have an incoming ${isVideo ? 'video' : 'audio'} call",
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               FlutterRingtonePlayer().stop();
//               Vibration.cancel();
//               Navigator.pop(context);
//               signalingService.disconnect(); // Decline
//             },
//             child: const Text("Decline", style: TextStyle(color: Colors.red)),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               FlutterRingtonePlayer().stop();
//               Vibration.cancel();
//               Navigator.pop(context);
//               Constants.navigatorKey.currentState?.push(
//                 MaterialPageRoute(
//                   builder: (_) => CallScreen(
//                     roomId: roomId,
//                     isIncomingCall: true,
//                     isInitialVideo: isVideo,
//                   ),
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

import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/recording_service.dart';
import 'package:chess_game_manika/services/signaling_service.dart';
import 'package:chess_game_manika/ui/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

class GlobalCallHandler {
  static final GlobalCallHandler _instance = GlobalCallHandler._internal();
  factory GlobalCallHandler() => _instance;
  GlobalCallHandler._internal();

  // Separate instances for general and user-specific rooms
  SignalingService? _generalSignalingService;
  SignalingService? _userSignalingService;
  bool _initialized = false;

  // Accessors to reuse disconnected services for outgoing calls
  SignalingService? get generalSignalingService => _generalSignalingService;
  SignalingService? get userSignalingService => _userSignalingService;

  // Track minimized state
  final ValueNotifier<bool> isMinimized = ValueNotifier<bool>(false);
  final ValueNotifier<String?> activeRoomId = ValueNotifier<String?>(null);

  SignalingService? get activeService {
    if (_userSignalingService?.isCallActive == true)
      return _userSignalingService;
    if (_generalSignalingService?.isCallActive == true)
      return _generalSignalingService;
    return null;
  }

  // CHANGE: Modified init() to connect to general chess_room_1 using a dedicated instance
  // This room is used for chess board calls (everyone can hear)
  void init() async {
    if (_initialized) return;
    _initialized = true;

    const homeRoom = "chess_room_1";

    // Create a dedicated instance for general signaling
    _generalSignalingService = SignalingService();

    // Listen for incoming calls in the general room
    _generalSignalingService!.onIncomingCall = () {
      debugPrint('🔔 Incoming call received in general room: $homeRoom');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = _generalSignalingService!.pendingMediaType == 'video';
        _showIncomingCallDialog(context, homeRoom, isVideo: isVideo);
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    };

    _generalSignalingService!.onHangup = () {
      debugPrint('🔔 Peer hung up in general room');
      _handleGlobalHangup();
    };

    // ✅ START SIGNALING for general chess room
    try {
      debugPrint(
        '🌐 Connecting to general signaling: ${Constants.wsBaseUrl} (Room: $homeRoom)',
      );
      await _generalSignalingService!.connect(Constants.wsBaseUrl, homeRoom);
      debugPrint('✅ Connected to general signaling room: $homeRoom');
    } catch (e) {
      debugPrint('❌ Failed to connect to general signaling: $e');
    }
  }

  // CHANGE: Added connectForUser() to enable user-specific signaling using a separate instance
  // This allows users to receive calls targeted specifically at them
  // Each user listens on their own room: user_{userId}
  Future<void> connectForUser(int userId) async {
    final roomId = "user_$userId";

    // Create a dedicated instance for user-specific signaling (if not already created)
    if (_userSignalingService != null) {
      debugPrint('⚠️ User signaling already connected, skipping');
      return;
    }
    _userSignalingService = SignalingService();

    // Listen for incoming calls in the user-specific room
    _userSignalingService!.onIncomingCall = () {
      debugPrint('🔔 Incoming call received in user-specific room: $roomId');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = _userSignalingService!.pendingMediaType == 'video';
        _showIncomingCallDialog(context, roomId, isVideo: isVideo);
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    };

    try {
      debugPrint(
        '🌐 Connecting to user-specific signaling: ${Constants.wsBaseUrl} (Room: $roomId)',
      );
      await _userSignalingService!.connect(Constants.wsBaseUrl, roomId);
      debugPrint('✅ Connected to user-specific signaling room: $roomId');

      _userSignalingService!.onHangup = () {
        debugPrint('🔔 Peer hung up in user-specific room');
        _handleGlobalHangup(userId: userId);
      };
    } catch (e) {
      debugPrint('❌ Failed to connect to user-specific signaling: $e');
    }
  }

  void _handleGlobalHangup({int? userId}) {
    if (isMinimized.value) {
      debugPrint('🏠 Global handler: Cleaning up minimized call after hangup');
      isMinimized.value = false;
      RecordingService().stopRecording();
      ensureRoomResidency(userId);
    }
  }

  // RE-CONNECTION LOGIC: Ensure global services are on their correct "home" rooms
  void ensureRoomResidency(int? userId) {
    if (_generalSignalingService != null &&
        _generalSignalingService!.currentRoomId != "chess_room_1") {
      debugPrint('🏠 Re-connecting general signaling to home room');
      _generalSignalingService!.connect(Constants.wsBaseUrl, "chess_room_1");
    }

    if (userId != null &&
        _userSignalingService != null &&
        _userSignalingService!.currentRoomId != "user_$userId") {
      debugPrint('🏠 Re-connecting user signaling to home room: user_$userId');
      _userSignalingService!.connect(Constants.wsBaseUrl, "user_$userId");
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
              // Decline: Disconnect the relevant service
              if (roomId.startsWith('user_')) {
                _userSignalingService?.disconnect();
              } else {
                _generalSignalingService?.disconnect();
              }
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Vibration.cancel();
              Navigator.pop(context);
              // Determine which signaling service to use
              SignalingService? serviceToUse = roomId.startsWith('user_')
                  ? _userSignalingService
                  : _generalSignalingService;
              Constants.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    roomId: roomId,
                    isIncomingCall: true,
                    isInitialVideo: isVideo,
                    signalingService: serviceToUse,
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

  // Optional: Method to disconnect all services (e.g., on app close)
  void disconnectAll() {
    _generalSignalingService?.disconnect();
    _userSignalingService?.disconnect();
  }
}
