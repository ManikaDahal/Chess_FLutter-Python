import 'package:chess_python/core/utils/color_utils.dart';
import 'package:flutter/material.dart';

class DisplaySnackbar {
  static void show(BuildContext context, String message,
      {Color backgroundColor =  primaryColor,
      Color textColor = Colors.white,
      Duration duration = const Duration(seconds: 3),
      IconData? icon,
      bool isError=false
      , bool isSuccess=false}) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          if (icon != null) Icon(icon, color: textColor),
          if (icon != null) const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 16),
            ),
          ),
        ],
      ),
      backgroundColor:isError?Colors.red:isSuccess?Colors.green: backgroundColor,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    //  if (isError) {
    //   HapticFeedback.heavyImpact(); // Trigger haptic feedback if it's an error
    // }
  }
}