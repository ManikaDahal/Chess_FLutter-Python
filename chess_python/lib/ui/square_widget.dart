import 'package:chess_python/core/utils/color_utils.dart';
import 'package:flutter/material.dart';
import '../models/chess_piece.dart';

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
    Color? baseColor = isWhiteSquare ? backgroundColor : foregroundColor;
    if (isSelected) baseColor = Colors.green;
    if (isValidMove) baseColor = Colors.greenAccent;

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
