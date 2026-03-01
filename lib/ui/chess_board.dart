import 'dart:async';
import 'package:badges/badges.dart' as badges;
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/ui/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chess_piece.dart';
import '../ui/square_widget.dart';
import '../helper/helper.dart';
import '../ui/call_screen.dart';
import '../core/utils/global_callhandler.dart';
import '../services/game_websocket_service.dart';
import '../services/signaling_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class GameBoard extends StatefulWidget {
  final int roomId;
  final int currentUserId;
  final bool isMultiplayer;
  final bool amIWhite;
  final int? opponentId;
  final bool showLeaveButton; // New parameter
  const GameBoard({
    super.key,
    required this.currentUserId,
    required this.roomId,
    this.isMultiplayer = false,
    this.amIWhite = true,
    this.opponentId,
    this.showLeaveButton = false, // Default to false
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

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  void _startCall(bool isVideo) {
    final String callRoomId = widget.opponentId != null
        ? "user_${widget.opponentId}"
        : "chess_call_${widget.roomId}";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          roomId: callRoomId,
          isIncomingCall: false,
          isInitialVideo: isVideo,
          signalingService:
              (widget.opponentId != null &&
                  GlobalCallHandler().userSignalingService?.currentRoomId ==
                      callRoomId)
              ? GlobalCallHandler().userSignalingService
              : (callRoomId == "chess_room_1" &&
                    GlobalCallHandler()
                            .generalSignalingService
                            ?.currentRoomId ==
                        "chess_room_1")
              ? GlobalCallHandler().generalSignalingService
              : null,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
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
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // exit GameBoard
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
          }
        } else if (data['type'] == 'reset') {
          print("RECEIVE RESET [Room ${widget.roomId}]");
          setState(() => _initializeBoard());
        }
      });

      // Initialize ChatProvider for the game room
      WidgetsBinding.instance.addPostFrameCallback((_) {
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

  @override
  void dispose() {
    _gameSubscription?.cancel();
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

        // SYNC: Send move to server if multiplayer
        if (widget.isMultiplayer) {
          // Check connection status
          if (!_gameService.isConnected) {
            print(
              "SEND MOVE FAILED: Socket not connected (Room: ${widget.roomId})",
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Not connected to server. Trying to reconnect...",
                ),
              ),
            );
            _gameService.connect(widget.roomId);
            return;
          }

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
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 40,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              _isSyncing
                  ? "Syncing..."
                  : "${whiteTurn ? "White" : "Black"}'s Turn ${checkStatus ? "(!)" : ""}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    stream: GlobalCallHandler()
                        .userSignalingService
                        ?.connectionStream,
                    initialData:
                        GlobalCallHandler().userSignalingService?.isConnected,
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
          if (widget.isMultiplayer)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'audio') _startCall(false);
                if (value == 'video') _startCall(true);
                if (value == 'leave') _showLeaveDialog();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'audio',
                  child: ListTile(
                    leading: Icon(Icons.phone),
                    title: Text("Audio Call"),
                  ),
                ),
                const PopupMenuItem(
                  value: 'video',
                  child: ListTile(
                    leading: Icon(Icons.videocam),
                    title: Text("Video Call"),
                  ),
                ),
                if (widget.showLeaveButton)
                  const PopupMenuItem(
                    value: 'leave',
                    child: ListTile(
                      leading: Icon(Icons.exit_to_app, color: Colors.red),
                      title: Text(
                        "Leave Game",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
              ],
            )
          else if (widget.showLeaveButton)
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
      body: ValueListenableBuilder<bool>(
        valueListenable: GlobalCallHandler().isMinimized,
        builder: (context, isMinimized, _) {
          final bool showCallView =
              widget.isMultiplayer &&
              isMinimized &&
              GlobalCallHandler().activeService != null;

          if (showCallView) {
            return Column(
              children: [
                Expanded(child: _buildIntegratedCallHeader()),
                AspectRatio(aspectRatio: 1.0, child: _buildChessBoard()),
              ],
            );
          }

          return Column(
            children: [
              AspectRatio(aspectRatio: 1.0, child: _buildChessBoard()),
              if (widget.isMultiplayer)
                const Expanded(
                  child: Center(
                    child: Text(
                      "Chess Room",
                      style: TextStyle(
                        color: Colors.white10,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
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

  Widget _buildIntegratedCallHeader() {
    return ValueListenableBuilder<SignalingService?>(
      valueListenable: GlobalCallHandler().activeCallService,
      builder: (context, activeCall, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: GlobalCallHandler().isMinimized,
          builder: (context, isMinimized, _) {
            final service = GlobalCallHandler().activeService;
            if (!isMinimized || service == null) {
              return Container(
                color: Colors.black,
                child: const Center(
                  child: Text(
                    "Chess Room",
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }

            return Container(
              decoration: const BoxDecoration(color: Colors.black),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildVideoOrAvatar(
                          service.remoteStreamNotifier,
                          "Opponent",
                          Icons.person,
                          false,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: _buildVideoOrAvatar(
                          service.localStreamNotifier,
                          "You",
                          Icons.videocam,
                          true,
                        ),
                      ),
                    ],
                  ),
                  // Controls Overlay
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildMiniActionCircle(
                          icon: GlobalCallHandler().isMuted.value
                              ? Icons.mic_off
                              : Icons.mic,
                          color: GlobalCallHandler().isMuted.value
                              ? Colors.redAccent
                              : Colors.white24,
                          onPressed: () {
                            setState(() {
                              GlobalCallHandler().isMuted.value =
                                  !GlobalCallHandler().isMuted.value;
                              service.toggleMute(
                                GlobalCallHandler().isMuted.value,
                              );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildMiniActionCircle(
                          icon: GlobalCallHandler().isVideoEnabled.value
                              ? Icons.videocam
                              : Icons.videocam_off,
                          color: GlobalCallHandler().isVideoEnabled.value
                              ? Colors.white24
                              : Colors.redAccent,
                          onPressed: () {
                            setState(() {
                              GlobalCallHandler().isVideoEnabled.value =
                                  !GlobalCallHandler().isVideoEnabled.value;
                              service.toggleVideo(
                                GlobalCallHandler().isVideoEnabled.value,
                              );
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildMiniActionCircle(
                          icon: Icons.open_in_full,
                          color: Colors.blueAccent,
                          onPressed: () {
                            GlobalCallHandler().isMinimized.value = false;
                            final roomId =
                                GlobalCallHandler().activeRoomId.value;
                            if (roomId != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CallScreen(
                                    roomId: roomId,
                                    isIncomingCall: false,
                                    signalingService: service,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildMiniActionCircle(
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          onPressed: () {
                            service.endCall();
                            GlobalCallHandler().isMinimized.value = false;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoOrAvatar(
    ValueNotifier<MediaStream?> streamNotifier,
    String label,
    IconData placeholder,
    bool isLocal,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalCallHandler().isVideoEnabled,
      builder: (context, videoEnabled, _) {
        return ValueListenableBuilder<MediaStream?>(
          valueListenable: streamNotifier,
          builder: (context, stream, _) {
            if (isLocal) {
              if (_localRenderer.srcObject != stream) {
                _localRenderer.srcObject = stream;
              }
            } else {
              if (_remoteRenderer.srcObject != stream) {
                _remoteRenderer.srcObject = stream;
              }
            }
            bool showVideo = videoEnabled && stream != null;
            if (isLocal && !videoEnabled) showVideo = false;
            // For remote, it depends on their stream tracks
            if (!isLocal && stream != null && stream.getVideoTracks().isEmpty)
              showVideo = false;

            return Container(
              color: Colors.black54,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (showVideo)
                    RTCVideoView(
                      isLocal ? _localRenderer : _remoteRenderer,
                      mirror: isLocal,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    Center(
                      child: Icon(placeholder, color: Colors.white24, size: 40),
                    ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniActionCircle({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: Colors.white),
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
