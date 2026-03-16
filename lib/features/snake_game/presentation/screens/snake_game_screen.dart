import 'dart:async';
import 'dart:math';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:flutter/material.dart';

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<SnakeGameScreen>
    with TickerProviderStateMixin {
  // Game constants
  static const int gridSize = 10;
  static const int totalSquares = gridSize * gridSize;

  // Game state
  int playerPosition = 0; // 0 means not on board
  int diceValue = 1;
  bool isRolling = false;
  bool isMoving = false;
  bool hasStarted = false;
  String gameStatus = "Roll a 1 to enter the board!";

  // Standard Snakes and Ladders
  final Map<int, int> snakes = {
    17: 7,
    54: 34,
    62: 19,
    64: 60,
    87: 24,
    93: 73,
    95: 75,
    99: 78,
  };

  final Map<int, int> ladders = {
    4: 14,
    9: 31,
    21: 42,
    28: 84,
    36: 44,
    51: 67,
    71: 91,
    80: 100,
  };

  Future<void> rollDice() async {
    if (isRolling || isMoving) return;

    setState(() {
      isRolling = true;
      gameStatus = "Waiting for luck...";
    });

    // Dice animation
    for (int i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 70));
      setState(() {
        diceValue = Random().nextInt(6) + 1;
      });
    }

    setState(() {
      isRolling = false;
    });

    await handleGameLogic(diceValue);
  }

  Future<void> handleGameLogic(int roll) async {
    if (!hasStarted) {
      if (roll == 1) {
        setState(() {
          isMoving = true;
          hasStarted = true;
          playerPosition = 1;
          gameStatus = "Warming up on Square 1!";
        });
        await Future.delayed(const Duration(milliseconds: 800));
        await checkSquareEffect();
      } else {
        setState(() {
          gameStatus = "Almost! Roll a 1 to start.";
        });
      }
      return;
    }
    await movePlayerSequence(roll);
  }

  Future<void> movePlayerSequence(int steps) async {
    setState(() => isMoving = true);
    int target = playerPosition + steps;
    if (target > totalSquares) {
      setState(() {
        gameStatus = "Too far! Need exact roll.";
        isMoving = false;
      });
      return;
    }
    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        playerPosition++;
      });
    }
    await checkSquareEffect();
  }

  Future<void> checkSquareEffect() async {
    setState(() => isMoving = true);
    await Future.delayed(const Duration(milliseconds: 500));

    if (snakes.containsKey(playerPosition)) {
      int endPos = snakes[playerPosition]!;
      setState(() => gameStatus = "SNAGGED BY A SNAKE!");
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() => playerPosition = endPos);
      await Future.delayed(const Duration(milliseconds: 400));
      setState(() => gameStatus = "Ouch. Dropped to $endPos.");
    } else if (ladders.containsKey(playerPosition)) {
      int endPos = ladders[playerPosition]!;
      setState(() => gameStatus = "LADDER ASCEND!");
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() => playerPosition = endPos);
      await Future.delayed(const Duration(milliseconds: 400));
      setState(() => gameStatus = "Climbed to $endPos!");
    } else if (playerPosition == totalSquares) {
      setState(() => gameStatus = "👑 CHAMPION! 👑");
      _showWinDialog();
    } else {
      setState(() => gameStatus = "Your move. Roll again!");
    }
    setState(() => isMoving = false);
  }

  void resetGame() {
    setState(() {
      playerPosition = 0;
      hasStarted = false;
      isMoving = false;
      isRolling = false;
      gameStatus = "Roll a 1 to enter the board!";
    });
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
              resetGame();
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
                resetGame();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: whiteColor),
          onPressed: () =>
              RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute),
        ),
        title: const Text(
          'SNAKE & LADDERS',
          style: TextStyle(
            color: whiteColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor,
        foregroundColor: whiteColor,

        elevation: 1,
        actions: [
          IconButton(
            onPressed: _showResetConfirmation,
            icon: const Icon(Icons.refresh, color: whiteColor),
          ),
        ],
      ),
      body: Column(
        children: [
          const Spacer(flex: 1),
          // Board Area - Maximized Size
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double cellSize = constraints.maxWidth / gridSize;
                    return Stack(
                      children: [
                        // 1. Grid Background (Subtle)
                        Positioned.fill(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: totalSquares,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridSize,
                                ),
                            itemBuilder: (context, index) => Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.05),
                                  width: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 2. Connections Painter
                        Positioned.fill(
                          child: CustomPaint(
                            painter: BoardLinesPainter(
                              snakes: snakes,
                              ladders: ladders,
                              gridSize: gridSize,
                            ),
                          ),
                        ),
                        // 3. Numbers Layer (On top, bold black)
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
                              bool hl = num == 100 || num == 1;
                              return Center(
                                child: Text(
                                  '$num',
                                  style: TextStyle(
                                    color: hl ? Colors.orange : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: hl
                                        ? FontWeight.w100
                                        : FontWeight.w800,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // 4. Player Token
                        Builder(
                          builder: (context) {
                            Offset p = getCoord(playerPosition);
                            return AnimatedPositioned(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut,
                              left: p.dx * cellSize,
                              top: p.dy * cellSize,
                              child: SizedBox(
                                width: cellSize,
                                height: cellSize,
                                child: Center(
                                  child: Opacity(
                                    opacity: playerPosition == 0 ? 0.3 : 1.0,
                                    child: Container(
                                      width: cellSize * 0.75,
                                      height: cellSize * 0.75,
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.orange.withOpacity(
                                              0.4,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.person,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
          // Controls Area - Light Theme
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 35),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gameStatus.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dice Container
                    Container(
                      width: 85,
                      height: 85,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isRolling
                            ? const SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                  color: Colors.orange,
                                ),
                              )
                            : CustomPaint(
                                size: const Size(42, 42),
                                painter: DiceDotsPainter(value: diceValue),
                              ),
                      ),
                    ),
                    const SizedBox(width: 35),
                    // Roll Button - Vibrant Orange
                    GestureDetector(
                      onTap: (isRolling || isMoving) ? null : rollDice,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 45,
                          vertical: 22,
                        ),
                        decoration: BoxDecoration(
                          color: (isRolling || isMoving)
                              ? Colors.grey.shade200
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: (isRolling || isMoving)
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.35),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                        ),
                        child: Text(
                          (isRolling || isMoving) ? "..." : "ROLL DICE",
                          style: TextStyle(
                            color: (isRolling || isMoving)
                                ? Colors.grey
                                : Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BoardLinesPainter extends CustomPainter {
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final int gridSize;

  BoardLinesPainter({
    required this.snakes,
    required this.ladders,
    required this.gridSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    double cell = size.width / gridSize;

    Offset center(int n) {
      int sq = n - 1;
      int r = sq ~/ gridSize;
      int c = sq % gridSize;
      if (r % 2 == 1) c = (gridSize - 1) - c;
      r = (gridSize - 1) - r;
      return Offset(c * cell + cell / 2, r * cell + cell / 2);
    }

    // Ladders (Solid Royal Blue)
    final lPaint = Paint()
      ..color = const Color(0xFF1976D2).withOpacity(0.7)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    ladders.forEach((s, e) {
      Offset p1 = center(s);
      Offset p2 = center(e);
      canvas.drawLine(p1, p2, lPaint);
      // Rungs
      final rPaint = Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..strokeWidth = 2.5;
      for (int i = 1; i < 7; i++) {
        Offset p = Offset.lerp(p1, p2, i / 7)!;
        double dx = p2.dx - p1.dx, dy = p2.dy - p1.dy;
        double len = sqrt(dx * dx + dy * dy);
        Offset perp = Offset(-dy / len, dx / len) * 11;
        canvas.drawLine(p - perp, p + perp, rPaint);
      }
    });

    // Snakes (Vivid Red)
    final sPaint = Paint()
      ..color = Colors.red.shade700.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    snakes.forEach((s, e) {
      Offset h = center(s), t = center(e);
      Path path = Path()..moveTo(h.dx, h.dy);
      double midY = (h.dy + t.dy) / 2,
          cX = (t.dx > h.dx) ? cell * 1.2 : -cell * 1.2;
      Offset c1 = Offset((h.dx + cX).clamp(0, size.width), midY - 12);
      Offset c2 = Offset((t.dx - cX).clamp(0, size.width), midY + 12);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, t.dx, t.dy);
      canvas.drawPath(path, sPaint);
      canvas.drawCircle(h, 4, Paint()..color = Colors.black); // Head
    });
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

class DiceDotsPainter extends CustomPainter {
  final int value;
  DiceDotsPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black87;
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
