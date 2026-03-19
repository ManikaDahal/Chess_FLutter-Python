import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SnakeGameState {
  final int playerPosition;
  final int diceValue;
  final bool isRolling;
  final bool isMoving;
  final bool hasStarted;
  final String gameStatus;
  final Map<int, int> snakes;
  final Map<int, int> ladders;

  SnakeGameState({
    this.playerPosition = 0,
    this.diceValue = 1,
    this.isRolling = false,
    this.isMoving = false,
    this.hasStarted = false,
    this.gameStatus = "Roll a 1 to enter the board!",
    this.snakes = const {},
    this.ladders = const {},
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
    );
  }
}

class SnakeGameNotifier extends Notifier<SnakeGameState> {
  @override
  SnakeGameState build() {
    return SnakeGameState();
  }

  void initBoard(Map<int, int> snakes, Map<int, int> ladders) {
    state = state.copyWith(snakes: snakes, ladders: ladders);
  }

  Future<void> rollDice() async {
    if (state.isRolling || state.isMoving) return;

    state = state.copyWith(
      isRolling: true,
      gameStatus: "Waiting for luck...",
    );

    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 70));
      state = state.copyWith(diceValue: Random().nextInt(6) + 1);
    }

    state = state.copyWith(isRolling: false);
    await handleGameLogic(state.diceValue);
  }

  Future<void> handleGameLogic(int roll) async {
    if (!state.hasStarted) {
      if (roll == 1) {
        state = state.copyWith(
          isMoving: true,
          hasStarted: true,
          playerPosition: 1,
          gameStatus: "Warming up on Square 1!",
        );
        await Future.delayed(const Duration(milliseconds: 800));
        await checkSquareEffect();
      } else {
        state = state.copyWith(gameStatus: "Almost! Roll a 1 to start.");
      }
      return;
    }
    await movePlayerSequence(roll);
  }

  Future<void> movePlayerSequence(int steps) async {
    state = state.copyWith(isMoving: true);
    int target = state.playerPosition + steps;
    if (target > 100) {
      state = state.copyWith(
        gameStatus: "Too far! Need exact roll.",
        isMoving: false,
      );
      return;
    }
    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      state = state.copyWith(playerPosition: state.playerPosition + 1);
    }
    await checkSquareEffect();
  }

  Future<void> checkSquareEffect() async {
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
  }

  void resetGame() {
    state = state.copyWith(
      playerPosition: 0,
      hasStarted: false,
      isMoving: false,
      isRolling: false,
      gameStatus: "Roll a 1 to enter the board!",
    );
  }
}

final snakeGameProvider = NotifierProvider<SnakeGameNotifier, SnakeGameState>(() {
  return SnakeGameNotifier();
});
