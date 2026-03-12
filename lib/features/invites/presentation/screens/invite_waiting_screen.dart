import 'dart:async';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:chess_game_manika/features/game/presentation/screens/chess_board.dart';
import 'package:chess_game_manika/features/notifications/services/notification_service.dart';
import 'package:chess_game_manika/features/invites/services/invite_services.dart';
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
  final SignalingService _signalingService = SignalingService();
  bool _isConnectingCall = false;
  String _statusMessage = "Waiting for opponent to accept...";
  Timer? _pollingTimer;

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
    _startPollingFallback();
  }

  void _startPollingFallback() {
    // Poll every 4 seconds as a fallback for missing FCM events (common on web foreground)
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!mounted || _isConnectingCall) return;

      debugPrint("[InviteWaiting] Polling fallback check...");
      try {
        final invites = await InviteService().getPendingInvites();
        // If our roomId is no longer in the pending invites list, it was likely accepted
        // (or declined, but we check for type in handleInviteAccepted usually)
        // Actually, the best way is to verify if we are now in the game room.
        final stillPending = invites.any(
          (inv) =>
              int.tryParse(inv['room_id']?.toString() ?? "0") == widget.roomId,
        );

        if (!stillPending && !_isConnectingCall) {
          debugPrint(
            "[InviteWaiting] Room ${widget.roomId} no longer pending. Triggering transition.",
          );
          _handleInviteAccepted();
        }
      } catch (e) {
        debugPrint("[InviteWaiting] Polling error: $e");
      }
    });
  }

  void _listenForInviteResponse() {
    _fcmSubscription = NotificationService.fcmEventStream.listen((data) {
      if (!mounted) return;

      debugPrint("[InviteWaiting] FCM event received: $data");

      int evRoomId = int.tryParse(data['room_id']?.toString() ?? "0") ?? 0;

      if (evRoomId == widget.roomId && data['type'] == 'invite_accepted') {
        _handleInviteAccepted();
      } else if (evRoomId == widget.roomId &&
          data['type'] == 'invite_declined') {
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });
  }

  void _handleInviteAccepted() async {
    if (!mounted) return;

    setState(() {
      _isConnectingCall = true;
      _statusMessage = "Advancing to game board...";
    });

    // We navigate immediately. The GameBoard will handle initializing signaling
    // in its own initState, which is more robust as it owns the cycle.
    _enterGameBoard();
  }

  Future<void> _enterGameBoard() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int currentUserId = prefs.getInt('userId') ?? 0;

    if (!mounted) return;

    // Use pushReplacement to ENSURE the waiting screen (the loader) is gone
    // and replaced by the game board in the navigation stack.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameBoard(
          roomId: widget.roomId,
          currentUserId: currentUserId,
          isMultiplayer: true,
          amIWhite: true,
          opponentId: widget.targetUserId,
          showLeaveButton: true,
          signalingService: _signalingService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
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
            colors: [Color(0xFF303030), Color(0xFF121212)],
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
              _isConnectingCall
                  ? "Invitation Accepted!"
                  : "Waiting for Opponent",
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isConnectingCall
                  ? _statusMessage
                  : "Waiting for ${widget.targetUserName} to accept...",
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
