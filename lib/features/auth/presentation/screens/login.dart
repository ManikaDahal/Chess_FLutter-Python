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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';
import 'package:app_settings/app_settings.dart';

class Login extends ConsumerStatefulWidget {
  const Login({super.key});

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login> {
  final BiometricAuth _biometricAuth = BiometricAuth();
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  bool visible = false;
  bool rememberMe = false;
  final _formKey = GlobalKey<FormState>();
  bool loader = false;
  bool _isHardwareSupported = false;
  bool _isBiometricEnrolled = false;
  bool _isBiometricAvailable =
      false; // Backward compatibility with previous if check

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

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

        // Update Riverpod auth state
        final userId = result['user']['id'];
        ref.read(authProvider.notifier).login(userId, googleUser.email);

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
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final isSupported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      final availableBiometrics = await auth.getAvailableBiometrics();
      if (mounted) {
        setState(() {
          _isHardwareSupported = isSupported && canCheck;
          _isBiometricEnrolled = availableBiometrics.isNotEmpty;
          _isBiometricAvailable = _isHardwareSupported && _isBiometricEnrolled;
        });
      }
    } catch (e) {
      print("Error checking biometrics: $e");
    }
  }

  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.fingerprint, color: Color(0xFF2196F3), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Setup Biometrics",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: const Text(
          "Your phone supports biometrics, but you haven't set up any fingerprints or face data yet.\n\n"
          "After clicking 'Go to Settings', please find the 'Biometrics' or 'Fingerprint' section in the Security menu to enroll yours.",
          style: TextStyle(color: Colors.black54, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Not Now",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                // On some devices Security is broad, but it's the safest cross-platform type
                AppSettings.openAppSettings(
                  type: AppSettingsType.generalSettings,
                );
              },
              child: const Text(
                "Go to Settings",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

        int finalUserId = 0;
        // Fetch real user ID from backend profile API
        try {
          final profile = await ApiService().getProfile();
          finalUserId = profile['id'] ?? 0;
          await prefs.setInt('userId', finalUserId);
          print("Login: Saved real userId=$finalUserId from profile API");
        } catch (e) {
          print("Login: WARNING - Could not fetch profile to get userId: $e");
          // userId will be 0 as fallback — game features will fail
        }

        if (mounted) {
          // Update Riverpod auth state
          ref.read(authProvider.notifier).login(finalUserId, email);

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
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_back, color: Color(0xFF2196F3)),
                ),
              ),

              SizedBox(height: 40),

              // Minimalist Header akin to Instagram/Facebook branding
              Center(
                child: CustomText(
                  data: welcomeBackStr,
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  color: primaryColor,
                ),
              ),
              SizedBox(height: 40),
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

              if (_isHardwareSupported) ...[
                const SizedBox(height: 25),
                Center(
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFF2196F3),
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        foregroundColor: const Color(0xFF2196F3),
                      ),
                      onPressed: () async {
                        if (_isBiometricEnrolled) {
                          try {
                            bool ok = await _biometricAuth
                                .loginWithBiometrics();
                            if (ok) {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              final int userId = prefs.getInt('userId') ?? 0;
                              final String email =
                                  prefs.getString('email') ?? '';
                              ref
                                  .read(authProvider.notifier)
                                  .login(userId, email);

                              RouteGenerator.navigateToPage(
                                context,
                                Routes.bottomNavBarRoute,
                              );
                              DisplaySnackbar.show(
                                context,
                                loginSuccessfullStr,
                              );
                            } else {
                              DisplaySnackbar.show(context, loginFailedStr);
                            }
                          } catch (e) {
                            DisplaySnackbar.show(context, loginFailedStr);
                          }
                        } else {
                          _showBiometricSetupDialog();
                        }
                      },
                      icon: Icon(
                        _isBiometricEnrolled
                            ? Icons.fingerprint
                            : Icons.settings_applications_rounded,
                        size: 28,
                      ),
                      label: Text(
                        _isBiometricEnrolled
                            ? "Login with Biometrics"
                            : "Set up Biometrics",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
              SizedBox(height: 24),
              // Enhanced Google Sign In (Full width like Facebook)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _handleGoogleSignIn,
                  icon: Image.asset(
                    "assets/images/google_logo.png",
                    height: 24,
                  ),
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
