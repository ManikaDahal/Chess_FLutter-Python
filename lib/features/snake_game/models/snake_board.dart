class SnakeBoard {
  final String id;
  final String name;
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final String description;

  SnakeBoard({
    required this.id,
    required this.name,
    required this.snakes,
    required this.ladders,
    this.description = "",
  });
}
