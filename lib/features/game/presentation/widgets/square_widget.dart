import 'package:chess_game_manika/features/game/data/models/chess_piece.dart';
import 'package:flutter/material.dart';

class Square extends StatelessWidget {
  final bool isWhiteSquare;
  final ChessPiece? piece;
  final bool isSelected;
  final bool isValidMove;
  final VoidCallback onTap;

  const Square({
    super.key,
    required this.isWhiteSquare,
    required this.piece,
    required this.isSelected,
    required this.isValidMove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Premium Blue/Light Blue theme for better visibility
    Color? baseColor = isWhiteSquare ? const Color(0xFFDEE3E6) : const Color(0xFF8CA2AD); // Cream and Gray/Blue
    if (isSelected) baseColor = Colors.yellow.withOpacity(0.7);
    if (isValidMove) baseColor = Colors.greenAccent.withOpacity(0.5);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: baseColor,
        child: piece != null
            ? Padding(
                padding: const EdgeInsets.all(4.0),
                child: Image.asset(piece!.imagePath),
              )
            : null,
      ),
    );
  }
}
