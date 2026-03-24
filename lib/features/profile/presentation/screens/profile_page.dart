import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/display_snackbar.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/core/utils/string_utils.dart';
import 'package:chess_game_manika/core/widgets/custom_elevatedbutton.dart';
import 'package:chess_game_manika/features/auth/services/auth_services.dart';
import 'package:chess_game_manika/features/chat/services/chat_websocket_service.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {

  final ApiService api = ApiService();
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

    // 1. Stop services and clear providers
    ref.read(chatProvider.notifier).clear();

    ChatWebsocketService().disconnectAll();

    // 2. Perform centralized logout
    await AuthServices().logout();

    // 3. Navigate to Login
    if (mounted) {
      RouteGenerator.navigateToPage(context, Routes.loginRoute);
    }
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

        title: Text(profilePageStr, style: TextStyle(color: whiteColor)),
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

            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: ListTile(
                leading: const Icon(Icons.mic, color: Colors.blue),
                title: const Text(
                  "Talk with Yourself",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text("AI Voice Twin"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  RouteGenerator.navigateToPage(context, Routes.selfChatRoute);
                },
              ),
            ),
            // Card(
            //   elevation: 3,
            //   shape: RoundedRectangleBorder(
            //     borderRadius: BorderRadius.circular(12),
            //   ),
            //   margin: const EdgeInsets.symmetric(vertical: 10),
            //   child: ListTile(
            //     leading: const Icon(Icons.videogame_asset, color: Colors.green),
            //     title: const Text(
            //       "Play Snake Game",
            //       style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            //     ),
            //     subtitle: const Text("Classic Grid Game"),
            //     trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            //     onTap: () {
            //       RouteGenerator.navigateToPage(
            //         context,
            //         Routes.snakeBoardSelectionRoute,
            //       );
            //     },
            //   ),
            // ),

            const SizedBox(height: 20),

            // // TEMPORARY TEST BUTTON
            // ElevatedButton.icon(
            //   icon: const Icon(Icons.bug_report),
            //   label: const Text("TEST MQTT"),
            //   style: ElevatedButton.styleFrom(
            //     backgroundColor: Colors.orange,
            //     foregroundColor: Colors.white,
            //   ),
            //   onPressed: () {
            //     SharedPreferences.getInstance().then((prefs) {
            //       final uid = prefs.getInt('userId');
            //       if (uid != null) {
            //         MqttService().testPublish(uid);
            //         ScaffoldMessenger.of(context).showSnackBar(
            //           SnackBar(content: Text("Sent Test MQTT to User $uid")),
            //         );
            //       }
            //     });
            //   },
            // ),

            // const Spacer(),
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
              child: Text(
                logoutStr,
                style: TextStyle(color: whiteColor, fontSize: 20),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
