import 'dart:async';
import 'package:badges/badges.dart' as badges;
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/core/utils/global_callhandler.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/features/call/services/recording_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/chat_page.dart';
import 'package:chess_game_manika/features/game/presentation/widgets/square_widget.dart';
import 'package:chess_game_manika/core/providers/global_providers.dart';
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

  late List<List<ChessPiece?>> board;
  ChessPiece? selectedPiece;
  int selectedRow = -1;
  int selectedCol = -1;
  List<List<int>> validMoves = [];
  bool whiteTurn = true;

  // Add position of kings to track them easily
  List<int> whiteKingPosition = [7, 4];
  List<int> blackKingPosition = [0, 4];
  bool checkStatus = false;
  bool _isSyncing = false; // Track if we are replaying history

  final GameWebsocketService _gameService = GameWebsocketService();
  StreamSubscription? _gameSubscription;
  StreamSubscription? _gameConnSub;
  StreamSubscription? _signalingConnSub;

  // Embedded Call Variables
  SignalingService? _signalingService;
  StreamSubscription? _incomingCallSub;
  StreamSubscription? _customMessageSub;
  StreamSubscription? _peerJoinedSub;
  StreamSubscription? _onHangupSub;
  StreamSubscription? _onCallAcceptedSub;
  bool _isCallStarted = false;
  Timer? _handshakePulseTimer;
  Timer? _callTimeoutTimer;
  String _callStatus = "Initializing...";

  // Call Controls State
  bool _isLocalAudioMuted = false; // Microphone ON by default
  bool _isLocalVideoEnabled = false; // Camera OFF by default
  bool _isRemoteAudioMuted = false;
  bool _isRemoteVideoEnabled = false;
  bool _isOpponentLocallySilenced = false;
  bool _amISilencedByOpponent = false; // New: signaled by peer
  bool _isRendererReady =
      false; // NEW: Guard for RTCVideoRenderer srcObject assignments

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RecordingService _recordingService = RecordingService();

  void _setupEmbeddedCall() {
    final String callRoomId = "game_call_${widget.roomId}";

    // Reuse external service if provided, otherwise create new one
    if (widget.signalingService != null) {
      print("[GAME CALL] Using externally provided SignalingService.");
      _signalingService = widget.signalingService!;
      // Sync initial state from the service's notifiers
      _isRemoteAudioMuted = _signalingService!.isRemoteMuted.value;
      _isRemoteVideoEnabled = _signalingService!.isRemoteVideoEnabled.value;
    } else {
      _signalingService = SignalingService();
    }

    // Listen for incoming calls (Invitee side)
    _incomingCallSub = _signalingService!.onIncomingCallStream.listen((_) {
      if (!mounted) return;
      _showIncomingCallDialog();
    });

    // Listen for remote mute state changes
    _customMessageSub = _signalingService!.onCustomMessageStream.listen((data) {
      if (data['action'] == 'toggle_mute') {
        setState(() {
          _isRemoteAudioMuted = data['isMuted'];
        });
      } else if (data['action'] == 'toggle_video') {
        setState(() {
          _isRemoteVideoEnabled = data['isVideoEnabled'];
        });
      } else if (data['action'] == 'local_silence_toggle') {
        setState(() {
          _amISilencedByOpponent = data['isSilenced'];
        });
      } else if (data['action'] == 'room_ready') {
        print("[GAME CALL] 🏢 Peer signaled room_ready!");
        if (widget.amIWhite && !_isCallStarted) {
          _startCallConnection();
        }
      }
    });

    // Listen for peer join notifications (to start call as inviter)
    _peerJoinedSub = _signalingService!.onPeerJoinedStream.listen((_) {
      print(
        "[GAME CALL] 👥 Peer joined! isWhite: ${widget.amIWhite}, _isCallStarted: $_isCallStarted",
      );
      if (widget.amIWhite && !_isCallStarted) {
        _startCallConnection();
      }
    });

    // Listen for hangups (to clean up UI when call ends)
    _onHangupSub = _signalingService!.onHangupStream.listen((_) {
      print("[GAME CALL] 🛑 Peer hung up. Cleaning up...");
      setState(() {
        _isCallStarted = false;
        _callStatus = "Disconnected";
        _isRemoteVideoEnabled = false;
      });
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
        setState(() {
          if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
            _callStatus = "Connecting media...";
          } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            _callStatus = "Connected";
          } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _callStatus = "Media Failed";
          } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
            _callStatus = "Media Dropped";
          }
        });
      }
    };

    _signalingService!.onLog = (msg) {
      if (mounted) {
        print("[GAME CALL_LOG] $msg");
        if (msg.contains("ICE Connection State: failed") ||
            msg.contains("ICE Connection State: disconnected")) {
          setState(() {
            _callStatus = "ICE Connection Issue";
          });
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
    _isCallStarted = true;
    _signalingService!.startCall(isVideo: _isLocalVideoEnabled);
    setState(() {
      _callStatus = "Starting call...";
    });

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _callStatus == "Starting call...") {
        print("[GAME CALL] ⚠️ Call connection timeout. Resetting...");
        setState(() {
          _isCallStarted = false;
          _callStatus = "Waiting for peer...";
        });
        _signalingService!.endCall(sendSignal: false);
      }
    });
    // Listen for call acceptance (inviter side)
    _onCallAcceptedSub = _signalingService!.onCallAcceptedStream.listen((_) {
      print("[GAME CALL] ✅ Call accepted by peer! Establishing media...");
      setState(() {
        _callStatus = "Handshaking...";
      });
      // Monitor if we get stuck in Handshaking
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _callStatus == "Handshaking...") {
          setState(() {
            _callStatus = "Slow connection. Retrying...";
          });
        }
      });
    });
  }

  void _onRemoteMediaTypeChanged() {
    final mediaType = _signalingService!.remoteMediaTypeNotifier.value;
    if (mounted && mediaType != null) {
      print("[GAME CALL] 🏢 Remote media type detected: $mediaType");
      setState(() {
        _isRemoteVideoEnabled = (mediaType == 'video');
      });
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

      // Use a redundant assignment with a small delay to ensure the renderer picks up the stream
      _remoteRenderer.srcObject = remoteStream;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _remoteRenderer.srcObject != remoteStream) {
          print("[GAME CALL] 🚞 Redundant remote stream assignment.");
          setState(() {
            _remoteRenderer.srcObject = remoteStream;
          });
        }
      });

      setState(() {
        _callStatus = "Connected";
        // Check if there are active video tracks
        final videoTracks = remoteStream.getVideoTracks();
        _isRemoteVideoEnabled =
            videoTracks.isNotEmpty && videoTracks.any((t) => t.enabled);
        print(
          "[GAME CALL] 🏢 Remote video enabled: $_isRemoteVideoEnabled (${videoTracks.length} tracks)",
        );
      });
      _startCallRecording();
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

    // Connect to signaling - this now waits for the websocket to actually be ready
    _signalingService!
        .connect(Constants.wsBaseUrl, callRoomId)
        .then((_) async {
          if (!mounted) return;
          _startHandshakeSequence();
        })
        .catchError((e) {
          print("[GAME CALL] ❌ Connection failed: $e");
          if (mounted) {
            setState(() {
              _callStatus = "Connection Error";
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Call connection error: $e"),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
  }

  void _startHandshakeSequence() {
    if (!mounted) return;

    // NEW: Ensure Pulse timer starts even if already initialized (for reconnects/edge cases)
    _handshakePulseTimer?.cancel();
    _handshakePulseTimer = Timer.periodic(const Duration(milliseconds: 2000), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Continue pulsing until the call is actually CONNECTED
      // This ensures that if signaling drops and comes back, the handshake is resumed
      if (_callStatus != "Connected") {
        if (_signalingService!.isConnected) {
          print(
            "[GAME CALL] 💓 Sending periodic room_ready pulse (Status: $_callStatus)...",
          );
          _signalingService!.sendCustomMessage({'action': 'room_ready'});

          if (!_isCallStarted && _callStatus == "Handshake started...") {
            setState(() {
              _callStatus = "Waiting for peer...";
            });
          }
        } else {
          // If not connected to WS yet, show different status
          if (_callStatus != "Connecting to signaling...") {
            setState(() {
              _callStatus = "Connecting to signaling...";
            });
          }
        }
      } else {
        print("[GAME CALL] ✅ Call connected, stopping room_ready pulse.");
        timer.cancel();
      }
    });

    // Initial immediate signal
    print("[GAME CALL] 🚀 Sending initial room_ready signal...");
    _signalingService!.sendCustomMessage({'action': 'room_ready'});

    // Update initial status
    setState(() {
      _callStatus = widget.amIWhite
          ? "Handshake started..."
          : "Waiting for offer...";
    });

    // If an offer is already pending (race condition), accept it immediately
    if (!widget.amIWhite && _signalingService!.pendingMediaType != null) {
      print("[GAME CALL] Pending offer found. Accepting immediately.");
      _isCallStarted = true;
      _signalingService!.acceptCall(isVideo: _isLocalVideoEnabled);
      setState(() {
        _callStatus = "Call Connected";
      });
    }
  }

  void _toggleLocalAudio() {
    setState(() {
      _isLocalAudioMuted = !_isLocalAudioMuted;
    });
    _signalingService!.toggleMute(_isLocalAudioMuted);
    _signalingService!.sendCustomMessage({
      'action': 'toggle_mute',
      'isMuted': _isLocalAudioMuted,
    });
  }

  void _toggleLocalVideo() {
    setState(() {
      _isLocalVideoEnabled = !_isLocalVideoEnabled;
    });
    _signalingService!.toggleVideo(_isLocalVideoEnabled);
    _onLocalStreamChanged(); // Force the renderer to pick up the enabled/disabled stream state
    _signalingService!.sendCustomMessage({
      'action': 'toggle_video',
      'isVideoEnabled': _isLocalVideoEnabled,
    });
  }

  void _toggleRemoteAudioLocalOverride() {
    setState(() {
      _isOpponentLocallySilenced = !_isOpponentLocallySilenced;
    });

    // Mute/Unmute the remote audio tracks locally so the opponent cannot be heard.
    final remoteStream = _signalingService!.remoteStreamNotifier.value;
    if (remoteStream != null) {
      for (var track in remoteStream.getAudioTracks()) {
        track.enabled = !_isOpponentLocallySilenced;
      }
    }

    // Notify peer so they see the "Silenced" indicator
    _signalingService!.sendCustomMessage({
      'action': 'local_silence_toggle',
      'isSilenced': _isOpponentLocallySilenced,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isOpponentLocallySilenced
              ? "Opponent silenced locally"
              : "Opponent unsilenced locally",
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showLeaveDialog() {
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

      // 1. CRITICAL: Initialize board FIRST to avoid LateInitializationError in build()
      _initializeBoard();

      // 2. Initialize renderers (async, but we don't await here to not block initState)
      _initRenderers().catchError((e) {
        print("GameBoard: Error initializing renderers: $e");
      });

      if (widget.isMultiplayer) {
        _setupEmbeddedCall(); // Initialize the embedded call first

        // SYNC: Populate GlobalCallHandler with game context for the overlay
        GlobalCallHandler().activeChessRoomId.value = widget.roomId;
        GlobalCallHandler().currentUserId.value = widget.currentUserId;
        GlobalCallHandler().opponentId.value = widget.opponentId;
        GlobalCallHandler().amIWhite.value = widget.amIWhite;
        GlobalCallHandler().userSignalingService = _signalingService;

        print(
          "[GAME] Init Room: ${widget.roomId}, Me: ${widget.currentUserId}, Opponent: ${widget.opponentId}, amIWhite: ${widget.amIWhite}",
        );

        _gameConnSub = _gameService.connectionStream.listen((connected) {
          if (!mounted) return;
          _showTransientSnackBar(
            connected ? "Game Server Connected" : "Game Server Disconnected",
            color: connected ? Colors.green : Colors.red,
          );
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

        _onHangupSub = _signalingService!.onHangupStream.listen((_) {
          if (!mounted) return;
          _showGameOverDialog(
            "Congratulations! Your opponent has resigned. You win!",
            isVictory: true,
          );
        });

        _gameService.connect(widget.roomId);
        _gameSubscription = _gameService.stream.listen((data) {
          final dynamic rawRoomId = data['room_id'];
          final int? moveRoomId = rawRoomId is int
              ? rawRoomId
              : int.tryParse(rawRoomId?.toString() ?? "");

          if (moveRoomId != null && moveRoomId != widget.roomId) return;

          if (data['type'] == 'move') {
            final bool isMyMove =
                data['sender_id']?.toString() ==
                widget.currentUserId.toString();
            if (isMyMove && !_isSyncing) return;
            _handleRemoteMove(data);
          } else if (data['type'] == 'history') {
            setState(() {
              _isSyncing = true;
              _initializeBoard();
              final List history = data['history'];
              for (var move in history) {
                _handleRemoteMove(Map<String, dynamic>.from(move));
              }
              _isSyncing = false;
            });
          } else if (data['type'] == 'user_left') {
            if (data['user_id']?.toString() !=
                widget.currentUserId.toString()) {
              _showGameOverDialog(
                "Congratulations! Your opponent has left the game. You win!",
                isVictory: true,
              );
              _signalingService?.endCall(sendSignal: false);
            }
          } else if (data['type'] == 'reset') {
            setState(() => _initializeBoard());
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(chatProvider).init(
            widget.roomId,
            widget.currentUserId,
            setAsActive: true,
          );
        });

      }
    } catch (e, st) {
      print("GameBoard FATAL ERROR in initState: $e\n$st");
      // If we failed early, ensure board is at least initialized to an empty state
      _initializeBoard();
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

  void _showIncomingCallDialog() {
    // This dialog is shown when an incoming call is received.
    // For game calls, we auto-accept, so this dialog is not strictly needed
    // unless we want to give the user an option to decline.
    // For now, we'll just auto-accept as per the original logic.
    print("[GAME CALL] Incoming call received. Auto-accepting...");
    _signalingService!.acceptCall(isVideo: _isLocalVideoEnabled);
    _isCallStarted = true;
    setState(() {
      _callStatus = "Call Connected";
    });
  }

  @override
  void dispose() {
    _recordingService.stopRecording();
    if (_signalingService != null) {
      _signalingService!.remoteStreamNotifier.removeListener(
        _onRemoteStreamChanged,
      );
    }
    _gameSubscription?.cancel();
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
    // Clear game context from GlobalCallHandler
    if (GlobalCallHandler().activeChessRoomId.value == widget.roomId) {
      GlobalCallHandler().activeChessRoomId.value = null;
    }
    super.dispose();
  }

  void _initializeBoard() {
    board = List.generate(8, (_) => List.generate(8, (_) => null));

    // Pawns
    for (int i = 0; i < 8; i++) {
      board[1][i] = ChessPiece(
        type: ChessPieceType.pawn,
        isWhite: false,
        imagePath: "assets/images/black/pawn.png",
      );
      board[6][i] = ChessPiece(
        type: ChessPieceType.pawn,
        isWhite: true,
        imagePath: "assets/images/white/pawn.png",
      );
    }

    // Back row
    void placeBackRow(int row, bool isWhite) {
      String base = isWhite ? "white" : "black";
      board[row][0] = ChessPiece(
        type: ChessPieceType.rook,
        isWhite: isWhite,
        imagePath: "assets/images/$base/rook.png",
      );
      board[row][1] = ChessPiece(
        type: ChessPieceType.knight,
        isWhite: isWhite,
        imagePath: "assets/images/$base/knight.png",
      );
      board[row][2] = ChessPiece(
        type: ChessPieceType.bishop,
        isWhite: isWhite,
        imagePath: "assets/images/$base/bishop.png",
      );
      board[row][3] = ChessPiece(
        type: ChessPieceType.queen,
        isWhite: isWhite,
        imagePath: "assets/images/$base/queen.png",
      );
      board[row][4] = ChessPiece(
        type: ChessPieceType.king,
        isWhite: isWhite,
        imagePath: "assets/images/$base/king.png",
      );
      board[row][5] = ChessPiece(
        type: ChessPieceType.bishop,
        isWhite: isWhite,
        imagePath: "assets/images/$base/bishop.png",
      );
      board[row][6] = ChessPiece(
        type: ChessPieceType.knight,
        isWhite: isWhite,
        imagePath: "assets/images/$base/knight.png",
      );
      board[row][7] = ChessPiece(
        type: ChessPieceType.rook,
        isWhite: isWhite,
        imagePath: "assets/images/$base/rook.png",
      );
    }

    placeBackRow(0, false);
    placeBackRow(7, true);

    // Reset king positions
    whiteKingPosition = [7, 4];
    blackKingPosition = [0, 4];
    whiteTurn = true;
    checkStatus = false;
  }

  void _handleRemoteMove(Map<String, dynamic> data) {
    int? fR = int.tryParse(data['from_row']?.toString() ?? "");
    int? fC = int.tryParse(data['from_col']?.toString() ?? "");
    int? tR = int.tryParse(data['to_row']?.toString() ?? "");
    int? tC = int.tryParse(data['to_col']?.toString() ?? "");

    if (fR == null || fC == null || tR == null || tC == null) {
      print("Error parsing remote move data: $data");
      return;
    }

    setState(() {
      ChessPiece? piece = board[fR][fC];
      if (piece != null) {
        // Apply move locally
        if (piece.type == ChessPieceType.king) {
          if (piece.isWhite)
            whiteKingPosition = [tR, tC];
          else
            blackKingPosition = [tR, tC];
        }
        board[tR][tC] = piece;
        board[fR][fC] = null;
        whiteTurn = !whiteTurn;
        checkStatus = isKingInCheck(whiteTurn);
        if (isCheckMate(whiteTurn)) {
          _showGameOverDialog(whiteTurn ? "Black Wins!" : "White Wins!");
        }
      }
    });
  }

  void onSquareTap(int row, int col) {
    setState(() {
      ChessPiece? piece = board[row][col];

      // Move selected piece
      if (selectedPiece != null &&
          validMoves.any((m) => m[0] == row && m[1] == col)) {
        // Multiplayer Turn Enforcement
        if (widget.isMultiplayer && whiteTurn != widget.amIWhite) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Wait for your turn!"),
              duration: Duration(seconds: 1),
            ),
          );
          return;
        }

        // SYNC: if we're in multiplayer mode then send the move **after**
        // applying it locally. doing the board mutation first means the UI
        // isn't waiting on the WebSocket send, and we can even queue the data
        // if we're temporarily offline.
        if (widget.isMultiplayer) {
          // apply local move immediately (will also flip turn below)
          // store last move data in case we need to resend later
        }

        // Update king position if king is moved
        if (selectedPiece!.type == ChessPieceType.king) {
          if (selectedPiece!.isWhite) {
            whiteKingPosition = [row, col];
          } else {
            blackKingPosition = [row, col];
          }
        }

        board[row][col] = selectedPiece;
        board[selectedRow][selectedCol] = null;

        // Pawn promotion
        if (selectedPiece!.type == ChessPieceType.pawn &&
            (row == 0 || row == 7)) {
          board[row][col] = ChessPiece(
            type: ChessPieceType.queen,
            isWhite: selectedPiece!.isWhite,
            imagePath:
                "assets/images/${selectedPiece!.isWhite ? "white" : "black"}/queen.png",
          );
        }

        selectedPiece = null;
        validMoves.clear();
        whiteTurn = !whiteTurn;

        // now that the board has been flipped, send the move if the socket is
        // healthy – if not we will reconnect and flush later.
        if (widget.isMultiplayer) {
          if (_gameService.isConnected) {
            print(
              "SEND MOVE [Room ${widget.roomId}]: (${selectedRow},${selectedCol}) -> ($row,$col)",
            );
            _gameService.sendMove(
              widget.roomId,
              widget.currentUserId,
              selectedRow,
              selectedCol,
              row,
              col,
            );
          } else {
            // start a reconnect attempt; move will be resent when the history
            // message arrives from the server (see _isSyncing flag handling).
            print("Socket offline, will resend move later");
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Connecting to game server... Please wait."),
              ),
            );
            _gameService.connect(widget.roomId);
          }
        }

        // Check if the other king is in check
        checkStatus = isKingInCheck(whiteTurn);

        // Check for checkmate
        if (isCheckMate(whiteTurn)) {
          _showGameOverDialog(whiteTurn ? "Black Wins!" : "White Wins!");
        }

        return;
      }

      // Select new piece
      if (piece != null &&
          piece.isWhite ==
              (widget.isMultiplayer ? widget.amIWhite : whiteTurn)) {
        selectedPiece = piece;
        selectedRow = row;
        selectedCol = col;
        validMoves = calculateRealValidMoves(row, col, piece, true);
      } else {
        selectedPiece = null;
        validMoves.clear();
      }
    });
  }

  List<List<int>> calculateRawValidMoves(int row, int col, ChessPiece piece) {
    switch (piece.type) {
      case ChessPieceType.pawn:
        return _pawnMoves(row, col, piece);
      case ChessPieceType.rook:
        return _rookMoves(row, col, piece);
      case ChessPieceType.knight:
        return _knightMoves(row, col, piece);
      case ChessPieceType.bishop:
        return _bishopMoves(row, col, piece);
      case ChessPieceType.queen:
        return [
          ..._rookMoves(row, col, piece),
          ..._bishopMoves(row, col, piece),
        ];
      case ChessPieceType.king:
        return _kingMoves(row, col, piece);
    }
  }

  // Filter moves that would put/keep the king in check
  List<List<int>> calculateRealValidMoves(
    int row,
    int col,
    ChessPiece piece,
    bool checkCheck,
  ) {
    List<List<int>> rawMoves = calculateRawValidMoves(row, col, piece);
    if (!checkCheck) return rawMoves;

    List<List<int>> realMoves = [];
    for (var move in rawMoves) {
      int endRow = move[0];
      int endCol = move[1];

      // Simulate the move
      ChessPiece? targetPiece = board[endRow][endCol];

      // If moving king, update simulated king position
      List<int> originalKingPos = piece.isWhite
          ? [...whiteKingPosition]
          : [...blackKingPosition];
      if (piece.type == ChessPieceType.king) {
        if (piece.isWhite)
          whiteKingPosition = [endRow, endCol];
        else
          blackKingPosition = [endRow, endCol];
      }

      board[endRow][endCol] = piece;
      board[row][col] = null;

      // Check if king is in check after move
      bool inCheck = isKingInCheck(piece.isWhite);

      // Undo the move
      board[row][col] = piece;
      board[endRow][endCol] = targetPiece;
      if (piece.type == ChessPieceType.king) {
        if (piece.isWhite)
          whiteKingPosition = originalKingPos;
        else
          blackKingPosition = originalKingPos;
      }

      if (!inCheck) {
        realMoves.add(move);
      }
    }
    return realMoves;
  }

  bool isKingInCheck(bool isWhite) {
    List<int> kingPos = isWhite ? whiteKingPosition : blackKingPosition;

    // Check all opponent pieces to see if any can hit the king
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        ChessPiece? p = board[r][c];
        if (p != null && p.isWhite != isWhite) {
          List<List<int>> pieceMoves = calculateRawValidMoves(r, c, p);
          if (pieceMoves.any((m) => m[0] == kingPos[0] && m[1] == kingPos[1])) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool isCheckMate(bool isWhite) {
    if (!isKingInCheck(isWhite)) return false;

    // If king is in check, see if any move can get him out of it
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        ChessPiece? p = board[r][c];
        if (p != null && p.isWhite == isWhite) {
          List<List<int>> moves = calculateRealValidMoves(r, c, p, true);
          if (moves.isNotEmpty) return false;
        }
      }
    }
    return true;
  }

  void _showGameOverDialog(String message, {bool isVictory = false}) {
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
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _initializeBoard();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isVictory ? Colors.green : Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Play Again",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<List<int>> _pawnMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    int dir = piece.isWhite ? -1 : 1;
    if (isInBoard(row + dir, col) && board[row + dir][col] == null)
      moves.add([row + dir, col]);

    if ((row == 6 && piece.isWhite) || (row == 1 && !piece.isWhite))
      if (isInBoard(row + dir, col) &&
          board[row + dir][col] == null &&
          isInBoard(row + 2 * dir, col) &&
          board[row + 2 * dir][col] == null)
        moves.add([row + 2 * dir, col]);

    for (int dc in [-1, 1])
      if (isInBoard(row + dir, col + dc) &&
          board[row + dir][col + dc] != null &&
          board[row + dir][col + dc]!.isWhite != piece.isWhite)
        moves.add([row + dir, col + dc]);
    return moves;
  }

  List<List<int>> _rookMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    for (var d in dirs) {
      int r = row, c = col;
      while (true) {
        r += d[0];
        c += d[1];
        if (!isInBoard(r, c)) break;
        if (board[r][c] == null)
          moves.add([r, c]);
        else {
          if (board[r][c]!.isWhite != piece.isWhite) moves.add([r, c]);
          break;
        }
      }
    }
    return moves;
  }

  List<List<int>> _bishopMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [
      [1, 1],
      [1, -1],
      [-1, 1],
      [-1, -1],
    ];
    for (var d in dirs) {
      int r = row, c = col;
      while (true) {
        r += d[0];
        c += d[1];
        if (!isInBoard(r, c)) break;
        if (board[r][c] == null)
          moves.add([r, c]);
        else {
          if (board[r][c]!.isWhite != piece.isWhite) moves.add([r, c]);
          break;
        }
      }
    }
    return moves;
  }

  List<List<int>> _knightMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    List<List<int>> jumps = [
      [2, 1],
      [2, -1],
      [-2, 1],
      [-2, -1],
      [1, 2],
      [1, -2],
      [-1, 2],
      [-1, -2],
    ];
    for (var j in jumps) {
      int r = row + j[0], c = col + j[1];
      if (isInBoard(r, c) &&
          (board[r][c] == null || board[r][c]!.isWhite != piece.isWhite))
        moves.add([r, c]);
    }
    return moves;
  }

  List<List<int>> _kingMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [
      [1, 0],
      [1, 1],
      [0, 1],
      [-1, 1],
      [-1, 0],
      [-1, -1],
      [0, -1],
      [1, -1],
    ];
    for (var d in dirs) {
      int r = row + d[0], c = col + d[1];
      if (isInBoard(r, c) &&
          (board[r][c] == null || board[r][c]!.isWhite != piece.isWhite))
        moves.add([r, c]);
    }
    return moves;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
                      _isCallStarted &&
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
                  if (widget.isMultiplayer && !_isCallStarted)
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
                isEnabled: _isLocalVideoEnabled,
                label: "You",
                isLocal: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildVideoContainer(
                notifier: _signalingService!.remoteStreamNotifier,
                renderer: _remoteRenderer,
                isEnabled: _isRemoteVideoEnabled,
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
                    color: whiteTurn ? Colors.white : Colors.blueGrey,
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (whiteTurn)
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
                  whiteTurn ? "WHITE'S TURN" : "BLACK'S TURN",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                if (checkStatus) ...[
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
                  provider.resetUnreadCount(widget.roomId);
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
                      label + (isEnabled ? "" : " (Camera Off)"),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 10,
                      ),
                    ),
                    if (!isLocal && stream == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _callStatus,
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
                        icon: _isLocalAudioMuted ? Icons.mic_off : Icons.mic,
                        color: _isLocalAudioMuted
                            ? Colors.redAccent
                            : Colors.white,
                        onPressed: _toggleLocalAudio,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: _isRemoteAudioMuted ? Icons.mic_off : Icons.mic,
                        color: _isRemoteAudioMuted
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    const SizedBox(width: 4),
                    if (isLocal)
                      _buildOverlayIconButton(
                        icon: _isLocalVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: _isLocalVideoEnabled
                            ? Colors.blue
                            : Colors.white70,
                        onPressed: _toggleLocalVideo,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: _isRemoteVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: _isRemoteVideoEnabled
                            ? Colors.blue
                            : Colors.white24,
                      ),
                  ],
                ),

                // Audio Output / Silence Indicator
                if (isLocal)
                  (_amISilencedByOpponent
                      ? _buildOverlayIndicator(
                          icon: Icons.volume_off,
                          color: Colors.redAccent,
                          label: "Silenced",
                        )
                      : const SizedBox.shrink())
                else
                  _buildOverlayIconButton(
                    icon: _isOpponentLocallySilenced
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: _isOpponentLocallySilenced
                        ? Colors.redAccent
                        : Colors.white,
                    onPressed: _toggleRemoteAudioLocalOverride,
                    label: _isOpponentLocallySilenced ? "Silenced" : null,
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

        return Square(
          isWhiteSquare: isWhiteSquare(index),
          piece: board[row][col],
          isSelected: row == selectedRow && col == selectedCol,
          isValidMove: validMoves.any((m) => m[0] == row && m[1] == col),
          onTap: () => onSquareTap(row, col),
        );
      },
    );
  }
}
