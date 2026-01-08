import 'package:chess_python/core/utils/otp_args.dart';
import 'package:chess_python/core/utils/resetPassword_args.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:flutter/material.dart';

class OtpPage extends StatefulWidget {
  final String contact;
  const OtpPage({super.key, required this.contact});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController _otpController = TextEditingController();
  AuthServices _authServices = AuthServices();
  late String email;

  bool isVerifying = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is OtpArguments) {
      email = args.contact;
    } else {
      email = "";
    }
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
              decoration: const InputDecoration(
                labelText: "Enter 6-digit OTP",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  bool ok = await _authServices.verifyOtp(
                    email,
                    _otpController.text,
                  );
                  if (ok) {
                    RouteGenerator.navigateToPage(
                      context,
                      Routes.resetPasswordRoute,
                      arguments: ResetPasswordArguments(contact: email),
                    );
                  }
                },

                child: Text("Verify OTP"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
