import 'dart:async';
import 'package:badges/badges.dart' as badges;
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/features/call/presentation/providers/call_provider.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/features/call/services/recording_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/chat_page.dart';
import 'package:chess_game_manika/features/game/presentation/widgets/square_widget.dart';
import 'package:chess_game_manika/features/game/presentation/providers/chess_provider.dart';
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';
import 'package:chess_game_manika/features/game/services/game_websocket_service.dart';
import 'package:chess_game_manika/helper/helper.dart';
import 'package:chess_game_manika/features/game/data/models/chess_piece.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';

class GameBoard extends ConsumerStatefulWidget {
  final int roomId;
  final int currentUserId;
  final bool isMultiplayer;
  final bool amIWhite;
  final int? opponentId;
  final bool showLeaveButton;
  final SignalingService? signalingService; // Optional external service

  const GameBoard({
    super.key,
    required this.currentUserId,
    required this.roomId,
    this.isMultiplayer = false,
    this.amIWhite = true,
    this.opponentId,
    this.showLeaveButton = false,
    this.signalingService,
  });

  @override
  ConsumerState<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends ConsumerState<GameBoard>
    with AutomaticKeepAliveClientMixin {
  final GameWebsocketService _gameService = GameWebsocketService();
  final RecordingService _recordingService = RecordingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  SignalingService? _signalingService;
  bool _isRendererReady = false;

  // Cleanup subscriptions
  StreamSubscription? _gameConnSub;
  StreamSubscription? _signalingConnSub;
  StreamSubscription? _incomingCallSub;
  StreamSubscription? _customMessageSub;
  StreamSubscription? _peerJoinedSub;
  StreamSubscription? _onHangupSub;
  StreamSubscription? _onCallAcceptedSub;
  Timer? _handshakePulseTimer;
  Timer? _callTimeoutTimer;

  void _setupEmbeddedCall() {
    final String callRoomId = "game_call_${widget.roomId}";

    // Always create a fresh SignalingService instance for the game board
    // to ensure a clean state and reliable WebRTC handshake.
    _signalingService = SignalingService();

    // Listen for incoming calls (Invitee side)
    _incomingCallSub = _signalingService!.onIncomingCallStream.listen((_) {
      if (!mounted) return;
      _handleIncomingCall();
    });

    // Listen for remote mute state changes
    _customMessageSub = _signalingService!.onCustomMessageStream.listen((data) {
      if (data['action'] == 'toggle_mute') {
        ref.read(chessProvider.notifier).setRemoteAudioMuted(data['isMuted']);
      } else if (data['action'] == 'toggle_video') {
        ref.read(chessProvider.notifier).setRemoteVideoEnabled(data['isVideoEnabled']);
      } else if (data['action'] == 'local_silence_toggle') {
        ref.read(chessProvider.notifier).setAmISilencedByOpponent(data['isSilenced']);
      } else if (data['action'] == 'room_ready') {
        print("[GAME CALL] 🏢 Peer signaled room_ready! (Status: ${ref.read(chessProvider).callStatus})");
        if (widget.amIWhite && !ref.read(chessProvider).isCallStarted) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !ref.read(chessProvider).isCallStarted) {
              _startCallConnection();
            }
          });
        }
      }
    });

    // Listen for peer join notifications (to start call as inviter)
    _peerJoinedSub = _signalingService!.onPeerJoinedStream.listen((_) {
      print(
        "[GAME CALL] 👥 Peer joined! isWhite: ${widget.amIWhite}",
      );
      if (widget.amIWhite && !ref.read(chessProvider).isCallStarted) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !ref.read(chessProvider).isCallStarted) {
            _startCallConnection();
          }
        });
      }
    });

    // Listen for hangups (to clean up UI when call ends)
    _onHangupSub = _signalingService!.onHangupStream.listen((_) {
      print("[GAME CALL] 🛑 Peer hung up. Cleaning up...");
      ref.read(chessProvider.notifier).setCallStarted(false);
      ref.read(chessProvider.notifier).setCallStatus("Disconnected");
      ref.read(chessProvider.notifier).setRemoteVideoEnabled(false);
      _stopCallTimers();
      _signalingService!.endCall(sendSignal: false);
    });

    _signalingService!.localStreamNotifier.addListener(_onLocalStreamChanged);
    _signalingService!.remoteStreamNotifier.addListener(_onRemoteStreamChanged);
    _signalingService!.remoteMediaTypeNotifier.addListener(
      _onRemoteMediaTypeChanged,
    );

    _signalingService!.onConnectionStateChange = (state) {
      print("[GAME CALL] 🧊 PeerConnection State: ${state.name}");
      if (mounted) {
        if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
          ref.read(chessProvider.notifier).setCallStatus("Connecting media...");
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          ref.read(chessProvider.notifier).setCallStatus("Connected");
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          ref.read(chessProvider.notifier).setCallStatus("Media Failed");
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          ref.read(chessProvider.notifier).setCallStatus("Media Dropped");
        }
      }
    };

    _signalingService!.onIceConnectionStateChange = (state) {
      if (!mounted) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        print("[GAME CALL] 🧊 ICE connected (${state.name})...");
        ref.read(chessProvider.notifier).setCallStatus("Connected");
        _startCallRecording();
      }
    };

    _signalingService!.onLog = (msg) {
      if (mounted) {
        print("[GAME CALL_LOG] $msg");
        if (msg.contains("ICE Connection State: failed") ||
            msg.contains("ICE Connection State: disconnected")) {
          ref.read(chessProvider.notifier).setCallStatus("ICE Connection Issue");
        }
      }
    };
    _onRemoteStreamChanged();
    _onLocalStreamChanged();
    _onRemoteMediaTypeChanged();
    _connectToSignaling(callRoomId);
  }

  void _startCallConnection() {
    print("[GAME CALL] 🚀 Triggering call start...");
    ref.read(chessProvider.notifier).setCallStarted(true);
    _signalingService!.startCall(isVideo: ref.read(chessProvider).isLocalVideoEnabled);
    ref.read(chessProvider.notifier).setCallStatus("Starting call...");

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && ref.read(chessProvider).callStatus == "Starting call...") {
        print("[GAME CALL] ⚠️ Call connection timeout. Resetting...");
        ref.read(chessProvider.notifier).setCallStarted(false);
        ref.read(chessProvider.notifier).setCallStatus("Waiting for peer...");
        _signalingService!.endCall(sendSignal: false);
      }
    });
    // Listen for call acceptance (inviter side)
    _onCallAcceptedSub = _signalingService!.onCallAcceptedStream.listen((_) {
      print("[GAME CALL] ✅ Call accepted by peer! Establishing media...");
      ref.read(chessProvider.notifier).setCallStatus("Handshaking...");
      // Monitor if we get stuck in Handshaking
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && ref.read(chessProvider).callStatus == "Handshaking...") {
          ref.read(chessProvider.notifier).setCallStatus("Slow connection. Retrying...");
        }
      });
    });
  }

  void _onRemoteMediaTypeChanged() {
    final mediaType = _signalingService!.remoteMediaTypeNotifier.value;
    if (mounted && mediaType != null) {
      print("[GAME CALL] 🏢 Remote media type detected: $mediaType");
      ref.read(chessProvider.notifier).setRemoteVideoEnabled(mediaType == 'video');
    }
  }

  void _onLocalStreamChanged() {
    if (!_isRendererReady) return;
    final localStream = _signalingService!.localStreamNotifier.value;
    if (mounted) {
      // Always re-assign to ensure renderer picks up changes (e.g. tracks added)
      setState(() {
        _localRenderer.srcObject = localStream;
      });
    }
  }

  void _onRemoteStreamChanged() {
    if (!_isRendererReady) return;
    final remoteStream = _signalingService!.remoteStreamNotifier.value;
    if (mounted && remoteStream != null) {
      print(
        "[GAME CALL] 🚞 Remote stream detected (${remoteStream.id}). Attaching to renderer...",
      );

      _remoteRenderer.srcObject = remoteStream;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _remoteRenderer.srcObject != remoteStream) {
          print("[GAME CALL] 🚞 Redundant remote stream assignment.");
          setState(() {
            _remoteRenderer.srcObject = remoteStream;
          });
        }
      });

      ref.read(chessProvider.notifier).setCallStatus("Connected");
      // Check if there are active video tracks
      final videoTracks = remoteStream.getVideoTracks();
      final bool videoEnabled = videoTracks.isNotEmpty && videoTracks.any((t) => t.enabled);
      ref.read(chessProvider.notifier).setRemoteVideoEnabled(videoEnabled);
      print(
        "[GAME CALL] 🏢 Remote video enabled: $videoEnabled (${videoTracks.length} tracks)",
      );
    }
  }

  bool _recordingDialogShown = false;

  void _startCallRecording() async {
    if (_recordingDialogShown) return;
    _recordingDialogShown = true;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.black87,
          title: const Row(
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.red),
              SizedBox(width: 10),
              Text("Recording Started", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            "Your voice and video is being recorded for security and quality purposes.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final size = MediaQuery.of(context).size;
                final roomId = "game_${widget.roomId}";

                Navigator.pop(dialogContext);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Preparing recording... (Please grant microphone & screen casting permission if asked)",
                      ),
                      backgroundColor: Colors.blueAccent,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }

                Future.delayed(const Duration(milliseconds: 3000), () async {
                  await _recordingService.startRecording(
                    roomId,
                    width: size.width.toInt(),
                    height: size.height.toInt(),
                  );
                });
              },
              child: const Text(
                "OK",
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _connectToSignaling(String callRoomId) {
    // If already connected/in call (external case), just trigger handshake
    if (widget.signalingService != null && _signalingService!.isConnected) {
      print("[GAME CALL] Signaling already connected. Starting handshake...");
      _startHandshakeSequence();
      return;
    }

    _signalingService!.connect(Constants.wsBaseUrl, callRoomId).then((_) {
      if (!mounted) return;
      _startHandshakeSequence();
    }).catchError((e) {
      if (mounted) {
        print("[GAME CALL] ❌ Signaling connection error: $e");
        ref.read(chessProvider.notifier).setCallStatus("Connection Error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Call connection error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  void _retryCall() {
    print("[GAME CALL] 🔄 Manually retrying call connection...");
    ref.read(chessProvider.notifier).setCallStatus("Retrying...");
    _startCallConnection();
  }

  void _manualSyncBoard() {
    print("[GAME BOARD] 🔄 Manually resyncing board...");
    ref.read(chessProvider.notifier).resyncHistory(widget.roomId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Resyncing board state...", style: TextStyle(color: Colors.white)), backgroundColor: Colors.orange),
    );
  }

  void _startHandshakeSequence() {
    if (!mounted) return;

    // Pulse room_ready every 2s until Connected
    _handshakePulseTimer?.cancel();
    _handshakePulseTimer = Timer.periodic(const Duration(milliseconds: 2000), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final state = ref.read(chessProvider);
      if (state.callStatus != "Connected") {
        if (_signalingService!.isConnected) {
          debugPrint("[GAME CALL] 💓 Sending periodic room_ready pulse (Status: ${state.callStatus})...");
          _signalingService!.sendCustomMessage({'action': 'room_ready'});
        } else {
          debugPrint("[GAME CALL] ⚠️ Pulse skipped: Signaling not connected.");
        }
      } else {
        debugPrint("[GAME CALL] 🛑 Pulse stopped: Call is Connected.");
        timer.cancel();
      }
    });

    // Initial immediate signal
    print("[GAME CALL] 🚀 Sending initial room_ready signal...");
    _signalingService!.sendCustomMessage({'action': 'room_ready'});

    // Update initial status
    ref.read(chessProvider.notifier).setCallStatus(widget.amIWhite
        ? "Handshake started..."
        : "Waiting for offer...");

    // If an offer is already pending (race condition), accept it immediately
    if (!widget.amIWhite && _signalingService!.pendingMediaType != null) {
      print("[GAME CALL] Pending offer found. Accepting immediately.");
      ref.read(chessProvider.notifier).setCallStarted(true);
      _signalingService!.acceptCall(isVideo: ref.read(chessProvider).isLocalVideoEnabled);
      ref.read(chessProvider.notifier).setCallStatus("Call Connected");
    }
  }

  void _toggleLocalAudio() {
    ref.read(chessProvider.notifier).toggleLocalAudio(!ref.read(chessProvider).isLocalAudioMuted);
  }

  void _toggleLocalVideo() {
    ref.read(chessProvider.notifier).toggleLocalVideo(!ref.read(chessProvider).isLocalVideoEnabled);
    _onLocalStreamChanged(); // Force the renderer to pick up the enabled/disabled stream state
  }

  void _toggleRemoteAudioLocalOverride() {
    final bool currentSilenced = ref.read(chessProvider).isOpponentLocallySilenced;
    ref.read(chessProvider.notifier).setOpponentLocallySilenced(!currentSilenced);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !currentSilenced
              ? "Opponent silenced locally"
              : "Opponent unsilenced locally",
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showLeaveDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Resign Game?",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Are you sure you want to leave? If you leave now, your opponent will win the game.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Keep Playing"),
          ),
          ElevatedButton(
            onPressed: () {
              _recordingService.stopRecording();
              _signalingService?.endCall();
              RouteGenerator.navigateToPageWithoutStack(
                context,
                Routes.bottomNavBarRoute,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Leave (Resign)",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    try {
      print("GameBoard: initState starting for room ${widget.roomId}");


      // 2. Initialize renderers (async, but we don't await here to not block initState)
      _initRenderers().catchError((e) {
        print("GameBoard: Error initializing renderers: $e");
      });

      if (widget.isMultiplayer) {
        _setupEmbeddedCall(); // Initialize the embedded call first

        // SYNC: Populate callProvider with game context for the overlay
        ref.read(callProvider.notifier).setChessContext(
          roomId: widget.roomId,
          currentUserId: widget.currentUserId,
          opponentId: widget.opponentId,
          amIWhite: widget.amIWhite,
        );
        ref.read(callProvider.notifier).userSignalingService = _signalingService;

        // Reactive listener for Game Over
        ref.listenManual(chessProvider, (previous, next) {
          if (next.isGameOver && !(previous?.isGameOver ?? false)) {
            _showGameOverDialog(next.winnerMessage ?? "Game Over", isVictory: next.winnerMessage?.contains("Win") ?? false);
          }
        });

        print(
          "[GAME] Init Room: ${widget.roomId}, Me: ${widget.currentUserId}, Opponent: ${widget.opponentId}, amIWhite: ${widget.amIWhite}",
        );

        _gameConnSub = _gameService.connectionStream.listen((connected) {
          if (!mounted) return;
          _showTransientSnackBar(
            connected ? "Game Server Connected" : "Game Server Disconnected",
            color: connected ? Colors.green : Colors.red,
          );
          if (connected) {
            _gameService.sendJoin(widget.roomId, widget.currentUserId);
          }
        });

        _signalingConnSub = _signalingService!.connectionStream.listen((
          connected,
        ) {
          if (!mounted) return;
          _showTransientSnackBar(
            connected
                ? "Signaling Service Connected"
                : "Signaling Service Offline",
            color: connected ? Colors.blue : Colors.orange,
          );
        });

        // Use Notifier to manage game logic and WebSocket stream
        ref.read(chessProvider.notifier).initGame(
          widget.roomId,
          widget.currentUserId,
          signalingService: _signalingService,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(chatProvider.notifier).init(
            widget.roomId,
            widget.currentUserId,
            setAsActive: true,
          );
        });

      }
    } catch (e, st) {
      print("GameBoard FATAL ERROR in initState: $e\n$st");
    }
  }

  void _showTransientSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    // Delay to ensure ScaffoldMessenger is accessible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (mounted) {
        setState(() {
          _isRendererReady = true;
        });
        // Now that renderers are ready, sync the streams
        _onLocalStreamChanged();
        _onRemoteStreamChanged();
      }
    } catch (e) {
      print("GameBoard: Error during renderer init: $e");
    }
  }

  void _stopCallTimers() {
    _handshakePulseTimer?.cancel();
    _callTimeoutTimer?.cancel();
    _handshakePulseTimer = null;
    _callTimeoutTimer = null;
  }

  void _handleIncomingCall() {
    print("[GAME CALL] Incoming call received. Auto-accepting...");
    _signalingService!.acceptCall(isVideo: ref.read(chessProvider).isLocalVideoEnabled);
    ref.read(chessProvider.notifier).setCallStarted(true);
    ref.read(chessProvider.notifier).setCallStatus("Call Connected");
  }

  @override
  void dispose() {
    _recordingService.stopRecording();
    if (_signalingService != null) {
      _signalingService!.remoteStreamNotifier.removeListener(
        _onRemoteStreamChanged,
      );
    }
    _gameConnSub?.cancel();
    _signalingConnSub?.cancel();
    _incomingCallSub?.cancel();
    _customMessageSub?.cancel();
    _peerJoinedSub?.cancel();
    _onHangupSub?.cancel();
    _onCallAcceptedSub?.cancel();
    if (_signalingService != null) {
      _signalingService!.onLog = null;
    }
    _stopCallTimers();
    if (_signalingService != null) {
      _signalingService!.localStreamNotifier.removeListener(
        _onLocalStreamChanged,
      );
      _signalingService!.remoteStreamNotifier.removeListener(
        _onRemoteStreamChanged,
      );
      _signalingService!.remoteMediaTypeNotifier.removeListener(
        _onRemoteMediaTypeChanged,
      );
    }

    if (widget.signalingService == null) {
      _signalingService?.endCall(); // Only end if we own the service
      _signalingService?.disconnect();
    } else {
      // Even if we don't own it, if we're in a call session, we should end it when leaving the board
      if (_signalingService?.inCallSession ?? false) {
        _signalingService?.endCall(sendSignal: true);
      }
    }

    _localRenderer.dispose();
    _remoteRenderer.dispose();
    // SEND LEAVE SIGNAL
    if (widget.isMultiplayer) {
      _gameService.sendLeave(widget.roomId, widget.currentUserId);
    }
    // Clear game context from callProvider
    if (ref.read(callProvider).activeChessRoomId == widget.roomId) {
      ref.read(callProvider.notifier).clearChessContext();
    }
    super.dispose();
  }

  bool isWhiteSquare(int index) {
    int r = index ~/ 8;
    int c = index % 8;
    return (r + c) % 2 == 0;
  }

  bool isInBoard(int row, int col) => row >= 0 && row < 8 && col >= 0 && col < 8;



  void _showGameOverDialog(String message, {bool isVictory = false}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          isVictory ? "CONGRATULATIONS!" : "Game Over",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isVictory ? Colors.yellowAccent : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isVictory)
              const Icon(Icons.emoji_events, color: Colors.yellow, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _recordingService.stopRecording();
              _signalingService?.endCall();
              RouteGenerator.navigateToPageWithoutStack(
                context,
                Routes.bottomNavBarRoute,
              );
            },
            child: const Text("Home", style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Listen for game over or opponent departure to show celebration dialog
    ref.listen(chessProvider, (previous, next) {
      if (!mounted) return;
      if (next.isGameOver && !(previous?.isGameOver ?? false)) {
        debugPrint("[GAME] 🏁 Game Over detected: ${next.winnerMessage}");
        _showGameOverDialog(
          next.winnerMessage ?? "Game Over",
          isVictory: next.winnerMessage?.toLowerCase().contains("win") ?? false,
        );
      }
    });

    try {
      final bool isPractice = !widget.isMultiplayer;

      return PopScope(
        canPop: isPractice,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (!isPractice) {
            _showLeaveDialog();
          }
        },
        child: Scaffold(
          backgroundColor: widget.isMultiplayer
              ? const Color(0xFF212121)
              : whiteColor,
          appBar: widget.isMultiplayer
              ? null
              : AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: whiteColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text("Game Board"),
                  centerTitle: true,
                  backgroundColor: backgroundColor,
                  foregroundColor: whiteColor,
                ),
          body: SafeArea(
            child: Container(
              decoration: widget.isMultiplayer
                  ? const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF303030), Color(0xFF121212)],
                      ),
                    )
                  : const BoxDecoration(color: whiteColor),
              child: Column(
                children: [
                  if (widget.isMultiplayer) _buildSafeHeader(),

                  // Call Frame
                  if (widget.isMultiplayer &&
                      ref.watch(chessProvider).isCallStarted &&
                      _signalingService != null)
                    Expanded(flex: 3, child: _buildCallFrame()),

                  // Chess Board
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: _buildChessBoard(),
                        ),
                      ),
                    ),
                  ),

                  // Bottom spacing for non-call multiplayer
                  if (widget.isMultiplayer && !ref.watch(chessProvider).isCallStarted)
                    const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      // Handle any top-level build errors
      return Scaffold(body: Center(child: Text("An error occurred: $e")));
    }
  }

  // Helper widget to build the embedded call frame
  Widget _buildCallFrame() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: _buildVideoContainer(
                notifier: _signalingService!.localStreamNotifier,
                renderer: _localRenderer,
                isEnabled: ref.watch(chessProvider).isLocalVideoEnabled,
                label: "You",
                isLocal: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildVideoContainer(
                notifier: _signalingService!.remoteStreamNotifier,
                renderer: _remoteRenderer,
                isEnabled: ref.watch(chessProvider).isRemoteVideoEnabled,
                label: widget.opponentId?.toString() ?? "Opponent",
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeHeader() {
    try {
      return _buildControlHeader();
    } catch (e) {
      return Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            "UI Error: $e",
            style: const TextStyle(color: Colors.redAccent, fontSize: 10),
          ),
        ),
      );
    }
  }

  Widget _buildControlHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back Button
          GestureDetector(
            onTap: _showLeaveDialog,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          // Turn Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: ref.watch(chessProvider).whiteTurn ? Colors.white : Colors.blueGrey,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (ref.watch(chessProvider).whiteTurn)
                        const BoxShadow(
                          color: Colors.white54,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  ref.watch(chessProvider).whiteTurn ? "WHITE'S TURN" : "BLACK'S TURN",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                if (ref.watch(chessProvider).checkStatus) ...[
                  const SizedBox(width: 10),
                  const Text(
                    "CHECK!",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
              ],
            ),
          ),

          // Message Button
          Consumer(
            builder: (context, ref, _) {
              final provider = ref.watch(chatProvider);
              final int unreadCount = provider.getUnreadCount(widget.roomId);
              return GestureDetector(
                onTap: () {
                  ref.read(chatProvider.notifier).resetUnreadCount(widget.roomId);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        roomId: widget.roomId,
                        currentUserId: widget.currentUserId,
                      ),
                    ),
                  );
                },

                child: badges.Badge(
                  badgeContent: Text(
                    unreadCount.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  showBadge: unreadCount > 0,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSmallAction({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _buildVideoContainer({
    required ValueListenable<MediaStream?> notifier,
    required RTCVideoRenderer renderer,
    required bool isEnabled,
    required String label,
    bool isLocal = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ValueListenableBuilder<MediaStream?>(
            valueListenable: notifier,
            builder: (context, stream, _) {
              if (stream != null &&
                  stream.getVideoTracks().isNotEmpty &&
                  isEnabled) {
                return RTCVideoView(
                  renderer,
                  mirror: isLocal,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                );
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white10,
                      child: Icon(
                        Icons.person,
                        color: Colors.white24,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label + (ref.watch(chessProvider).isLocalVideoEnabled ? "" : " (Camera Off)"),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                    if (!isLocal && stream == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          ref.watch(chessProvider).callStatus,
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // Bottom Controls and Indicators
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Call Status Icons (Mic/Video)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLocal)
                      _buildOverlayIconButton(
                        icon: ref.watch(chessProvider).isLocalAudioMuted ? Icons.mic_off : Icons.mic,
                        color: ref.watch(chessProvider).isLocalAudioMuted
                            ? Colors.redAccent
                            : Colors.white,
                        onPressed: _toggleLocalAudio,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: ref.watch(chessProvider).isRemoteAudioMuted ? Icons.mic_off : Icons.mic,
                        color: ref.watch(chessProvider).isRemoteAudioMuted
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    const SizedBox(width: 4),
                    if (isLocal)
                      _buildOverlayIconButton(
                        icon: ref.watch(chessProvider).isLocalVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: ref.watch(chessProvider).isLocalVideoEnabled
                            ? Colors.blue
                            : Colors.white70,
                        onPressed: _toggleLocalVideo,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: ref.watch(chessProvider).isRemoteVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: ref.watch(chessProvider).isRemoteVideoEnabled
                            ? Colors.blue
                            : Colors.white24,
                      ),
                  ],
                ),

                // Audio Output / Silence Indicator
                if (isLocal)
                  (ref.watch(chessProvider).amISilencedByOpponent
                      ? _buildOverlayIndicator(
                          icon: Icons.volume_off,
                          color: Colors.redAccent,
                          label: "Silenced",
                        )
                      : const SizedBox.shrink())
                else
                  _buildOverlayIconButton(
                    icon: ref.watch(chessProvider).isOpponentLocallySilenced
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: ref.watch(chessProvider).isOpponentLocallySilenced
                        ? Colors.redAccent
                        : Colors.white,
                    onPressed: _toggleRemoteAudioLocalOverride,
                    label: ref.watch(chessProvider).isOpponentLocallySilenced ? "Silenced" : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? label,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayIndicator({
    required IconData icon,
    required Color color,
    String? label,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChessBoard() {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 64,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemBuilder: (context, index) {
        int r = index ~/ 8, c = index % 8;

        // Perspective Flip for Black player
        final int row = (widget.isMultiplayer && !widget.amIWhite)
            ? (7 - r)
            : r;
        final int col = (widget.isMultiplayer && !widget.amIWhite)
            ? (7 - c)
            : c;

        final gameState = ref.watch(chessProvider);
        return Square(
          isWhiteSquare: isWhiteSquare(index),
          piece: gameState.board[row][col],
          isSelected: row == gameState.selectedRow && col == gameState.selectedCol,
          isValidMove: gameState.validMoves.any((m) => m[0] == row && m[1] == col),
          isCheck: gameState.whiteTurn
              ? (gameState.checkStatus && gameState.whiteKingPosition[0] == row && gameState.whiteKingPosition[1] == col)
              : (gameState.checkStatus && gameState.blackKingPosition[0] == row && gameState.blackKingPosition[1] == col),
          onTap: () {
            ref.read(chessProvider.notifier).onSquareTap(
              row, col,
              isMultiplayer: widget.isMultiplayer,
              amIWhite: widget.amIWhite,
              roomId: widget.roomId,
              currentUserId: widget.currentUserId,
            );
          },
        );
      },
    );
  }
}
