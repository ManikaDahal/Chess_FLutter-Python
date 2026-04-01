import 'dart:async';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/features/call/services/recording_service.dart';
import 'package:chess_game_manika/features/call/services/signaling_service.dart';
import 'package:chess_game_manika/features/notifications/services/sticky_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess_game_manika/features/call/presentation/providers/call_provider.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String roomId;
  final bool isIncomingCall;
  final bool isInitialVideo;
  final SignalingService?
  signalingService; // For incoming calls, use existing instance
  final int? currentUserId; // Required to restore room residency on exit
  final bool canMinimize; // Restrict minimization for non-game calls

  const CallScreen({
    super.key,
    required this.roomId,
    this.isIncomingCall = false,
    this.isInitialVideo = true,
    this.signalingService,
    this.currentUserId,
    this.canMinimize = true,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  late final SignalingService _signalingService;
  bool _isMuted = false;
  late String _status;
  final List<String> _logs = [];
  bool _showDiagnostics = false;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RecordingService _recordingService = RecordingService();
  bool _isMinimizing = false;

  // Stream subscriptions for cleanup
  StreamSubscription? _hangupSubscription;
  StreamSubscription? _acceptSubscription;
  StreamSubscription? _connectionSubscription;

  bool _isVideoOn = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late String _wsUrl;

  @override
  void initState() {
    super.initState();

    // Use provided signaling service for incoming calls, or create new for outgoing
    _signalingService = widget.signalingService ?? SignalingService();
    // Using scheduleMicrotask to avoid modifying provider state during build/initState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callProvider.notifier).setActiveCallService(_signalingService);
      ref.read(callProvider.notifier).setVideoEnabled(_isVideoOn);
      ref.read(callProvider.notifier).setMuted(_isMuted);
    });

    // Set initial status based on call type
    String callType = widget.isInitialVideo ? "Video" : "Audio";

    // Check if we are restoring an already active call session.
    if (_signalingService.hasActiveCall) {
      _status = _signalingService.isCallConnected ? "Connected" : "Calling...";
    } else {
      _status = widget.isIncomingCall
          ? "Incoming $callType Call..."
          : "${callType} Calling...";
    }
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
    _initRenderers().then((_) async {
      if (mounted) {
        _wsUrl = Constants.wsBaseUrl;
        _setupSignalingListeners();
        _setupRecordingStatusListener(); // Listen for recording changes

        // Reset the recording flag for every fresh call screen instance
        _recordingService.hasShownRecordingPopup = false;

        // NOTE: We do NOT stop the StickyNotificationService here anymore.
        // It will be stopped once the user confirms recording in the dialog.
        // An early stop here was causing a double-stop bug.

        // If this screen is being restored (e.g. from minimized overlay),
        // the service already has streams. Attach them immediately.
        _attachExistingStreams();
        _connectAndInitiate();
      }
    });
  }

  void _setupRecordingStatusListener() {
    _recordingService.statusNotifier.addListener(() {
      if (!mounted) return;
      final status = _recordingService.statusNotifier.value;
      debugPrint('CallScreen: Recording status changed to: $status');

      // Wrap in try/catch: in release mode, ScaffoldMessenger can fail if
      // the widget tree is in an unexpected state during async callbacks.
      try {
        if (status == RecordingStatus.recording) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("🔴 Recording ACTIVE"),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        } else if (status == RecordingStatus.saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ Recording Saved successfully!"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        } else if (status == RecordingStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Recording failed to save."),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        debugPrint('CallScreen: Error showing recording status snackbar: $e');
      }
    });
  }

  /// Instantly populates renderers if the signaling service already has
  /// active streams (used when restoring a minimized call).
  void _attachExistingStreams() {
    final existingRemote = _signalingService.remoteStream;
    final existingLocal = _signalingService.localStream;

    // If we have a remote stream, we are definitely connected.
    if (existingRemote != null && mounted) {
      setState(() => _status = 'Connected');

      // Short delay to ensure texture/renderer is ready
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = existingRemote;
          });
          debugPrint('CallScreen: Attached existing remote stream on restore');
          _startCallRecording(); // Ensure recording trigger on restore
        }
      });
    }

    if (existingLocal != null && mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = existingLocal;
          });
          debugPrint('CallScreen: Attached existing local stream on restore');
        }
      });
    }
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
            _startCallRecording();
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

    // Use broadcast streams instead of direct callbacks to avoid listener hijacking
    _acceptSubscription = _signalingService.onCallAcceptedStream.listen((_) {
      if (mounted) {
        _logs.add('📶 Peer accepted via signaling. Waiting for ICE...');
      }
    });

    _hangupSubscription = _signalingService.onHangupStream.listen((_) {
      debugPrint('CallScreen: Hangup signal received from peer');
      _endCallAndCleanup(fromPeer: true);
    });

    _signalingService.localStreamNotifier.addListener(_onLocalStreamChanged);
    _signalingService.remoteStreamNotifier.addListener(_onRemoteStreamChanged);
  }

  void _onLocalStreamChanged() {
    final stream = _signalingService.localStreamNotifier.value;
    if (mounted && stream != null) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
      _logs.add('📹 Local renderer set');
    }
  }

  void _onRemoteStreamChanged() {
    final stream = _signalingService.remoteStreamNotifier.value;
    if (mounted && stream != null) {
      debugPrint(
        'CallScreen: [STATUS_SYNC] Remote stream detected (${stream.id}), attaching to renderer.',
      );

      setState(() {
        _remoteRenderer.srcObject = stream;
      });

      // Redundant assignment for stability
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _remoteRenderer.srcObject != stream) {
          setState(() => _remoteRenderer.srcObject = stream);
        }
      });

      _logs.add('📹 Remote renderer set');
      // DO NOT set _status = "Connected" or trigger _startCallRecording here.
      // Wait for the actual RTCPeerConnectionStateConnected event to fire for that.
    }
  }

  void _connectAndInitiate() async {
    try {
      // Connect if not already connected (from BottomnavBar)
      if (!_signalingService.isConnected) {
        await _signalingService.connect(_wsUrl, widget.roomId);
      }

      // If we are already in the middle of a call session (sent offer or sent answer),
      // then we are restoring the UI and should not re-initiate signaling.
      if (_signalingService.inCallSession) {
        debugPrint(
          'CallScreen: Signaling session already active (restoring), skipping initiation.',
        );
        // If it's already connected, ensure the status reflects it
        if (_signalingService.isCallConnected && mounted) {
          setState(() => _status = "Connected");
          _startCallRecording(); // Ensure trigger if already connected
        }
        return;
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

  bool _isCleanedUp = false;

  @override
  void dispose() {
    debugPrint(
      'CallScreen: dispose() called. isCleanedUp: $_isCleanedUp, isMinimizing: $_isMinimizing',
    );

    // Always dispose renderers safely
    try {
      _remoteRenderer.srcObject = null;
      _localRenderer.srcObject = null;
      _remoteRenderer.dispose();
      _localRenderer.dispose();
    } catch (e) {
      debugPrint('CallScreen: Error disposing renderers: $e');
    }

    // Only run cleanup if it hasn't been done yet (e.g., when Android kills the screen directly)
    // If _endCallAndCleanup() already ran, skip to avoid double-ending the stream
    if (!_isCleanedUp && !_isMinimizing) {
      debugPrint('CallScreen: Running emergency dispose cleanup...');
      try {
        _signalingService.endCall(sendSignal: true);
      } catch (e) {
        debugPrint('CallScreen: Error in emergency endCall: $e');
      }
      try {
        _recordingService.stopRecording();
      } catch (e) {
        debugPrint('CallScreen: Error in emergency stopRecording: $e');
      }
      ref.read(callProvider.notifier).setActiveCallService(null);
      ref.read(callProvider.notifier).setIsMinimized(false);
      ref.read(callProvider.notifier).setActiveRoomId(null);
    }

    try {
      _signalingService.localStreamNotifier.removeListener(
        _onLocalStreamChanged,
      );
      _signalingService.remoteStreamNotifier.removeListener(
        _onRemoteStreamChanged,
      );
      _hangupSubscription?.cancel();
      _acceptSubscription?.cancel();
      _connectionSubscription?.cancel();
      FlutterRingtonePlayer().stop();
      _pulseController.dispose();
    } catch (e) {
      debugPrint('CallScreen: Error in final dispose: $e');
    }

    super.dispose();
  }

  // Called when user presses End, or peer sends hangup signal.
  // Strategy: navigate away FIRST, then clean up native resources in a
  // fully-isolated static async context that cannot crash the UI.
  Future<void> _endCallAndCleanup({bool fromPeer = false}) async {
    if (_isCleanedUp) return;
    _isCleanedUp = true;

    debugPrint('CallScreen: Starting cleanup (fromPeer=$fromPeer)');

    // Immediately detach renderers and stop ringtone (sync, safe)
    try {
      _remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      _localRenderer.srcObject = null;
    } catch (_) {}
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}

    // Capture all references BEFORE popping (widget.* unavailable after pop)
    final signalingService = _signalingService;
    final recordingService = _recordingService;
    final currentUserId = widget.currentUserId;
    final shouldSendHangup = !fromPeer;
    final callNotifier = ref.read(callProvider.notifier);

    // Navigate away NOW -- removes Flutter from the equation before native teardown
    if (mounted) {
      RouteGenerator.navigateToPageWithoutStack(
        context,
        Routes.bottomNavBarRoute,
      );
    }

    // Run all heavy cleanup AFTER the screen is gone -- completely safe
    _runPostCallCleanup(
      signalingService: signalingService,
      recordingService: recordingService,
      currentUserId: currentUserId,
      sendHangup: shouldSendHangup,
      callNotifier: callNotifier,
    );
  }

  static Future<void> _runPostCallCleanup({
    required SignalingService signalingService,
    required RecordingService recordingService,
    required int? currentUserId,
    required bool sendHangup,
    required CallNotifier callNotifier,
  }) async {
    // 1. PAUSE: Minimal wait for UI stabilization
    await Future.delayed(const Duration(milliseconds: 200));

    // 2. STOP RECORDING.
    // We do this BEFORE ending signaling to ensure the audio/video tracks are still "alive"
    // while the recorder is wrapping up the file meta-data.
    try {
      if (recordingService.isRecording) {
        debugPrint('PostCallCleanup: Stopping recording...');
        // Extra safety delay before stopping
        await Future.delayed(const Duration(milliseconds: 100));
        await recordingService.stopRecording();
        debugPrint('PostCallCleanup: Recording stop logic completed');
      }
    } catch (e) {
      debugPrint('PostCallCleanup: Recording stop error (non-fatal): $e');
    }

    // 3. PAUSE: Let recorder release file locks
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. END SIGNALING / WebRTC. Releasing Camera/Mic now.
    try {
      debugPrint('PostCallCleanup: Ending signaling...');
      // By now, the recorder is done, so it's safe to tear down the PeerConnection
      await signalingService.endCall(sendSignal: sendHangup);
      debugPrint('PostCallCleanup: Signaling ended');
    } catch (e) {
      debugPrint('PostCallCleanup: Signaling end error (non-fatal): $e');
    }

    // 5. PAUSE: Final settle
    await Future.delayed(const Duration(milliseconds: 200));

    // 7. Restore basic global flags
    try {
      callNotifier.setActiveCallService(null);
      callNotifier.setIsMinimized(false);
      callNotifier.setActiveRoomId(null);
      
      // REMOVED: callNotifier.ensureRoomResidency(currentUserId);
      // NOTE: We no longer trigger a background reconnect here because
      // the LandingPage/AuthChecker handles its own state on entry.
      // Background reconnects in static context were causing 4-second app exits.
    } catch (e) {
      debugPrint('PostCallCleanup: Global state error (non-fatal): $e');
    }
    try {
      debugPrint('PostCallCleanup: Resetting sticky notification to tips mode...');
      // Small delay ensures screen recording plugin has fully cleared its own notification first
      await Future.delayed(const Duration(milliseconds: 500));
      await StickyNotificationService.setRecordingState(false);
      debugPrint('PostCallCleanup: Sticky notification reset.');
    } catch (e) {
      debugPrint('PostCallCleanup: Notification reset error (non-fatal): $e');
    }
  }

  void _startCallRecording() async {
    if (_recordingService.hasShownRecordingPopup) return;
    _recordingService.hasShownRecordingPopup = true;

    // Show popup notification
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.black87,
          title: const Row(
            children: [
              Icon(Icons.fiber_manual_record, color: Colors.red),
              SizedBox(width: 10),
              Text("Recording Started", style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            "Your voice and video is being recorded for security and quality purposes.",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // Capture details BEFORE popping the dialog to be absolutely safe
                final size = MediaQuery.of(context).size;
                final roomId = widget.roomId;

                Navigator.pop(dialogContext);

                debugPrint('CallScreen: User clicked OK on recording dialog');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Preparing recording... (Please grant microphone & screen casting permission if asked)",
                      ),
                      backgroundColor: Colors.blueAccent,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }

                // Wait 3 seconds to ensure SNACKBAR shows and FGS is ready.
                Future.delayed(const Duration(milliseconds: 3000), () async {
                  debugPrint(
                    'CallScreen: Triggering RecordingService.startRecording with roomId: $roomId',
                  );

                  await _recordingService.startRecording(
                    roomId,
                    width: size.width.toInt(),
                    height: size.height.toInt(),
                  );
                });
              },
              child: const Text(
                "OK",
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _signalingService.toggleMute(_isMuted);
    ref.read(callProvider.notifier).setMuted(_isMuted);
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOn = !_isVideoOn;
    });
    _signalingService.toggleVideo(_isVideoOn);
    ref.read(callProvider.notifier).setVideoEnabled(_isVideoOn);
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

  void _minimizeCall() {
    debugPrint('CallScreen: Minimizing call for room ${widget.roomId}');
    _isMinimizing = true;
    ref.read(callProvider.notifier).setActiveRoomId(widget.roomId);
    ref.read(callProvider.notifier).setIsMinimized(true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video/audio background. keep the renderer in
          // the widget tree at all times so that audio is routed correctly
          // even on audio‑only calls.  A placeholder is painted on top when
          // there's no video track.
          Positioned.fill(
            child: RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
          if (_remoteRenderer.srcObject == null ||
              _remoteRenderer.srcObject!.getVideoTracks().isEmpty)
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
                Stack(
                  children: [
                    _buildHeader(),
                    if (widget.canMinimize)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: IconButton(
                          icon: const Icon(
                            Icons.close_fullscreen,
                            color: Colors.white,
                          ),
                          onPressed: _minimizeCall,
                          tooltip: "Minimize",
                        ),
                      ),
                  ],
                ),

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
                onPressed: _endCallAndCleanup,
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
