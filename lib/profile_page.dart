import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/services/api_services.dart';
import 'package:chess_game_manika/services/auth_services.dart';
import 'package:chess_game_manika/services/foreground_service_manager.dart';
import 'package:chess_game_manika/services/chat_websocket_service.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:chess_game_manika/services/mqtt_service.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:chess_game_manika/widgets/custom_elevatedbutton.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // 1. Stop MQTT foreground service
    await ForegroundServiceManager.stop();

    // 2. Clear Chat Provider and Close WebSocket
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    chatProvider.clear();
    ChatWebsocketService().disconnectAll();

    // 3. Clear saved login info
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);
    await prefs.remove('userId');
    await prefs.remove('username');
    await prefs.remove('roomId');

    // 4. Navigate to Login
    RouteGenerator.navigateToPage(context, Routes.loginRoute);
  }

  @override
  Widget build(BuildContext context) {
    if (profileData == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: whiteColor),
          onPressed: () {
            RouteGenerator.navigateToPage(context, Routes.bottomNavBarRoute);
          },
        ),

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: Text("Email"),
              ),
            ),

            const SizedBox(height: 20),
            // TEMPORARY TEST BUTTON
            ElevatedButton.icon(
              icon: const Icon(Icons.bug_report),
              label: const Text("TEST MQTT"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                SharedPreferences.getInstance().then((prefs) {
                  final uid = prefs.getInt('userId');
                  if (uid != null) {
                    MqttService().testPublish(uid);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Sent Test MQTT to User $uid")),
                    );
                  }
                });
              },
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
