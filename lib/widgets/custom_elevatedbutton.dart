import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:flutter/material.dart';

class CustomElevatedbutton extends StatelessWidget {
  final FocusNode _focusNode = FocusNode();
  Function()? onPressed;
  Widget? child;
  Color? backgroundColor;
  Color? foregroundColor;
  Color? borderColor;
  double? width;
  double? height;
  CustomElevatedbutton(
      {super.key,
      required this.onPressed,
      required this.child,
      this.height,
      this.width,
      this.backgroundColor,
      this.foregroundColor,
      this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
        height: height ?? 50,
        width: width ?? MediaQuery.of(context).size.width,
        child: ElevatedButton(
          focusNode: _focusNode,
          onPressed: onPressed,
          style:
          //  ButtonStyle(
          //   backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          //     if (states.contains(WidgetState.pressed)||states.contains(WidgetState.hovered)|| _focusNode.hasFocus) {
          //       return primaryColor.withValues(alpha: 0.6);
          //     }
          //     return backgroundColor?? primaryColor;
          //   }),
          //   foregroundColor:
          //       WidgetStateProperty.all<Color>(foregroundColor ?? Colors.white),
          //   textStyle: WidgetStateProperty.all<TextStyle>(
          //     TextStyle(fontSize: 14),
          //   ),
          //   shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          //     RoundedRectangleBorder(
          //       side: BorderSide(
          //         color: borderColor ?? primaryColor,
          //         width: 1,
          //       ),
          //       borderRadius: BorderRadius.circular(10),
          //     ),
          //   ),
          //   elevation: WidgetStateProperty.all<double>(0),
          // ),
                ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: backgroundColor?? primaryColor,
                  foregroundColor:foregroundColor?? Colors.white,
                  textStyle: TextStyle(fontSize: 20),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: borderColor ??primaryColor,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
          child: child,
        ));
  }
}