import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/ads/ad_service.dart';
import 'package:flutter/material.dart';

import 'package:chess_game_manika/features/snake_game/models/snake_board.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/snake_game/presentation/providers/snake_game_provider.dart';

class SnakeGameScreen extends ConsumerStatefulWidget {
  final SnakeBoard board;
  const SnakeGameScreen({super.key, required this.board});

  @override
  ConsumerState<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends ConsumerState<SnakeGameScreen>
    with TickerProviderStateMixin {
  // Game constants
  static const int gridSize = 10;
  static const int totalSquares = gridSize * gridSize;

  @override
  void initState() {
    super.initState();
    // Initialize provider with board data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(snakeGameProvider.notifier).initBoard(
        widget.board.snakes,
        widget.board.ladders,
      );
    });
  }

  // Color Palette - Exact Reference Sequence
  final List<Color> cellColors = [
    const Color(0xFFFFEB3B), // Yellow (1)
    Colors.white, // White (2)
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
    if (bg == const Color(0xFFF44336) ||
        bg == const Color(0xFF2196F3) ||
        bg == const Color(0xFF4CAF50)) {
      return Colors.white;
    }
    return Colors.black87;
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
              ref.read(snakeGameProvider.notifier).resetGame();
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
                ref.read(snakeGameProvider.notifier).resetGame();
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


  Widget build(BuildContext context) {
    ref.listen(snakeGameProvider, (previous, next) {
      if (next.playerPosition == totalSquares &&
          (previous?.playerPosition ?? 0) != totalSquares) {
        _showWinDialog();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFEEEEEE),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.board.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
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
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2), // Board frame thickness
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double cellSize = constraints.maxWidth / gridSize;
                    return Stack(
                      children: [
                        // 0. Background Image (if board config has one)
                        if (widget.board.imagePath != null)
                          Positioned.fill(
                            child: Image.asset(
                              widget.board.imagePath!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        // 1. Colorful Cells Grid (Hide colors if image is present)
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
                              return Container(
                                decoration: BoxDecoration(
                                  color: widget.board.imagePath != null
                                      ? Colors.transparent
                                      : (num == 100
                                            ? const Color(0xFFF44336)
                                            : _getCellColor(num)),
                                  border: Border.all(
                                    color: widget.board.imagePath != null
                                        ? Colors.transparent
                                        : Colors.black,
                                    width: 0.8,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    if (num == 100)
                                      const Center(
                                        child: Icon(
                                          Icons.star,
                                          color: Color(0xFFFFEB3B),
                                          size: 30,
                                        ),
                                      ),
                                    Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Text(
                                          '$num',
                                          style: TextStyle(
                                            color:
                                                widget.board.imagePath != null
                                                ? _getTextColor(
                                                    num,
                                                  ).withOpacity(0.0)
                                                : _getTextColor(num),
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
                              snakes: widget.board.imagePath != null
                                  ? {}
                                  : widget.board.snakes,
                              ladders: widget.board.imagePath != null
                                  ? {}
                                  : widget.board.ladders,
                              gridSize: gridSize,
                            ),
                          ),
                        ),
                        // 3. Player Token
                        Builder(
                          builder: (context) {
                            final gameState = ref.watch(snakeGameProvider);
                            Offset p = getCoord(gameState.playerPosition);
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
                                    opacity: gameState.playerPosition == 0 ? 0.3 : 1.0,
                                    child: Container(
                                      width: cellSize * 0.7,
                                      height: cellSize * 0.7,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black45,
                                            blurRadius: 5,
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.black,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.stars,
                                          size: 20,
                                          color: Colors.orange,
                                        ),
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
          // Controls Area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ref.watch(snakeGameProvider).gameStatus.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: ref.watch(snakeGameProvider).isRolling
                            ? const CircularProgressIndicator(
                                color: Colors.black87,
                              )
                            : CustomPaint(
                                size: const Size(40, 40),
                                painter: DiceDotsPainter(value: ref.watch(snakeGameProvider).diceValue),
                              ),
                      ),
                    ),
                    const SizedBox(width: 30),
                    GestureDetector(
                      onTap: () {
                         final state = ref.read(snakeGameProvider);
                         if (state.isRolling || state.isMoving) return;
                         ref.read(snakeGameProvider.notifier).rollDice();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: (ref.watch(snakeGameProvider).isRolling || ref.watch(snakeGameProvider).isMoving)
                              ? Colors.grey
                              : Colors.black87,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          "ROLL",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // const SizedBox(height: 20),
                // GestureDetector(
                //   onTap: () {
                //     AdService().showRewardedAd(
                //       onUserEarnedReward: (reward) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //           SnackBar(content: Text('Reward Earned: ${reward.amount} ${reward.type}')),
                //         );
                //       },
                //     );
                //   },
                //   child: Container(
                //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                //     decoration: BoxDecoration(
                //       color: Colors.orange,
                //       borderRadius: BorderRadius.circular(10),
                //     ),
                //     child: const Row(
                //       mainAxisSize: MainAxisSize.min,
                //       children: [
                //         Icon(Icons.play_circle_fill, color: Colors.white),
                //         SizedBox(width: 8),
                //         Text(
                //           "WATCH AD FOR REWARD",
                //           style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),
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

  RetroBoardLinesPainter({
    required this.snakes,
    required this.ladders,
    required this.gridSize,
  });

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
    final railPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final stepPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.5;

    ladders.forEach((s, e) {
      Offset p1 = getC(s);
      Offset p2 = getC(e);
      double dx = p2.dx - p1.dx, dy = p2.dy - p1.dy;
      double len = sqrt(dx * dx + dy * dy);
      Offset perp = Offset(-dy / len, dx / len) * (cell * 0.2);

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
      _drawRealisticSnake(
        canvas,
        getC(entry.key),
        getC(entry.value),
        cell,
        baseColor: snakeColors[entry.key] ?? Colors.green,
      );
    }
  }

  void _drawRealisticSnake(
    Canvas canvas,
    Offset head,
    Offset tail,
    double cellSize, {
    required Color baseColor,
  }) {
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
        pathMetric.extractPath(
          pathMetric.length * startPercent,
          pathMetric.length * endPercent,
        ),
        Paint()
          ..color = Color.lerp(baseColor.withOpacity(0.9), baseColor, progress)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      // B. Layer: Belly Stripe (Simulating depth)
      if (strokeWidth > 4) {
        canvas.drawPath(
          pathMetric.extractPath(
            pathMetric.length * startPercent,
            pathMetric.length * endPercent,
          ),
          Paint()
            ..color = Colors.white.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.35
            ..strokeCap = StrokeCap.round,
        );
      }

      // C. Layer: Spine Pattern (Zig-zag/Dots)
      if (i % 2 == 0) {
        canvas.drawPath(
          pathMetric.extractPath(
            pathMetric.length * startPercent,
            pathMetric.length * endPercent,
          ),
          Paint()
            ..color = Colors.black.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth * 0.2,
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
      headPath.quadraticBezierTo(26, -6, 30, 0); // Fine snout
      headPath.quadraticBezierTo(26, 6, 12, 10); // Jaw symmetry
      headPath.quadraticBezierTo(2, 14, 0, 0);

      canvas.drawPath(headPath, Paint()..color = baseColor);
      canvas.drawPath(
        headPath,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );

      // Refined Eyes (Side-facing predatory placement)
      canvas.drawCircle(
        const Offset(14, -6),
        3.0,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        const Offset(15.5, -7.5),
        0.8,
        Paint()..color = Colors.white,
      ); // Glint
      canvas.drawCircle(
        const Offset(14, 6),
        3.0,
        Paint()..color = Colors.black,
      );
      canvas.drawCircle(
        const Offset(15.5, 7.5),
        0.8,
        Paint()..color = Colors.white,
      ); // Glint

      // Long Forked Tongue
      final tonguePaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
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
