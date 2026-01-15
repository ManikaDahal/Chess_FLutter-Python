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

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
          'stun:stun3.l.google.com:19302',
          'stun:stun4.l.google.com:19302',
        ],
      },
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

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
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _log('ICE Connection Failed - check STUN/TURN servers');
      }
    };

    _peerConnection!.onIceCandidate = (candidate) {
      _sendSignal({
        'type': 'new_ice_candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
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

    // Ignore if we are the caller (self-signaling fix)
    if (type == 'call_offer' && _isCaller) return;
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
          _peerConnection!.addTrack(track, _localStream!);
        });
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

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _sendSignal({
      'type': 'call_answer',
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(answerData['sdp'], answerData['type']),
    );
  }

  Future<void> _handleCandidate(Map<String, dynamic> candidateData) async {
    await _peerConnection!.addCandidate(
      RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      ),
    );
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

    final offer = await _peerConnection!.createOffer();
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
    _isCaller = false;
  }

  void disconnect() {
    _log('🔌 Manually disconnecting from signaling');
    _currentRoomId = null; // Prevent auto-reconnect
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    endCall();
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
  }
}
