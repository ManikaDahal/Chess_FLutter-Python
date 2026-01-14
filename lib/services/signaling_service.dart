import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  StreamStateCallback? onLocalStream;
  StreamStateCallback? onRemoteStream;
  Function(RTCSignalingState)? onSignalingStateChange;
  Function(RTCPeerConnectionState)? onConnectionStateChange;
  Function(String)? onLog;

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
        ],
      },
    ],
  };

  Future<void> connect(String wsUrl, String roomId) async {
    if (_isConnected && _currentRoomId == roomId) {
      onLog?.call('Already connected to room: $roomId');
      return;
    }

    _currentRoomId = roomId;
    final url = '$wsUrl/ws/call/$roomId/';
    onLog?.call('Connecting to WebSocket: $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          onLog?.call('WebSocket Error: $error');
          _isConnected = false;
        },
        onDone: () {
          onLog?.call('WebSocket Closed');
          _isConnected = false;
        },
      );

      await _createPeerConnection();
    } catch (e) {
      onLog?.call('Signaling/Connection Error: $e');
      _isConnected = false;
      throw e;
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;

    _peerConnection = await createPeerConnection(_configuration);

    _peerConnection!.onSignalingState = (state) {
      onSignalingStateChange?.call(state);
    };

    _peerConnection!.onConnectionState = (state) {
      onConnectionStateChange?.call(state);
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

  void _handleMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];
    onLog?.call('RX: $type');

    if (type == 'call_offer') {
      _pendingOffer = data['offer'];
      onIncomingCall?.call();
    } else if (type == 'call_answer') {
      onCallAccepted?.call();
      await _handleAnswer(data['answer']);
    } else if (type == 'new_ice_candidate') {
      await _handleCandidate(data['candidate']);
    } else {
      onLog?.call('Unknown msg: $type');
    }
  }

  Map<String, dynamic>? _pendingOffer;

  Future<void> acceptCall() async {
    if (_pendingOffer == null) {
      onLog?.call('No pending offer to accept');
      return;
    }

    // Ensure we have local stream before accepting
    await _setupLocalStream();

    await _handleOffer(_pendingOffer!);
    _pendingOffer = null;
  }

  Future<void> _setupLocalStream() async {
    if (_localStream != null) return;

    final mediaConstraints = {'audio': true, 'video': false};
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      onLocalStream?.call(_localStream!);

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    } catch (e) {
      onLog?.call('getUserMedia Error: $e');
      throw Exception('Failed to get microphone access.');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> offerData) async {
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

  Future<void> startCall() async {
    await _setupLocalStream();

    if (_peerConnection == null) return;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignal({
      'type': 'call_offer',
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  void _sendSignal(Map<String, dynamic> data) {
    if (_channel != null) {
      onLog?.call('TX: ${data['type']}');
      _channel!.sink.add(jsonEncode(data));
    } else {
      onLog?.call('Error: Channel is null, cannot send ${data['type']}');
    }
  }

  void toggleMute(bool mute) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !mute;
      });
    }
  }

  void endCall() {
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream!.dispose();
      _localStream = null;
    }
    _remoteStream = null;
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
    _pendingOffer = null;
  }

  void disconnect() {
    endCall();
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
    _currentRoomId = null;
  }
}
