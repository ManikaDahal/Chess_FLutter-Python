import 'package:flutter/material.dart';

class CustomInkwell extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget? child;
  const CustomInkwell({super.key, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, child: child);
  }
}
