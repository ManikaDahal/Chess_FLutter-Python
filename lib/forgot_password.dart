import 'dart:core';
import 'package:chess_python/core/utils/color_utils.dart';
import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/string_utils.dart';
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
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailAddressController = TextEditingController();
  bool useEmail = true;
  bool isSendingOtp = false;

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
            Row(
              children: [
                ChoiceChip(
                  label: Text(emailAddressStr),
                  selected: useEmail,
                  onSelected: (selected) {
                    setState(() {
                      useEmail = true;
                    });
                  },
                ),
                SizedBox(width: 20),
                ChoiceChip(
                  label: Text(phoneStr),
                  
                  selected: !useEmail,
                  onSelected: (selected) {
                    setState(() {
                      useEmail = false;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 30),

            useEmail
                ? CustomTextformfield(
                    controller: _emailAddressController,
                    hintText: emailAddressStr,
                    validator: (p0) {
                      if (p0 == null || p0.isEmpty) {
                        return validateEmailAddressStr;
                      }
                      return null;
                    },
                  )
                : CustomTextformfield(
                    controller: _phoneController,
                    hintText: phoneStr,
                    validator: (p0) {
                      if (p0 == null || p0.isEmpty) {
                        return validatePhoneStr;
                      }
                      return null;
                    },
                  ),
            SizedBox(height: 50),
            CustomElevatedbutton(
              // onPressed: isSendingOtp
              //     ? null
              //     : () async {
              //         setState(() {
              //           isSendingOtp = true;
              //         });
              //         if (useEmail) {
              //           String email = _emailAddressController.text.trim();
              //           if (email.isEmpty) {
              //             DisplaySnackbar.show(
              //               context,
              //               validateEmailAddressStr,
              //             );
              //             setState(() {
              //               isSendingOtp = false;
              //             });
              //             return;
              //           }

              //           String otp = authService.generateOtp();
              //           await authService.saveOtp(email, otp);
              //           DisplaySnackbar.show(context, otpSendStr);
              //           RouteGenerator.navigateToPage(
              //             context,
              //             Routes.enterOTPRoute,
              //             arguments: OtpArguments(
              //               isEmail: true,
              //               contact: email,
              //               verificationId: '',
              //             ),
              //           );
              //         } else {
              //           String phone = _phoneController.text.trim();
              //           if (phone.isEmpty) {
              //             DisplaySnackbar.show(context, validatePhoneStr);
              //             setState(() {
              //               isSendingOtp = false;
              //             });
              //             return;
              //           }

              //           await authService.sendPhoneOtp(
              //             phone,
              //             codeSent: (verId) {
              //               RouteGenerator.navigateToPage(
              //                 context,
              //                 Routes.enterOTPRoute,
              //                 arguments: OtpArguments(
              //                   isEmail: false,
              //                   contact: phone,
              //                   verificationId: verId,
              //                 ),
              //               );
              //             },
              //             verificationFailed: (error) {
              //               DisplaySnackbar.show(
              //                 context,
              //                 error.message ?? "Phone Error",
              //               );
              //             },
              //           );
              //         }
              //         setState(() {
              //           isSendingOtp = false;
              //         });
              //       },

              // child: isSendingOtp
              //     ? CircularProgressIndicator(): 
                  onPressed: () {  },
                  child: Text(sendCodeStr, style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}