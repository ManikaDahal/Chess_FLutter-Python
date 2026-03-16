import 'dart:async';
import 'dart:math';
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

    // Normal movement
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

    // Move square by square
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

  void _showWinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Center(
          child: Text(
            "YOU DID IT!",
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
        ),
        content: const Text(
          "The board has been conquered.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
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
                style: TextStyle(color: Colors.amber),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset getCoord(int index) {
    if (index <= 0) return const Offset(0, 9); // Square 1 spot
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
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'LEGENDARY SNAKE & LADDERS',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w100),
        ),
        actions: [
          IconButton(
            onPressed: resetGame,
            icon: const Icon(Icons.refresh, color: Colors.white24),
          ),
        ],
      ),
      body: Column(
        children: [
          // Board Area
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.05),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double cellSize = constraints.maxWidth / gridSize;

                      return Stack(
                        children: [
                          // 1. Grid Cells Gradient Background
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
                                    color: Colors.white.withOpacity(0.02),
                                    width: 0.5,
                                  ),
                                  color: (index % 2 == 0)
                                      ? Colors.white.withOpacity(0.01)
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                          ),

                          // 2. Connections Painter (Snakes and Ladders)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: BoardLinesPainter(
                                snakes: snakes,
                                ladders: ladders,
                                gridSize: gridSize,
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                          ),

                          // 3. Numbers Layer (On top of lines)
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
                                      color: hl
                                          ? Colors.amber
                                          : Colors.white.withOpacity(0.6),
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
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
                                duration: const Duration(milliseconds: 300),
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
                                        width: cellSize * 0.7,
                                        height: cellSize * 0.7,
                                        decoration: BoxDecoration(
                                          color: Colors.amber,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.amber.withOpacity(
                                                0.5,
                                              ),
                                              blurRadius: 10,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_pin,
                                          size: 18,
                                          color: Colors.black,
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
          ),

          // Controls Area
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    gameStatus.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dice
                      GestureDetector(
                        onTap: (isRolling || isMoving) ? null : rollDice,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: isRolling
                                ? const SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 5,
                                      color: Colors.amber,
                                    ),
                                  )
                                : CustomPaint(
                                    size: const Size(40, 40),
                                    painter: DiceDotsPainter(value: diceValue),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 30),
                      // Roll Instruction
                      Text(
                        (isRolling || isMoving) ? "BUSY..." : "TAP TO ROLL",
                        style: TextStyle(
                          color: (isRolling || isMoving)
                              ? Colors.white10
                              : Colors.amber,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
  final Color color;

  BoardLinesPainter({
    required this.snakes,
    required this.ladders,
    required this.gridSize,
    required this.color,
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

    // Ladders (Blue)
    final lPaint = Paint()
      ..color = Colors.blue.withOpacity(0.4)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    ladders.forEach((s, e) {
      Offset p1 = center(s);
      Offset p2 = center(e);
      canvas.drawLine(p1, p2, lPaint);

      // Rungs
      final rPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 2;
      for (int i = 1; i < 6; i++) {
        Offset p = Offset.lerp(p1, p2, i / 6)!;
        double dx = p2.dx - p1.dx;
        double dy = p2.dy - p1.dy;
        double len = sqrt(dx * dx + dy * dy);
        Offset perp = Offset(-dy / len, dx / len) * 10;
        canvas.drawLine(p - perp, p + perp, rPaint);
      }
    });

    // Snakes (Red)
    final sPaint = Paint()
      ..color = Colors.red.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    snakes.forEach((s, e) {
      Offset h = center(s);
      Offset t = center(e);

      Path path = Path();
      path.moveTo(h.dx, h.dy);

      double midY = (h.dy + t.dy) / 2;
      double curveX = (t.dx > h.dx) ? cell : -cell;

      // Clamp control points to board size
      Offset c1 = Offset((h.dx + curveX).clamp(0, size.width), midY - 10);
      Offset c2 = Offset((t.dx - curveX).clamp(0, size.width), midY + 10);

      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, t.dx, t.dy);
      canvas.drawPath(path, sPaint);
      // Small eyes at head
      canvas.drawCircle(h, 3, Paint()..color = Colors.black38);
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
    final p = Paint()..color = Colors.black;
    final r = size.width * 0.12;
    void dot(double x, double y) =>
        canvas.drawCircle(Offset(size.width * x, size.height * y), r, p);

    if (value % 2 == 1) dot(0.5, 0.5);
    if (value > 1) {
      dot(0.2, 0.2);
      dot(0.8, 0.8);
    }
    if (value > 3) {
      dot(0.8, 0.2);
      dot(0.2, 0.8);
    }
    if (value == 6) {
      dot(0.2, 0.5);
      dot(0.8, 0.5);
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}
