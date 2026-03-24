import 'dart:ui';

import 'package:flutter/material.dart';
class Loader {
  static Widget backdropFilter(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5), // Lighter blur akin to Insta
      child: Container(
        color: Colors.black.withOpacity(0.2), // Darker overlay for contrast
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            // Facebook/Insta uses a sleek, solid color ring rather than bouncing dots
            child: const CircularProgressIndicator(
              strokeWidth: 3.0,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F3460)), // App Primary Color
            ),
          ),
        ),
      ),
    );
  }
}
