import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
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

  // Exact Reference Mapping
  final Map<int, int> snakes = {
    17: 7,   // Purple (Bottom)
    54: 34,  // Orange/Yellow
    62: 19,  // Large Green
    64: 60,  // Small Brown
    87: 36,  // Orange Patterned
    93: 73,  // Purple Slender
    95: 75,  // Yellow/Brown
    98: 78,  // Green Slender
  };

  final Map<int, int> ladders = {
    1: 38,
    4: 14,
    9: 31,
    21: 42,
    28: 84,
    36: 44,
    51: 67,
    71: 91,
    80: 99,
  };

  // Color Palette - Exact Reference Sequence
  final List<Color> cellColors = [
    const Color(0xFFFFEB3B), // Yellow (1)
    Colors.white,           // White (2)
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
    // Darker colors get white text
    if (bg == const Color(0xFFF44336) || bg == const Color(0xFF2196F3) || bg == const Color(0xFF4CAF50)) {
      return Colors.white;
    }
    return Colors.black87;
  }

  Future<void> rollDice() async {
    if (isRolling || isMoving) return;

    setState(() {
      isRolling = true;
      gameStatus = "Waiting for luck...";
    });

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
        title: const Text("Restart Game?", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        content: const Text("Your current progress will be lost.", style: TextStyle(color: Colors.black54)),
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
            child: const Text("RESTART", style: TextStyle(color: Colors.deepOrange)),
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
        title: const Center(child: Text("YOU DID IT!", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
        content: const Text("The board has been conquered.", textAlign: TextAlign.center, style: TextStyle(color: Colors.black87)),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                resetGame();
              },
              child: const Text("NEW ADVENTURE", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute),
        ),
        title: const Text('RETRO BOARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 4,
        actions: [
          IconButton(
            onPressed: _showResetConfirmation,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
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
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
                  ],
                ),
                padding: const EdgeInsets.all(2), // Board frame thickness
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double cellSize = constraints.maxWidth / gridSize;
                    return Stack(
                      children: [
                        // 1. Colorful Cells Grid
                        Positioned.fill(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: totalSquares,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridSize),
                            itemBuilder: (context, index) {
                              int cellRow = index ~/ gridSize;
                              int cellCol = index % gridSize;
                              int dRow = 9 - cellRow;
                              int dCol = (dRow % 2 == 1) ? (9 - cellCol) : cellCol;
                              int num = dRow * 10 + dCol + 1;
                              return Container(
                                decoration: BoxDecoration(
                                  color: num == 100 ? const Color(0xFFF44336) : _getCellColor(num),
                                  border: Border.all(color: Colors.black, width: 0.8),
                                ),
                                child: Stack(
                                  children: [
                                    if (num == 100)
                                      const Center(
                                        child: Icon(Icons.star, color: Color(0xFFFFEB3B), size: 30),
                                      ),
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Text(
                                          '$num',
                                          style: TextStyle(
                                            color: _getTextColor(num),
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
                              snakes: snakes,
                              ladders: ladders,
                              gridSize: gridSize,
                            ),
                          ),
                        ),
                        // 3. Player Token
                        Builder(builder: (context) {
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
                                    width: cellSize * 0.7,
                                    height: cellSize * 0.7,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 5)],
                                      border: Border.all(color: Colors.black, width: 2),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.stars, size: 20, color: Colors.orange),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -3))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gameStatus.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w800),
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
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))],
                      ),
                      child: Center(
                        child: isRolling
                            ? const CircularProgressIndicator(color: Colors.black87)
                            : CustomPaint(size: const Size(40, 40), painter: DiceDotsPainter(value: diceValue)),
                      ),
                    ),
                    const SizedBox(width: 30),
                    GestureDetector(
                      onTap: (isRolling || isMoving) ? null : rollDice,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                        decoration: BoxDecoration(
                          color: (isRolling || isMoving) ? Colors.grey : Colors.black87,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          "ROLL",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
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

class RetroBoardLinesPainter extends CustomPainter {
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final int gridSize;

  RetroBoardLinesPainter({required this.snakes, required this.ladders, required this.gridSize});

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
    final railPaint = Paint()..color = Colors.black87..strokeWidth = 3.5..strokeCap = StrokeCap.square..style = PaintingStyle.stroke;
    final stepPaint = Paint()..color = Colors.black87..strokeWidth = 2.5;

    ladders.forEach((s, e) {
      Offset p1 = getC(s);
      Offset p2 = getC(e);
      double dx = p2.dx - p1.dx, dy = p2.dy - p1.dy;
      double len = sqrt(dx*dx + dy*dy);
      Offset perp = Offset(-dy/len, dx/len) * (cell * 0.2);

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
      _drawRealisticSnake(canvas, getC(entry.key), getC(entry.value), cell, 
        baseColor: snakeColors[entry.key] ?? Colors.green);
    }
  }

  void _drawRealisticSnake(Canvas canvas, Offset head, Offset tail, double cellSize, {required Color baseColor}) {
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
    
    // 1. Slender Shadow/Outline
    final outlinePaint = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    
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
        pathMetric.extractPath(pathMetric.length * startPercent, pathMetric.length * endPercent),
        Paint()
          ..color = Color.lerp(baseColor.withOpacity(0.9), baseColor, progress)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
      );
      
      // B. Layer: Belly Stripe (Simulating depth)
      if (strokeWidth > 4) {
        canvas.drawPath(
          pathMetric.extractPath(pathMetric.length * startPercent, pathMetric.length * endPercent),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.35
            ..strokeCap = StrokeCap.round
        );
      }
      
      // C. Layer: Spine Pattern (Zig-zag/Dots)
      if (i % 2 == 0) {
        canvas.drawPath(
          pathMetric.extractPath(pathMetric.length * startPercent, pathMetric.length * endPercent),
          Paint()
            ..color = Colors.black.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.2
        );
      }
    }

    // 3. Realistic Illustrator Head
    ui.Tangent? tangent = pathMetric.getTangentForOffset(0);
    if (tangent != null) {
      double angle = atan2(tangent.vector.dy, tangent.vector.dx) + pi;
      double headScale = (cellSize / 38).clamp(0.5, 0.85); // More slender head
      
      canvas.save();
      canvas.translate(head.dx, head.dy);
      canvas.rotate(angle);
      canvas.scale(headScale);

      // Wider Jaw & Pointed Snout
      Path headPath = Path();
      headPath.moveTo(0, 0); 
      headPath.quadraticBezierTo(2, -14, 12, -10); // Wide jaw base
      headPath.quadraticBezierTo(26, -6, 30, 0);   // Fine snout
      headPath.quadraticBezierTo(26, 6, 12, 10);   // Jaw symmetry
      headPath.quadraticBezierTo(2, 14, 0, 0); 
      
      canvas.drawPath(headPath, Paint()..color = baseColor);
      canvas.drawPath(headPath, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.4);

      // Refined Eyes (Side-facing predatory placement)
      canvas.drawCircle(const Offset(14, -6), 3.0, Paint()..color = Colors.black);
      canvas.drawCircle(const Offset(15.5, -7.5), 0.8, Paint()..color = Colors.white); // Glint
      canvas.drawCircle(const Offset(14, 6), 3.0, Paint()..color = Colors.black);
      canvas.drawCircle(const Offset(15.5, 7.5), 0.8, Paint()..color = Colors.white); // Glint

      // Long Forked Tongue
      final tonguePaint = Paint()..color = Colors.red..strokeWidth = 1.8..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
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
    void dot(double x, double y) => canvas.drawCircle(Offset(size.width * x, size.height * y), r, p);
    if (value % 2 == 1) dot(0.5, 0.5);
    if (value > 1) { dot(0.22, 0.22); dot(0.78, 0.78); }
    if (value > 3) { dot(0.78, 0.22); dot(0.22, 0.78); }
    if (value == 6) { dot(0.22, 0.5); dot(0.78, 0.5); }
  }

  @override
  bool shouldRepaint(CustomPainter old) => true;
}
