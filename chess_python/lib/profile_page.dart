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
  padding: const EdgeInsets.all(16.0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      CircleAvatar(
        radius: 60,
        backgroundColor: Colors.grey.shade200,
        child: ClipOval(
          child: Image.asset(
            "assets/images/profileImg.png",
            fit: BoxFit.cover,
            height: 120,
            width: 120,
          ),
        ),
      ),
      const SizedBox(height: 30),

      // Profile info card
      Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: ListTile(
          leading: Icon(Icons.person, color: foregroundColor),
          title: Text(
            profileData!['username'] ?? '',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text("Username"),
        ),
      ),

      Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: ListTile(
          leading: Icon(Icons.email, color: foregroundColor),
          title: Text(
            profileData!['email'] ?? '',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text("Email"),
        ),
      ),

      const Spacer(),

      CustomElevatedbutton(
        onPressed: () async {
          try {
            bool? confirmLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(confirmLogoutStr),
                content: Text(reConfirmLogoutStr),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(noStr),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(yesStr),
                  ),
                ],
              ),
            );
            if (confirmLogout == true) {
              _logout();
              RouteGenerator.navigateToPage(context, Routes.loginRoute);
              DisplaySnackbar.show(context, logoutSuccessfulStr);
            }
          } catch (e) {
            DisplaySnackbar.show(context, e.toString());
          }
        },
        child: Text(logoutStr),
      ),
      const SizedBox(height: 20),
    ],
  ),
),

  
  );
}
}
