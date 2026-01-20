import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:flutter/material.dart';

class CustomTextformfield extends StatelessWidget {
  final Function(String)? onChanged;
  final String? labelText;
  final String? hintText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool? obscureText;
  final TextInputType? keyboardType;
  final TextEditingController? controller;
  final String? Function(String?)? validator;

  const CustomTextformfield({
    super.key,
    this.labelText,
    this.onChanged,
    this.hintText,
    this.suffixIcon,
    this.prefixIcon,
    this.obscureText,
    this.keyboardType,
    this.controller,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (labelText != null) ...[
            Text(
              labelText!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
          ],
          TextFormField(
            onChanged: onChanged,
            controller: controller,
            keyboardType: keyboardType ?? TextInputType.text,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validator,
            obscureText: obscureText ?? false,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle:  TextStyle(color: blackColor),
              alignLabelWithHint: true,
              suffixIcon: suffixIcon,
              prefixIcon: prefixIcon,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}