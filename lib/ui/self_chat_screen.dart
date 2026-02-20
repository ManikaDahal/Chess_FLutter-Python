import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'voice_call_screen.dart';
import '../services/voice_service.dart';
import '../core/utils/color_utils.dart';

class SelfChatScreen extends StatefulWidget {
  const SelfChatScreen({super.key});

  @override
  State<SelfChatScreen> createState() => _SelfChatScreenState();
}

class _SelfChatScreenState extends State<SelfChatScreen> {
  final VoiceService _voiceService = VoiceService();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isTrained = false;
  bool _isLoading = true;
  bool _isRecording = false;

  // Training State
  int _sampleCount = 0;
  final int _targetSamples = 5;
  List<String> _recordedPaths = [];

  // Chat State
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final status = await _voiceService.getVoiceStatus();
    if (mounted) {
      setState(() {
        _isTrained = status['is_trained'] ?? false;
        _isLoading = false;
      });
    }
  }

  // --- TRAINING LOGIC ---

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/sample_${_sampleCount + 1}.wav';

        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );
        setState(() => _isRecording = true);
      }
    } catch (e) {
      print("ERROR: Recording failed: $e");
    }
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      setState(() {
        _recordedPaths.add(path);
        _sampleCount++;
      });

      if (_sampleCount >= _targetSamples) {
        _uploadSamples();
      }
    }
  }

  Future<void> _uploadSamples() async {
    setState(() => _isLoading = true);
    final success = await _voiceService.uploadVoiceSamples(_recordedPaths);

    if (success) {
      _checkStatus();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Training failed. Please try again.")),
        );
        setState(() {
          _isLoading = false;
          _sampleCount = 0;
          _recordedPaths.clear();
        });
      }
    }
  }

  Future<void> _deleteProfile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Voice Profile?"),
        content: const Text(
          "This will permanently delete your voice samples and profile. You will need to re-train the AI to talk with yourself again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final success = await _voiceService.deleteVoiceProfile();
      if (success) {
        setState(() {
          _isTrained = false;
          _sampleCount = 0;
          _recordedPaths.clear();
          _messages.clear();
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Voice profile deleted.")),
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to delete profile.")),
          );
        }
      }
    }
  }

  // --- CHAT LOGIC ---

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"text": text, "is_me": true});
      _msgController.clear();
      _isTyping = true;
    });

    final response = await _voiceService.chatWithSelf(text);

    if (mounted) {
      if (response != null) {
        setState(() {
          _isTyping = false;
          _messages.add({
            "text": response['text'] ?? "Error: No response text",
            "is_me": false,
            "audio_id": response['audio_id'],
          });
        });

        // Auto-play response if audio was available
        if (response['audio_url'] != null) {
          _audioPlayer.play(UrlSource(response['audio_url']));
        } else if (response['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Voice Error: ${response['error']}")),
          );
        }
      } else {
        setState(() {
          _isTyping = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Server error: Failed to get response."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Talk with Yourself"),
        backgroundColor: foregroundColor,
        actions: [
          if (_isTrained)
            IconButton(
              icon: const Icon(Icons.call, color: Colors.white),
              tooltip: "Voice Call",
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VoiceCallScreen(),
                  ),
                );
              },
            ),
          if (_isTrained)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: "Delete Voice Profile",
              onPressed: _deleteProfile,
            ),
        ],
      ),
      body: _isTrained ? _buildChatUI() : _buildTrainingUI(),
    );
  }

  Widget _buildTrainingUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              "Train your digital twin",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              "Read the following sentence 5 times to clone your voice:\n'Hello, I am training my digital assistant in the Chess Mobile App.'",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),
            Text(
              "Samples: $_sampleCount / $_targetSamples",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Hold to record"),
          ],
        ),
      ),
    );
  }

  Widget _buildChatUI() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isMe = msg['is_me'];
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.blue[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(msg['text']),
                      if (!isMe && msg['audio_id'] != null)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.volume_up,
                            size: 20,
                            color: Colors.blue,
                          ),
                          onPressed: () {
                            _audioPlayer.play(UrlSource(msg['audio_id']));
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_isTyping)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              "Your twin is thinking...",
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    hintText: "Say something to yourself...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
