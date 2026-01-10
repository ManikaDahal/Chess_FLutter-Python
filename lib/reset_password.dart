import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/services/token_storage.dart';
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
  TokenStorage _storage = TokenStorage();
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
                setState(() => isLoading = true);
                final response = await _authServices.resetPassword(
                  email,
                  _passwordController.text.trim(),
                );
                setState(() => isLoading = false);

                if (response['access'] != null && response['refresh'] != null) {
                  await _storage.saveAccessToken(response['access']);
                  await _storage.saveRefreshToken(response['refresh']);

                  RouteGenerator.navigateToPage(
                    context,
                    Routes.bottomNavBarRoute,
                  );
                  DisplaySnackbar.show(context, "Password reset successful!");
                } else {
                  DisplaySnackbar.show(context, "Password reset failed!");
                }
              },
              child: isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text(resetStr),
            ),
          ],
        ),
      ),
    );
  }
}
