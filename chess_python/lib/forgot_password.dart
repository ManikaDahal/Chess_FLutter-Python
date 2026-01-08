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
  AuthServices _authServices = AuthServices();
  // final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailAddressController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),
            CircleAvatar(
              backgroundColor: foregroundColor,
              child: IconButton(
                onPressed: () {
                  RouteGenerator.navigateToPage(context, Routes.loginRoute);
                },
                icon: Icon(Icons.arrow_back),
              ),
            ),
            SizedBox(height: 10),
            Center(
              child: CustomText(
                data: forgotPasswordStr,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 20),
            CustomText(data: emailAddressStr, fontWeight: FontWeight.bold),

            CustomTextformfield(
              controller: _emailAddressController,
              hintText: emailAddressStr,
              validator: (p0) {
                if (p0 == null || p0.isEmpty) {
                  return validateEmailAddressStr;
                }
                return null;
              },
            ),

            SizedBox(height: 50),
            CustomElevatedbutton(
              onPressed: () async {
                await _authServices.forgotPassword(
                  _emailAddressController.text,
                );
                RouteGenerator.navigateToPage(
                  context,
                  Routes.enterOTPRoute,
                  arguments: OtpArguments(
                    contact: _emailAddressController.text,
                  ),
                );
              },
              child: Text(sendCodeStr, style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
