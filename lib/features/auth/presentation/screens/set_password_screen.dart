import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/core/widgets/custom_text.dart';
import 'package:chess_game_manika/core/widgets/custom_textformfield.dart';
import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:flutter/material.dart';

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ApiService().setPassword(_passwordController.text.trim());
      if (mounted) {
        DisplaySnackbar.show(context, "Password set successfully!");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => BottomNavBarWrapper()),
        );
      }
    } catch (e) {
      if (mounted) {
        DisplaySnackbar.show(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Set Your Password"),
        automaticallyImplyLeading: false, // Don't allow going back to login
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CustomText(
                data: "Welcome! Please set a password for your account so you can also login without Google later.",
                textAlign: TextAlign.center,
                fontSize: 16,
              ),
              const SizedBox(height: 30),
              CustomTextformfield(
                controller: _passwordController,
                hintText: "Enter new password",
                obscureText: true,
                validator: (val) => (val == null || val.length < 6) ? "Password must be at least 6 characters" : null,
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator()
                  : CustomElevatedbutton(
                      onPressed: _submit,
                      child: const CustomText(data: "SAVE & CONTINUE", color: Colors.white),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
