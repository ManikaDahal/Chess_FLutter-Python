import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

typedef StreamStateCallback = void Function(MediaStream stream);

class SignalingService {
  // Singleton pattern for global access
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  WebSocketChannel? _channel;
  String? _currentRoomId;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _isCaller = false;
  String? _wsUrl;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _isReconnecting = false;
  final List<RTCIceCandidate> _remoteCandidatesBuffer = [];

  StreamStateCallback? onLocalStream;
  StreamStateCallback? onRemoteStream;
  Function(RTCSignalingState)? onSignalingStateChange;
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(String)? onLog;

  void _log(String message) {
    debugPrint('SERVICE_LOG: $message');
    onLog?.call(message);
  }

  // Callback for incoming call - can be used globally
  Function()? onIncomingCall;

  // Callback for when the call is actually accepted by the remote peer
  Function()? onCallAccepted;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // CHANGE: Added getter to expose current room ID
  // This allows GlobalCallHandler to know which room incoming calls are from
  String? get currentRoomId => _currentRoomId;

  bool _isRemoteDescriptionSet = false;

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:3478'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:3478'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:3478'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:3478'},
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
    'bundlePolicy':
        'balanced', // Balanced is often more compatible than max-bundle
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  Timer? _iceRestartTimer;

  // Future<void> connect(String wsUrl, String roomId) async {
  //   if (_isConnected && _currentRoomId == roomId) {
  //     onLog?.call('Already connected to room: $roomId');
  //     return;
  //   }

  //   _currentRoomId = roomId;
  //   final url = '$wsUrl/ws/call/$roomId/';
  //   onLog?.call('Connecting to WebSocket: $url');

  //   try {
  //     _channel = WebSocketChannel.connect(Uri.parse(url));
  //     _isConnected = true;

  //     _channel!.stream.listen(
  //       (message) {
  //         _handleMessage(message);
  //       },
  //       onError: (error) {
  //         _log('WebSocket Error: $error');
  //         _isConnected = false;
  //       },
  //       onDone: () {
  //         _log('WebSocket Closed');
  //         _isConnected = false;
  //       },
  //     );

  //     await _createPeerConnection();
  //   } catch (e) {
  //     onLog?.call('Signaling/Connection Error: $e');
  //     _isConnected = false;
  //     throw e;
  //   }
  // }

  Future<void> connect(String wsUrl, String roomId) async {
    _wsUrl = wsUrl;
    _currentRoomId = roomId;

    if (_isConnected && !_isReconnecting) {
      _log('Already connected to signaling');
      return;
    }

    final url = '$wsUrl/ws/call/$roomId/';
    _log('${_isReconnecting ? "🔄 Reconnecting" : "🌐 Connecting"} to: $url');

    try {
      await _ensurePeerConnection();

      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          _isConnected = true;
          _isReconnecting = false;
          _startHeartbeat();
          _handleMessage(message);
        },
        onError: (error) {
          _log('❌ WebSocket Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          _log('📡 WebSocket Closed');
          _handleDisconnect();
        },
      );
    } catch (e) {
      _log('❌ Connection Error: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _stopHeartbeat();
    _reconnectTimer?.cancel();

    // Only auto-reconnect if we have a room ID and didn't manually disconnect
    if (_currentRoomId != null) {
      _isReconnecting = true;
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (_currentRoomId != null && !_isConnected) {
          connect(_wsUrl!, _currentRoomId!);
        }
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_isConnected && _channel != null) {
        _log('💓 Sending Heartbeat');
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) return;
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
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _log('❌ ICE Connection Failed - attempting restart...');
        _stopIceRestartTimer();
        if (_isCaller) _triggerIceRestart();
      }
    };

    _peerConnection!.onIceGatheringState = (state) {
      _log('📡 ICE Gathering State: ${state.name}');
    };

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        String type = "unknown";
        if (candidate.candidate!.contains("typ host")) {
          type = "HOST (Local)";
        }
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

    _peerConnection!.onTrack = (event) {
      _log(
        '🚞 onTrack: Kind=${event.track.kind}, Streams=${event.streams.length}',
      );
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
      // If there are no streams (rare), the track is still part of the session
      // but we need a stream to render it.
    };
  }

  // void _handleMessage(dynamic message) async {
  //   final data = jsonDecode(message);
  //   final type = data['type'];
  //   onLog?.call('RX: $type');

  //   if (type == 'call_offer') {
  //     _pendingOffer = data['offer'];
  //     onIncomingCall?.call();
  //   } else if (type == 'call_answer') {
  //     onCallAccepted?.call();
  //     await _handleAnswer(data['answer']);
  //   } else if (type == 'new_ice_candidate') {
  //     await _handleCandidate(data['candidate']);
  //   } else {
  //     onLog?.call('Unknown msg: $type');
  //   }
  // }

  void _handleMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];

    // For initial call setup:
    // Ignore duplicate setup offers if we are already connected or calling
    if (type == 'call_offer' &&
        _isCaller &&
        _peerConnection?.signalingState ==
            RTCSignalingState.RTCSignalingStateStable) {
      // This might be a renegotiation offer from the remote side
    } else if (type == 'call_offer' && _isCaller) {
      return;
    }
    // Also ignore duplicate offers
    if (type == 'call_offer' && _pendingOffer != null) return;

    _log('RX: $type');

    if (type == 'call_offer') {
      _pendingOffer = data['offer'];
      _pendingMediaType = data['mediaType'] ?? 'video';
      onIncomingCall?.call();
    } else if (type == 'call_answer') {
      onCallAccepted?.call();
      await _handleAnswer(data['answer']);
    } else if (type == 'new_ice_candidate') {
      await _handleCandidate(data['candidate']);
    } else {
      _log('Unknown msg: $type');
    }
  }

  Map<String, dynamic>? _pendingOffer;
  String? _pendingMediaType;

  String? get pendingMediaType => _pendingMediaType;

  Future<void> acceptCall({bool isVideo = true}) async {
    if (_pendingOffer == null) {
      _log('No pending offer to accept');
      return;
    }

    await _ensurePeerConnection();

    // Ensure we have local stream before accepting
    await _setupLocalStream(isVideo: isVideo);

    await _handleOffer(_pendingOffer!);
    _pendingOffer = null;
  }

  Future<void> _setupLocalStream({bool isVideo = true}) async {
    if (_localStream != null) return;

    // Explicitly check/request permissions
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

    final mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': '640',
              'height': '480',
              'frameRate': '30',
            }
          : false,
    };

    int attempts = 0;
    while (attempts < 2) {
      try {
        if (attempts > 0) {
          _log('⏳ Waiting before media retry (attempt ${attempts + 1})...');
          await Future.delayed(const Duration(milliseconds: 500));
        }

        _localStream = await navigator.mediaDevices.getUserMedia(
          mediaConstraints,
        );
        _log('✅ Got Local Stream: ${_localStream!.id}');
        onLocalStream?.call(_localStream!);

        _localStream!.getTracks().forEach((track) {
          _log('➕ Adding track to PC: ${track.kind}');
          // In Unified Plan, using addTransceiver or addTrack with stream is preferred
          _peerConnection!.addTrack(track, _localStream!);
        });

        // Ensure transceivers are set to receive immediately
        final transceivers = await _peerConnection!.getTransceivers();
        for (var t in transceivers) {
          final kind = t.receiver.track?.kind ?? t.sender.track?.kind;
          if (kind == 'audio' || kind == 'video') {
            await t.setDirection(TransceiverDirection.SendRecv);
          }
        }
        return; // Success
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
  }

  Future<void> _handleOffer(Map<String, dynamic> offerData) async {
    await _ensurePeerConnection();
    _log('📨 Handling Offer: ${offerData['type']}');
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], offerData['type']),
    );
    _isRemoteDescriptionSet = true;

    final constraints = {
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
      'optional': [],
    };

    final answer = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(answer);

    _sendSignal({
      'type': 'call_answer',
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    });

    // Drain buffered candidates
    _drainRemoteCandidates();
  }

  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerData['sdp'], answerData['type']),
    );
    _isRemoteDescriptionSet = true;

    // Drain buffered candidates
    _drainRemoteCandidates();
  }

  Future<void> _handleCandidate(Map<String, dynamic> candidateData) async {
    try {
      final String? candidateStr = candidateData['candidate'];
      final String? sdpMid = candidateData['sdpMid'];
      final int? sdpMLineIndex = candidateData['sdpMLineIndex'] is String
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

  // Future<void> startCall() async {
  //   await _setupLocalStream();

  //   if (_peerConnection == null) return;

  //   final offer = await _peerConnection!.createOffer();
  //   await _peerConnection!.setLocalDescription(offer);

  //   _sendSignal({
  //     'type': 'call_offer',
  //     'offer': {'type': offer.type, 'sdp': offer.sdp},
  //   });
  // }

  Future<void> startCall({bool isVideo = true}) async {
    _isCaller = true;
    _log('📞 Starting Call (video: $isVideo)');
    await _ensurePeerConnection();
    await _setupLocalStream(isVideo: isVideo); // MUST be first

    if (_peerConnection == null) return;

    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': isVideo,
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
    if (_channel != null) {
      _log('TX: ${data['type']}');
      _channel!.sink.add(jsonEncode(data));
    } else {
      _log('Error: Channel is null, cannot send ${data['type']}');
    }
  }

  void toggleMute(bool mute) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !mute;
      });
    }
  }

  void toggleVideo(bool videoOn) async {
    if (_localStream == null) return;

    // If we want to turn it ON but don't have video tracks, we need to get them
    if (videoOn && _localStream!.getVideoTracks().isEmpty) {
      try {
        final videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': '640',
            'height': '480',
            'frameRate': '30',
          },
        });

        final videoTrack = videoStream.getVideoTracks()[0];
        await _localStream!.addTrack(videoTrack);
        _peerConnection!.addTrack(videoTrack, _localStream!);

        // Renegotiate
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _sendSignal({
          'type': 'call_offer',
          'offer': {'type': offer.type, 'sdp': offer.sdp},
        });
      } catch (e) {
        _log('Failed to add video track: $e');
      }
    } else {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = videoOn;
      });
    }
  }

  void switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void endCall() {
    _log('🛑 Ending call and releasing resources');
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _log('⏹️ Stopping track: ${track.kind}');
        track.stop();
      });
      _localStream!.dispose();
      _localStream = null;
    }
    _remoteStream = null;
    if (_peerConnection != null) {
      _log('🔌 Closing PeerConnection');
      _peerConnection!.close();
      _peerConnection = null;
    }
    _pendingOffer = null;
    _pendingMediaType = null;
    _remoteCandidatesBuffer.clear();
    _isRemoteDescriptionSet = false;
    _isCaller = false;
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
    _currentRoomId = null; // Prevent auto-reconnect
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
