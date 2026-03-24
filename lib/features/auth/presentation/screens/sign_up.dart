import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/splin_kit.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/core/widgets/custom_Inkwell.dart';
import 'package:chess_game_manika/core/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/core/widgets/custom_text.dart';
import 'package:chess_game_manika/core/widgets/custom_textformfield.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/set_password_screen.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/features/auth/services/auth_services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';

class Signup extends ConsumerStatefulWidget {
  const Signup({super.key});

  @override
  ConsumerState<Signup> createState() => _SignupState();
}

class _SignupState extends ConsumerState<Signup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailAddressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  final _formKey = GlobalKey<FormState>();
  bool loader = false;
  bool visible = false;
  bool isTermsAndConditionedAgreed = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      loader = true;
    });

    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => loader = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception("Failed to get ID Token from Google");
      }

      // Call backend
      final result = await ApiService().googleLogin(idToken);

      // Save session info
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('loggedIn', true);
      await prefs.setString('email', googleUser.email);
      await prefs.setInt('userId', result['user']['id']);

      if (mounted) {
        setState(() {
          loader = false;
        });

        // Update Riverpod auth state
        final userId = result['user']['id'];
        ref.read(authProvider.notifier).login(userId, googleUser.email);

        if (result['is_new_user'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SetPasswordScreen()),
          );
        } else {
          RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
        }
        DisplaySnackbar.show(context, "Google Login Successful");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loader = false;
        });
      }
      print("Google Sign-In Error: $e");
      if (mounted) {
        String errMsg = e.toString();
        if (errMsg.contains("Exception: ")) {
          errMsg = errMsg.split("Exception: ").last;
        }
        DisplaySnackbar.show(context, "Google Sign-In failed: $errMsg");
      }
    }
  }

  // CHANGE: Added loading state and better error handling
  Future<void> signup() async {
    // Show loader
    setState(() {
      loader = true;
    });

    try {
      final success = await _authService.signup(
        _nameController.text.trim(),
        _passwordController.text.trim(),
        _emailAddressController.text.trim(),
      );

      // Hide loader
      setState(() {
        loader = false;
      });

      if (success) {
        // Save auth data
        final prefs = await SharedPreferences.getInstance();
        final email = _emailAddressController.text.trim();
        await prefs.setString('email', email);
        await prefs.setBool('loggedIn', true);

        int finalUserId = 0;
        try {
          final profile = await ApiService().getProfile();
          finalUserId = profile['id'] ?? 0;
          await prefs.setInt('userId', finalUserId);
        } catch (e) {
          print("Signup: WARNING - Could not fetch profile to get userId: $e");
        }

        if (mounted) {
          // Update Riverpod
          ref.read(authProvider.notifier).login(finalUserId, email);

          DisplaySnackbar.show(context, signupSuccessfullStr);
          RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
        }
      } else {
        if (mounted) {
          DisplaySnackbar.show(context, signupFailedStr);
        }
      }
    } catch (e) {
      // Hide loader on error
      setState(() {
        loader = false;
      });

      if (mounted) {
        // CHANGE: Extract specific error message from exception
        String errorMessage = signupFailedStr;

        // Parse the exception message
        String exceptionMsg = e.toString();
        if (exceptionMsg.contains('Username already exists')) {
          errorMessage = 'Username already exists';
        } else if (exceptionMsg.contains('Email already registered')) {
          errorMessage = 'Email already registered';
        } else if (exceptionMsg.contains('Exception:')) {
          // Extract message after "Exception: "
          errorMessage = exceptionMsg.split('Exception: ').last;
        }

        DisplaySnackbar.show(context, errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Solid minimal background like Instagram/Facebook
          Container(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            color: Colors.white,
          ),
          ui(),
          loader ? Loader.backdropFilter(context) : const SizedBox(),
        ],
      ),
    );
  }

  Widget ui() => SafeArea(
    child: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: const Icon(Icons.close, color: Color(0xFF2196F3)),
                ),
              ),

              SizedBox(height: 20),
              Center(
                child: CustomText(
                  data: createAccountStr,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              SizedBox(height: 24),
              CustomText(
                data: nameStr,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              CustomTextformfield(
                controller: _nameController,
                hintText: nameStr,
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validateNameStr;
                  }
                  return null;
                },
              ),
              SizedBox(height: 10),
              CustomText(
                data: emailAddressStr,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              CustomTextformfield(
                controller: _emailAddressController,
                hintText: emailAddressStr,
                // CHANGE: Added email format validation
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validateEmailAddressStr;
                  }
                  // Check email format
                  final emailRegex = RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  );
                  if (!emailRegex.hasMatch(p0)) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              SizedBox(height: 10),
              CustomText(
                data: passwordStr,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              CustomTextformfield(
                obscureText: visible ? false : true,
                controller: _passwordController,
                hintText: passwordStr,
                // CHANGE: Added password length validation (minimum 8 characters)
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validatePasswordStr;
                  }
                  if (p0.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
                suffixIcon: IconButton(
                  color: primaryColor,
                  onPressed: () {
                    setState(() {
                      visible = !visible;
                    });
                  },
                  icon: visible
                      ? Icon(Icons.visibility_outlined)
                      : Icon(Icons.visibility_off_outlined),
                ),
              ),
              SizedBox(height: 15),
              Row(
                children: [
                  Checkbox(
                    value: isTermsAndConditionedAgreed,
                    onChanged: (bool? value) {
                      setState(() {
                        isTermsAndConditionedAgreed = value! ? true : false;
                      });
                    },
                  ),
                  CustomText(data: agreeTermsAndConditionStr),
                  Spacer(),
                ],
              ),
              SizedBox(height: 15),
              CustomElevatedbutton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    // CHANGE: Check terms and conditions first
                    if (!isTermsAndConditionedAgreed) {
                      DisplaySnackbar.show(
                        context,
                        notagreedToTermsAndConditionStr,
                      );
                      return;
                    }
                    // Call signup function (loader handled inside)
                    signup();
                  }
                },
                child: Text(SignupStr, style: TextStyle(color: Colors.white)),
              ),

              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider()),
                  Text("Or"),
                  Expanded(child: Divider()),
                ],
              ),
              SizedBox(height: 20),
              SizedBox(height: 24),
              // Enhanced Google Sign In (Full width like Facebook)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _handleGoogleSignIn,
                  icon: Image.asset("assets/images/google_logo.png", height: 24),
                  label: const Text(
                    "Continue with Google",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.black12, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                children: [
                  Spacer(),
                  CustomText(data: alreadyHaveanAccountStr, fontSize: 20),
                  CustomInkwell(
                    child: CustomText(
                      data: loginStr,
                      color: primaryColor,
                      fontSize: 20,
                    ),
                    onTap: () {
                      RouteGenerator.navigateToPage(context, Routes.loginRoute);
                    },
                  ),
                  Spacer(),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
