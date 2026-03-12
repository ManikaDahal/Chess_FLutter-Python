import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// typedef StreamStateCallback = void Function(MediaStream stream);

class SignalingService {
  // REMOVED: Singleton pattern to allow multiple instances (e.g., for general and user-specific rooms)
  // Now, create separate instances in GlobalCallHandler and CallScreen as needed

  WebSocketChannel? _channel;
  String? _currentRoomId;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Completer<void>? _readyCompleter;

  // ValueNotifiers to allow multiple listeners (e.g. CallScreen and Overlay)
  final ValueNotifier<MediaStream?> remoteStreamNotifier =
      ValueNotifier<MediaStream?>(null);
  final ValueNotifier<MediaStream?> localStreamNotifier =
      ValueNotifier<MediaStream?>(null);
  final ValueNotifier<bool> isRemoteMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isRemoteVideoEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String?> remoteMediaTypeNotifier = ValueNotifier<String?>(
    null,
  );

  bool _isCaller = false;
  String? _wsUrl;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isReconnecting = false;
  bool _isConnecting = false;
  final List<RTCIceCandidate> _remoteCandidatesBuffer = [];

  Completer<void>? _pcCompleter;
  Completer<void>? _streamCompleter;
  // StreamStateCallback? onLocalStream;
  // StreamStateCallback? onRemoteStream;
  Function(RTCSignalingState)? onSignalingStateChange;
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(String)? onLog;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  void _log(String message) {
    debugPrint('SERVICE_LOG: $message');
    onLog?.call(message);
  }

  final _incomingCallController = StreamController<void>.broadcast();
  Stream<void> get onIncomingCallStream => _incomingCallController.stream;

  final _hangupController = StreamController<void>.broadcast();
  Stream<void> get onHangupStream => _hangupController.stream;

  final _callAcceptedController = StreamController<void>.broadcast();
  Stream<void> get onCallAcceptedStream => _callAcceptedController.stream;

  // New stream for syncing custom states (like mute/video toggles without full SDP renegotiation)
  final _customMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onCustomMessageStream =>
      _customMessageController.stream;

  final _peerJoinedController = StreamController<void>.broadcast();
  Stream<void> get onPeerJoinedStream => _peerJoinedController.stream;

  // Deprecated: Use streams instead
  @Deprecated('Use onIncomingCallStream')
  Function()? onIncomingCall;

  // Callback for when the call is accepted
  @Deprecated('Use onCallAcceptedStream')
  Function()? onCallAccepted;

  // Callback for when peer hangs up
  @Deprecated('Use onHangupStream')
  Function()? onHangup;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _inCallSession = false;
  bool get inCallSession => _inCallSession;

  String? get currentRoomId => _currentRoomId;
  bool get hasActiveCall =>
      _inCallSession || _peerConnection != null || _pendingOffer != null;
  bool get isCallConnected => _remoteStream != null;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  bool _isRemoteDescriptionSet = false;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
      {'urls': 'stun:stun.services.mozilla.com'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:3478',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': [
          'turns:openrelay.metered.ca:443?transport=tcp',
          'turns:openrelay.metered.ca:3478?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 10,
    'bundlePolicy': 'balanced', // Reverted to balanced for wider compatibility
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  Timer? _iceRestartTimer;
  Timer? _handshakeTimeout;

  Future<void> connect(String wsUrl, String roomId) async {
    if (_isConnecting) {
      _log('⚠️ Connection attempt already in progress for room: $roomId');
      return;
    }

    _isConnecting = true;
    _wsUrl = wsUrl;
    _currentRoomId = roomId;

    // Reset completer for new connection attempt
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError('Aborted by new connection attempt');
    }
    _readyCompleter = Completer<void>();

    try {
      if (_isConnected && !_isReconnecting) {
        if (_currentRoomId == roomId) {
          _log('Already connected to room: $roomId');
          _isConnecting = false;
          return;
        } else if (hasActiveCall) {
          _log(
            '⚠️ Cannot switch room while call is active (Current: $_currentRoomId, Target: $roomId)',
          );
          _isConnecting = false;
          return;
        }
        _log('🔄 Switching room from $_currentRoomId to $roomId');
      }

      // 🧹 Cleanup previous channel before reconnecting to avoid multiple active streams
      if (_channel != null) {
        _log('🧹 Cleaning up previous WebSocket channel');
        try {
          await _channel!.sink.close();
        } catch (e) {
          _log('⚠️ Error closing old channel: $e');
        }
        _channel = null;
      }

      // STRICT SANITIZATION: Remove any stray characters like '#' or trailing slashes
      final cleanWsUrl = wsUrl.trim().replaceAll(RegExp(r'[#/]+$'), '');
      // REMOVE TRAILING SLASH: consistency with working Game service
      final url = '$cleanWsUrl/ws/call/$roomId';

      _log('🌐 Connecting to Signaling: $url (Room: $roomId)');

      // inner helper that actually does one attempt and may throw
      Future<void> _attempt(Uri uri) async {
        await _ensurePeerConnection();

        // sanitize fragments or extra characters that might have crept in
        if (uri.fragment.isNotEmpty) {
          uri = uri.replace(fragment: '');
        }

        // Fix: Use proper default ports if not explicitly set
        if (uri.port == 0) {
          final port = uri.scheme == 'wss' ? 443 : 80;
          uri = uri.replace(port: port);
        }

        _log(
          '📍 URI Components: scheme=${uri.scheme}, host=${uri.host}, port=${uri.port}, path=${uri.path}',
        );

        // diagnostics probe as before
        try {
          final probeScheme = (uri.scheme == 'wss')
              ? 'https'
              : (uri.scheme == 'ws' ? 'http' : uri.scheme);
          // WAKE UP: Hit the root URL (/) instead of the WebSocket path to wake up the server
          // hitting /ws/call/... via GET often returns 404 even if the server is awake
          final probeUri = uri.replace(scheme: probeScheme, path: '/');
          _log('🔎 Probing server root to wake up: $probeUri');
          final resp = await http
              .get(probeUri)
              .timeout(const Duration(seconds: 15));
          _log('🔎 Probe response: ${resp.statusCode}');
        } catch (e) {
          _log('⚠️ Probe failed (server might still be sleeping): $e');
        }

        _channel = WebSocketChannel.connect(uri);
      }

      try {
        try {
          await _attempt(Uri.parse(url));
        } catch (e) {
          _log(
            '🔁 First attempt failed (${e.runtimeType}): $e – attempting fallback scheme',
          );
          // try flipping wss<->ws, https<->http just in case
          Uri fallback = Uri.parse(url);
          if (fallback.scheme == 'wss') {
            fallback = fallback.replace(scheme: 'ws');
          } else if (fallback.scheme == 'ws') {
            fallback = fallback.replace(scheme: 'wss');
          }
          try {
            await _attempt(fallback);
          } catch (e2) {
            _log('❌ Both connection attempts failed (${e2.runtimeType}): $e2');
            // swallow error so caller does not see exception
            // connection state remains false; reconnect timer will retry
          }
        }

        _handshakeTimeout?.cancel();
        // INCREASED TIMEOUT: 30s to handle Render wake-up and slow upgrades
        _handshakeTimeout = Timer(const Duration(seconds: 30), () {
          _log('⏱️ WebSocket handshake timeout - no response from server');
          _channel?.sink.close();
          _handleDisconnect();
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.completeError('Handshake timeout');
          }
        });

        if (_channel == null) {
          throw Exception('WebSocket channel could not be established');
        }

        // Optimistically set connected immediately!
        _isConnected = true;
        if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }
        _startHeartbeat();
        _log('✅ WebSocket Connected optimistically to $roomId');

        _log('✅ WebSocket Connected optimistically to $roomId');

        _channel!.stream.listen(
          (message) {
            _handshakeTimeout?.cancel();
            _isReconnecting = false;
            try {
              _handleMessage(message);
            } catch (e) {
              _log('❌ Error in message handler: $e\nMessage: $message');
            }
          },
          onError: (error) {
            _handshakeTimeout?.cancel();
            _isConnected = false;
            _log('❌ WebSocket Error: $error');
            _handleDisconnect();
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.completeError(error);
            }
          },
          onDone: () {
            _handshakeTimeout?.cancel();
            _isConnected = false;
            _log('📡 WebSocket Closed');
            if (!_connectionController.isClosed) {
              _connectionController.add(false);
            }
            _handleDisconnect();
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.completeError('WebSocket closed');
            }
          },
        );

        // NOW actually wait for the connection to be ready before returning
        await _readyCompleter!.future.timeout(
          const Duration(seconds: 60), // Increased to handle Render wake-up
          onTimeout: () {
            _log('❌ Connection ready timeout after 60 seconds');
            if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
              _readyCompleter!.completeError('Timeout');
            }
            throw Exception(
              'WebSocket connection failed to establish within 15 seconds',
            );
          },
        );
      } catch (e) {
        _handshakeTimeout?.cancel();
        _log('❌ Connection Error during setup: $e');
        _handleDisconnect();
        // swallow error to avoid unhandled exceptions at call sites
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _handshakeTimeout?.cancel();
    _stopHeartbeat();
    _reconnectTimer?.cancel();

    if (_currentRoomId != null) {
      _isReconnecting = true;
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (_currentRoomId != null && !_isConnected) {
          connect(_wsUrl!, _currentRoomId!);
        }
      });
    }
  }

  DateTime? _lastMessageTime;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _lastMessageTime = DateTime.now();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (!_isConnected || _channel == null) return;

      // Check for zombie connection (no message for 60s)
      final now = DateTime.now();
      if (_lastMessageTime != null &&
          now.difference(_lastMessageTime!).inSeconds > 90) {
        _log(
          '⚠️ Zombie connection detected (no message for 90s). Reconnecting...',
        );
        _channel?.sink.close();
        _handleDisconnect();
        return;
      }

      _log('💓 Sending Heartbeat');
      try {
        _channel!.sink.add(
          jsonEncode({'type': 'ping', 'room_id': _currentRoomId}),
        );
      } catch (e) {
        _log('❌ Heartbeat send failed: $e');
        _handleDisconnect();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) return;
    if (_pcCompleter != null) return _pcCompleter!.future;

    _pcCompleter = Completer<void>();
    try {
      _log('🏗️ Creating new PeerConnection');
      _peerConnection = await createPeerConnection(_configuration);

      _peerConnection!.onSignalingState = (state) {
        onSignalingStateChange?.call(state);
      };

      _peerConnection!.onConnectionState = (state) {
        _log('Connection State: ${state.name}');
        onConnectionStateChange?.call(state);
      };

      _peerConnection!.onIceConnectionState = (state) {
        _log('🧊 ICE Connection State: ${state.name}');
        if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
          _startIceRestartTimer();
        } else if (state ==
                RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _stopIceRestartTimer();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _log('❌ ICE Connection Failed/Disconnected - attempting restart...');
          _stopIceRestartTimer();
          if (_isCaller) {
            // Delay slightly to avoid spamming restarts
            Future.delayed(const Duration(seconds: 2), () {
              if (_inCallSession) _triggerIceRestart();
            });
          }
        }
      };

      _peerConnection!.onIceGatheringState = (state) {
        _log('📡 ICE Gathering State: ${state.name}');
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          String type = "unknown";
          if (candidate.candidate!.contains("typ host")) type = "HOST (Local)";
          if (candidate.candidate!.contains("typ srflx")) {
            type = "SRFLX (Public IP)";
          }
          if (candidate.candidate!.contains("typ relay")) {
            type = "RELAY (TURN Server)";
          }

          _log('🧊 Local ICE Candidate: $type');
          _sendSignal({
            'type': 'new_ice_candidate',
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        }
      };

      _peerConnection!.onAddStream = (MediaStream stream) {
        _log('🚞 onAddStream: ${stream.id}');
        // Always assign and update the notifier so UI components refresh
        _remoteStream = stream;
        remoteStreamNotifier.value = null; // force update
        remoteStreamNotifier.value = stream;
      };

      _peerConnection!.onTrack = (event) {
        _log(
          '🚞 onTrack: Kind=${event.track.kind}, Streams=${event.streams.length}',
        );
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          // Always assign and update the notifier so UI components refresh, especially
          // when a new video track is added to the same existing stream ID.
          _remoteStream = stream;
          remoteStreamNotifier.value = null; // force update
          remoteStreamNotifier.value = _remoteStream;
        } else {
          _log('🚞 onTrack: Stream list empty. Manually handling track.');
          // If no stream is provided, we can either use the existing remote one or create a dummy
          if (_remoteStream != null) {
            _remoteStream!.addTrack(event.track);
            remoteStreamNotifier.value = null; // force update
            remoteStreamNotifier.value = _remoteStream;
          }
        }
      };
      _pcCompleter!.complete();
    } catch (e) {
      _pcCompleter!.completeError(e);
      _pcCompleter = null;
      rethrow;
    }
  }

  void _handleMessage(dynamic message) async {
    _lastMessageTime = DateTime.now();
    final data = jsonDecode(message);
    final type = data['type'];

    if (type == 'pong') {
      _log('💓 Pong received');
      return;
    }

    if (type == 'connection_established') {
      _log('✅ Server connection handshake verified');
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _readyCompleter!.complete();
      }
      return;
    }

    if (type == 'peer_joined') {
      if (_inCallSession) {
        _log('📶 Peer joined notification received');
      }
      if (!_peerJoinedController.isClosed) {
        _peerJoinedController.add(null);
      }
      return;
    }

    _log('RX: $type');

    if (type == 'call_offer') {
      _log('📶 Incoming call offer received (InSession: $_inCallSession)');
      _pendingOffer = data['offer'];
      _pendingMediaType = data['mediaType'] ?? 'video';
      remoteMediaTypeNotifier.value = _pendingMediaType;
      if (_inCallSession) {
        await _handleOffer(
          _pendingOffer!,
          isVideo: _localStream?.getVideoTracks().isNotEmpty ?? true,
        );
      } else {
        if (!_incomingCallController.isClosed) {
          _incomingCallController.add(null);
        }
        onIncomingCall?.call(); // Still call deprecated if set
      }
    } else if (type == 'call_answer') {
      _log('📶 Call accepted signal received');
      if (!_callAcceptedController.isClosed) {
        _callAcceptedController.add(null);
      }
      onCallAccepted?.call(); // Still call deprecated if set
      final mediaType = data['mediaType'] as String?;
      if (mediaType != null) {
        remoteMediaTypeNotifier.value = mediaType;
      }
      await _handleAnswer(data['answer']);
    } else if (type == 'call_hangup') {
      _log('📶 Peer hung up signal received');
      if (!_hangupController.isClosed) {
        _hangupController.add(null);
      }
      onHangup?.call(); // Still call deprecated if set
    } else if (type == 'new_ice_candidate') {
      await _handleCandidate(data['candidate']);
    } else if (type == 'custom_message') {
      _log('📶 Custom message received: ${data['data']}');
      final Map<String, dynamic> customData = Map<String, dynamic>.from(
        data['data'],
      );
      if (customData['action'] == 'toggle_mute') {
        isRemoteMuted.value = customData['isMuted'] ?? false;
      } else if (customData['action'] == 'toggle_video') {
        isRemoteVideoEnabled.value = customData['isVideoEnabled'] ?? false;
      }
      if (!_customMessageController.isClosed) {
        _customMessageController.add(customData);
      }
    }
  }

  Map<String, dynamic>? _pendingOffer;
  String? _pendingMediaType;

  String? get pendingMediaType => _pendingMediaType;

  Future<void> prepareMedia({bool isVideo = true}) async {
    _log('🏗️ Preparing media (video: $isVideo)');
    await _ensurePeerConnection();
    await _setupLocalStream(isVideo: isVideo);
  }

  Future<void> acceptCall({bool isVideo = true}) async {
    if (_pendingOffer == null) {
      _log('No pending offer to accept');
      return;
    }

    await _ensurePeerConnection();
    await _setupLocalStream(isVideo: isVideo);
    if (_pendingOffer != null) {
      _inCallSession = true;
      await _handleOffer(_pendingOffer!, isVideo: isVideo);
      _pendingOffer = null;
    }
  }

  Future<void> _setupLocalStream({bool isVideo = true}) async {
    if (_streamCompleter != null) return _streamCompleter!.future;
    _streamCompleter = Completer<void>();

    try {
      // If we already have a stream, check if it satisfies the video requirement
      if (_localStream != null) {
        bool hasVideo = _localStream!.getVideoTracks().isNotEmpty;
        if (!isVideo || hasVideo) {
          _log('♻️ Using existing local stream (Video: $hasVideo)');
          _streamCompleter!.complete();
          return;
        }
        _log('🔄 Existing stream lacks video; re-acquiring...');
        await _localStream!.dispose();
        _localStream = null;
      }

      var micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          _log('Microphone permission denied');
          throw Exception('Microphone permission is required for calls.');
        }
      }

      if (isVideo) {
        var camStatus = await Permission.camera.status;
        if (!camStatus.isGranted) {
          camStatus = await Permission.camera.request();
          if (!camStatus.isGranted) {
            _log('⚠️ Camera permission denied');
          }
        }
      }

      // Use legacy mandatory/optional structure for widest mobile compatibility
      final mediaConstraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isVideo
            ? {
                'mandatory': {
                  'minWidth': '480',
                  'minHeight': '360',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };

      // Fallback constraints for the 2nd attempt (no size requirements - maximum compatibility)
      final fallbackConstraints = <String, dynamic>{
        'audio': true,
        'video': isVideo,
      };

      int attempts = 0;
      while (attempts < 2) {
        try {
          final constraints = attempts == 0 ? mediaConstraints : fallbackConstraints;
          _log('🎥 getUserMedia attempt ${attempts + 1} with constraints: $constraints');
          
          final MediaStream? localStream = await navigator.mediaDevices.getUserMedia(constraints);
          if (localStream == null) {
            throw Exception('navigator.mediaDevices.getUserMedia returned null');
          }
          
          _localStream = localStream;
          localStreamNotifier.value = localStream;
          _log('✅ Got Local Stream: ${localStream.id}');
          // onLocalStream?.call(localStream); // Deprecated

          // Guard: if peerConnection became null (e.g., call was ended during setup),
          // attempt to recover by re-creating it rather than aborting.
          if (_peerConnection == null) {
            _log('⚠️ PeerConnection became null during getUserMedia. Re-creating...');
            _pcCompleter = null;
            await _ensurePeerConnection();
            if (_peerConnection == null) {
              throw Exception('PeerConnection could not be created.');
            }
          }
          
          final RTCPeerConnection pc = _peerConnection!;

          final senders = await pc.getSenders();
          for (var track in localStream.getTracks()) {
            bool alreadyAdded = senders.any((s) => s.track?.id == track.id);
            if (!alreadyAdded) {
              _log('➕ Adding track to pc: ${track.kind} (${track.id})');
              await pc.addTrack(track, localStream);
            } else {
              _log('ℹ️ Track already added: ${track.kind}');
            }
          }

          final transceivers = await pc.getTransceivers();
          for (var t in transceivers) {
            final kind = t.receiver.track?.kind ?? t.sender.track?.kind;
            if (kind == 'audio' || kind == 'video') {
              _log('📡 Explicitly setting transceiver $kind to SendRecv');
              await t.setDirection(TransceiverDirection.SendRecv);
            }
          }
          _streamCompleter!.complete();
          return;
        } catch (e) {
          attempts++;
          _log('❌ getUserMedia Trial $attempts Failed: $e');
          if (attempts >= 2) {
            throw Exception(
              'Cannot access camera/microphone. Please ensure other apps are closed and permissions are granted.',
            );
          }
        }
      }
    } catch (e) {
      _streamCompleter!.completeError(e);
      _streamCompleter = null;
      rethrow;
    } finally {
      _streamCompleter = null; // Reset for toggling video later if needed
    }
  }

  Future<void> _handleOffer(
    Map<String, dynamic> offerData, {
    bool isVideo = true,
  }) async {
    await _ensurePeerConnection();
    _log('📨 Handling Offer: ${offerData['type']} (Video: $isVideo)');
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], offerData['type']),
    );
    _isRemoteDescriptionSet = true;

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true, // Always negotiate video channel
      },
      'optional': [],
    };
    final answer = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(answer);

    _sendSignal({
      'type': 'call_answer',
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'mediaType': isVideo ? 'video' : 'audio',
    });
    _drainRemoteCandidates();
  }

  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerData['sdp'], answerData['type']),
    );
    _isRemoteDescriptionSet = true;
    _drainRemoteCandidates();
  }

  Future<void> _handleCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidateStr = candidateData['candidate'];
      final sdpMid = candidateData['sdpMid'];
      final sdpMLineIndex = candidateData['sdpMLineIndex'] is String
          ? int.tryParse(candidateData['sdpMLineIndex'])
          : candidateData['sdpMLineIndex'];

      if (candidateStr == null) {
        _log('ℹ️ End of candidates signal received');
        return;
      }

      final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);

      if (_peerConnection != null && _isRemoteDescriptionSet) {
        _log('🧊 Adding Remote ICE Candidate immediately');
        await _peerConnection!.addCandidate(candidate);
      } else {
        _log('📦 Buffering Remote ICE Candidate');
        _remoteCandidatesBuffer.add(candidate);
      }
    } catch (e) {
      _log('❌ Error parsing/adding ICE candidate: $e');
    }
  }

  void _drainRemoteCandidates() async {
    if (_peerConnection == null || _remoteCandidatesBuffer.isEmpty) return;
    _log(
      '📥 Draining ${_remoteCandidatesBuffer.length} buffered ICE candidates',
    );
    for (var candidate in _remoteCandidatesBuffer) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteCandidatesBuffer.clear();
  }

  Future<void> startCall({bool isVideo = true}) async {
    _isCaller = true;
    _inCallSession = true;
    _log('📞 Starting Call (video: $isVideo)');
    await _ensurePeerConnection();
    await _setupLocalStream(isVideo: isVideo);

    if (_peerConnection == null) return;

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true, // Always negotiate video channel
      },
      'optional': [],
    };

    final offer = await _peerConnection!.createOffer(constraints);
    await _peerConnection!.setLocalDescription(offer);

    _sendSignal({
      'type': 'call_offer',
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'mediaType': isVideo ? 'video' : 'audio',
    });
  }

  void _sendSignal(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      try {
        _log('TX: ${data['type']}');
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        _log('Error sending signal (channel might be closed): $e');
      }
    } else {
      _log(
        'Error: Channel is null or disconnected, cannot send ${data['type']}',
      );
    }
  }

  void sendCustomMessage(Map<String, dynamic> customData) {
    _sendSignal({'type': 'custom_message', 'data': customData});
  }

  void toggleMute(bool mute) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !mute;
      });
    }
  }

  void toggleVideo(bool videoOn) async {
    final localStream = _localStream;
    if (localStream == null) return;

    if (videoOn && localStream.getVideoTracks().isEmpty) {
      try {
        final MediaStream? videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'mandatory': {
              'minWidth': '480',
              'minHeight': '360',
              'minFrameRate': '30',
            },
            'facingMode': 'user',
            'optional': [],
          },
        });
        
        if (videoStream == null) {
          throw Exception('Video stream is null');
        }

        final videoTrack = videoStream.getVideoTracks()[0];
        await localStream.addTrack(videoTrack);
        
        final pc = _peerConnection;
        if (pc != null) {
          await pc.addTrack(videoTrack, localStream);

          // TRIGGER REBUILD
          localStreamNotifier.value = null;
          localStreamNotifier.value = localStream;

          final offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          _sendSignal({
            'type': 'call_offer',
            'offer': {'type': offer.type, 'sdp': offer.sdp},
            'mediaType': 'video',
          });
        }
      } catch (e) {
        _log('Failed to add video track: $e');
      }
    } else {
      localStream.getVideoTracks().forEach((track) {
        track.enabled = videoOn;
      });
    }
  }


  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  bool _isEnding = false;

  Future<void> endCall({bool sendSignal = true}) async {
    if (_isEnding) {
      _log('⚠️ endCall already in progress, skipping');
      return;
    }
    _isEnding = true;

    _log('🛑 Ending call (SendSignal: $sendSignal)');

    if (sendSignal && _isConnected) {
      _sendSignal({'type': 'call_hangup'});
    }

    final local = _localStream;
    _localStream = null;
    localStreamNotifier.value = null; // Update notifier immediately
    if (local != null) {
      _log('⏹️ Stopping local stream tracks...');
      final tracks = local.getTracks();
      for (var track in tracks) {
        _log('⏹️ Stopping local track: ${track.kind} (${track.id})');
        track.enabled = false;
        track.stop();
      }
      await local.dispose();
    }

    final remote = _remoteStream;
    _remoteStream = null;
    remoteStreamNotifier.value = null; // Update notifier immediately
    if (remote != null) {
      _log('⏹️ Stopping remote stream tracks...');
      final tracks = remote.getTracks();
      for (var track in tracks) {
        _log('⏹️ Stopping remote track: ${track.kind} (${track.id})');
        track.enabled = false;
        track.stop();
      }
      await remote.dispose();
    }

    final pc = _peerConnection;
    _peerConnection = null;
    if (pc != null) {
      _log('🔌 Closing PeerConnection');
      await pc.close();
    }

    _pendingOffer = null;
    _pendingMediaType = null;
    _remoteCandidatesBuffer.clear();
    _isRemoteDescriptionSet = false;
    _isCaller = false;
    _inCallSession = false;
    _isEnding = false;
  }

  void _startIceRestartTimer() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(const Duration(seconds: 15), () {
      if (_peerConnection != null && _isCaller) {
        _log('⏳ ICE stuck in checking. Triggering restart...');
        _triggerIceRestart();
      }
    });
  }

  void _stopIceRestartTimer() {
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
  }

  Future<void> _triggerIceRestart() async {
    if (_peerConnection == null || !_isCaller) return;
    try {
      final offer = await _peerConnection!.createOffer({'iceRestart': true});
      await _peerConnection!.setLocalDescription(offer);
      _sendSignal({
        'type': 'call_offer',
        'offer': {'type': offer.type, 'sdp': offer.sdp},
        'mediaType': _localStream?.getVideoTracks().isNotEmpty == true
            ? 'video'
            : 'audio',
        'iceRestart': true,
      });
    } catch (e) {
      _log('Failed to restart ICE: $e');
    }
  }

  void disconnect() {
    _log('🔌 Manually disconnecting from signaling');
    _currentRoomId = null;
    _handshakeTimeout?.cancel();
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _stopIceRestartTimer();
    endCall();
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
  }
}
