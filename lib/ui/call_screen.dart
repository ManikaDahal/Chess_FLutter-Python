import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/signaling_service.dart';
import '../core/utils/const.dart';

class CallScreen extends StatefulWidget {
  final String roomId;
  final bool isIncomingCall;
  final bool isInitialVideo;
  final SignalingService? signalingService; // For incoming calls, use existing instance

  const CallScreen({
    super.key,
    required this.roomId,
    this.isIncomingCall = false,
    this.isInitialVideo = true,
    this.signalingService,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late final SignalingService _signalingService;
  bool _isMuted = false;
  late String _status;
  final List<String> _logs = [];
  bool _showDiagnostics = false;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  bool _isVideoOn = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late String _wsUrl;

  @override
  void initState() {
    super.initState();

    // Use provided signaling service for incoming calls, or create new for outgoing
    _signalingService = widget.signalingService ?? SignalingService();

    // Set initial status based on call type
    String callType = widget.isInitialVideo ? "Video" : "Audio";
    _status = widget.isIncomingCall
        ? "Incoming $callType Call..."
        : "${callType} Calling...";
    _isVideoOn = widget.isInitialVideo;

    // Pulse animation for avatar
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize renderers first, then start signaling
    _initRenderers().then((_) {
      if (mounted) {
        // CHANGE: Using wsBaseUrl for WebSocket (Render)
        _wsUrl = Constants.wsBaseUrl;
        _setupSignalingListeners();
        _connectAndInitiate();
      }
    });
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

    _signalingService.onLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
        _logs.add('📹 Local renderer set');
      }
    };

    _signalingService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _status = "Connected";
          _remoteRenderer.srcObject = stream;
        });
        _logs.add('📹 Remote renderer set');
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
        await _signalingService.startCall(isVideo: widget.isInitialVideo);
      } else {
        // If it's an incoming call, we auto-accept since the user already clicked "Accept" in the dialog
        _acceptCall();
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
    _remoteRenderer.srcObject = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.dispose();
    _localRenderer.dispose();

    _signalingService.endCall();
    FlutterRingtonePlayer().stop();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _signalingService.toggleMute(_isMuted);
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOn = !_isVideoOn;
      // Update status if connected
      if (_status == "Connected") {
        // We keep it as "Connected" but we can add a subtype if we want
      }
    });
    _signalingService.toggleVideo(_isVideoOn);
  }

  void _switchCamera() {
    _signalingService.switchCamera();
  }

  Future<void> _initRenderers() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
  }

  void _acceptCall() {
    FlutterRingtonePlayer().stop();
    _signalingService.acceptCall(isVideo: widget.isInitialVideo);
    setState(() => _status = "Connecting...");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video (Background)
          // We show the renderer only if we have a stream AND we have video tracks in it
          if (_remoteRenderer.srcObject != null &&
              _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            _buildAvatarPlaceholder(),

          // Local Video (PiP)
          if (_localRenderer.srcObject != null && _isVideoOn)
            Positioned(
              right: 20,
              top: 50,
              width: 120,
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black26,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // Overlay Content
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Header
                _buildHeader(),

                if (_status != "Connected" || _showDiagnostics)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "DEBUG DIAGNOSTICS",
                                style: TextStyle(
                                  color: Colors.yellow,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                onPressed: () =>
                                    setState(() => _showDiagnostics = false),
                              ),
                            ],
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (context, index) => Text(
                                _logs[index],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Controls
                Column(
                  children: [
                    if (_status == "Connected")
                      TextButton(
                        onPressed: () => setState(
                          () => _showDiagnostics = !_showDiagnostics,
                        ),
                        child: const Text(
                          "Show Debug Info",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    _buildControls(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3E50), Color(0xFF000000)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: (_status == "Connected")
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _status == "Connected"
                  ? (_isVideoOn
                        ? "Video Call - Connected"
                        : "Audio Call - Connected")
                  : (_status == "RTCIceConnectionStateChecking" ||
                            _status ==
                                "RTCIceConnectionState.RTCIceConnectionStateChecking"
                        ? "Searching for best connection path..."
                        : _status),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Room: ${widget.roomId}",
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 40.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Middle Row: Mic, Camera, Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildRoundButton(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                color: _isMuted ? Colors.redAccent : Colors.white24,
                onPressed: _toggleMute,
              ),
              const SizedBox(width: 20),
              _buildRoundButton(
                icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
                color: _isVideoOn ? Colors.white24 : Colors.redAccent,
                onPressed: _toggleVideo,
              ),
              const SizedBox(width: 20),
              _buildRoundButton(
                icon: Icons.flip_camera_ios,
                color: Colors.white24,
                onPressed: _switchCamera,
              ),
            ],
          ),
          const SizedBox(height: 40),
          // Bottom Row: Hangup/Accept
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.call_end,
                color: Colors.redAccent,
                label: "End",
                onPressed: () => Navigator.pop(context),
              ),
              if (widget.isIncomingCall &&
                  (_status.contains("Incoming") &&
                      !_status.contains("Connected")))
                _buildActionButton(
                  icon: Icons.call,
                  color: Colors.green,
                  label: "Accept",
                  onPressed: _acceptCall,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 55,
        height: 55,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 75,
            height: 75,
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
            child: Icon(icon, color: Colors.white, size: 35),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
