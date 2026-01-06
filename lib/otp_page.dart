
import 'package:flutter/material.dart';


class OtpPage extends StatefulWidget {
  final bool isEmail; // true = email OTP, false = phone OTP
  final String contact; // email or phone
  final String verificationId; // only for phone OTP

  const OtpPage({
    super.key,
    required this.isEmail,
    required this.contact,
    required this.verificationId,
  });

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController otpController = TextEditingController();

  bool isVerifying = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify OTP")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              widget.isEmail
                  ? "OTP sent to ${widget.contact}"
                  : "OTP sent to ${widget.contact}",
              style: const TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 30),

            TextField(
              controller: otpController,
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
                onPressed: (){
                  
                },
                // onPressed: isVerifying
                //     ? null
                //     : () async {
                //         String otp = otpController.text.trim();

                //         if (otp.length != 6) {
                //           ScaffoldMessenger.of(context).showSnackBar(
                //             const SnackBar(content: Text("Enter valid 6-digit OTP")),
                //           );
                //           return;
                //         }

                //         setState(() => isVerifying = true);

                //         bool isValid = false;

                        
                //         if (widget.isEmail) {
                //           isValid = await authService.verifyOtp(
                //             widget.contact,
                //             otp,
                //           );
                //         }
                //         // 🔹 Phone OTP verification
                //         else {
                //           isValid = await authService.verifyPhoneOtp(
                //             widget.verificationId,
                //             otp,
                //           );
                //         }

                //         setState(() => isVerifying = false);

                //         if (isValid) {
                //           Navigator.pushReplacement(
                //             context,
                //             MaterialPageRoute(
                //               builder: (_) => ResetPassword(
                //                 isEmail: widget.isEmail,
                //                 contact: widget.contact,
                //               ),
                //             ),
                //           );
                //         } else {
                //           ScaffoldMessenger.of(context).showSnackBar(
                //             const SnackBar(content: Text("Invalid or expired OTP")),
                //           );
                //         }
                //       },
                child:Text("Verify OTP"),
                // isVerifying
                //     ? const CircularProgressIndicator(color: Colors.white)
                //     : const 
              ),
            ),
          ],
        ),
      ),
    );
  }
}