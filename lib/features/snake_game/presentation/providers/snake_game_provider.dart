import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/game/services/game_websocket_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';

class SnakeGameState {
  final int playerPosition;
  final int diceValue;
  final bool isRolling;
  final bool isMoving;
  final bool hasStarted;
  final String gameStatus;
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final int opponentPosition;
  final bool isMultiplayer;
  final bool isMyTurn;
  final int? roomId;
  final int? myUserId;
  final int? opponentUserId;
  // Call State
  final bool isCallStarted;
  final String callStatus;
  final bool isLocalAudioMuted;
  final bool isLocalVideoEnabled;
  final bool isRemoteAudioMuted;
  final bool isRemoteVideoEnabled;
  final bool isOpponentLocallySilenced;
  final bool amISilencedByOpponent;

  SnakeGameState({
    this.playerPosition = 0,
    this.diceValue = 1,
    this.isRolling = false,
    this.isMoving = false,
    this.hasStarted = false,
    this.gameStatus = "Roll a 1 to enter the board!",
    this.snakes = const {},
    this.ladders = const {},
    this.opponentPosition = 0,
    this.isMultiplayer = false,
    this.isMyTurn = true,
    this.roomId,
    this.myUserId,
    this.opponentUserId,
    this.isCallStarted = false,
    this.callStatus = "Initializing...",
    this.isLocalAudioMuted = false,
    this.isLocalVideoEnabled = false,
    this.isRemoteAudioMuted = false,
    this.isRemoteVideoEnabled = false,
    this.isOpponentLocallySilenced = false,
    this.amISilencedByOpponent = false,
  });

  SnakeGameState copyWith({
    int? playerPosition,
    int? diceValue,
    bool? isRolling,
    bool? isMoving,
    bool? hasStarted,
    String? gameStatus,
    Map<int, int>? snakes,
    Map<int, int>? ladders,
    int? opponentPosition,
    bool? isMultiplayer,
    bool? isMyTurn,
    int? roomId,
    int? myUserId,
    int? opponentUserId,
    bool? isCallStarted,
    String? callStatus,
    bool? isLocalAudioMuted,
    bool? isLocalVideoEnabled,
    bool? isRemoteAudioMuted,
    bool? isRemoteVideoEnabled,
    bool? isOpponentLocallySilenced,
    bool? amISilencedByOpponent,
  }) {
    return SnakeGameState(
      playerPosition: playerPosition ?? this.playerPosition,
      diceValue: diceValue ?? this.diceValue,
      isRolling: isRolling ?? this.isRolling,
      isMoving: isMoving ?? this.isMoving,
      hasStarted: hasStarted ?? this.hasStarted,
      gameStatus: gameStatus ?? this.gameStatus,
      snakes: snakes ?? this.snakes,
      ladders: ladders ?? this.ladders,
      opponentPosition: opponentPosition ?? this.opponentPosition,
      isMultiplayer: isMultiplayer ?? this.isMultiplayer,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      roomId: roomId ?? this.roomId,
      myUserId: myUserId ?? this.myUserId,
      opponentUserId: opponentUserId ?? this.opponentUserId,
      isCallStarted: isCallStarted ?? this.isCallStarted,
      callStatus: callStatus ?? this.callStatus,
      isLocalAudioMuted: isLocalAudioMuted ?? this.isLocalAudioMuted,
      isLocalVideoEnabled: isLocalVideoEnabled ?? this.isLocalVideoEnabled,
      isRemoteAudioMuted: isRemoteAudioMuted ?? this.isRemoteAudioMuted,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      isOpponentLocallySilenced:
          isOpponentLocallySilenced ?? this.isOpponentLocallySilenced,
      amISilencedByOpponent:
          amISilencedByOpponent ?? this.amISilencedByOpponent,
    );
  }
}

class SnakeGameNotifier extends Notifier<SnakeGameState> {
  StreamSubscription? _socketSubscription;
  StreamSubscription? _socketConnSub;
  SignalingService? _signalingService;

  @override
  SnakeGameState build() {
    ref.onDispose(() {
      _socketSubscription?.cancel();
      _socketConnSub?.cancel();
    });
    return SnakeGameState();
  }

  void initBoard(
    Map<int, int> snakes,
    Map<int, int> ladders, {
    int? roomId,
    bool isMultiplayer = false,
    int? myUserId,
    bool startsMyTurn = true,
    SignalingService? signalingService,
  }) {
    _signalingService = signalingService;
    _signalingService?.onCustomMessageStream.listen((data) {
      if (data['action'] == 'local_silence_toggle') {
        state = state.copyWith(amISilencedByOpponent: data['isSilenced']);
      }
    });

    // Reset everything to defaults first to ensure a clean board
    state = SnakeGameState(
      snakes: snakes,
      ladders: ladders,
      roomId: roomId,
      isMultiplayer: isMultiplayer,
      myUserId: myUserId,
      isMyTurn: !isMultiplayer || startsMyTurn,
      // Preserve call info if it was already connecting?
      // Usually initBoard is called once per screen entry
      callStatus: state.callStatus,
      isCallStarted: state.isCallStarted,
    );

    if (isMultiplayer && roomId != null) {
      _connectSocket(roomId);
    }
  }

  void _connectSocket(int roomId) {
    _socketSubscription?.cancel();
    _socketConnSub?.cancel();
    final socketService = GameWebsocketService();
    // Force reconnect if we are entering the board fresh, even if the room_id is the same (rematch)
    socketService.connect(roomId, forceReconnect: true);

    _socketConnSub = socketService.connectionStream.listen((connected) {
      if (connected && state.myUserId != null) {
        socketService.sendJoin(roomId, state.myUserId!);
      }
    });

    _socketSubscription = socketService.stream.listen((data) {
      if (data['type'] == 'move') {
        print("[SNAKE SYNC] Move received: $data");
        _handleOpponentMove(data);
      } else if (data['type'] == 'reset') {
        resetGame(remote: true);
      } else if (data['type'] == 'user_left' ||
          data['type'] == 'player_left' ||
          data['type'] == 'leave') {
        print(
          "[SNAKE SYNC] Opponent left detected (message: ${data['type']}): $data",
        );
        final senderId = data['user_id']?.toString();
        if (senderId == null || senderId != state.myUserId?.toString()) {
          state = state.copyWith(
            gameStatus: "Opponent Resigned/Left board",
            isMyTurn: false,
          );
        }
      }
    });
  }

  void _handleOpponentMove(Map<String, dynamic> data) {
    final senderId = data['sender_id'];
    if (senderId == state.myUserId) return;

    final diceValue = data['from_row'];
    final targetPos = data['to_row'];

    state = state.copyWith(
      diceValue: diceValue,
      isMyTurn: true,
      gameStatus: "Opponent rolled $diceValue!",
    );

    print(
      "[SNAKE SYNC] Applying remote move: Dice=$diceValue, TargetPos=$targetPos, OldOpponentPos=${state.opponentPosition}",
    );
    // Update opponent position
    _moveOpponent(targetPos);
  }

  Future<void> _moveOpponent(int targetPos) async {
    if (state.opponentPosition == targetPos) return;

    state = state.copyWith(isMoving: true);

    // Animate movement if it's a normal move (optional, but better)
    // For now, let's at least handle it step by step if it's forward
    if (targetPos > state.opponentPosition &&
        targetPos - state.opponentPosition <= 6) {
      int steps = targetPos - state.opponentPosition;
      for (int i = 0; i < steps; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        state = state.copyWith(opponentPosition: state.opponentPosition + 1);
      }
    } else {
      // Jump for snakes/ladders or if too far
      state = state.copyWith(opponentPosition: targetPos);
    }

    state = state.copyWith(isMoving: false);
  }

  Future<void> rollDice() async {
    if (state.isRolling || state.isMoving) return;
    if (state.isMultiplayer && !state.isMyTurn) {
      state = state.copyWith(gameStatus: "Wait for opponent's turn!");
      return;
    }

    state = state.copyWith(isRolling: true, gameStatus: "Waiting for luck...");

    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 70));
      state = state.copyWith(diceValue: Random().nextInt(6) + 1);
    }

    state = state.copyWith(isRolling: false);
    await handleGameLogic(state.diceValue);
  }

  Future<void> handleGameLogic(int roll) async {
    int startPos = state.playerPosition;
    if (!state.hasStarted) {
      state = state.copyWith(hasStarted: true);
    }
    await movePlayerSequence(roll, startPos);
  }

  Future<void> movePlayerSequence(int steps, int startPos) async {
    state = state.copyWith(isMoving: true);
    int target = state.playerPosition + steps;
    if (target > 100) {
      state = state.copyWith(
        gameStatus: "Too far! Need exact roll.",
        isMoving: false,
      );
      _finalizeTurn(startPos, state.playerPosition);
      return;
    }
    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      state = state.copyWith(playerPosition: state.playerPosition + 1);
    }
    await checkSquareEffect(startPos);
  }

  Future<void> checkSquareEffect(int startPos) async {
    state = state.copyWith(isMoving: true);
    await Future.delayed(const Duration(milliseconds: 500));

    if (state.snakes.containsKey(state.playerPosition)) {
      int endPos = state.snakes[state.playerPosition]!;
      state = state.copyWith(gameStatus: "SNAGGED BY A SNAKE!");
      await Future.delayed(const Duration(milliseconds: 800));
      state = state.copyWith(playerPosition: endPos);
      await Future.delayed(const Duration(milliseconds: 400));
      state = state.copyWith(gameStatus: "Ouch. Dropped to $endPos.");
    } else if (state.ladders.containsKey(state.playerPosition)) {
      int endPos = state.ladders[state.playerPosition]!;
      state = state.copyWith(gameStatus: "LADDER ASCEND!");
      await Future.delayed(const Duration(milliseconds: 800));
      state = state.copyWith(playerPosition: endPos);
      await Future.delayed(const Duration(milliseconds: 400));
      state = state.copyWith(gameStatus: "Climbed to $endPos!");
    } else if (state.playerPosition == 100) {
      state = state.copyWith(gameStatus: "👑 CHAMPION! 👑");
    } else {
      state = state.copyWith(gameStatus: "Your move. Roll again!");
    }
    state = state.copyWith(isMoving: false);

    _finalizeTurn(startPos, state.playerPosition);
  }

  void _finalizeTurn(int oldPos, int newPos) {
    if (state.isMultiplayer && state.isMyTurn) {
      // Send move to opponent
      final socketService = GameWebsocketService();
      if (state.roomId != null && state.myUserId != null) {
        socketService.sendMove(
          state.roomId!,
          state.myUserId!,
          state.diceValue, // from_row
          oldPos, // from_col (Need to capture oldPos)
          newPos, // to_row
          0, // to_col
        );
        state = state.copyWith(
          isMyTurn: false,
          gameStatus: "Waiting for opponent...",
        );
      }
    } else {
      state = state.copyWith(isMyTurn: false, gameStatus: "Turn ended.");
    }
  }

  // Call management methods
  void setCallStarted(bool val) => state = state.copyWith(isCallStarted: val);
  void setCallStatus(String val) => state = state.copyWith(callStatus: val);
  void setLocalAudioMuted(bool val) =>
      state = state.copyWith(isLocalAudioMuted: val);
  void setLocalVideoEnabled(bool val) =>
      state = state.copyWith(isLocalVideoEnabled: val);
  void setRemoteAudioMuted(bool val) =>
      state = state.copyWith(isRemoteAudioMuted: val);
  void setRemoteVideoEnabled(bool val) =>
      state = state.copyWith(isRemoteVideoEnabled: val);
  void setOpponentLocallySilenced(bool val) {
    state = state.copyWith(isOpponentLocallySilenced: val);

    // 1. Mute/Unmute the remote audio tracks locally
    final remoteStream = _signalingService?.remoteStreamNotifier.value;
    if (remoteStream != null) {
      for (var track in remoteStream.getAudioTracks()) {
        track.enabled = !val; // Track enabled = NOT silenced
      }
    }

    // 2. Notify peer via signaling
    _signalingService?.sendCustomMessage({
      'action': 'local_silence_toggle',
      'isSilenced': val,
    });
  }

  void setAmISilencedByOpponent(bool val) =>
      state = state.copyWith(amISilencedByOpponent: val);

  void resetGame({bool remote = false}) {
    state = state.copyWith(
      playerPosition: 0,
      opponentPosition: 0,
      hasStarted: false,
      isMoving: false,
      isRolling: false,
      isMyTurn: true,
      gameStatus: "Roll a 1 to enter the board!",
    );

    if (!remote && state.isMultiplayer && state.roomId != null) {
      GameWebsocketService().resetGame(state.roomId!);
    }
  }
}

final snakeGameProvider = NotifierProvider<SnakeGameNotifier, SnakeGameState>(
  () {
    return SnakeGameNotifier();
  },
);
