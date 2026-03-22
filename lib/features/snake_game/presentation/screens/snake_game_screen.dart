import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:chess_game_manika/features/call/services/recording_service.dart';
import 'package:chess_game_manika/features/call/presentation/providers/call_provider.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:flutter/foundation.dart';

import 'package:chess_game_manika/features/snake_game/models/snake_board.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/snake_game/presentation/providers/snake_game_provider.dart';

class SnakeGameScreen extends ConsumerStatefulWidget {
  final SnakeBoard board;
  final int? roomId;
  final bool isMultiplayer;
  final bool startsMyTurn;

  const SnakeGameScreen({
    super.key,
    required this.board,
    this.roomId,
    this.isMultiplayer = false,
    this.startsMyTurn = true,
  });

  @override
  ConsumerState<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends ConsumerState<SnakeGameScreen>
    with TickerProviderStateMixin {
  final RecordingService _recordingService = RecordingService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  SignalingService? _signalingService;
  bool _isRendererReady = false;

  // Cleanup subscriptions
  StreamSubscription? _signalingConnSub;
  StreamSubscription? _incomingCallSub;
  StreamSubscription? _customMessageSub;
  StreamSubscription? _peerJoinedSub;
  StreamSubscription? _onHangupSub;
  StreamSubscription? _onCallAcceptedSub;
  Timer? _handshakePulseTimer;
  Timer? _callTimeoutTimer;
  // Game constants
  static const int gridSize = 10;
  static const int totalSquares = gridSize * gridSize;

  @override
  void initState() {
    super.initState();
    // Initialize provider with board data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider).value;
      final currentUserId = authState?.userId ?? 1;

      Future.microtask(() {
        final notifier = ref.read(snakeGameProvider.notifier);
        notifier.initBoard(
          widget.board.snakes,
          widget.board.ladders,
          roomId: widget.roomId,
          isMultiplayer: widget.isMultiplayer,
          myUserId: currentUserId,
          startsMyTurn: widget.startsMyTurn,
          signalingService: _signalingService,
        );
      });

      if (widget.isMultiplayer && widget.roomId != null) {
        _setupEmbeddedCall(); // Initialize SignalingService first
        
        _initRenderers().catchError((e) {
          debugPrint("SnakeGame: Error initializing renderers: $e");
        });

        // Sync context to callProvider
        ref.read(callProvider.notifier).setSnakeContext(
          roomId: widget.roomId,
          currentUserId: currentUserId,
          opponentId: null, // We'll update this if we know it
        );

        // Reset the recording flag for every fresh game instance
        _recordingService.hasShownRecordingPopup = false;
      }
    });
  }

  @override
  void dispose() {
    _signalingConnSub?.cancel();
    _incomingCallSub?.cancel();
    _customMessageSub?.cancel();
    _peerJoinedSub?.cancel();
    _onHangupSub?.cancel();
    _onCallAcceptedSub?.cancel();
    _handshakePulseTimer?.cancel();
    _callTimeoutTimer?.cancel();

    _signalingService?.localStreamNotifier.removeListener(_onLocalStreamChanged);
    _signalingService?.remoteStreamNotifier.removeListener(_onRemoteStreamChanged);
    _signalingService?.remoteMediaTypeNotifier.removeListener(_onRemoteMediaTypeChanged);

    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) {
      setState(() {
        _isRendererReady = true;
      });
      _onLocalStreamChanged();
      _onRemoteStreamChanged();
    }
  }

  void _setupEmbeddedCall() {
    final String callRoomId = "snake_call_${widget.roomId}";
    _signalingService = SignalingService();

    _incomingCallSub = _signalingService!.onIncomingCallStream.listen((_) {
      if (!mounted) return;
      _showIncomingCallDialog();
    });

    _customMessageSub = _signalingService!.onCustomMessageStream.listen((data) {
      final notifier = ref.read(snakeGameProvider.notifier);
      if (data['action'] == 'toggle_mute') {
        notifier.setRemoteAudioMuted(data['isMuted']);
      } else if (data['action'] == 'toggle_video') {
        notifier.setRemoteVideoEnabled(data['isVideoEnabled']);
      } else if (data['action'] == 'local_silence_toggle') {
        notifier.setAmISilencedByOpponent(data['isSilenced']);
      } else if (data['action'] == 'room_ready') {
        if (widget.startsMyTurn && !ref.read(snakeGameProvider).isCallStarted) {
          _startCallConnection();
        }
      }
    });

    _signalingService!.onPeerJoinedStream.listen((_) {
      if (widget.startsMyTurn && !ref.read(snakeGameProvider).isCallStarted) {
        _startCallConnection();
      }
    });

    _onHangupSub = _signalingService!.onHangupStream.listen((_) {
      final notifier = ref.read(snakeGameProvider.notifier);
      notifier.setCallStarted(false);
      notifier.setCallStatus("Disconnected");
      notifier.setRemoteVideoEnabled(false);
      _callTimeoutTimer?.cancel();
      _signalingService!.endCall(sendSignal: false);
    });

    _signalingService!.localStreamNotifier.addListener(_onLocalStreamChanged);
    _signalingService!.remoteStreamNotifier.addListener(_onRemoteStreamChanged);
    _signalingService!.remoteMediaTypeNotifier.addListener(_onRemoteMediaTypeChanged);

    _signalingService!.onIceConnectionStateChange = (state) {
      if (!mounted) return;
      final notifier = ref.read(snakeGameProvider.notifier);
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        debugPrint("[SNAKE CALL] 🧊 ICE connected (${state.name})...");
        notifier.setCallStatus("Connected");
        _startCallRecording();
      }
    };

    _connectToSignaling(callRoomId);
  }

  void _connectToSignaling(String callRoomId) {
    _signalingService!.connect(Constants.wsBaseUrl, callRoomId).then((_) {
      if (!mounted) return;
      _startHandshakeSequence();
    }).catchError((e) {
      if (mounted) {
        debugPrint("[SNAKE CALL] ❌ Signaling connection error: $e");
        ref.read(snakeGameProvider.notifier).setCallStatus("Connection Error: $e");
      }
    });
  }

  void _startHandshakeSequence() {
    _handshakePulseTimer?.cancel();
    _handshakePulseTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || ref.read(snakeGameProvider).callStatus == "Connected") {
        timer.cancel();
        return;
      }
      _signalingService!.sendCustomMessage({'action': 'room_ready'});
    });
    _signalingService!.sendCustomMessage({'action': 'room_ready'});
    ref.read(snakeGameProvider.notifier).setCallStatus(
      widget.startsMyTurn ? "Handshaking..." : "Waiting for offer..."
    );
  }

  void _startCallConnection() {
    ref.read(snakeGameProvider.notifier).setCallStarted(true);
    _signalingService!.startCall(isVideo: ref.read(snakeGameProvider).isLocalVideoEnabled);
    ref.read(snakeGameProvider.notifier).setCallStatus("Starting call...");

    _onCallAcceptedSub = _signalingService!.onCallAcceptedStream.listen((_) {
      ref.read(snakeGameProvider.notifier).setCallStatus("Handshaking...");
    });
  }

  void _showIncomingCallDialog() {
    _signalingService!.acceptCall(isVideo: ref.read(snakeGameProvider).isLocalVideoEnabled);
    ref.read(snakeGameProvider.notifier).setCallStarted(true);
    ref.read(snakeGameProvider.notifier).setCallStatus("Connected");
  }

  void _onLocalStreamChanged() {
    if (!_isRendererReady) return;
    setState(() {
      _localRenderer.srcObject = _signalingService?.localStreamNotifier.value;
    });
  }

  void _onRemoteStreamChanged() {
    if (!_isRendererReady) return;
    final remoteStream = _signalingService?.remoteStreamNotifier.value;
    if (mounted && remoteStream != null) {
      setState(() {
        _remoteRenderer.srcObject = remoteStream;
      });
      ref.read(snakeGameProvider.notifier).setCallStatus("Connected");
      final videoTracks = remoteStream.getVideoTracks();
      ref.read(snakeGameProvider.notifier).setRemoteVideoEnabled(
        videoTracks.isNotEmpty && videoTracks.any((t) => t.enabled)
      );
    }
  }

  bool _recordingDialogShown = false;

  void _startCallRecording() async {
    final status = ref.read(snakeGameProvider).callStatus;
    if (status != "Connected") {
       print("[SNAKE RECORD] ⏳ Waiting for full connection before recording...");
       _recordingDialogShown = false; 
       return;
    }
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
              Text("Recording Started", style: TextStyle(color: Colors.white, fontSize: 16)),
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
                final roomId = "snake_${widget.roomId}";

                Navigator.pop(dialogContext);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Preparing recording...",
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

  void _onRemoteMediaTypeChanged() {
    final mediaType = _signalingService?.remoteMediaTypeNotifier.value;
    if (mounted && mediaType != null) {
      ref.read(snakeGameProvider.notifier).setRemoteVideoEnabled(mediaType == 'video');
    }
  }

  void _toggleLocalAudio() {
    final notifier = ref.read(snakeGameProvider.notifier);
    final isMuted = !ref.read(snakeGameProvider).isLocalAudioMuted;
    notifier.setLocalAudioMuted(isMuted);
    _signalingService?.toggleMute(isMuted);
  }

  void _toggleLocalVideo() {
    final notifier = ref.read(snakeGameProvider.notifier);
    final isVideo = !ref.read(snakeGameProvider).isLocalVideoEnabled;
    notifier.setLocalVideoEnabled(isVideo);
    _signalingService?.toggleVideo(isVideo);
    _onLocalStreamChanged();
  }

  // Color Palette - Exact Reference Sequence
  final List<Color> cellColors = [
    const Color(0xFFFFEB3B), // Yellow (1)
    Colors.white, // White (2)
    const Color(0xFFF44336), // Red (3)
    const Color(0xFF2196F3), // Blue (4)
    const Color(0xFF4CAF50), // Green (5)
  ];

  Color _getCellColor(int n) {
    if (n == 0) return Colors.white;
    return cellColors[(n - 1) % cellColors.length];
  }

  Color _getTextColor(int n) {
    Color bg = _getCellColor(n);
    if (bg == const Color(0xFFF44336) ||
        bg == const Color(0xFF2196F3) ||
        bg == const Color(0xFF4CAF50)) {
      return Colors.white;
    }
    return Colors.black87;
  }

  void _startCallStatusRecording() async {
    // This is a placeholder if we want to add the recording dialog later
  }

  void _showResetConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Restart Game?",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Your current progress will be lost.",
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(snakeGameProvider.notifier).resetGame();
            },
            child: const Text(
              "RESTART",
              style: TextStyle(color: Colors.deepOrange),
            ),
          ),
        ],
      ),
    );
  }

  void _showWinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Center(
          child: Text(
            "YOU DID IT!",
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
        ),
        content: const Text(
          "The board has been conquered.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(snakeGameProvider.notifier).resetGame();
              },
              child: const Text(
                "NEW ADVENTURE",
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset getCoord(int index) {
    if (index <= 0) return const Offset(0, 9);
    int sq = index - 1;
    int row = sq ~/ gridSize;
    int col = sq % gridSize;
    if (row % 2 == 1) col = (gridSize - 1) - col;
    row = (gridSize - 1) - row;
    return Offset(col.toDouble(), row.toDouble());
  }


  @override
  Widget build(BuildContext context) {
    ref.listen(snakeGameProvider, (previous, next) {
      if (next.playerPosition == totalSquares &&
          (previous?.playerPosition ?? 0) != totalSquares) {
        _showWinDialog();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.board.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 4,
        actions: [
          if (widget.isMultiplayer && !ref.watch(snakeGameProvider).isCallStarted)
            IconButton(
              onPressed: _startCallConnection,
              icon: const Icon(Icons.videocam, color: Colors.greenAccent),
              tooltip: "Start Video Call",
            ),
          IconButton(
            onPressed: _showResetConfirmation,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.isMultiplayer &&
              ref.watch(snakeGameProvider).isCallStarted &&
              _signalingService != null)
            Expanded(flex: 3, child: _buildCallFrame()),
          
          if (!ref.watch(snakeGameProvider).isCallStarted)
            const Spacer(flex: 1),
          // Board Area - Maximum Width
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black, // Background of the grid lines
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2), // Board frame thickness
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double cellSize = constraints.maxWidth / gridSize;
                    return Stack(
                      children: [
                        // 0. Background Image (if board config has one)
                        if (widget.board.imagePath != null)
                          Positioned.fill(
                            child: Image.asset(
                              widget.board.imagePath!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        // 1. Colorful Cells Grid (Hide colors if image is present)
                        Positioned.fill(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: totalSquares,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridSize,
                                ),
                            itemBuilder: (context, index) {
                              int cellRow = index ~/ gridSize;
                              int cellCol = index % gridSize;
                              int dRow = 9 - cellRow;
                              int dCol = (dRow % 2 == 1)
                                  ? (9 - cellCol)
                                  : cellCol;
                              int num = dRow * 10 + dCol + 1;
                              return Container(
                                decoration: BoxDecoration(
                                  color: widget.board.imagePath != null
                                      ? Colors.transparent
                                      : (num == 100
                                            ? const Color(0xFFF44336)
                                            : _getCellColor(num)),
                                  border: Border.all(
                                    color: widget.board.imagePath != null
                                        ? Colors.transparent
                                        : Colors.black,
                                    width: 0.8,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    if (num == 100)
                                      const Center(
                                        child: Icon(
                                          Icons.star,
                                          color: Color(0xFFFFEB3B),
                                          size: 30,
                                        ),
                                      ),
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Text(
                                          '$num',
                                          style: TextStyle(
                                            color:
                                                widget.board.imagePath != null
                                                ? _getTextColor(
                                                    num,
                                                  ).withOpacity(0.0)
                                                : _getTextColor(num),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // 2. Connections Painter
                        Positioned.fill(
                          child: CustomPaint(
                            painter: RetroBoardLinesPainter(
                              snakes: widget.board.imagePath != null
                                  ? {}
                                  : widget.board.snakes,
                              ladders: widget.board.imagePath != null
                                  ? {}
                                  : widget.board.ladders,
                              gridSize: gridSize,
                            ),
                          ),
                        ),
                        // 3. Player Token
                        Builder(
                          builder: (context) {
                            final gameState = ref.watch(snakeGameProvider);
                            Offset p = getCoord(gameState.playerPosition);
                            Offset op = getCoord(gameState.opponentPosition);

                            return Stack(
                              children: [
                                // Opponent Token
                                if (gameState.isMultiplayer)
                                  AnimatedPositioned(
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeInOut,
                                    left: op.dx * cellSize,
                                    top: op.dy * cellSize,
                                    child: SizedBox(
                                      width: cellSize,
                                      height: cellSize,
                                      child: Center(
                                        child: Opacity(
                                          opacity: gameState.opponentPosition == 0 ? 0.3 : 1.0,
                                          child: Container(
                                            width: cellSize * 0.6,
                                            height: cellSize * 0.6,
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                const BoxShadow(
                                                  color: Colors.black45,
                                                  blurRadius: 5,
                                                ),
                                              ],
                                              border: Border.all(
                                                color: Colors.black,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                Icons.person,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // My Token
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeInOut,
                                  left: p.dx * cellSize,
                                  top: p.dy * cellSize,
                                  child: SizedBox(
                                    width: cellSize,
                                    height: cellSize,
                                    child: Center(
                                      child: Opacity(
                                        opacity: gameState.playerPosition == 0 ? 0.3 : 1.0,
                                        child: Container(
                                          width: cellSize * 0.7,
                                          height: cellSize * 0.7,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              const BoxShadow(
                                                color: Colors.black45,
                                                blurRadius: 5,
                                              ),
                                            ],
                                            border: Border.all(
                                              color: Colors.black,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.stars,
                                              size: 20,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const Spacer(flex: 1),
          // Controls Area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ref.watch(snakeGameProvider).gameStatus.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.black, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: ref.watch(snakeGameProvider).isRolling
                            ? const CircularProgressIndicator(
                                color: Colors.black87,
                              )
                            : CustomPaint(
                                size: const Size(40, 40),
                                painter: DiceDotsPainter(value: ref.watch(snakeGameProvider).diceValue),
                              ),
                      ),
                    ),
                    const SizedBox(width: 30),
                    GestureDetector(
                      onTap: () {
                         final state = ref.read(snakeGameProvider);
                         if (state.isRolling || state.isMoving) return;
                         ref.read(snakeGameProvider.notifier).rollDice();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: (ref.watch(snakeGameProvider).isRolling || ref.watch(snakeGameProvider).isMoving)
                              ? Colors.grey
                              : Colors.black87,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          "ROLL",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // const SizedBox(height: 20),
                // GestureDetector(
                //   onTap: () {
                //     AdService().showRewardedAd(
                //       onUserEarnedReward: (reward) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //           SnackBar(content: Text('Reward Earned: ${reward.amount} ${reward.type}')),
                //         );
                //       },
                //     );
                //   },
                //   child: Container(
                //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                //     decoration: BoxDecoration(
                //       color: Colors.orange,
                //       borderRadius: BorderRadius.circular(10),
                //     ),
                //     child: const Row(
                //       mainAxisSize: MainAxisSize.min,
                //       children: [
                //         Icon(Icons.play_circle_fill, color: Colors.white),
                //         SizedBox(width: 8),
                //         Text(
                //           "WATCH AD FOR REWARD",
                //           style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget to build the embedded call frame
  Widget _buildCallFrame() {
    final gameState = ref.watch(snakeGameProvider);
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
                isEnabled: gameState.isLocalVideoEnabled,
                label: "You",
                isLocal: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildVideoContainer(
                notifier: _signalingService!.remoteStreamNotifier,
                renderer: _remoteRenderer,
                isEnabled: gameState.isRemoteVideoEnabled,
                label: "Opponent",
              ),
            ),
          ],
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
    final gameState = ref.watch(snakeGameProvider);
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
                        isLocal ? Icons.person : Icons.person_outline,
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
                          gameState.callStatus,
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
                        icon: gameState.isLocalAudioMuted ? Icons.mic_off : Icons.mic,
                        color: gameState.isLocalAudioMuted
                            ? Colors.redAccent
                            : Colors.white,
                        onPressed: _toggleLocalAudio,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: gameState.isRemoteAudioMuted ? Icons.mic_off : Icons.mic,
                        color: gameState.isRemoteAudioMuted
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    const SizedBox(width: 4),
                    if (isLocal)
                      _buildOverlayIconButton(
                        icon: gameState.isLocalVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: gameState.isLocalVideoEnabled
                            ? Colors.blue
                            : Colors.white70,
                        onPressed: _toggleLocalVideo,
                      )
                    else
                      _buildOverlayIndicator(
                        icon: gameState.isRemoteVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        color: gameState.isRemoteVideoEnabled
                            ? Colors.blue
                            : Colors.white24,
                      ),
                  ],
                ),

                // Audio Output / Silence Indicator
                if (!isLocal)
                  _buildOverlayIconButton(
                    icon: gameState.isOpponentLocallySilenced
                        ? Icons.volume_off
                        : Icons.volume_up,
                    color: gameState.isOpponentLocallySilenced
                        ? Colors.redAccent
                        : Colors.white,
                    onPressed: () {
                      ref.read(snakeGameProvider.notifier).setOpponentLocallySilenced(!gameState.isOpponentLocallySilenced);
                    },
                    label: gameState.isOpponentLocallySilenced ? "Silenced" : null,
                  )
                else if (gameState.amISilencedByOpponent)
                  _buildOverlayIndicator(
                    icon: Icons.volume_off,
                    color: Colors.redAccent,
                    label: "Silenced",
                  ),
              ],
            ),
          ),
          
          if (isLocal)
            Positioned(
              top: 6,
              right: 6,
              child: _buildOverlayIconButton(
                icon: Icons.call_end,
                color: Colors.red,
                onPressed: () {
                   _signalingService?.endCall();
                },
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
}

class RetroBoardLinesPainter extends CustomPainter {
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final int gridSize;

  RetroBoardLinesPainter({
    required this.snakes,
    required this.ladders,
    required this.gridSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    double cell = size.width / gridSize;

    // Center helper
    Offset getC(int n) {
      int sq = n - 1;
      int row = sq ~/ gridSize;
      int col = sq % gridSize;
      if (row % 2 == 1) col = (gridSize - 1) - col;
      row = (gridSize - 1) - row;
      return Offset(col * cell + cell / 2, row * cell + cell / 2);
    }

    // Spacious 2-Rail Ladders
    final railPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final stepPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.5;

    ladders.forEach((s, e) {
      Offset p1 = getC(s);
      Offset p2 = getC(e);
      double dx = p2.dx - p1.dx, dy = p2.dy - p1.dy;
      double len = math.sqrt(dx * dx + dy * dy);
      Offset perp = Offset(-dy / len, dx / len) * (cell * 0.2);

      canvas.drawLine(p1 - perp, p2 - perp, railPaint);
      canvas.drawLine(p1 + perp, p2 + perp, railPaint);

      int steps = (len / 15).floor().clamp(3, 12);
      for (int i = 0; i <= steps; i++) {
        Offset p = Offset.lerp(p1, p2, i / steps)!;
        canvas.drawLine(p - perp, p + perp, stepPaint);
      }
    });

    // Realistic Snakes with Unique Colors from Reference
    final Map<int, Color> snakeColors = {
      17: Colors.purple,
      54: Colors.orange,
      62: Colors.green,
      64: Colors.brown,
      87: Colors.deepOrange,
      93: Colors.purpleAccent,
      95: Colors.orangeAccent,
      98: Colors.greenAccent,
    };

    for (var entry in snakes.entries) {
      _drawRealisticSnake(
        canvas,
        getC(entry.key),
        getC(entry.value),
        cell,
        baseColor: snakeColors[entry.key] ?? Colors.green,
      );
    }
  }

  void _drawRealisticSnake(
    Canvas canvas,
    Offset head,
    Offset tail,
    double cellSize, {
    required Color baseColor,
  }) {
    final Path path = Path()..moveTo(head.dx, head.dy);

    // Create multi-segment organic slithering path (S-curves)
    double dist = (tail - head).distance;
    Offset dir = (tail - head) / dist;
    Offset perp = Offset(-dir.dy, dir.dx);

    // Control points for S-curve
    double curveStrength = cellSize * 2.2;
    Offset mid = Offset.lerp(head, tail, 0.5)!;
    Offset cp1 = Offset.lerp(head, mid, 0.5)! + perp * curveStrength;
    Offset cp2 = Offset.lerp(mid, tail, 0.5)! - perp * curveStrength;

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, tail.dx, tail.dy);

    final ui.PathMetrics pathMetrics = path.computeMetrics();
    final ui.PathMetric pathMetric = pathMetrics.first;

    // 2. Multi-Layer Skin Rendering
    int segments = 40; // Higher fidelity for S-curves
    for (int i = 0; i < segments; i++) {
      double startPercent = i / segments;
      double endPercent = (i + 1) / segments;
      double progress = i / segments;

      // Taper from width 12 to 2 (slender for spacious feel)
      double strokeWidth = 12 * (1.0 - progress * 0.9);

      // A. Layer: Main Body
      canvas.drawPath(
        pathMetric.extractPath(
          pathMetric.length * startPercent,
          pathMetric.length * endPercent,
        ),
        Paint()
          ..color = Color.lerp(baseColor.withOpacity(0.9), baseColor, progress)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      // B. Layer: Belly Stripe (Simulating depth)
      if (strokeWidth > 4) {
        canvas.drawPath(
          pathMetric.extractPath(
            pathMetric.length * startPercent,
            pathMetric.length * endPercent,
          ),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.35
            ..strokeCap = StrokeCap.round,
        );
      }

      // C. Layer: Spine Pattern (Zig-zag/Dots)
      if (i % 2 == 0) {
        canvas.drawPath(
          pathMetric.extractPath(
            pathMetric.length * startPercent,
            pathMetric.length * endPercent,
          ),
          Paint()
            ..color = Colors.black.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.2,
        );
      }
    }

    // 3. Realistic Illustrator Head
    ui.Tangent? tangent = pathMetric.getTangentForOffset(0);
    if (tangent != null) {
      double angle = math.atan2(tangent.vector.dy, tangent.vector.dx) + math.pi;
      double headScale = (cellSize / 38).clamp(0.5, 0.85); // More slender head

      canvas.save();
      canvas.translate(head.dx, head.dy);
      canvas.rotate(angle);
      canvas.scale(headScale);

      // Wider Jaw & Pointed Snout
      Path headPath = Path();
      headPath.moveTo(0, 0);
      headPath.quadraticBezierTo(2, -14, 12, -10); // Wide jaw base
      headPath.quadraticBezierTo(26, -6, 30, 0); // Fine snout
      headPath.quadraticBezierTo(26, 6, 12, 10); // Jaw symmetry
      headPath.quadraticBezierTo(2, 14, 0, 0);

      canvas.drawPath(headPath, Paint()..color = baseColor);
      canvas.drawPath(
        headPath,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );

      // Refined Eyes (Side-facing predatory placement)
      canvas.drawCircle(
        const Offset(14, -6),
        3.0,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        const Offset(15.5, -7.5),
        0.8,
        Paint()..color = Colors.white,
      ); // Glint
      canvas.drawCircle(
        const Offset(14, 6),
        3.0,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        const Offset(15.5, 7.5),
        0.8,
        Paint()..color = Colors.white,
      ); // Glint

      // Long Forked Tongue
      final tonguePaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Path tongue = Path();
      tongue.moveTo(30, 0);
      tongue.lineTo(48, 0);
      tongue.moveTo(48, 0);
      tongue.lineTo(55, -7);
      tongue.moveTo(48, 0);
      tongue.lineTo(55, 7);
      canvas.drawPath(tongue, tonguePaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

class DiceDotsPainter extends CustomPainter {
  final int value;
  DiceDotsPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black;
    final r = size.width * 0.12;
    void dot(double x, double y) =>
        canvas.drawCircle(Offset(size.width * x, size.height * y), r, p);
    if (value % 2 == 1) dot(0.5, 0.5);
    if (value > 1) {
      dot(0.22, 0.22);
      dot(0.78, 0.78);
    }
    if (value > 3) {
      dot(0.78, 0.22);
      dot(0.22, 0.78);
    }
    if (value == 6) {
      dot(0.22, 0.5);
      dot(0.78, 0.5);
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}
