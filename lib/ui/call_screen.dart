import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/signaling_service.dart';
import '../core/utils/const.dart';

class CallScreen extends StatefulWidget {
  final String roomId;
  final bool isIncomingCall;

  const CallScreen({
    super.key,
    required this.roomId,
    this.isIncomingCall = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final SignalingService _signalingService = SignalingService();
  bool _isMuted = false;
  late String _status;
  final List<String> _logs = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late String _wsUrl;

  @override
  void initState() {
    super.initState();

    // Set initial status based on call type
    _status = widget.isIncomingCall ? "Incoming Call..." : "Calling...";

    // Pulse animation for avatar
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (Constants.baseUrl.startsWith("https")) {
      _wsUrl = Constants.baseUrl.replaceAll("https://", "wss://");
    } else {
      _wsUrl = Constants.baseUrl.replaceAll("http://", "ws://");
    }

    _setupSignalingListeners();
    _connectAndInitiate();
  }

  void _setupSignalingListeners() {
    _signalingService.onConnectionStateChange = (state) {
      if (!mounted) return;
      setState(() {
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _status = "Connected";
            FlutterRingtonePlayer().stop();
            _pulseController.stop();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _status = "Failed";
            FlutterRingtonePlayer().stop();
            break;
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _status = "Disconnected";
            FlutterRingtonePlayer().stop();
            break;
          default:
            _status = state.toString().split('.').last;
        }
      });
    };

    _signalingService.onLog = (log) {
      if (mounted) setState(() => _logs.add(log));
    };

    _signalingService.onCallAccepted = () {
      if (mounted) {
        setState(() => _status = "Connected");
      }
    };

    _signalingService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() => _status = "Audio Connected");
      }
    };
  }

  void _connectAndInitiate() async {
    try {
      // Connect if not already connected (from BottomnavBar)
      if (!_signalingService.isConnected) {
        await _signalingService.connect(_wsUrl, widget.roomId);
      }

      // If we are the caller, start the call
      if (!widget.isIncomingCall) {
        await _signalingService.startCall();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
        setState(() => _status = "Connection Failed");
      }
    }
  }

  @override
  void dispose() {
    // If we leave the screen, we stop the call tracks but keep the websocket (endCall vs disconnect)
    _signalingService.endCall();
    FlutterRingtonePlayer().stop();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _signalingService.toggleMute(_isMuted);
  }

  void _acceptCall() {
    FlutterRingtonePlayer().stop();
    _signalingService.acceptCall();
    setState(() => _status = "Connecting...");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2C3E50), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Room: ${widget.roomId}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Avatar with Pulse
              Center(
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_status == "Connected" ||
                                  _status == "Audio Connected")
                              ? Colors.greenAccent.withOpacity(0.3)
                              : Colors.white10,
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 80,
                      backgroundColor: Colors.white10,
                      child: Icon(Icons.person, size: 80, color: Colors.white),
                    ),
                  ),
                ),
              ),

              // Controls
              Padding(
                padding: const EdgeInsets.only(bottom: 50.0),
                child: Column(
                  children: [
                    // Mute Toggle (Only show if connected or calling)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 30.0),
                      child: IconButton(
                        icon: Icon(
                          _isMuted ? Icons.mic_off : Icons.mic,
                          color: _isMuted ? Colors.redAccent : Colors.white,
                          size: 30,
                        ),
                        onPressed: _toggleMute,
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline / Hangup Button
                        _buildCallButton(
                          color: Colors.redAccent,
                          icon: Icons.call_end,
                          label: "End",
                          onPressed: () => Navigator.pop(context),
                        ),

                        // Answer Button (Only if incoming and not yet connected)
                        if (widget.isIncomingCall &&
                            _status == "Incoming Call...")
                          _buildCallButton(
                            color: Colors.green,
                            icon: Icons.call,
                            label: "Accept",
                            onPressed: _acceptCall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
