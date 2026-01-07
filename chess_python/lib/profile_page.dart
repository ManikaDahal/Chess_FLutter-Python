import 'dart:convert';

import 'package:chess_python/core/utils/display_snackbar.dart';
import 'package:chess_python/core/utils/route_const.dart';
import 'package:chess_python/core/utils/route_generator.dart';
import 'package:chess_python/services/api_services.dart';
import 'package:chess_python/services/auth_services.dart';
import 'package:chess_python/services/token_storage.dart';
import 'package:chess_python/widgets/custom_elevatedbutton.dart';
import 'package:chess_python/core/utils/color_utils.dart';

import 'package:chess_python/core/utils/string_utils.dart';
import 'package:chess_python/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiService api = ApiService();
  final TokenStorage _storage = TokenStorage();
  final AuthServices _authService = AuthServices();
  Map<String, dynamic>? profileData;
  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  //Load Profile
  Future<void> _loadProfile() async {
    profileData = await api.getProfile();
    setState(() {});
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    RouteGenerator.navigateToPage(context, Routes.loginRoute);
    DisplaySnackbar.show(context, logoutSuccessfulStr);
  }

  @override
  Widget build(BuildContext context) {
    if (profileData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(profilePageStr),
        centerTitle: true,
        backgroundColor: foregroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CircleAvatar(
              child: Center(
                child: Image.asset(
                  "assets/images/profileImg.png",
                  height: 600,
                  width: 600,
                ),
              ),
            ),

            SizedBox(height: 40),
            Text("Username = ${profileData!['name']}"),
            Text("Email = ${profileData!['email']}"),
            Spacer(),
            CustomElevatedbutton(
              onPressed: () {
                _logout();
              },
              child: Text(logoutStr),
            ),
          ],
        ),
      ),
    );

    // return Scaffold(
    //   appBar: AppBar(
    //     title: Text(profilePageStr),
    //     centerTitle: true,
    //     backgroundColor: foregroundColor,
    //   ),
    //   body: Padding(
    //     padding: const EdgeInsets.all(12.0),
    //     child: Column(
    //       children: [
    //         CircleAvatar(
    //           child: Center(
    //             child: Image.asset(
    //               "assets/images/profileImg.png",
    //               height: 600,
    //               width: 600,
    //             ),
    //           ),
    //         ),
    //         Spacer(),
    //         CustomElevatedbutton(
    //            onPressed:(){

    //            },
    //            child: Text(logoutStr),
    //           //() async {
    //           //  try{
    //           //   bool? confirmLogout= await showDialog<bool>(
    //           //     builder: (context)=>AlertDialog(title: Text(confirmLogoutStr),
    //           //     content: Text(reConfirmLogoutStr),
    //           //     actions: [
    //           //       TextButton(onPressed: (){
    //           //         Navigator.pop(context,false);
    //           //       }, child: Text(noStr)),
    //           //       TextButton(onPressed: (){
    //           //           Navigator.pop(context,true);
    //           //       }, child: Text(yesStr)),
    //           //     ],
    //           //     ), context: context);
    //           //    if(confirmLogout==true){
    //           //     await authServices.logout();
    //           //     await SecureStorage().clear();

    //           //   RouteGenerator.navigateToPage(context, Routes.loginRoute);
    //           //   DisplaySnackbar.show(context, logoutSuccessfulStr);
    //           //    }
    //           //  }catch(e){
    //           //   DisplaySnackbar.show(context, e.toString());
    //           //  }
    //           // },

    //         ),
    //       ],
    //     ),
    //   ),
    // );
  }
}
