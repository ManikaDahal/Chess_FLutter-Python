class SnakeBoard {
  final int id;
  final String name;
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final String description;
  /// Optional: asset path to use as the board background image.
  /// When set, the game screen renders this image instead of the drawn grid.
  final String? imagePath;

  SnakeBoard({
    required this.id,
    required this.name,
    required this.snakes,
    required this.ladders,
    this.description = "",
    this.imagePath,
  });
}
