import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/splin_kit.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/services/auth_services.dart';
import 'package:chess_game_manika/widgets/custom_Inkwell.dart';
import 'package:chess_game_manika/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/widgets/custom_text.dart';
import 'package:chess_game_manika/widgets/custom_textformfield.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailAddressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  final _formKey = GlobalKey<FormState>();
  bool loader = false;
  bool visible = false;
  bool isTermsAndConditionedAgreed = false;

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
        if (mounted) {
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
      body: Stack(
        children: [
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
          padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: foregroundColor,
                child: IconButton(
                  onPressed: () {
                    // RouteGenerator.navigateToPage(context, Routes.getStartedRoute);
                  },
                  icon: Icon(Icons.close),
                ),
              ),

              SizedBox(height: 20),
              Center(
                child: CustomText(
                  data: createAccountStr,
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomElevatedbutton(
                    onPressed: () {},
                    width: MediaQuery.of(context).size.width * 0.25,
                    backgroundColor: Colors.white,
                    child: Image.asset("assets/images/google_logo.png"),
                  ),
                  SizedBox(width: 30),
                  CustomElevatedbutton(
                    onPressed: () {},
                    width: MediaQuery.of(context).size.width * 0.25,
                    backgroundColor: Colors.white,
                    child: Image.asset(
                      "assets/images/facebook_logo.png",
                      height: 40,
                    ),
                  ),
                ],
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
