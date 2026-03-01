import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chess_piece.dart';
import '../ui/square_widget.dart';
import '../helper/helper.dart';
import '../services/game_websocket_service.dart';

class MiniGameBoard extends StatefulWidget {
  final int roomId;
  final int currentUserId;
  final bool amIWhite;

  const MiniGameBoard({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.amIWhite,
  });

  @override
  State<MiniGameBoard> createState() => _MiniGameBoardState();
}

class _MiniGameBoardState extends State<MiniGameBoard> {
  late List<List<ChessPiece?>> board;
  ChessPiece? selectedPiece;
  int selectedRow = -1;
  int selectedCol = -1;
  List<List<int>> validMoves = [];
  bool whiteTurn = true;
  List<int> whiteKingPosition = [7, 4];
  List<int> blackKingPosition = [0, 4];

  final GameWebsocketService _gameService = GameWebsocketService();
  StreamSubscription? _gameSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBoard();
    _gameService.connect(widget.roomId);
    _gameSubscription = _gameService.stream.listen((data) {
      final dynamic rawRoomId = data['room_id'];
      final int? moveRoomId = rawRoomId is int
          ? rawRoomId
          : int.tryParse(rawRoomId?.toString() ?? "");

      if (moveRoomId != null && moveRoomId != widget.roomId) return;

      if (data['type'] == 'move') {
        _handleRemoteMove(data);
      } else if (data['type'] == 'history') {
        setState(() {
          _initializeBoard();
          final List history = data['history'];
          for (var move in history) {
            _handleRemoteMove(Map<String, dynamic>.from(move));
          }
        });
      } else if (data['type'] == 'reset') {
        setState(() => _initializeBoard());
      }
    });
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    super.dispose();
  }

  void _initializeBoard() {
    board = List.generate(8, (_) => List.generate(8, (_) => null));
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
    whiteKingPosition = [7, 4];
    blackKingPosition = [0, 4];
    whiteTurn = true;
  }

  void _handleRemoteMove(Map<String, dynamic> data) {
    int? fR = int.tryParse(data['from_row']?.toString() ?? "");
    int? fC = int.tryParse(data['from_col']?.toString() ?? "");
    int? tR = int.tryParse(data['to_row']?.toString() ?? "");
    int? tC = int.tryParse(data['to_col']?.toString() ?? "");
    if (fR == null || fC == null || tR == null || tC == null) return;
    setState(() {
      ChessPiece? piece = board[fR][fC];
      if (piece != null) {
        if (piece.type == ChessPieceType.king) {
          if (piece.isWhite)
            whiteKingPosition = [tR, tC];
          else
            blackKingPosition = [tR, tC];
        }
        board[tR][tC] = piece;
        board[fR][fC] = null;
        whiteTurn = !whiteTurn;
      }
    });
  }

  void onSquareTap(int row, int col) {
    setState(() {
      ChessPiece? piece = board[row][col];
      if (selectedPiece != null &&
          validMoves.any((m) => m[0] == row && m[1] == col)) {
        if (whiteTurn != widget.amIWhite) return;
        if (_gameService.isConnected) {
          _gameService.sendMove(
            widget.roomId,
            widget.currentUserId,
            selectedRow,
            selectedCol,
            row,
            col,
          );
        }
        if (selectedPiece!.type == ChessPieceType.king) {
          if (selectedPiece!.isWhite)
            whiteKingPosition = [row, col];
          else
            blackKingPosition = [row, col];
        }
        board[row][col] = selectedPiece;
        board[selectedRow][selectedCol] = null;
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
        return;
      }
      if (piece != null && piece.isWhite == widget.amIWhite) {
        selectedPiece = piece;
        selectedRow = row;
        selectedCol = col;
        validMoves = _calculateRealValidMoves(row, col, piece, true);
      } else {
        selectedPiece = null;
        validMoves.clear();
      }
    });
  }

  List<List<int>> _calculateRawValidMoves(int row, int col, ChessPiece piece) {
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

  List<List<int>> _calculateRealValidMoves(
    int row,
    int col,
    ChessPiece piece,
    bool checkCheck,
  ) {
    List<List<int>> rawMoves = _calculateRawValidMoves(row, col, piece);
    if (!checkCheck) return rawMoves;
    List<List<int>> realMoves = [];
    for (var move in rawMoves) {
      int endR = move[0], endC = move[1];
      ChessPiece? target = board[endR][endC];
      List<int> oldKingPos = piece.isWhite
          ? [...whiteKingPosition]
          : [...blackKingPosition];
      if (piece.type == ChessPieceType.king) {
        if (piece.isWhite)
          whiteKingPosition = [endR, endC];
        else
          blackKingPosition = [endR, endC];
      }
      board[endR][endC] = piece;
      board[row][col] = null;
      bool inCheck = _isKingInCheck(piece.isWhite);
      board[row][col] = piece;
      board[endR][endC] = target;
      if (piece.type == ChessPieceType.king) {
        if (piece.isWhite)
          whiteKingPosition = oldKingPos;
        else
          blackKingPosition = oldKingPos;
      }
      if (!inCheck) realMoves.add(move);
    }
    return realMoves;
  }

  bool _isKingInCheck(bool isWhite) {
    List<int> kPos = isWhite ? whiteKingPosition : blackKingPosition;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        ChessPiece? p = board[r][c];
        if (p != null && p.isWhite != isWhite) {
          if (_calculateRawValidMoves(
            r,
            c,
            p,
          ).any((m) => m[0] == kPos[0] && m[1] == kPos[1]))
            return true;
        }
      }
    }
    return false;
  }

  List<List<int>> _pawnMoves(int r, int c, ChessPiece p) {
    List<List<int>> m = [];
    int d = p.isWhite ? -1 : 1;
    if (isInBoard(r + d, c) && board[r + d][c] == null) m.add([r + d, c]);
    if (((r == 6 && p.isWhite) || (r == 1 && !p.isWhite)) &&
        isInBoard(r + d, c) &&
        board[r + d][c] == null &&
        board[r + 2 * d][c] == null)
      m.add([r + 2 * d, c]);
    for (int dc in [-1, 1])
      if (isInBoard(r + d, c + dc) &&
          board[r + d][c + dc] != null &&
          board[r + d][c + dc]!.isWhite != p.isWhite)
        m.add([r + d, c + dc]);
    return m;
  }

  List<List<int>> _rookMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    var dirs = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    for (var d in dirs) {
      int r = row + d[0], c = col + d[1];
      while (isInBoard(r, c)) {
        if (board[r][c] == null) {
          moves.add([r, c]);
        } else {
          if (board[r][c]!.isWhite != piece.isWhite) moves.add([r, c]);
          break;
        }
        r += d[0];
        c += d[1];
      }
    }
    return moves;
  }

  List<List<int>> _bishopMoves(int row, int col, ChessPiece piece) {
    List<List<int>> moves = [];
    var dirs = [
      [1, 1],
      [1, -1],
      [-1, 1],
      [-1, -1],
    ];
    for (var d in dirs) {
      int r = row + d[0], c = col + d[1];
      while (isInBoard(r, c)) {
        if (board[r][c] == null) {
          moves.add([r, c]);
        } else {
          if (board[r][c]!.isWhite != piece.isWhite) moves.add([r, c]);
          break;
        }
        r += d[0];
        c += d[1];
      }
    }
    return moves;
  }

  List<List<int>> _knightMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    var jumps = [
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
      int nr = r + j[0], nc = c + j[1];
      if (isInBoard(nr, nc) &&
          (board[nr][nc] == null || board[nr][nc]!.isWhite != p.isWhite))
        moves.add([nr, nc]);
    }
    return moves;
  }

  List<List<int>> _kingMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    var dirs = [
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
      int nr = r + d[0], nc = c + d[1];
      if (isInBoard(nr, nc) &&
          (board[nr][nc] == null || board[nr][nc]!.isWhite != p.isWhite))
        moves.add([nr, nc]);
    }
    return moves;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
        ),
        itemCount: 64,
        itemBuilder: (context, index) {
          int row = index ~/ 8;
          int col = index % 8;
          return Square(
            isWhiteSquare: isWhiteSquare(index),
            piece: board[row][col],
            isSelected: selectedRow == row && selectedCol == col,
            isValidMove: validMoves.any((m) => m[0] == row && m[1] == col),
            onTap: () => onSquareTap(row, col),
          );
        },
      ),
    );
  }
}
