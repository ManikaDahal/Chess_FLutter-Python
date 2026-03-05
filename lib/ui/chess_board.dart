import 'dart:async';
import 'package:badges/badges.dart' as badges;
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chess_piece.dart';
import '../ui/square_widget.dart';
import '../helper/helper.dart';
import '../core/utils/global_callhandler.dart';
import '../services/game_websocket_service.dart';
import '../services/signaling_service.dart';
import '../core/utils/const.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import '../services/recording_service.dart';

class GameBoard extends StatefulWidget {
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
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard>
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

  // Embedded Call Variables
  late SignalingService _signalingService;
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
  bool _isLocalAudioMuted = false;
  bool _isLocalVideoEnabled =
      true; // CHANGED: Enable video by default for better UX
  bool _isRemoteAudioMuted = false;
  bool _isRemoteVideoEnabled = false;
  bool _isOpponentLocallySilenced = false;

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
      _isRemoteAudioMuted = _signalingService.isRemoteMuted.value;
      _isRemoteVideoEnabled = _signalingService.isRemoteVideoEnabled.value;
    } else {
      _signalingService = SignalingService();
    }

    // Listen for incoming calls (Invitee side)
    _incomingCallSub = _signalingService.onIncomingCallStream.listen((_) {
      if (!_isCallStarted) {
        print("[GAME CALL] Incoming call received. Auto-accepting...");
        _signalingService.acceptCall(isVideo: _isLocalVideoEnabled);
        _isCallStarted = true;
        setState(() {
          _callStatus = "Call Connected";
        });
      }
    });

    // Listen for remote mute state changes
    _customMessageSub = _signalingService.onCustomMessageStream.listen((data) {
      if (data['action'] == 'toggle_mute') {
        setState(() {
          _isRemoteAudioMuted = data['isMuted'];
        });
      } else if (data['action'] == 'toggle_video') {
        setState(() {
          _isRemoteVideoEnabled = data['isVideoEnabled'];
        });
      } else if (data['action'] == 'room_ready') {
        print("[GAME CALL] 🏢 Peer signaled room_ready!");
        if (widget.amIWhite && !_isCallStarted) {
          _startCallConnection();
        }
      }
    });

    // Listen for peer join notifications (to start call as inviter)
    _peerJoinedSub = _signalingService.onPeerJoinedStream.listen((_) {
      print(
        "[GAME CALL] 👥 Peer joined! isWhite: ${widget.amIWhite}, _isCallStarted: $_isCallStarted",
      );
      if (widget.amIWhite && !_isCallStarted) {
        _startCallConnection();
      }
    });

    // Listen for hangups (to clean up UI when call ends)
    _onHangupSub = _signalingService.onHangupStream.listen((_) {
      print("[GAME CALL] 🛑 Peer hung up. Cleaning up...");
      setState(() {
        _isCallStarted = false;
        _callStatus = "Disconnected";
        _isRemoteVideoEnabled = false;
      });
      _stopCallTimers();
      _signalingService.endCall(sendSignal: false);
    });

    _signalingService.localStreamNotifier.addListener(_onLocalStreamChanged);
    _signalingService.remoteStreamNotifier.addListener(_onRemoteStreamChanged);
    _signalingService.remoteMediaTypeNotifier.addListener(
      _onRemoteMediaTypeChanged,
    );

    _signalingService.onLog = (msg) => print("[SIGNALING] $msg");

    _onRemoteStreamChanged();
    _onLocalStreamChanged();
    _onRemoteMediaTypeChanged();
    _connectToSignaling(callRoomId);
  }

  void _startCallConnection() {
    print("[GAME CALL] 🚀 Triggering call start...");
    _isCallStarted = true;
    _signalingService.startCall(isVideo: _isLocalVideoEnabled);
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
        _signalingService.endCall(sendSignal: false);
      }
    });
    // Listen for call acceptance (inviter side)
    _onCallAcceptedSub = _signalingService.onCallAcceptedStream.listen((_) {
      print("[GAME CALL] ✅ Call accepted by peer! Establishing media...");
      setState(() {
        _callStatus = "Establishing media...";
      });
    });
  }

  void _onRemoteMediaTypeChanged() {
    final mediaType = _signalingService.remoteMediaTypeNotifier.value;
    if (mounted && mediaType != null) {
      print("[GAME CALL] 🏢 Remote media type detected: $mediaType");
      setState(() {
        _isRemoteVideoEnabled = (mediaType == 'video');
      });
    }
  }

  void _onLocalStreamChanged() {
    final localStream = _signalingService.localStreamNotifier.value;
    if (mounted) {
      if (_localRenderer.srcObject?.id != localStream?.id) {
        setState(() {
          _localRenderer.srcObject = localStream;
        });
      }
    }
  }

  void _onRemoteStreamChanged() {
    final remoteStream = _signalingService.remoteStreamNotifier.value;
    if (mounted && remoteStream != null) {
      if (_remoteRenderer.srcObject?.id != remoteStream.id) {
        _remoteRenderer.srcObject = remoteStream;
      }
      setState(() {
        _callStatus = "Connected";
        // If the stream HAS video tracks, assume it should be visible initially
        if (remoteStream.getVideoTracks().isNotEmpty) {
          _isRemoteVideoEnabled = true;
        }
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
    if (widget.signalingService != null && _signalingService.isConnected) {
      print("[GAME CALL] Signaling already connected. Starting handshake...");
      _startHandshakeSequence();
      return;
    }

    // Connect to signaling - this now waits for the websocket to actually be ready
    _signalingService
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
    _handshakePulseTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (!_isCallStarted) {
        if (_signalingService.isConnected) {
          print("[GAME CALL] 💓 Sending periodic room_ready pulse...");
          _signalingService.sendCustomMessage({'action': 'room_ready'});
          if (_callStatus != "Waiting for peer...") {
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
        timer.cancel();
      }
    });

    // Initial immediate signal
    print("[GAME CALL] 🚀 Sending initial room_ready signal...");
    _signalingService.sendCustomMessage({'action': 'room_ready'});

    // Update initial status
    setState(() {
      _callStatus = widget.amIWhite
          ? "Handshake started..."
          : "Waiting for offer...";
    });

    // If an offer is already pending (race condition), accept it immediately
    if (!widget.amIWhite && _signalingService.pendingMediaType != null) {
      print("[GAME CALL] Pending offer found. Accepting immediately.");
      _isCallStarted = true;
      _signalingService.acceptCall(isVideo: _isLocalVideoEnabled);
      setState(() {
        _callStatus = "Call Connected";
      });
    }
  }

  void _toggleLocalAudio() {
    setState(() {
      _isLocalAudioMuted = !_isLocalAudioMuted;
    });
    _signalingService.toggleMute(_isLocalAudioMuted);
    _signalingService.sendCustomMessage({
      'action': 'toggle_mute',
      'isMuted': _isLocalAudioMuted,
    });
  }

  void _toggleLocalVideo() {
    setState(() {
      _isLocalVideoEnabled = !_isLocalVideoEnabled;
    });
    _signalingService.toggleVideo(_isLocalVideoEnabled);
    _signalingService.sendCustomMessage({
      'action': 'toggle_video',
      'isVideoEnabled': _isLocalVideoEnabled,
    });

    // Send state to peer so they know we turned video on
  }

  void _toggleRemoteAudioLocalOverride() {
    // This allows muting the opponent LOCALLY so we don't hear them, regardless of their own mute state
    final remoteStream = _signalingService.remoteStreamNotifier.value;
    if (remoteStream != null) {
      bool currentlyEnabled =
          remoteStream.getAudioTracks().isNotEmpty &&
          remoteStream.getAudioTracks().first.enabled;
      remoteStream.getAudioTracks().forEach((track) {
        track.enabled = !currentlyEnabled;
      });

      setState(() {
        _isOpponentLocallySilenced = currentlyEnabled;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyEnabled
                ? "Opponent silenced locally"
                : "Opponent unsilenced locally",
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Leave Game?"),
        content: const Text("Are you sure you want to leave this room?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _recordingService.stopRecording();
              // STOP CALL BEFORE LEAVING
              _signalingService.endCall();
              // Explicitly navigate back to the main bottom nav screen
              // This ensures that any intermediate loaders (like InviteWaitingScreen) are cleared
              RouteGenerator.navigateToPageWithoutStack(
                context,
                Routes.bottomNavBarRoute,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Leave", style: TextStyle(color: Colors.white)),
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
    _initRenderers();
    _initializeBoard();
    if (widget.isMultiplayer) {
      // SYNC: Populate GlobalCallHandler with game context for the overlay
      GlobalCallHandler().activeChessRoomId.value = widget.roomId;
      GlobalCallHandler().currentUserId.value = widget.currentUserId;
      GlobalCallHandler().opponentId.value = widget.opponentId;
      GlobalCallHandler().amIWhite.value = widget.amIWhite;

      print(
        "[GAME] Init Room: ${widget.roomId}, Me: ${widget.currentUserId}, Opponent: ${widget.opponentId}, amIWhite: ${widget.amIWhite}",
      );

      _setupEmbeddedCall(); // Initialize the embedded call

      _gameService.connect(widget.roomId);
      _gameSubscription = _gameService.stream.listen((data) {
        // Filter moves by roomId to prevent crosstalk
        final dynamic rawRoomId = data['room_id'];
        final int? moveRoomId = rawRoomId is int
            ? rawRoomId
            : int.tryParse(rawRoomId?.toString() ?? "");

        if (moveRoomId != null && moveRoomId != widget.roomId) {
          print("Ignoring move from another room: $moveRoomId");
          return;
        }

        if (data['type'] == 'move') {
          print("RECEIVE MOVE [Room ${widget.roomId}]: $data");
          final bool isMyMove =
              data['sender_id']?.toString() == widget.currentUserId.toString();

          if (isMyMove && !_isSyncing) {
            print("Ignoring echo of my own move.");
            return;
          }

          _handleRemoteMove(data);

          if (!isMyMove && !_isSyncing) {
            // Only show feedback for opponent moves
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Opponent moved"),
                duration: Duration(milliseconds: 500),
              ),
            );
          }
        } else if (data['type'] == 'history') {
          print(
            "RECEIVE HISTORY [Room ${widget.roomId}]: ${data['history'].length} moves",
          );
          setState(() {
            _isSyncing = true;
            _initializeBoard(); // Start fresh
            final List history = data['history'];
            for (var move in history) {
              _handleRemoteMove(Map<String, dynamic>.from(move));
            }
            _isSyncing = false;
          });
        } else if (data['type'] == 'user_left') {
          print("OPPONENT LEFT [Room ${widget.roomId}]: ${data['user_id']}");
          if (data['user_id']?.toString() != widget.currentUserId.toString()) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Opponent left the game"),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 3),
              ),
            );
            // STOP CALL ON OPPONENT DISCONNECT
            _signalingService.endCall(sendSignal: false);
          }
        } else if (data['type'] == 'reset') {
          print("RECEIVE RESET [Room ${widget.roomId}]");
          setState(() => _initializeBoard());
        }
      });

      // Initialize ChatProvider for the game room
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<ChatProvider>(
          context,
          listen: false,
        ).init(widget.roomId, widget.currentUserId, setAsActive: true);
      });
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _stopCallTimers() {
    _handshakePulseTimer?.cancel();
    _callTimeoutTimer?.cancel();
    _handshakePulseTimer = null;
    _callTimeoutTimer = null;
  }

  @override
  void dispose() {
    _recordingService.stopRecording();
    _signalingService.remoteStreamNotifier.removeListener(
      _onRemoteStreamChanged,
    );
    _gameSubscription?.cancel();
    _incomingCallSub?.cancel();
    _customMessageSub?.cancel();
    _peerJoinedSub?.cancel();
    _onHangupSub?.cancel();
    _onCallAcceptedSub?.cancel();
    _signalingService.onLog = null;
    _stopCallTimers();
    _signalingService.localStreamNotifier.removeListener(_onLocalStreamChanged);
    _signalingService.remoteStreamNotifier.removeListener(
      _onRemoteStreamChanged,
    );
    _signalingService.remoteMediaTypeNotifier.removeListener(
      _onRemoteMediaTypeChanged,
    );
    if (widget.signalingService == null) {
      _signalingService.endCall(); // Only end if we own the service
      _signalingService.disconnect();
    } else {
      // Even if we don't own it, if we're in a call session, we should end it when leaving the board
      if (_signalingService.inCallSession) {
        _signalingService.endCall(sendSignal: true);
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
                content: Text("Not connected – trying to reconnect."),
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

  void _showGameOverDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Game Over"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _initializeBoard();
              });
            },
            child: const Text("Play Again"),
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final bool isPractice = !widget.isMultiplayer;

    return PopScope(
      canPop:
          isPractice, // Allow pop only in practice mode (it's in a tab anyway)
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isPractice) {
          _showLeaveDialog();
        }
      },
      child: Scaffold(
        backgroundColor: isPractice ? Colors.white : backgroundColor,
        appBar: AppBar(
          leadingWidth: isPractice ? 0 : 40,
          leading: isPractice
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _showLeaveDialog,
                ),
          title: Column(
            children: [
              Text(
                _isSyncing
                    ? "Syncing..."
                    : "${whiteTurn ? "White" : "Black"}'s Turn ${checkStatus ? "(!)" : ""}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.isMultiplayer)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StreamBuilder<bool>(
                      stream: _gameService.connectionStream,
                      initialData: _gameService.isConnected,
                      builder: (context, snapshot) =>
                          _buildStatusDot(snapshot.data ?? false),
                    ),
                    const SizedBox(width: 8),
                    StreamBuilder<bool>(
                      stream: _signalingService.connectionStream,
                      initialData: _signalingService.isConnected,
                      builder: (context, snapshot) =>
                          _buildStatusDot(snapshot.data ?? false, Colors.blue),
                    ),
                    const SizedBox(width: 8),
                    StreamBuilder<bool>(
                      stream: GlobalCallHandler()
                          .generalSignalingService
                          ?.connectionStream,
                      initialData: GlobalCallHandler()
                          .generalSignalingService
                          ?.isConnected,
                      builder: (context, snapshot) =>
                          _buildStatusDot(snapshot.data ?? false, Colors.teal),
                    ),
                  ],
                ),
            ],
          ),
          centerTitle: true,
          actions: [
            if (widget.isMultiplayer && !_gameService.isConnected)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.amber),
                tooltip: "Retry Connection",
                onPressed: () {
                  _gameService.connect(widget.roomId);
                },
              ),
            if (widget.showLeaveButton)
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.red),
                onPressed: _showLeaveDialog,
              ),
            Consumer<ChatProvider>(
              builder: (_, provider, __) {
                return badges.Badge(
                  badgeContent: Text(
                    provider.getUnreadCount(widget.roomId).toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  showBadge: provider.getUnreadCount(widget.roomId) > 0,
                  position: badges.BadgePosition.topEnd(top: 0, end: 3),
                  child: IconButton(
                    icon: const Icon(Icons.chat),
                    tooltip: "Messenger",
                    onPressed: () {
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
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.isMultiplayer &&
                  (_isCallStarted ||
                      _callStatus == "Waiting for peer..." ||
                      _callStatus == "Handshake started..."))
                Expanded(
                  flex: 2, // Slightly more space for the video area if needed
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildCallFrame(),
                  ),
                ),
              // Board Section
              isPractice
                  ? Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildChessBoard(),
                          ),
                        ),
                      ),
                    )
                  : Expanded(
                      flex: 3, // More space for the chess board
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: _buildChessBoard(),
                          ),
                        ),
                      ),
                    ),
              if (isPractice) const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build the embedded call frame
  Widget _buildCallFrame() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Local User Video
                  Expanded(
                    child: _buildVideoContainer(
                      notifier: _signalingService.localStreamNotifier,
                      renderer: _localRenderer,
                      isEnabled: _isLocalVideoEnabled,
                      label: "You",
                      isLocal: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Remote User Video
                  Expanded(
                    child: _buildVideoContainer(
                      notifier: _signalingService.remoteStreamNotifier,
                      renderer: _remoteRenderer,
                      isEnabled: _isRemoteVideoEnabled,
                      label: widget.opponentId?.toString() ?? "Opponent",
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Call Controls Strip
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.white.withOpacity(0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCompactIconButton(
                  icon: _isLocalAudioMuted ? Icons.mic_off : Icons.mic,
                  color: _isLocalAudioMuted ? Colors.redAccent : Colors.white,
                  onPressed: _toggleLocalAudio,
                ),
                _buildCompactIconButton(
                  icon: _isLocalVideoEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  color: _isLocalVideoEnabled ? Colors.white : Colors.redAccent,
                  onPressed: _toggleLocalVideo,
                ),
                _buildCompactIconButton(
                  icon: _isOpponentLocallySilenced
                      ? Icons.volume_off
                      : Icons.volume_up,
                  color: _isOpponentLocallySilenced
                      ? Colors.redAccent
                      : Colors.white,
                  onPressed: _toggleRemoteAudioLocalOverride,
                ),
              ],
            ),
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
          if (isLocal && _isLocalAudioMuted)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.mic_off, color: Colors.redAccent, size: 14),
            ),
          if (!isLocal && _isRemoteAudioMuted)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic_off, color: Colors.redAccent, size: 16),
              ),
            ),
          if (!isLocal && _isOpponentLocallySilenced)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.volume_off, color: Colors.redAccent, size: 12),
                    SizedBox(width: 2),
                    Text(
                      "Silenced",
                      style: TextStyle(color: Colors.redAccent, fontSize: 8),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onPressed,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildStatusDot(bool connected, [Color? activeColor]) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: connected ? (activeColor ?? Colors.green) : Colors.red,
        shape: BoxShape.circle,
        boxShadow: connected
            ? [
                BoxShadow(
                  color: (activeColor ?? Colors.green).withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
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
        int row = index ~/ 8, col = index % 8;
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
