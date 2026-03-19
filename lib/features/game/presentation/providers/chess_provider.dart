import 'dart:async';
import 'package:chess_game_manika/features/game/data/models/chess_piece.dart';
import 'package:chess_game_manika/features/game/services/game_websocket_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChessState {
  final List<List<ChessPiece?>> board;
  final ChessPiece? selectedPiece;
  final int selectedRow;
  final int selectedCol;
  final List<List<int>> validMoves;
  final bool whiteTurn;
  final List<int> whiteKingPosition;
  final List<int> blackKingPosition;
  final bool checkStatus;
  final bool isSyncing;
  final bool isGameOver;
  final String? winnerMessage;
  final bool isCallStarted;
  final String callStatus;
  final bool isLocalAudioMuted;
  final bool isLocalVideoEnabled;
  final bool isRemoteAudioMuted;
  final bool isRemoteVideoEnabled;
  final bool isOpponentLocallySilenced;
  final bool amISilencedByOpponent;

  const ChessState({
    required this.board,
    this.selectedPiece,
    this.selectedRow = -1,
    this.selectedCol = -1,
    this.validMoves = const [],
    this.whiteTurn = true,
    this.whiteKingPosition = const [7, 4],
    this.blackKingPosition = const [0, 4],
    this.checkStatus = false,
    this.isSyncing = false,
    this.isGameOver = false,
    this.winnerMessage,
    this.isCallStarted = false,
    this.callStatus = "Initializing...",
    this.isLocalAudioMuted = false,
    this.isLocalVideoEnabled = false,
    this.isRemoteAudioMuted = false,
    this.isRemoteVideoEnabled = false,
    this.isOpponentLocallySilenced = false,
    this.amISilencedByOpponent = false,
  });

  ChessState copyWith({
    List<List<ChessPiece?>>? board,
    ChessPiece? selectedPiece,
    bool clearSelection = false,
    int? selectedRow,
    int? selectedCol,
    List<List<int>>? validMoves,
    bool? whiteTurn,
    List<int>? whiteKingPosition,
    List<int>? blackKingPosition,
    bool? checkStatus,
    bool? isSyncing,
    bool? isGameOver,
    String? winnerMessage,
    bool? isCallStarted,
    String? callStatus,
    bool? isLocalAudioMuted,
    bool? isLocalVideoEnabled,
    bool? isRemoteAudioMuted,
    bool? isRemoteVideoEnabled,
    bool? isOpponentLocallySilenced,
    bool? amISilencedByOpponent,
  }) {
    return ChessState(
      board: board ?? this.board,
      selectedPiece: clearSelection ? null : (selectedPiece ?? this.selectedPiece),
      selectedRow: clearSelection ? -1 : (selectedRow ?? this.selectedRow),
      selectedCol: clearSelection ? -1 : (selectedCol ?? this.selectedCol),
      validMoves: clearSelection ? const [] : (validMoves ?? this.validMoves),
      whiteTurn: whiteTurn ?? this.whiteTurn,
      whiteKingPosition: whiteKingPosition ?? this.whiteKingPosition,
      blackKingPosition: blackKingPosition ?? this.blackKingPosition,
      checkStatus: checkStatus ?? this.checkStatus,
      isSyncing: isSyncing ?? this.isSyncing,
      isGameOver: isGameOver ?? this.isGameOver,
      winnerMessage: winnerMessage ?? this.winnerMessage,
      isCallStarted: isCallStarted ?? this.isCallStarted,
      callStatus: callStatus ?? this.callStatus,
      isLocalAudioMuted: isLocalAudioMuted ?? this.isLocalAudioMuted,
      isLocalVideoEnabled: isLocalVideoEnabled ?? this.isLocalVideoEnabled,
      isRemoteAudioMuted: isRemoteAudioMuted ?? this.isRemoteAudioMuted,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      isOpponentLocallySilenced: isOpponentLocallySilenced ?? this.isOpponentLocallySilenced,
      amISilencedByOpponent: amISilencedByOpponent ?? this.amISilencedByOpponent,
    );
  }

  static List<List<ChessPiece?>> createInitialBoard() {
    List<List<ChessPiece?>> board = List.generate(8, (_) => List.generate(8, (_) => null));
    for (int i = 0; i < 8; i++) {
        board[1][i] = ChessPiece(type: ChessPieceType.pawn, isWhite: false, imagePath: "assets/images/black/pawn.png");
        board[6][i] = ChessPiece(type: ChessPieceType.pawn, isWhite: true, imagePath: "assets/images/white/pawn.png");
    }
    void placeBackRow(int row, bool isWhite) {
        String base = isWhite ? "white" : "black";
        board[row][0] = ChessPiece(type: ChessPieceType.rook, isWhite: isWhite, imagePath: "assets/images/$base/rook.png");
        board[row][1] = ChessPiece(type: ChessPieceType.knight, isWhite: isWhite, imagePath: "assets/images/$base/knight.png");
        board[row][2] = ChessPiece(type: ChessPieceType.bishop, isWhite: isWhite, imagePath: "assets/images/$base/bishop.png");
        board[row][3] = ChessPiece(type: ChessPieceType.queen, isWhite: isWhite, imagePath: "assets/images/$base/queen.png");
        board[row][4] = ChessPiece(type: ChessPieceType.king, isWhite: isWhite, imagePath: "assets/images/$base/king.png");
        board[row][5] = ChessPiece(type: ChessPieceType.bishop, isWhite: isWhite, imagePath: "assets/images/$base/bishop.png");
        board[row][6] = ChessPiece(type: ChessPieceType.knight, isWhite: isWhite, imagePath: "assets/images/$base/knight.png");
        board[row][7] = ChessPiece(type: ChessPieceType.rook, isWhite: isWhite, imagePath: "assets/images/$base/rook.png");
    }
    placeBackRow(0, false);
    placeBackRow(7, true);
    return board;
  }
}

class ChessNotifier extends Notifier<ChessState> {
  final GameWebsocketService _gameService = GameWebsocketService();
  SignalingService? _signalingService;
  StreamSubscription? _gameSubscription;

  @override
  ChessState build() {
    return ChessState(board: ChessState.createInitialBoard());
  }

  void initGame(int roomId, int currentUserId, {SignalingService? signalingService}) {
    _signalingService = signalingService;
    _gameService.connect(roomId);

    _gameSubscription = _gameService.stream.listen((data) {
      final dynamic rawRoomId = data['room_id'];
      final int? moveRoomId = rawRoomId is int ? rawRoomId : int.tryParse(rawRoomId?.toString() ?? "");
      if (moveRoomId != null && moveRoomId != roomId) return;

      if (data['type'] == 'move') {
        final bool isMyMove = data['sender_id']?.toString() == currentUserId.toString();
        if (isMyMove && !state.isSyncing) return;
        handleRemoteMove(data);
      } else if (data['type'] == 'history') {
        state = state.copyWith(isSyncing: true, board: ChessState.createInitialBoard(), whiteTurn: true, whiteKingPosition: [7,4], blackKingPosition: [0,4]);
        final List history = data['history'];
        for (var move in history) {
            handleRemoteMove(Map<String, dynamic>.from(move));
        }
        state = state.copyWith(isSyncing: false);
      } else if (data['type'] == 'user_left') {
        if (data['user_id']?.toString() != currentUserId.toString()) {
           state = state.copyWith(isGameOver: true, winnerMessage: "Congratulations! Your opponent has left the game. You win!");
        }
      } else if (data['type'] == 'reset') {
         state = state.copyWith(board: ChessState.createInitialBoard(), whiteTurn: true, whiteKingPosition: [7,4], blackKingPosition: [0,4]);
      }
    });
  }

  void handleRemoteMove(Map<String, dynamic> data) {
    int? fR = int.tryParse(data['from_row']?.toString() ?? "");
    int? fC = int.tryParse(data['from_col']?.toString() ?? "");
    int? tR = int.tryParse(data['to_row']?.toString() ?? "");
    int? tC = int.tryParse(data['to_col']?.toString() ?? "");
    if (fR == null || fC == null || tR == null || tC == null) return;
    
    final piece = state.board[fR][fC];
    if (piece != null) {
        _applyMoveLocally(fR, fC, tR, tC, piece);
    }
  }

  bool isInBoard(int row, int col) => row >= 0 && row < 8 && col >= 0 && col < 8;

  void onSquareTap(int row, int col, {required bool isMultiplayer, required bool amIWhite, required int roomId, required int currentUserId}) {
    final piece = state.board[row][col];

    // Move piece if one is selected and target is valid
    if (state.selectedPiece != null && state.validMoves.any((m) => m[0] == row && m[1] == col)) {
      if (isMultiplayer && state.whiteTurn != amIWhite) return;

      int fromR = state.selectedRow;
      int fromC = state.selectedCol;
      final selectedP = state.selectedPiece!;

      // Apply move locally
      _applyMoveLocally(fromR, fromC, row, col, selectedP);

      // Send via socket
      if (isMultiplayer) {
         _gameService.sendMove(roomId, currentUserId, fromR, fromC, row, col);
      }
      return;
    }

    // Select new piece
    if (piece != null && piece.isWhite == (isMultiplayer ? amIWhite : state.whiteTurn)) {
        final moves = calculateRealValidMoves(row, col, piece, true);
        state = state.copyWith(selectedPiece: piece, selectedRow: row, selectedCol: col, validMoves: moves);
    } else {
        state = state.copyWith(clearSelection: true);
    }
  }

  void _applyMoveLocally(int fromR, int fromC, int toR, int toC, ChessPiece piece) {
    final newBoard = List<List<ChessPiece?>>.from(state.board.map((r) => List<ChessPiece?>.from(r)));
    
    List<int> newWhiteKing = [...state.whiteKingPosition];
    List<int> newBlackKing = [...state.blackKingPosition];

    if (piece.type == ChessPieceType.king) {
        if (piece.isWhite) newWhiteKing = [toR, toC];
        else newBlackKing = [toR, toC];
    }

    newBoard[toR][toC] = piece;
    newBoard[fromR][fromC] = null;

    // Pawn promotion to Queen
    if (piece.type == ChessPieceType.pawn && (toR == 0 || toR == 7)) {
        newBoard[toR][toC] = ChessPiece(
            type: ChessPieceType.queen,
            isWhite: piece.isWhite,
            imagePath: "assets/images/${piece.isWhite ? 'white' : 'black'}/queen.png",
        );
    }

    state = state.copyWith(
        board: newBoard,
        whiteTurn: !state.whiteTurn,
        whiteKingPosition: newWhiteKing,
        blackKingPosition: newBlackKing,
        clearSelection: true,
        checkStatus: false, // will update below
    );

    final nextCheck = isKingInCheck(state.whiteTurn);
    state = state.copyWith(checkStatus: nextCheck);

    if (isCheckMate(state.whiteTurn)) {
        state = state.copyWith(isGameOver: true, winnerMessage: state.whiteTurn ? "Black Wins!" : "White Wins!");
    }
  }

  List<List<int>> calculateRawValidMoves(int row, int col, ChessPiece piece) {
    switch (piece.type) {
      case ChessPieceType.pawn: return _pawnMoves(row, col, piece);
      case ChessPieceType.rook: return _rookMoves(row, col, piece);
      case ChessPieceType.knight: return _knightMoves(row, col, piece);
      case ChessPieceType.bishop: return _bishopMoves(row, col, piece);
      case ChessPieceType.queen: return [..._rookMoves(row, col, piece), ..._bishopMoves(row, col, piece)];
      case ChessPieceType.king: return _kingMoves(row, col, piece);
    }
  }

  List<List<int>> calculateRealValidMoves(int row, int col, ChessPiece piece, bool checkCheck) {
    List<List<int>> rawMoves = calculateRawValidMoves(row, col, piece);
    if (!checkCheck) return rawMoves;

    List<List<int>> realMoves = [];
    for (var move in rawMoves) {
      int endR = move[0];
      int endC = move[1];
      ChessPiece? targetP = state.board[endR][endC];
      List<int> oldKingPos = piece.isWhite ? [...state.whiteKingPosition] : [...state.blackKingPosition];

      // Simulate
      if (piece.type == ChessPieceType.king) {
          if (piece.isWhite) state = state.copyWith(whiteKingPosition: [endR, endC]);
          else state = state.copyWith(blackKingPosition: [endR, endC]);
      }
      final tempBoard = state.board[endR][endC];
      state.board[endR][endC] = piece;
      state.board[row][col] = null;

      bool inCheck = isKingInCheck(piece.isWhite);

      // Undo
      state.board[row][col] = piece;
      state.board[endR][endC] = tempBoard;
      if (piece.type == ChessPieceType.king) {
          if (piece.isWhite) state = state.copyWith(whiteKingPosition: oldKingPos);
          else state = state.copyWith(blackKingPosition: oldKingPos);
      }

      if (!inCheck) realMoves.add(move);
    }
    return realMoves;
  }

  bool isKingInCheck(bool isWhite) {
    List<int> kingPos = isWhite ? state.whiteKingPosition : state.blackKingPosition;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        ChessPiece? p = state.board[r][c];
        if (p != null && p.isWhite != isWhite) {
          List<List<int>> moves = calculateRawValidMoves(r, c, p);
          if (moves.any((m) => m[0] == kingPos[0] && m[1] == kingPos[1])) return true;
        }
      }
    }
    return false;
  }

  bool isCheckMate(bool isWhite) {
    if (!isKingInCheck(isWhite)) return false;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        ChessPiece? p = state.board[r][c];
        if (p != null && p.isWhite == isWhite) {
          if (calculateRealValidMoves(r, c, p, true).isNotEmpty) return false;
        }
      }
    }
    return true;
  }

  List<List<int>> _pawnMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    int dir = p.isWhite ? -1 : 1;
    if (isInBoard(r + dir, c) && state.board[r + dir][c] == null) moves.add([r + dir, c]);
    if ((r == 6 && p.isWhite) || (r == 1 && !p.isWhite)) {
        if (isInBoard(r + dir, c) && state.board[r + dir][c] == null && isInBoard(r + 2 * dir, c) && state.board[r + 2 * dir][c] == null) {
            moves.add([r + 2 * dir, c]);
        }
    }
    for (int dc in [-1, 1]) {
        if (isInBoard(r + dir, c + dc) && state.board[r + dir][c + dc] != null && state.board[r + dir][c + dc]!.isWhite != p.isWhite) {
            moves.add([r + dir, c + dc]);
        }
    }
    return moves;
  }

  List<List<int>> _rookMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [[1,0], [-1,0], [0,1], [0,-1]];
    for (var d in dirs) {
      int currR = r, currC = c;
      while (true) {
        currR += d[0]; currC += d[1];
        if (!isInBoard(currR, currC)) break;
        if (state.board[currR][currC] == null) moves.add([currR, currC]);
        else {
          if (state.board[currR][currC]!.isWhite != p.isWhite) moves.add([currR, currC]);
          break;
        }
      }
    }
    return moves;
  }

  List<List<int>> _bishopMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [[1,1], [1,-1], [-1,1], [-1,-1]];
    for (var d in dirs) {
      int currR = r, currC = c;
      while (true) {
        currR += d[0]; currC += d[1];
        if (!isInBoard(currR, currC)) break;
        if (state.board[currR][currC] == null) moves.add([currR, currC]);
        else {
          if (state.board[currR][currC]!.isWhite != p.isWhite) moves.add([currR, currC]);
          break;
        }
      }
    }
    return moves;
  }

  List<List<int>> _knightMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    List<List<int>> jumps = [[2,1],[2,-1],[-2,1],[-2,-1],[1,2],[1,-2],[-1,2],[-1,-2]];
    for (var j in jumps) {
      int currR = r + j[0], currC = c + j[1];
      if (isInBoard(currR, currC) && (state.board[currR][currC] == null || state.board[currR][currC]!.isWhite != p.isWhite)) {
          moves.add([currR, currC]);
      }
    }
    return moves;
  }

  List<List<int>> _kingMoves(int r, int c, ChessPiece p) {
    List<List<int>> moves = [];
    List<List<int>> dirs = [[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]];
    for (var d in dirs) {
      int currR = r + d[0], currC = c + d[1];
      if (isInBoard(currR, currC) && (state.board[currR][currC] == null || state.board[currR][currC]!.isWhite != p.isWhite)) {
          moves.add([currR, currC]);
      }
    }
    return moves;
  }

  // Call Controls
  void setCallStarted(bool started) => state = state.copyWith(isCallStarted: started);
  void setCallStatus(String status) => state = state.copyWith(callStatus: status);
  void toggleLocalAudio(bool muted) {
    state = state.copyWith(isLocalAudioMuted: muted);
    _signalingService?.toggleMute(muted);
    _signalingService?.sendCustomMessage({'action': 'toggle_mute', 'isMuted': muted});
  }
  void toggleLocalVideo(bool enabled) {
    state = state.copyWith(isLocalVideoEnabled: enabled);
    _signalingService?.toggleVideo(enabled);
    _signalingService?.sendCustomMessage({'action': 'toggle_video', 'isVideoEnabled': enabled});
  }
  void setRemoteAudioMuted(bool muted) => state = state.copyWith(isRemoteAudioMuted: muted);
  void setRemoteVideoEnabled(bool enabled) => state = state.copyWith(isRemoteVideoEnabled: enabled);
  void setOpponentLocallySilenced(bool silenced) => state = state.copyWith(isOpponentLocallySilenced: silenced);
  void setAmISilencedByOpponent(bool silenced) => state = state.copyWith(amISilencedByOpponent: silenced);

  void resetGame(int roomId) {
    _gameService.resetGame(roomId);
    state = ChessState(board: ChessState.createInitialBoard());
  }

  void dispose() {
    _gameSubscription?.cancel();
    _gameService.disconnect();
  }
}

final chessProvider = NotifierProvider<ChessNotifier, ChessState>(() => ChessNotifier());
