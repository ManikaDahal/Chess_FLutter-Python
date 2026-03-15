import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

enum Direction { up, down, left, right }

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  // Game constants
  static const int rowCount = 20;
  static const int columnCount = 20;
  
  // Game state
  List<int> snake = [45, 65, 85];
  int food = 300;
  Direction direction = Direction.down;
  bool isPlaying = false;
  int score = 0;
  Timer? gameTimer;

  void startGame() {
    isPlaying = true;
    score = 0;
    snake = [45, 65, 85];
    direction = Direction.down;
    generateFood();
    
    gameTimer?.cancel();
    gameTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      updateGame();
    });
  }

  void generateFood() {
    food = Random().nextInt(rowCount * columnCount);
    while (snake.contains(food)) {
      food = Random().nextInt(rowCount * columnCount);
    }
  }

  void updateGame() {
    setState(() {
      // Move snake
      int nextHead = snake.first;
      switch (direction) {
        case Direction.up:
          nextHead -= columnCount;
          break;
        case Direction.down:
          nextHead += columnCount;
          break;
        case Direction.left:
          if (nextHead % columnCount == 0) {
            nextHead += columnCount - 1;
          } else {
            nextHead -= 1;
          }
          break;
        case Direction.right:
          if ((nextHead + 1) % columnCount == 0) {
            nextHead -= columnCount - 1;
          } else {
            nextHead += 1;
          }
          break;
      }

      // Check boundary collisions for up/down
      if (nextHead < 0) {
        nextHead += rowCount * columnCount;
      } else if (nextHead >= rowCount * columnCount) {
        nextHead -= rowCount * columnCount;
      }

      // Check self-collision
      if (snake.contains(nextHead)) {
        gameOver();
        return;
      }

      snake.insert(0, nextHead);

      // Check food collision
      if (nextHead == food) {
        score += 10;
        generateFood();
      } else {
        snake.removeLast();
      }
    });
  }

  void gameOver() {
    gameTimer?.cancel();
    isPlaying = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Game Over', style: TextStyle(color: Colors.white)),
        content: Text('Your Score: $score', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              startGame();
            },
            child: const Text('Play Again', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Snake Game - Score: $score', style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.delta.dy > 0 && direction != Direction.up) {
                  direction = Direction.down;
                } else if (details.delta.dy < 0 && direction != Direction.down) {
                  direction = Direction.up;
                }
              },
              onHorizontalDragUpdate: (details) {
                if (details.delta.dx > 0 && direction != Direction.left) {
                  direction = Direction.right;
                } else if (details.delta.dx < 0 && direction != Direction.right) {
                  direction = Direction.left;
                }
              },
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                    ),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rowCount * columnCount,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnCount,
                      ),
                      itemBuilder: (context, index) {
                        if (snake.contains(index)) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: snake.first == index ? Colors.green[400] : Colors.green[700],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        } else if (food == index) {
                          return Center(
                            child: Container(
                              margin: const EdgeInsets.all(1),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        } else {
                          return Container(
                            decoration: const BoxDecoration(
                              color: Colors.transparent,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: !isPlaying
                  ? ElevatedButton(
                      onPressed: startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                      child: const Text('Start Game', style: TextStyle(fontSize: 18, color: Colors.white)),
                    )
                  : const Text(
                      'Swipe to Change Direction',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
