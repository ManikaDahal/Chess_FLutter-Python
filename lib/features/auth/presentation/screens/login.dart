import 'package:chess_game_manika/bottom_navbar.dart';
import 'package:chess_game_manika/features/auth/presentation/screens/set_password_screen.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/splin_kit.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/features/auth/services/auth_biometrics.dart';
import 'package:chess_game_manika/features/auth/services/auth_services.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/core/widgets/custom_Inkwell.dart';
import 'package:chess_game_manika/core/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/core/widgets/custom_text.dart';
import 'package:chess_game_manika/core/widgets/custom_textformfield.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final BiometricAuth _biometricAuth = BiometricAuth();
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  bool visible = false;
  bool rememberMe = false;
  final _formKey = GlobalKey<FormState>();
  bool loader = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      loader = true;
    });

    try {
      await _googleSignIn.signOut(); // Force account picker
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

        if (result['is_new_user'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SetPasswordScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => BottomNavBarWrapper()),
          );
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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      rememberMe = prefs.getBool('rememberMe') ?? false;
      if (rememberMe) {
        _emailController.text = prefs.getString('savedEmail') ?? '';
        _passwordController.text = prefs.getString('savedPassword') ?? '';
      }
    });
  }

  // CHANGE: Updated to login with email
  Future<void> login() async {
    // Show loader
    setState(() {
      loader = true;
    });

    try {
      final success = await _authService.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      // Hide loader
      setState(() {
        loader = false;
      });

      if (success) {
        // Save email flag first for quick access
        final prefs = await SharedPreferences.getInstance();
        final email = _emailController.text.trim();
        final password = _passwordController.text.trim();

        await prefs.setBool('rememberMe', rememberMe);
        if (rememberMe) {
          await prefs.setString('savedEmail', email);
          await prefs.setString('savedPassword', password);
        } else {
          await prefs.remove('savedEmail');
          await prefs.remove('savedPassword');
        }

        await prefs.setString('email', email);
        await prefs.setBool('loggedIn', true);

        // Fetch real user ID from backend profile API
        try {
          final profile = await ApiService().getProfile();
          final int realUserId = profile['id'] ?? 0;
          await prefs.setInt('userId', realUserId);
          print("Login: Saved real userId=$realUserId from profile API");
        } catch (e) {
          print("Login: WARNING - Could not fetch profile to get userId: $e");
          // userId will be 0 as fallback — game features will fail
        }

        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => BottomNavBarWrapper()),
            );
          });
          DisplaySnackbar.show(context, loginSuccessfullStr);
        }
      } else {
        if (mounted) {
          DisplaySnackbar.show(context, 'Invalid email or password');
        }
      }
    } catch (e) {
      // Hide loader on error
      setState(() {
        loader = false;
      });

      if (mounted) {
        String errorMessage = 'Invalid email or password';
        String exceptionMsg = e.toString();
        if (exceptionMsg.contains('Exception:')) {
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
          // Premium Gradient Background
          Container(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFE3F2FD), // Light blue tint
                  Colors.white,
                  Colors.white,
                ],
              ),
            ),
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
                  RouteGenerator.navigateToPage(context, Routes.signupRoute);
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
                  child: const Icon(Icons.arrow_back, color: Color(0xFF2196F3)),
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
                data: emailAddressStr,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              CustomTextformfield(
                controller: _emailController,
                hintText: emailAddressStr,
                keyboardType: TextInputType.emailAddress,
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validateEmailAddressStr;
                  }
                  final emailRegex = RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  );
                  if (!emailRegex.hasMatch(p0)) {
                    return "Please enter a valid email address";
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

              const SizedBox(height: 25),
              Center(
                child: Container(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2196F3), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      foregroundColor: const Color(0xFF2196F3),
                    ),
                    onPressed: () async {
                      try {
                        bool ok = await _biometricAuth.loginWithBiometrics();
                        if (ok) {
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
                    icon: const Icon(Icons.fingerprint, size: 28),
                    label: const Text(
                      "Login with Biometrics",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

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
                    onPressed: _handleGoogleSignIn,
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  );
}
