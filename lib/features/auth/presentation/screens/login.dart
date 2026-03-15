import 'package:chess_game_manika/bottom_navbar.dart';
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
  final BiometricAuth _biometricAuth = BiometricAuth();
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  bool visible = false;
  bool rememberMe = false;
  final _formKey = GlobalKey<FormState>();
  bool loader = false;

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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  );
}
