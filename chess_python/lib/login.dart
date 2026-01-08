import 'package:chess_python/core/utils/color_utils.dart';
import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/auth_biometrics.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/widgets/custom_Inkwell.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:chess_python/widgets/custom_textformfield.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final BiometricAuth _biometricAuth = BiometricAuth();
  final LocalAuthentication auth = LocalAuthentication();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthServices _authService = AuthServices();
  bool visible = false;
  bool rememberMe = false;
  final _formKey = GlobalKey<FormState>();

  Future<void> login() async {
    final success = await _authService.login(
      _nameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (success) {
      RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
    } else {
      DisplaySnackbar.show(context, loginFailedStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                        //  RouteGenerator.navigateToPage(
                        //           context, Routes.signupRoute);
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
                    child: ElevatedButton.icon(onPressed: ()async {
                        try{
                          bool ok = await _biometricAuth.loginWithBiometrics();
                        if(ok){
                          RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
                           DisplaySnackbar.show(context, loginSuccessfullStr);
                    
                        }else{
                           DisplaySnackbar.show(context, loginFailedStr);
                        }
                        }catch(e){
                          DisplaySnackbar.show(context, loginFailedStr);
                        }
                      }, icon: Icon(Icons.fingerprint),
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
                      login();
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
      ),
    );
  }
}
