import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../core/utils/const.dart'; // Make sure this exists or replace with actual URL constant

class CallScreen extends StatefulWidget {
  final String roomId;
  const CallScreen({super.key, required this.roomId});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SignalingService _signalingService = SignalingService();
  bool _isMuted = false;
  String _status = "Connecting...";
  final List<String> _logs = [];

  // Use a hardcoded URL or one from Constants
  // Assuming 'ws://10.0.2.2:8000' for Android Emulator or 'ws://localhost:8000' for other environments
  // You might need to adjust this based on your API Constants.
  // For now I'll assume we construct it from Constants.baseUrl or similar.
  // Ideally, use the same host as API but ws protocol.
  final String _wsUrl =
      "ws://192.168.18.3:8000"; // REPLACE with your actual local IP or constant from config

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() async {
    _signalingService.onConnectionStateChange = (state) {
      if (mounted) {
        setState(() {
          switch (state) {
            case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
              _status = "Connected";
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
              _status = "Failed"; // Can also use _logs.add("Connection Failed")
              break;
            case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
              _status = "Disconnected";
              break;
            default:
              _status = state.toString();
          }
        });
      }
    };

    _signalingService.onLog = (log) {
      if (mounted) {
        setState(() {
          _logs.add(log);
        });
      }
    };

    _signalingService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _status = "Audio Connected";
        });
      }
    };

    try {
      await _signalingService.connect(_wsUrl, widget.roomId);
      if (mounted) {
        setState(() {
          _status = "Ready. Press Green Button to Call.";
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
        setState(() {
          _status = "Connection Failed";
        });
      }
    }
  }

  @override
  void dispose() {
    _signalingService.hangUp();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _signalingService.toggleMute(_isMuted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text("Audio Call: ${widget.roomId}"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blueGrey,
              child: Icon(Icons.person, size: 50, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: "mute",
                  backgroundColor: _isMuted ? Colors.white : Colors.blueAccent,
                  onPressed: _toggleMute,
                  child: Icon(
                    _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.black : Colors.white,
                  ),
                ),
                FloatingActionButton(
                  heroTag: "call",
                  backgroundColor: Colors.green,
                  onPressed: () {
                    _signalingService.startCall();
                  },
                  child: const Icon(Icons.call, color: Colors.white),
                ),
                FloatingActionButton(
                  heroTag: "hangup",
                  backgroundColor: Colors.redAccent,
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),
            const Text(
              "Press Green Phone to initiate offer if you are the Caller",
              style: TextStyle(color: Colors.grey),
            ),
            const Divider(color: Colors.white54),
            Container(
              height: 150,
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: Colors.black12,
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
