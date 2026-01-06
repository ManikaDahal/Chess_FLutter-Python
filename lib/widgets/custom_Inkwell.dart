import 'package:flutter/material.dart';

class CustomInkwell extends StatelessWidget {
  Function()? onTap;
  Widget? child;
  CustomInkwell({super.key,this.onTap,this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, child:child );
  }
}