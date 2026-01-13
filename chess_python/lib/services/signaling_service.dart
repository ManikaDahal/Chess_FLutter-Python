import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef StreamStateCallback = void Function(MediaStream stream);

class SignalingService {
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
    _currentRoomId = roomId;
    final url = '$wsUrl/ws/call/$roomId/';
    print('Connecting to WebSocket: $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          print('Received message: $message');
          _handleMessage(message);
        },
        onError: (error) {
          print('WebSocket Error: $error');
        },
        onDone: () {
          print('WebSocket Closed');
        },
      );

      await _createPeerConnection();
    } catch (e) {
      print('Signaling/Connection Error: $e');
      // Rethrow so UI can handle it if needed
      throw e;
    }
  }

  Future<void> _createPeerConnection() async {
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

    // Get user media
    // Get user media
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
      print('getUserMedia Error: $e');
      throw Exception(
        'Failed to get microphone access. Ensure you are using HTTPS or localhost.',
      );
    }
  }

  void _handleMessage(dynamic message) async {
    final data = jsonDecode(message);
    final type = data['type'];
    onLog?.call('RX: $type');

    if (type == 'call_offer') {
      await _handleOffer(data['offer']);
    } else if (type == 'call_answer') {
      await _handleAnswer(data['answer']);
    } else if (type == 'new_ice_candidate') {
      await _handleCandidate(data['candidate']);
    } else {
      onLog?.call('Unknown msg: $type');
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
      onLog?.call(
        'Error: Channel is null or closed, cannot send ${data['type']}',
      );
    }
  }

  void toggleMute(bool mute) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !mute;
      });
    }
  }

  void hangUp() {
    if (_localStream != null) {
      _localStream!.dispose();
      _localStream = null;
    }
    if (_remoteStream != null) {
      // Remote stream is disposed by peer connection usually, but good practice to clear ref
      _remoteStream = null;
    }
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }
}
