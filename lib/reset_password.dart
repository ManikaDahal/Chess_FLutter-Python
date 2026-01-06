import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:chess_python/widgets/custom_textformfield.dart';
import 'package:flutter/material.dart';


class ResetPassword extends StatefulWidget {
  final bool isEmail; // true if email reset, false if phone reset
  final String contact; // email or phone

  const ResetPassword({
    super.key,
    required this.isEmail,
    required this.contact,
  });

  @override
  State<ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<ResetPassword> {
 
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool isLoading = false;

  
  String getSanitizedEmail(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return "phone_$digitsOnly@chessgame.com"; // valid fake email
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
            // Header
            CustomText(
              data: widget.isEmail
                  ? "Reset password for ${widget.contact}"
                  : "Phone verified successfully",
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            const SizedBox(height: 30),

            // 🔹 EMAIL FLOW
            if (widget.isEmail)
              CustomElevatedbutton(
                onPressed: (){},
                child:Text(newPasswordStr),
                // onPressed: isLoading
                //     ? null
                //     : () async {
                //         setState(() => isLoading = true);
                //         try {
                //           await _auth.sendPasswordResetEmail(email: widget.contact);
                //           if (!mounted) return;

                //           DisplaySnackbar.show(context, "Password reset link sent to email");

                //           RouteGenerator.navigateToPageWithoutStack(context, Routes.loginRoute);
                //         } on FirebaseAuthException catch (e) {
                //           DisplaySnackbar.show(context, e.message ?? "Something went wrong");
                //         } finally {
                //           setState(() => isLoading = false);
                //         }
              //   //       },
              //    isLoading
              //       ? const CircularProgressIndicator(color: Colors.white)
              //       : 
              ),

            // 🔹 PHONE FLOW
            if (!widget.isEmail)
              Column(
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
                    onPressed: (){
                      
                    },
                      child:Text(resetStr),
                    // onPressed: isLoading
                    //     ? null
                    //     : () async {
                    //         setState(() => isLoading = true);

                    //         final password = _passwordController.text.trim();
                    //         final confirmPassword = _confirmPasswordController.text.trim();

                    //         // ✅ Validation
                    //         if (password.length < 6) {
                    //           DisplaySnackbar.show(context, "Password must be at least 6 characters");
                    //           setState(() => isLoading = false);
                    //           return;
                    //         }

                    //         if (password != confirmPassword) {
                    //           DisplaySnackbar.show(context, "Passwords do not match");
                    //           setState(() => isLoading = false);
                    //           return;
                    //         }

                    //         if (user == null) {
                    //           DisplaySnackbar.show(context, "User not logged in");
                    //           setState(() => isLoading = false);
                    //           return;
                    //         }

                    //         try {
                    //           final email = getSanitizedEmail(widget.contact);

                    //           final credential = EmailAuthProvider.credential(
                    //             email: email,
                    //             password: password,
                    //           );

                    //           // Link password to phone-auth user
                    //           await user.linkWithCredential(credential);

                    //           DisplaySnackbar.show(context, "Password set successfully. Please login again.");

                    //           // Logout user
                    //           await FirebaseAuth.instance.signOut();

                    //           // Navigate to login screen
                    //           RouteGenerator.navigateToPageWithoutStack(context, Routes.loginRoute);
                    //         } on FirebaseAuthException catch (e) {
                    //           DisplaySnackbar.show(context, e.message ?? "Failed to set password");
                    //         } finally {
                    //           setState(() => isLoading = false);
                    //         }
                    //       },
                    // child: isLoading
                    //     ? const CircularProgressIndicator(color: Colors.white)
                    //     : const 
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}