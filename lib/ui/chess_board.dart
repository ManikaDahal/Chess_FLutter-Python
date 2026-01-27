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

class GameBoard extends StatefulWidget {
  final int roomId;
  final int currentUserId;
  const GameBoard({
    super.key,
    required this.currentUserId,
    required this.roomId,
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeBoard();
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

  void onSquareTap(int row, int col) {
    setState(() {
      ChessPiece? piece = board[row][col];

      // Move selected piece
      if (selectedPiece != null &&
          validMoves.any((m) => m[0] == row && m[1] == col)) {
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
        checkStatus = isKingInCheck(!whiteTurn);

        // Check for checkmate
        if (isCheckMate(whiteTurn)) {
          _showGameOverDialog(whiteTurn ? "Black Wins!" : "White Wins!");
        }

        return;
      }

      // Select new piece
      if (piece != null && piece.isWhite == whiteTurn) {
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
        title: Text(
          whiteTurn
              ? "White's Turn"
              : "Black's Turn" + (checkStatus ? " - CHECK!" : ""),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: "Audio Call",
            onPressed: () {
              const roomId = "chess_room_1";
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    roomId: roomId,
                    isIncomingCall: false,
                    isInitialVideo: false,
                    // REUSE EXISTING SERVICE
                    signalingService:
                        GlobalCallHandler().generalSignalingService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: "Video Call",
            onPressed: () {
              const roomId = "chess_room_1";
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    roomId: roomId,
                    isIncomingCall: false,
                    isInitialVideo: true,
                    signalingService:
                        GlobalCallHandler().generalSignalingService,
                  ),
                ),
              );
            },
          ),

          Consumer<ChatProvider>(
            builder: (_, provider, __) {
              return badges.Badge(
                badgeContent: Text(
                  provider.totalUnreadCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                showBadge: provider.totalUnreadCount > 0,
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
      body: GridView.builder(
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
      ),
    );
  }
}
