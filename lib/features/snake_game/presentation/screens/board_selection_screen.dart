import 'package:flutter/material.dart';
import '../../models/snake_board.dart';
import '../../data/snake_boards_data.dart';
import 'snake_game_screen.dart';
import 'dart:math';

class BoardSelectionScreen extends StatefulWidget {
  const BoardSelectionScreen({super.key});

  @override
  State<BoardSelectionScreen> createState() => _BoardSelectionScreenState();
}

class _BoardSelectionScreenState extends State<BoardSelectionScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.85);
  double _currentPage = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page!;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("SELECT BOARD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
        children: [
          const SizedBox(height: 12),
          const Text(
            "CHOOSE YOUR ADVENTURE",
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300, letterSpacing: 2),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: snakeBoards.length,
              itemBuilder: (context, index) {
                double relativePosition = index - _currentPage;
                return _buildBoardCard(snakeBoards[index], relativePosition);
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildIndicator(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: ElevatedButton(
              onPressed: () {
                final selectedBoard = snakeBoards[_currentPage.round()];
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SnakeGameScreen(board: selectedBoard),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 10,
              ),
              child: const Text(
                "SELECT & PLAY",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ),
      ),
    );
  }

  Widget _buildBoardCard(SnakeBoard board, double relativePosition) {
    // Transform effect
    double scale = max(0.8, 1.0 - relativePosition.abs() * 0.2);
    double rotation = relativePosition * 0.1;

    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001) // perspective
        ..scale(scale)
        ..rotateY(rotation),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
            if (relativePosition.abs() < 0.1)
              BoxShadow(
                color: Colors.orangeAccent.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 2,
              ),
          ],
          border: Border.all(
            color: relativePosition.abs() < 0.1 ? Colors.orangeAccent : Colors.white12,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              board.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(
                board.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
            const Spacer(),
            // Simplified Preview
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CustomPaint(
                      painter: BoardPreviewPainter(board: board),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(snakeBoards.length, (index) {
        double opacity = (_currentPage.round() == index) ? 1.0 : 0.3;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: (_currentPage.round() == index) ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(opacity),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class BoardPreviewPainter extends CustomPainter {
  final SnakeBoard board;
  BoardPreviewPainter({required this.board});

  @override
  void paint(Canvas canvas, Size size) {
    double cell = size.width / 10;
    
    // Draw grid lines
    final linePaint = Paint()..color = Colors.white12..strokeWidth = 0.5;
    for (int i = 0; i <= 10; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), linePaint);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), linePaint);
    }

    Offset getC(int n) {
      int sq = n - 1;
      int row = sq ~/ 10;
      int col = sq % 10;
      if (row % 2 == 1) col = 9 - col;
      row = 9 - row;
      return Offset(col * cell + cell / 2, row * cell + cell / 2);
    }

    // Draw Ladders (Greenish)
    final ladderPaint = Paint()..color = Colors.greenAccent..strokeWidth = 2.0;
    board.ladders.forEach((s, e) {
      canvas.drawLine(getC(s), getC(e), ladderPaint);
    });

    // Draw Snakes (Reddish)
    final snakePaint = Paint()..color = Colors.redAccent..strokeWidth = 2.0;
    board.snakes.forEach((s, e) {
      // Draw simple curved path for snake
      final path = Path()..moveTo(getC(s).dx, getC(s).dy);
      final mid = Offset.lerp(getC(s), getC(e), 0.5)!;
      final control = mid + Offset(10, 0); // small curve
      path.quadraticBezierTo(control.dx, control.dy, getC(e).dx, getC(e).dy);
      canvas.drawPath(path, snakePaint..style = PaintingStyle.stroke);
    });
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}
