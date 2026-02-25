import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../core/utils/const.dart';
import '../core/utils/global_callhandler.dart';
import '../ui/call_screen.dart';

class FloatingCallOverlay extends StatefulWidget {
  const FloatingCallOverlay({super.key});

  @override
  State<FloatingCallOverlay> createState() => _FloatingCallOverlayState();
}

class _FloatingCallOverlayState extends State<FloatingCallOverlay> {
  Offset _offset = const Offset(20, 100);
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  SignalingService? _activeSignalingService;

  @override
  void initState() {
    super.initState();
    debugPrint('FloatingCallOverlay: Initializing overlay state');
    _initRenderer();

    // Listen for minimize changes to connect/disconnect
    GlobalCallHandler().isMinimized.addListener(_handleMinimizeChange);
  }

  void _handleMinimizeChange() {
    if (GlobalCallHandler().isMinimized.value) {
      debugPrint('FloatingCallOverlay: Minimized, connecting to service...');
      _connectToService();
    } else {
      debugPrint('FloatingCallOverlay: Restored, detaching stream...');
      _detachStream();
    }
  }

  void _detachStream() {
    // Stop listening to stream changes when not minimized to avoid wasting resources
    // or interfering with CallScreen.
    _activeSignalingService?.remoteStreamNotifier.removeListener(
      _onRemoteStreamChanged,
    );
    _activeSignalingService = null;
    if (mounted) {
      setState(() {
        _remoteRenderer.srcObject = null;
      });
    }
  }

  Future<void> _initRenderer() async {
    debugPrint('FloatingCallOverlay: Initializing renderer');
    await _remoteRenderer.initialize();
    _connectToService();
  }

  void _connectToService() {
    final service = GlobalCallHandler().activeService;
    debugPrint(
      'FloatingCallOverlay: Connecting to service. Active service found: ${service != null}',
    );

    if (service != null && mounted) {
      _activeSignalingService = service;

      // Update immediately if stream already exists
      if (service.remoteStreamNotifier.value != null) {
        // Give renderer a moment to be "ready" after initialize()
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted &&
              _activeSignalingService?.remoteStreamNotifier.value != null) {
            setState(() {
              _remoteRenderer.srcObject =
                  _activeSignalingService!.remoteStreamNotifier.value;
            });
          }
        });
      }

      // Listen for stream updates
      service.remoteStreamNotifier.addListener(_onRemoteStreamChanged);

      // If service disconnects or peer hangs up, close overlay
      service.onConnectionStateChange = (state) {
        if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          if (mounted) {
            _handleServiceTermination();
          }
        }
      };
    } else if (GlobalCallHandler().isMinimized.value) {
      // If no active service found yet but we are minimized, retry in a second
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && GlobalCallHandler().isMinimized.value) {
          _connectToService();
        }
      });
    }
  }

  void _onRemoteStreamChanged() {
    if (mounted && _activeSignalingService != null) {
      debugPrint('FloatingCallOverlay: Remote stream updated');
      setState(() {
        _remoteRenderer.srcObject =
            _activeSignalingService!.remoteStreamNotifier.value;
      });
    }
  }

  void _handleServiceTermination() {
    GlobalCallHandler().isMinimized.value = false;
    // We already stop recording in CallScreen or by service logic
    // But let's ensure residency is restored
    // Note: Overlay should ideally have currentUserId too, but GlobalCallHandler knows roomId
  }

  @override
  void dispose() {
    GlobalCallHandler().isMinimized.removeListener(_handleMinimizeChange);
    _activeSignalingService?.remoteStreamNotifier.removeListener(
      _onRemoteStreamChanged,
    );
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _restoreCall() {
    final roomId = GlobalCallHandler().activeRoomId.value;
    final navState = Constants.navigatorKey.currentState;

    if (roomId != null && navState != null) {
      GlobalCallHandler().isMinimized.value = false;
      navState.push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            roomId: roomId,
            isIncomingCall: false, // It's already active
            signalingService: GlobalCallHandler().activeService,
          ),
        ),
      );
    } else {
      debugPrint(
        'FloatingCallOverlay: Cannot restore call. Room: $roomId, NavState: ${navState != null}',
      );
    }
  }

  void _endCall() {
    GlobalCallHandler().activeService?.endCall();
    GlobalCallHandler().isMinimized.value = false;
    GlobalCallHandler().activeRoomId.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Colors.black87,
          child: Container(
            width: 120,
            height: 160,
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        children: [
                          ValueListenableBuilder<MediaStream?>(
                            valueListenable:
                                _activeSignalingService?.remoteStreamNotifier ??
                                ValueNotifier(null),
                            builder: (context, stream, _) {
                              if (stream != null) {
                                return RTCVideoView(
                                  _remoteRenderer,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                );
                              }
                              return const Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white24,
                                  size: 40,
                                ),
                              );
                            },
                          ),
                          // Note: In a real implementation, we'd need to pass the stream
                          // or have a shared renderer. For now, showing status.
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              color: Colors.black54,
                              child: const Text(
                                "Ongoing Call",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.open_in_full,
                        size: 18,
                        color: Colors.blueAccent,
                      ),
                      onPressed: _restoreCall,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.call_end,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      onPressed: _endCall,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
