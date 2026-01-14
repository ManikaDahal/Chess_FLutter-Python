import 'package:chess_python/reset_password.dart';
import 'package:flutter/material.dart';
import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/core/utils/resetPassword_args.dart';

class OtpPage extends StatefulWidget {
  final String contact; // this will receive the email from previous screen

  const OtpPage({super.key, required this.contact});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController _otpController = TextEditingController();
  late String email;
  bool isVerifying = false;

  AuthServices _authServices = AuthServices();

  @override
  void initState() {
    super.initState();
    email = widget.contact.trim(); // email is now guaranteed
    print("OTP PAGE EMAIL = $email"); // debug check
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify OTP")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: "Enter 6-digit OTP",
                border: OutlineInputBorder(),
                counterText: "",
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isVerifying
                    ? null
                    : () async {
                        String otp = _otpController.text.trim();

                        if (otp.length != 6) {
                          DisplaySnackbar.show(
                            context,
                            "Please enter a valid 6-digit OTP",
                          );
                          return;
                        }

                        setState(() => isVerifying = true);

                        bool ok = await _authServices.verifyOtp(email, otp);

                        setState(() => isVerifying = false);

                        if (ok) {
                          // Navigate to Reset Password page
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ResetPassword(
                                contact: email,
                                otp: otp,
                              ), // pass email to reset password
                            ),
                          );
                        } else {
                          DisplaySnackbar.show(context, "Invalid OTP");
                        }
                      },
                child: isVerifying
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Verify OTP"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
