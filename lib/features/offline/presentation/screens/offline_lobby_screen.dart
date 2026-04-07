import 'dart:io';

import 'package:chess_game_manika/core/services/connectivity_service.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/features/auth/presentation/providers/auth_provider.dart';
import 'package:chess_game_manika/features/multiplayer/presentation/local_lobby_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class OfflineLobbyScreen extends ConsumerStatefulWidget {
  const OfflineLobbyScreen({super.key});

  @override
  ConsumerState<OfflineLobbyScreen> createState() => _OfflineLobbyScreenState();
}

class _OfflineLobbyScreenState extends ConsumerState<OfflineLobbyScreen> {
  bool _dialogShown = false;

  @override
  Widget build(BuildContext context) {
    // When internet is restored, show the reconnection dialog once.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      next.whenData((isOnline) {
        if (isOnline && !_dialogShown) {
          setState(() => _dialogShown = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showReconnectionDialog();
          });
        }
      });
    });

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
              _buildOfflineBadge(),
              const Spacer(flex: 1),
              _buildLogo(),
              const Spacer(flex: 1),
              _buildHotspotButton(),
              const Spacer(flex: 2),
              _buildFootnote(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBadge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, color: Colors.redAccent, size: 16),
                SizedBox(width: 8),
                Text(
                  'OFFLINE MODE',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
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
                'assets/images/logo.png',
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
        const SizedBox(height: 12),
        Text(
          'Chess Manika',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildHotspotButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: GestureDetector(
        onTap: _showPermissionExplanationDialog,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: foregroundColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.blueAccent.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.15),
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
                  gradient: LinearGradient(
                    colors: [Colors.blueAccent, Colors.blueAccent.withAlpha(200)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 20),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOTSPOT CHESS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Play with nearby friends without internet',
                      style: TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFootnote() {
    return Text(
      'Connect to the internet to access your full account',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: 11,
      ),
    );
  }

  // ── Reconnection dialog ───────────────────────────────────────────────────

  void _showReconnectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.wifi, color: Colors.greenAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Connection Restored!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Internet connection is back. Would you like to return to the main app?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Allow dialog to re-appear if connectivity drops and returns again
              setState(() => _dialogShown = false);
            },
            child: const Text(
              'STAY OFFLINE',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              // Force a fresh auth check then exit offline mode
              ref.invalidate(authProvider);
              ref.read(offlineModeProvider.notifier).setOfflineMode(false);
            },
            child: const Text(
              'RETURN TO APP',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Permission + navigation helpers (same flow as original landing page) ──

  Future<void> _showPermissionExplanationDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF16213E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.security_rounded, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text(
                'Local Discovery',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'To play with friends nearby, we need permission to discover local devices.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 15),
              _buildPermInfo(
                Icons.wifi_rounded,
                'Nearby Devices',
                'Used to scan and broadcast game lobbies via mDNS.',
              ),
              const SizedBox(height: 10),
              _buildPermInfo(
                Icons.location_on_rounded,
                'Location',
                'Required by Android to detect local network neighbors (not used for tracking).',
              ),
              const SizedBox(height: 15),
              const Text(
                "If prompted, please select 'Allow' or 'While using the app'.",
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'NOT NOW',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _requestAndNavigate();
              },
              child: const Text(
                'CONTINUE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestAndNavigate() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.location,
        Permission.nearbyWifiDevices,
      ].request();

      final bool isLocGranted =
          statuses[Permission.location]?.isGranted ?? false;
      final bool isNearbyGranted =
          statuses[Permission.nearbyWifiDevices]?.isGranted ?? false;

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
        title: const Text(
          'Permissions Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'We cannot find nearby games without these permissions. Please enable them in app settings.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text(
              'OPEN SETTINGS',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToHotspot() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocalLobbyScreen()),
    );
  }
}
