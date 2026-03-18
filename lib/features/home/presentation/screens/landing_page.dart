import 'package:chess_game_manika/core/ads/ad_service.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/features/game/presentation/screens/chess_board.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chess_game_manika/core/api/api_services.dart';

class LandingPage extends StatefulWidget {
  final Function(int)? onTabChange;
  const LandingPage({super.key, this.onTabChange});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  Map<String, dynamic>? profileData;
  bool _loading = true;

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
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
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
                  Text(
                    profileData?['rank_name'] ?? "Novice", // Dynamic rank
                    style: const TextStyle(
                      color: primaryYellow,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              _buildResourceItem(Icons.monetization_on, "1,250", primaryYellow),
              const SizedBox(width: 10),
              _buildResourceItem(Icons.diamond, "50", Colors.cyanAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResourceItem(IconData icon, String value, Color color) {
    return Container(
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
            title: "PLAY WITH FRIENDS",
            subtitle: "Challenge and chat with your buddies",
            icon: Icons.people_alt_rounded,
            color: accentGreen,
            onTap: () {
              if (widget.onTabChange != null) {
                widget.onTabChange!(1);
              }
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSecondaryModeButton(
                  title: "PRACTICE",
                  icon: Icons.psychology_rounded,
                  color: Colors.blueAccent,
                  onTap: () {
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
                  },
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildSecondaryModeButton(
                  title: "SNAKE GAME",
                  icon: Icons.gesture_rounded,
                  color: Colors.orangeAccent,
                  onTap: () {
                    RouteGenerator.navigateToPage(
                      context,
                      Routes.snakeBoardSelectionRoute,
                    );
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
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Come back tomorrow for your daily gift!",
                    style: TextStyle(color: Colors.black),
                  ),
                  backgroundColor: Colors.white,
                ),
              );
            },
          ),
          Container(height: 40, width: 1, color: Colors.white10),
          _buildRewardIcon(
            Icons.play_circle_filled_rounded,
            "WATCH AD",
            Colors.purpleAccent,
            () {
              AdService().showRewardedAd(
                onUserEarnedReward: (reward) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Reward Earned! You got 100 gold.",
                        style: TextStyle(color: Colors.black),
                      ),
                      backgroundColor: Colors.white,
                    ),
                  );
                },
              );
            },
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
}
