import '../models/snake_board.dart';

final List<SnakeBoard> snakeBoards = [
  SnakeBoard(
    id: "classic",
    name: "Classic Retro",
    description: "The balanced layout you know and love.",
    snakes: {
      17: 7, 54: 34, 62: 19, 64: 60, 87: 36, 93: 73, 95: 75, 98: 78,
    },
    ladders: {
      1: 38, 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 80: 99,
    },
  ),
  SnakeBoard(
    id: "dangerous",
    name: "Serpent's Pit",
    description: "High risk, high reward. Watch the top!",
    snakes: {
      99: 10, 92: 70, 85: 45, 78: 58, 66: 26, 55: 35, 43: 13, 22: 2,
    },
    ladders: {
      3: 23, 15: 35, 27: 47, 39: 59, 51: 81, 63: 83, 75: 95, 8: 18,
    },
  ),
  SnakeBoard(
    id: "climber",
    name: "Ladder Heaven",
    description: "Plenty of shortcuts, if you can find them.",
    snakes: {
      16: 6, 48: 28, 64: 44, 79: 59, 94: 74, 98: 88,
    },
    ladders: {
      2: 32, 5: 15, 12: 42, 25: 55, 33: 73, 46: 86, 58: 78, 62: 92, 77: 97,
    },
  ),
  SnakeBoard(
    id: "zigzag",
    name: "Zig-Zag Maze",
    description: "A winding path with tricky turns.",
    snakes: {
      97: 77, 88: 68, 79: 59, 66: 46, 55: 35, 44: 24, 33: 13, 22: 2,
    },
    ladders: {
      1: 21, 10: 30, 19: 39, 28: 48, 40: 60, 49: 69, 61: 81, 70: 90, 82: 100,
    },
  ),
  SnakeBoard(
    id: "short_and_sweet",
    name: "Sprint Run",
    description: "Short ladders, short snakes. Fast-paced action.",
    snakes: {
      15: 5, 25: 15, 35: 25, 45: 35, 55: 45, 65: 55, 75: 65, 85: 75, 95: 85,
    },
    ladders: {
      2: 12, 12: 22, 22: 32, 32: 42, 42: 52, 52: 62, 62: 72, 72: 82, 82: 92,
    },
  ),
  SnakeBoard(
    id: "random_chaos",
    name: "Island Hop",
    description: "Clusters of activity across the board.",
    snakes: {
      98: 40, 91: 81, 76: 66, 63: 53, 47: 37, 29: 9,
    },
    ladders: {
      8: 28, 14: 34, 38: 58, 42: 62, 56: 76, 72: 92,
    },
  ),
];
