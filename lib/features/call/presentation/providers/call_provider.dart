import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/call/presentation/screens/call_screen.dart';
import 'package:chess_game_manika/features/call/services/recording_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallState {
  final bool isMinimized;
  final String? activeRoomId;
  final int? activeChessRoomId;
  final int? activeSnakeRoomId;
  final int? currentUserId;
  final int? opponentId;
  final bool amIWhite;
  final bool isMuted;
  final bool isVideoEnabled;

  const CallState({
    this.isMinimized = false,
    this.activeRoomId,
    this.activeChessRoomId,
    this.activeSnakeRoomId,
    this.currentUserId,
    this.opponentId,
    this.amIWhite = true,
    this.isMuted = false,
    this.isVideoEnabled = true,
  });

  CallState copyWith({
    bool? isMinimized,
    String? activeRoomId,
    int? activeChessRoomId,
    int? activeSnakeRoomId,
    int? currentUserId,
    int? opponentId,
    bool? amIWhite,
    bool? isMuted,
    bool? isVideoEnabled,
    bool clearActiveRoom = false,
    bool clearChessRoom = false,
    bool clearSnakeRoom = false,
    bool clearOpponent = false,
  }) {
    return CallState(
      isMinimized: isMinimized ?? this.isMinimized,
      activeRoomId: clearActiveRoom ? null : (activeRoomId ?? this.activeRoomId),
      activeChessRoomId: clearChessRoom ? null : (activeChessRoomId ?? this.activeChessRoomId),
      activeSnakeRoomId: clearSnakeRoom ? null : (activeSnakeRoomId ?? this.activeSnakeRoomId),
      currentUserId: currentUserId ?? this.currentUserId,
      opponentId: clearOpponent ? null : (opponentId ?? this.opponentId),
      amIWhite: amIWhite ?? this.amIWhite,
      isMuted: isMuted ?? this.isMuted,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
    );
  }
}

class CallNotifier extends Notifier<CallState> {
  SignalingService? generalSignalingService;
  SignalingService? userSignalingService;
  SignalingService? activeCallService;

  bool _initialized = false;
  bool _isDialogShowing = false;

  @override
  CallState build() {
    return const CallState();
  }

  SignalingService? get activeService {
    if (activeCallService != null) return activeCallService;
    if (userSignalingService?.inCallSession == true) return userSignalingService;
    if (generalSignalingService?.inCallSession == true) return generalSignalingService;
    return null;
  }

  void setIsMinimized(bool val) => state = state.copyWith(isMinimized: val);
  void setActiveRoomId(String? val) => state = state.copyWith(activeRoomId: val, clearActiveRoom: val == null);
  void setActiveCallService(SignalingService? service) => activeCallService = service;
  
  void setChessContext({int? roomId, int? currentUserId, int? opponentId, bool amIWhite = true}) {
    state = state.copyWith(
      activeChessRoomId: roomId,
      clearChessRoom: roomId == null,
      currentUserId: currentUserId,
      opponentId: opponentId,
      clearOpponent: opponentId == null,
      amIWhite: amIWhite,
    );
  }

  void clearChessContext() {
    state = state.copyWith(clearChessRoom: true, clearOpponent: true);
  }

  void setSnakeContext({int? roomId, int? currentUserId, int? opponentId}) {
    state = state.copyWith(
      activeSnakeRoomId: roomId,
      clearSnakeRoom: roomId == null,
      currentUserId: currentUserId,
      opponentId: opponentId,
      clearOpponent: opponentId == null,
    );
  }

  void clearSnakeContext() {
    state = state.copyWith(clearSnakeRoom: true, clearOpponent: true);
  }

  void setMuted(bool val) => state = state.copyWith(isMuted: val);
  void setVideoEnabled(bool val) => state = state.copyWith(isVideoEnabled: val);

  void init() async {
    if (_initialized) return;
    _initialized = true;

    generalSignalingService?.disconnect();
    userSignalingService?.disconnect();
    generalSignalingService = null;
    userSignalingService = null;

    const homeRoom = "chess_room_1";

    generalSignalingService = SignalingService();

    generalSignalingService!.onIncomingCallStream.listen((mediaType) {
      debugPrint('🔔 Incoming $mediaType call received in general room: $homeRoom');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = mediaType == 'video';
        _showIncomingCallDialog(context, homeRoom, isVideo: isVideo);
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    });

    generalSignalingService!.onHangupStream.listen((_) {
      debugPrint('🔔 Peer hung up in general room');
      _handleGlobalHangup();
    });

    try {
      debugPrint('🌐 Connecting to general signaling: ${Constants.wsBaseUrl} (Room: $homeRoom)');
      await generalSignalingService!.connect(Constants.wsBaseUrl, homeRoom);
      debugPrint('✅ Connected to general signaling room: $homeRoom');
    } catch (e) {
      debugPrint('❌ Failed to connect to general signaling: $e');
    }
  }

  Future<void> connectForUser(int userId) async {
    final roomId = "user_$userId";

    if (userSignalingService != null) {
      if (userSignalingService!.currentRoomId == roomId) {
        debugPrint('⚠️ User signaling already connected to $roomId, skipping');
        return;
      }
      debugPrint('🔄 Switch user signaling from ${userSignalingService!.currentRoomId} to $roomId');
      userSignalingService!.disconnect();
    }
    userSignalingService = SignalingService();
    state = state.copyWith(currentUserId: userId);

    userSignalingService!.onIncomingCallStream.listen((mediaType) {
      debugPrint('🔔 Incoming $mediaType call in user-specific room: $roomId');
      final context = Constants.navigatorKey.currentContext;
      if (context != null) {
        bool isVideo = mediaType == 'video';
        _showIncomingCallDialog(context, roomId, isVideo: isVideo);
      } else {
        debugPrint('❌ Cannot show incoming call dialog: context is null');
      }
    });

    userSignalingService!.onHangupStream.listen((_) {
      debugPrint('🔔 Peer hung up in user-specific room');
      _handleGlobalHangup(userId: userId);
    });
    try {
      debugPrint('🌐 Connecting to user-specific signaling: ${Constants.wsBaseUrl} (Room: $roomId)');
      await userSignalingService!.connect(Constants.wsBaseUrl, roomId);
      debugPrint('✅ Connected to user-specific signaling room: $roomId');
    } catch (e) {
      debugPrint('❌ Failed to connect to user-specific signaling: $e');
    }
  }

  void _handleGlobalHangup({int? userId}) {
    debugPrint('🏠 Global handler: Peer hung up. Cleaning up state.');
    activeService?.endCall(sendSignal: false);

    state = state.copyWith(isMinimized: false, clearActiveRoom: true);
    RecordingService().stopRecording();

    ensureRoomResidency(userId);
  }

  void ensureRoomResidency(int? userId) {
    if (generalSignalingService != null && generalSignalingService!.currentRoomId != "chess_room_1") {
      debugPrint('🏠 Re-connecting general signaling to home room');
      generalSignalingService!.connect(Constants.wsBaseUrl, "chess_room_1");
    }

    if (userId != null && userSignalingService != null && userSignalingService!.currentRoomId != "user_$userId") {
      debugPrint('🏠 Re-connecting user signaling to home room: user_$userId');
      userSignalingService!.connect(Constants.wsBaseUrl, "user_$userId");
    }
  }

  void _showIncomingCallDialog(BuildContext context, String roomId, {bool isVideo = true}) {
    if (_isDialogShowing) {
      debugPrint('⚠️ Skipping duplicate incoming call dialog for room: $roomId');
      return;
    }
    _isDialogShowing = true;

    FlutterRingtonePlayer().playRingtone(looping: true);
    Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text("Incoming ${isVideo ? 'Video' : 'Audio'} Call"),
        content: Text("You have an incoming ${isVideo ? 'video' : 'audio'} call"),
        actions: [
          TextButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Vibration.cancel();
              Navigator.pop(context);
              if (roomId.startsWith('user_')) {
                userSignalingService?.disconnect();
              } else {
                generalSignalingService?.disconnect();
              }
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              FlutterRingtonePlayer().stop();
              Vibration.cancel();
              Navigator.pop(context);
              SignalingService? serviceToUse = roomId.startsWith('user_') ? userSignalingService : generalSignalingService;
              Constants.navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    roomId: roomId,
                    isIncomingCall: true,
                    isInitialVideo: isVideo,
                    signalingService: serviceToUse,
                    currentUserId: state.currentUserId,
                    canMinimize: state.activeChessRoomId != null || state.activeSnakeRoomId != null,
                  ),
                ),
              );
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
      FlutterRingtonePlayer().stop();
      Vibration.cancel();
      debugPrint('ℹ️ Incoming call dialog dismissed. Ready for next call.');
    });
  }

  void disconnectAll() {
    generalSignalingService?.disconnect();
    userSignalingService?.disconnect();
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(() {
  return CallNotifier();
});
