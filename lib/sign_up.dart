import 'package:chess_python/core/utils/color_utils.dart';
import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/core/utils/splin_kit.dart';
import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/widgets/custom_Inkwell.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:chess_python/widgets/custom_textformfield.dart';
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

  Future<void> signup() async {
    final success = await _authService.signup(
      _nameController.text.trim(),
      _passwordController.text.trim(),
      _emailAddressController.text.trim(),
    );

    if(success){
      RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
    }
    else{
     DisplaySnackbar.show(context, signupFailedStr);

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
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validateEmailAddressStr;
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
                validator: (p0) {
                  if (p0 == null || p0.isEmpty) {
                    return validatePasswordStr;
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
                    if (!isTermsAndConditionedAgreed) {
                      DisplaySnackbar.show(
                        context,
                        notagreedToTermsAndConditionStr,
                      );
                    }
                    try{
                      signup();

                    }catch(e){
                      DisplaySnackbar.show(context, signupFailedStr);

                    }
                  //   Future.delayed(const Duration(seconds: 2), () async {
                  //     var data = {
                  //       "name": _nameController.text.trim(),
                  //       "email": _emailAddressController.text.trim(),
                  //       "password": _passwordController.text.trim(),
                  //     };
                  //     try {
                  //       FirebaseFirestore firestore =
                  //           FirebaseFirestore.instance;
                  //       await firestore.collection("Register").add(data);
                  //       setState(() {
                  //         loader = false;
                  //       });
                  //       RouteGenerator.navigateToPage(
                  //         context,
                  //         Routes.loginRoute,
                  //       );
                  //       DisplaySnackbar.show(context, signupSuccessfullyStr);
                  //     } catch (e) {
                  //       setState(() {
                  //         loader=false;
                  //       });
                  //       DisplaySnackbar.show(context, failedStr );
                  //     }
                  //   });
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
