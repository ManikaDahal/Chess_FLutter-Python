import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import '../services/voice_service.dart';
import '../core/utils/color_utils.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VoiceService _voiceService = VoiceService();

  bool _isListening = false;
  String _text = "Tap the mic and say something...";
  bool _isProcessing = false;
  String _twinResponse = "";

  // Animation state
  Timer? _animTimer;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _setupAudioListener();
  }

  void _setupAudioListener() {
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted && !_isProcessing) {
        // Auto-resume listening after twin finishes speaking
        _listen();
      }
    });
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _initSpeech() async {
    await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => print('Error: $error'),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _text = val.recognizedWords;
              if (val.finalResult) {
                _sendToAI(_text);
              }
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _sendToAI(String prompt) async {
    if (prompt.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _twinResponse = "Thinking...";
    });

    final response = await _voiceService.chatWithSelf(prompt);

    if (mounted) {
      if (response != null && response['audio_url'] != null) {
        setState(() {
          _isProcessing = false;
          _twinResponse = response['text'] ?? "";
        });

        // Play the response
        await _audioPlayer.play(UrlSource(response['audio_url']));
      } else {
        setState(() {
          _isProcessing = false;
          _twinResponse = "Something went wrong. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text("Digital Twin Call"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar Placeholder
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (foregroundColor ?? Colors.grey).withOpacity(0.1),
                  border: Border.all(color: Colors.blue, width: 2),
                  boxShadow: [
                    if (_isProcessing)
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                  ],
                ),
                child: const Icon(Icons.person, size: 80, color: Colors.blue),
              ),
              const SizedBox(height: 50),

              // Animated Text Status
              Text(
                _isProcessing
                    ? "Twin is responding..."
                    : (_isListening ? "Listening..." : "Idle"),
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Transcript
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),

              const SizedBox(height: 30),

              // Twin's Text Response
              if (_twinResponse.isNotEmpty)
                Text(
                  _twinResponse,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),

              const Spacer(),

              // Call Button
              GestureDetector(
                onTap: _listen,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.red : Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? Colors.red : Colors.green)
                            .withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.call,
                    color: Colors.white,
                    size: 35,
                  ),
                ),
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
