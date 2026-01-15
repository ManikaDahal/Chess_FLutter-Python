import 'dart:core';
import 'package:chess_python/core/utils/color_utils.dart';
import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/otp_args.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:chess_python/widgets/custom_textformfield.dart';
import 'package:flutter/material.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final AuthServices _authServices = AuthServices();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailAddressController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool loader = false;
  String selectedMethod = 'email';

  Future<void> forgotPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loader = true);

    bool ok = await _authServices.forgotPassword(
      email: selectedMethod == 'email'
          ? _emailAddressController.text.trim()
          : null,
      phone: selectedMethod == 'phone' ? _phoneController.text.trim() : null,
    );

    setState(() => loader = false);

    if (ok) {
      RouteGenerator.navigateToPage(
        context,
        Routes.enterOTPRoute,
        arguments: OtpArguments(
          contact: selectedMethod == 'email'
              ? _emailAddressController.text.trim()
              : _phoneController.text.trim(),
        ),
      );
    } else {
      DisplaySnackbar.show(context, "OTP send failed");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              backgroundColor: foregroundColor,
              child: IconButton(
                onPressed: () {
                  RouteGenerator.navigateToPage(context, Routes.loginRoute);
                },
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: CustomText(
                data: forgotPasswordStr,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Email / Phone selection
            Row(
              children: [
                Radio<String>(
                  value: 'email',
                  groupValue: selectedMethod,
                  onChanged: (value) => setState(() => selectedMethod = value!),
                ),
                CustomText(data: emailAddressStr, fontWeight: FontWeight.bold),
                Radio<String>(
                  value: 'phone',
                  groupValue: selectedMethod,
                  onChanged: (value) => setState(() => selectedMethod = value!),
                ),
                CustomText(data: phoneStr, fontWeight: FontWeight.bold),
              ],
            ),

            const SizedBox(height: 10),

            // Form Fields
            Form(
              key: _formKey,
              child: selectedMethod == 'email'
                  ? CustomTextformfield(
                      controller: _emailAddressController,
                      hintText: emailAddressStr,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return validateEmailAddressStr;
                        }
                        // Basic email format check
                        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                          return "Enter a valid email";
                        }
                        return null;
                      },
                    )
                  : CustomTextformfield(
                      controller: _phoneController,
                      hintText: phoneStr,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return validatePhoneStr;
                        }
                        
                        return null;
                      },
                    ),
            ),

            const SizedBox(height: 50),

            // Send OTP button or loader
            loader
                ? const Center(child: CircularProgressIndicator())
                : CustomElevatedbutton(
                    onPressed: forgotPassword,
                    child: const Text(
                      sendCodeStr,
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
