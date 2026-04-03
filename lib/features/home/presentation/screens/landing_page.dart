import 'package:chess_game_manika/core/ads/ad_service.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/features/game/presentation/screens/chess_board.dart';
import 'package:chess_game_manika/features/users/presentation/screens/friend_list.dart';
import 'package:chess_game_manika/features/multiplayer/presentation/local_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'dart:io';
import 'package:chess_game_manika/features/payment/presentation/screens/coin_store_screen.dart';

class LandingPage extends StatefulWidget {
  final Function(int)? onTabChange;
  final bool isSnakeMode;
  final int currentUserId;
  const LandingPage({super.key, this.onTabChange, this.isSnakeMode = false, this.currentUserId = 0});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  Map<String, dynamic>? profileData;

  // Live progress tracking
  final ValueNotifier<int> _coinsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String> _rankNotifier = ValueNotifier<String>("Novice");
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService().getProfile();
      if (mounted) {
        setState(() {
          profileData = data;
          _coinsNotifier.value = data['coins'] ?? 0;
          _rankNotifier.value = data['rank_name'] ?? "Novice";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundColor, Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const Spacer(flex: 1),
              _buildLogo(),
              const Spacer(flex: 1),
              _buildGameModes(),
              const Spacer(flex: 2),
              _buildRewardsSection(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryYellow.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: primaryYellow.withOpacity(0.2),
                  backgroundImage: const AssetImage(
                    "assets/images/profileImg.png",
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profileData?['username'] ?? "Guest",
                    style: const TextStyle(
                      color: whiteColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _rankNotifier,
                    builder: (context, rank, _) => Text(
                      rank,
                      style: const TextStyle(
                        color: primaryYellow,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _coinsNotifier,
                builder: (context, coins, _) => _buildResourceItem(
                  Icons.monetization_on,
                  coins.toString(),
                  primaryYellow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem(IconData icon, String value, Color color) {
    return GestureDetector(
      onTap: () {
        // Navigate to Coin Store
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CoinStoreScreen(
              currentUserId: widget.currentUserId,
            ),
          ),
        ).then((_) => _loadProfile()); // Refresh profile when returning
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(
              value,
              style: const TextStyle(
                color: whiteColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.add_circle, color: color, size: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        TweenAnimationBuilder(
          duration: const Duration(seconds: 2),
          tween: Tween<double>(begin: 0.9, end: 1.1),
          curve: Curves.easeInOutSine,
          builder: (context, double scale, child) {
            return Transform.scale(
              scale: scale,
              child: Image.asset(
                "assets/images/logo.png",
                height: 180,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.emoji_events,
                  size: 100,
                  color: primaryYellow,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGameModes() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        children: [
          _buildMainModeButton(
            title: widget.isSnakeMode ? "PLAY WITH FRIENDS" : "PLAY WITH FRIENDS",
            subtitle: widget.isSnakeMode 
                ? "Challenge friends to a Snake & Ladder match"
                : "Challenge and chat with your buddies",
            icon: widget.isSnakeMode ? Icons.emoji_people_rounded : Icons.people_alt_rounded,
            color: widget.isSnakeMode ? Colors.orangeAccent : accentGreen,
            onTap: () {
              if (widget.isSnakeMode) {
                // Navigate to Board Selection for multiplayer
                RouteGenerator.navigateToPage(
                  context,
                  Routes.snakeBoardSelectionRoute,
                  arguments: true, // true signals multiplayer intent
                );
              } else {
                // Navigate directly to FriendList pre-set for chess invites
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FriendListScreen(
                      currentUserId: widget.currentUserId,
                      gameType: 'chess',
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 15),
          _buildMainModeButton(
            title: "HOTSPOT MODE (OFFLINE)",
            subtitle: "Play with nearby friends without internet",
            icon: Icons.wifi_tethering_rounded,
            color: Colors.blueAccent,
            onTap: () => _showPermissionExplanationDialog(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSecondaryModeButton(
                  title: widget.isSnakeMode ? "SELECT BOARD" : "PRACTICE",
                  icon: widget.isSnakeMode ? Icons.grid_view_rounded : Icons.psychology_rounded,
                  color: Colors.blueAccent,
                  onTap: () {
                    if (widget.isSnakeMode) {
                      RouteGenerator.navigateToPage(
                        context,
                        Routes.snakeBoardSelectionRoute,
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GameBoard(
                            currentUserId: 1,
                            roomId: 1,
                            isMultiplayer: false,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSecondaryModeButton(
                  title: widget.isSnakeMode ? "CHESS GAME" : "SNAKE GAME",
                  icon: widget.isSnakeMode ? Icons.grid_4x4_rounded : Icons.gesture_rounded,
                  color: widget.isSnakeMode ? Colors.purpleAccent : Colors.orangeAccent,
                  onTap: () {
                    if (widget.isSnakeMode) {
                      // Return to Main (Chess) Landing Page
                      RouteGenerator.navigateToPageWithoutStack(
                        context,
                        Routes.bottomNavBarRoute,
                      );
                    } else {
                      // Navigate to Snake Landing Page
                      RouteGenerator.navigateToPage(
                        context,
                        Routes.snakeLandingPageRoute,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainModeButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: foregroundColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withAlpha(200)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: whiteColor, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              // Fix overflow
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: whiteColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: whiteColor.withOpacity(0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: whiteColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryModeButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Color.lerp(
            foregroundColor,
            Colors.black,
            0.3,
          ), // Glassmorphism-ish back
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [color, color.withOpacity(0.5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(bounds),
              child: Icon(icon, color: Colors.white, size: 45),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleWatchAd() {
    AdService().showRewardedAd(
      onUserEarnedReward: (reward) async {
        try {
          final result = await ApiService().updateCoins(100);
          print("COIN UPDATE SUCCESS: ${result['coins']} gold");
          _coinsNotifier.value = result['coins'];
          _rankNotifier.value = result['rank_name'];

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Reward Earned! You got 100 gold.",
                  style: TextStyle(color: Colors.black),
                ),
                backgroundColor: Colors.white,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Error updating coins: $e")));
          }
        }
      },
    );
  }

  void _handleClaimGift() async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);

    try {
      final result = await ApiService().claimDailyGift();
      _coinsNotifier.value = result['coins'];
      _rankNotifier.value = result['rank_name'];

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? "Daily gift claimed!",
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains("Exception: ")) {
          errorMsg = errorMsg.split("Exception: ").last;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMsg,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  Widget _buildRewardsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRewardIcon(
            Icons.card_giftcard_rounded,
            "DAILY GIFT",
            accentRed,
            _handleClaimGift,
          ),
          Container(height: 40, width: 1, color: Colors.white10),
          _buildRewardIcon(
            Icons.play_circle_filled_rounded,
            "WATCH AD",
            Colors.purpleAccent,
            _handleWatchAd,
          ),
        ],
      ),
    );
  }

  Widget _buildRewardIcon(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: whiteColor.withOpacity(0.8),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPermissionExplanationDialog() async {
    // Show premium explanation dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.security_rounded, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text("Local Discovery", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "To play with friends nearby, we need permission to discover local devices.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 15),
              _buildPermInfo(Icons.wifi_rounded, "Nearby Devices", "Used to scan and broadcast game lobbies via mDNS."),
              const SizedBox(height: 10),
              _buildPermInfo(Icons.location_on_rounded, "Location", "Required by Android to detect local network neighbors (not used for tracking)."),
              const SizedBox(height: 15),
              const Text(
                "If prompted, please select 'Allow' or 'While using the app'.",
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("NOT NOW", style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _requestAndNavigate();
              },
              child: const Text("CONTINUE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPermInfo(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.orangeAccent.withOpacity(0.8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestAndNavigate() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.nearbyWifiDevices,
      ].request();

      final bool isLocGranted = statuses[Permission.location]?.isGranted ?? false;
      final bool isNearbyGranted = statuses[Permission.nearbyWifiDevices]?.isGranted ?? false;

      if (isLocGranted || isNearbyGranted) {
        _navigateToHotspot();
      } else {
        _showPermissionDeniedDialog();
      }
    } else {
      _navigateToHotspot();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text("Permissions Required", style: TextStyle(color: Colors.white)),
        content: const Text(
          "We cannot find nearby games without these permissions. Please enable them in app settings.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text("OPEN SETTINGS", style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  void _navigateToHotspot() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalLobbyScreen(isSnakeMode: widget.isSnakeMode),
      ),
    );
  }
}
