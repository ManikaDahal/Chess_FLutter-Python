import 'dart:async';
import 'package:chess_game_manika/services/notification_service.dart';
import 'package:chess_game_manika/ui/chess_board.dart';
import 'package:chess_game_manika/core/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InviteWaitingScreen extends StatefulWidget {
  final int targetUserId;
  final String targetUserName;
  final int roomId;

  const InviteWaitingScreen({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.roomId,
  });

  @override
  State<InviteWaitingScreen> createState() => _InviteWaitingScreenState();
}

class _InviteWaitingScreenState extends State<InviteWaitingScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription? _fcmSubscription;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _listenForInviteResponse();
  }

  void _listenForInviteResponse() {
    _fcmSubscription = NotificationService.fcmEventStream.listen((data) {
      if (!mounted) return;

      AppLogger.d("[InviteWaiting] FCM event received: $data");

      int evRoomId = int.tryParse(data['room_id']?.toString() ?? "0") ?? 0;

      if (evRoomId == widget.roomId && data['type'] == 'invite_accepted') {
        _enterGameBoard();
      } else if (evRoomId == widget.roomId &&
          data['type'] == 'invite_declined') {
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });
  }

  Future<void> _enterGameBoard() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int currentUserId = prefs.getInt('userId') ?? 0;

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    if (NotificationService.navigatorKey?.currentState != null) {
      NotificationService.navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (_) => GameBoard(
            roomId: widget.roomId,
            currentUserId: currentUserId,
            isMultiplayer: true,
            amIWhite: true,
            opponentId: widget.targetUserId,
            showLeaveButton: true,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
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
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Column(
          children: [
            const Spacer(flex: 2),
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.1),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_search,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "Waiting for Opponent",
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Waiting for ${widget.targetUserName} to accept...",
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 60),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 3,
            ),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.8),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel Invitation",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
