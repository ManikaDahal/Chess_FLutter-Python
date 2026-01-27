import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/splin_kit.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/services/auth_biometrics.dart';
import 'package:chess_game_manika/services/auth_services.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:chess_game_manika/widgets/custom_Inkwell.dart';
import 'package:chess_game_manika/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/widgets/custom_text.dart';
import 'package:chess_game_manika/widgets/custom_textformfield.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final ApiService api = ApiService();
  final BiometricAuth _biometricAuth = BiometricAuth();
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  TokenStorage _storage = TokenStorage();
  bool visible = false;
  bool rememberMe = false;
  final _formKey = GlobalKey<FormState>();
  bool loader = false;

  // CHANGE: Added loading state and better error handling
  Future<void> login() async {
    // Show loader
    setState(() {
      loader = true;
    });

    try {
      final success = await _authService.login(
        _nameController.text.trim(),
        _passwordController.text.trim(),
      );

      // Hide loader
      setState(() {
        loader = false;
      });

      if (success) {
        // final int userId = _nameController.text.hashCode;

        // Save user ID in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userId = _nameController.text.hashCode;
        await prefs.setInt('userId', userId);
        final int roomId = 1; // Testing room ID
        await prefs.setInt('roomId', roomId);
        await prefs.setBool('loggedIn', true);

        // // Initialize GlobalCallHandler for this user
        // GlobalCallHandler().init();

        final token = await _storage.getAccessToken();
        final refresh = await _storage.getRefreshToken();
        print("Tokens after login -> Access: $token, Refresh: $refresh");

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => BottomNavBarWrapper()),
            );
          });
          DisplaySnackbar.show(context, loginSuccessfullStr);
          //RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
        }
      } else {
        if (mounted) {
          // CHANGE: Show specific error for invalid credentials
          DisplaySnackbar.show(context, 'Invalid username or password');
        }
      }
    } catch (e) {
      // Hide loader on error
      setState(() {
        loader = false;
      });

      if (mounted) {
        // CHANGE: Extract specific error message from exception
        String errorMessage = 'Invalid username or password';

        // Parse the exception message
        String exceptionMsg = e.toString();
        if (exceptionMsg.contains('Exception:')) {
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
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: foregroundColor,
                child: IconButton(
                  onPressed: () {
                    RouteGenerator.navigateToPage(context, Routes.signupRoute);
                  },
                  icon: Icon(Icons.arrow_back),
                ),
              ),

              SizedBox(height: 20),

              Center(
                child: CustomText(
                  data: welcomeBackStr,
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
              ),
              SizedBox(height: 20),
              CustomText(
                data: nameStr,
                fontWeight: FontWeight.bold,
                fontSize: 20,
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
              SizedBox(height: 20),
              CustomText(
                data: passwordStr,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              CustomTextformfield(
                controller: _passwordController,
                hintText: passwordStr,
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validatePasswordStr;
                  }
                  return null;
                },
                obscureText: visible ? true : false,
                suffixIcon: IconButton(
                  color: primaryColor,
                  onPressed: () {
                    setState(() {
                      visible = !visible;
                    });
                  },
                  icon: visible
                      ? Icon(Icons.visibility_off_outlined)
                      : Icon(Icons.visibility_outlined),
                ),
              ),

              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      bool ok = await _biometricAuth.loginWithBiometrics();
                      if (ok) {
                        // Real ID and FCM will be handled in BottomNavBarWrapper
                        RouteGenerator.navigateToPage(
                          context,
                          Routes.bottomNavBarRoute,
                        );
                        DisplaySnackbar.show(context, loginSuccessfullStr);
                      } else {
                        DisplaySnackbar.show(context, loginFailedStr);
                      }
                    } catch (e) {
                      DisplaySnackbar.show(context, loginFailedStr);
                    }
                  },
                  icon: Icon(Icons.fingerprint),
                  label: Text("Login with fingerprint"),
                ),
              ),

              Row(
                children: [
                  Checkbox(
                    value: rememberMe,
                    onChanged: (bool? value) {
                      setState(() {
                        rememberMe = value! ? true : false;
                      });
                    },
                  ),
                  CustomText(
                    data: rememberMeStr,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  Spacer(),
                  CustomInkwell(
                    onTap: () {
                      RouteGenerator.navigateToPage(
                        context,
                        Routes.forgotPasswordRoute,
                      );
                    },
                    child: CustomText(
                      data: forgotPasswordStr,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              CustomElevatedbutton(
                onPressed: () {
                  // CHANGE: Validate form and call login (loader handled inside)
                  if (_formKey.currentState!.validate()) {
                    login();
                  }
                },
                child: CustomText(data: loginStr, color: Colors.white),
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
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CustomElevatedbutton(
                    onPressed: () {},
                    width: MediaQuery.of(context).size.width * 0.25,
                    backgroundColor: Colors.white,
                    child: Image.asset("assets/images/google_logo.png"),
                  ),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomText(data: dontHAveanAccountStr, fontSize: 20),
                  CustomInkwell(
                    child: CustomText(
                      data: SignupStr,
                      color: primaryColor,
                      fontSize: 20,
                    ),
                    onTap: () {
                      RouteGenerator.navigateToPage(
                        context,
                        Routes.signupRoute,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
