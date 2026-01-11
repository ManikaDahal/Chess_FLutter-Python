import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:chess_python/widgets/custom_textformfield.dart';
import 'package:flutter/material.dart';

class ResetPassword extends StatefulWidget {
  final String contact;

  const ResetPassword({required this.contact});

  @override
  State<ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<ResetPassword> {
  AuthServices _authServices = AuthServices();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool isLoading = false;
  late String email;

  @override
  void initState() {
    super.initState();
    email = widget.contact;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextformfield(
              controller: _passwordController,
              hintText: newPasswordStr,
              obscureText: true,
            ),
            const SizedBox(height: 16),
            CustomTextformfield(
              controller: _confirmPasswordController,
              hintText: confirmPasswordStr,
              obscureText: true,
            ),
            const SizedBox(height: 30),
            CustomElevatedbutton(
              onPressed: () async {
                final password = _passwordController.text.trim();
                final confirmPassword = _confirmPasswordController.text.trim();
                if (password != confirmPassword) {
                  DisplaySnackbar.show(
                    context,
                    "Password must be same in both boxes",
                  );
                  return;
                }

                bool ok = await _authServices.resetPassword(
                  email,
                  password,
                );
                if (ok) {
                  RouteGenerator.navigateToPage(context, Routes.loginRoute);
                  DisplaySnackbar.show(
                    context,
                    "Password reset successfull,Login using new password",
                  );
                }
              },

              child: Text(resetStr),
            ),
          ],
        ),
      ),
    );
  }
}
