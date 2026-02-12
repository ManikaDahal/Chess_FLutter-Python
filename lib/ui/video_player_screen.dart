import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/video_model.dart';
import '../services/video_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final GameVideo video;

  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;

  // Static global future to track asynchronous disposal/initialization
  // This ensures ONLY ONE video can ever be in the "Acquiring Hardware" or "Releasing Hardware" phase
  static Future<void>? _globalHardwareLock;

  // Interaction State
  List<VideoComment> _comments = [];
  bool _loadingComments = true;
  final TextEditingController _commentController = TextEditingController();
  late GameVideo _currentVideo;

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;

    // We don't await here, but we ensure initialization follows the lock
    _initializePlayer();
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    try {
      final comments = await VideoService().getComments(_currentVideo.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _loadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  String _normalizeUrl(String url) {
    // 1. Fix protocol-relative URLs (//host.com -> https://host.com)
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    // 2. Force HTTPS for generic http links (Android/CDNs prefer safety)
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    // 3. Fix accidental whitespace
    return url.trim();
  }

  Future<void> _initializePlayer({int attempt = 1}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    // Await the global hardware lock to ensure no other screen is using or releasing decoders
    final previousLock = _globalHardwareLock;
    final completer = Completer<void>();
    _globalHardwareLock = completer.future;

    try {
      if (previousLock != null) {
        print('DEBUG: Waiting for Global Hardware Lock...');
        await previousLock;
      }

      // Mandatory settling period after ANY hardware release
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) {
        completer.complete();
        return;
      }

      // 2. Select URL (Direct Video first, then Stream fallback)
      String? rawToPlay;
      if (attempt == 1) {
        rawToPlay = _currentVideo.videoUrl ?? _currentVideo.streamUrl;
      } else {
        rawToPlay = VideoService().getStreamUrl(_currentVideo.id);
      }

      if (rawToPlay == null) throw Exception('No playable URL found');

      final urlToPlay = _normalizeUrl(rawToPlay);
      print('DEBUG: Initializing Video (Attempt $attempt): $urlToPlay');

      // 3. Clear existing local state
      if (_videoPlayerController != null || _chewieController != null) {
        await _cleanupResources(
          oldController: _videoPlayerController,
          oldChewie: _chewieController,
        );
        _videoPlayerController = null;
        _chewieController = null;
      }

      if (!mounted) {
        completer.complete();
        return;
      }

      // 4. Initialize Controller with Minimal Browser Headers
      final uri = Uri.parse(urlToPlay);
      _videoPlayerController = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
        },
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false, // Strict isolation
        ),
      );

      await _videoPlayerController!.initialize();

      if (!mounted) return;

      // 5. Config Chewie
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        isLive: false,
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Video Playback Error\n$errorMessage',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: () {
                      _globalHardwareLock = null; // FORCE CLEAR LOCK
                      _initializePlayer();
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Force Hardware Reset',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('DEBUG: Playback init error: $e');

      // Fallback logic
      if (attempt < 2) {
        print('DEBUG: Initial attempt failed. Retrying with fallback...');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          completer.complete(); // Release lock before retrying
          return _initializePlayer(attempt: attempt + 1);
        }
      }

      if (mounted) {
        setState(() {
          _error =
              'Unable to play video ($e). This can happen if the site prevents app access or hardware decoders are full.';
          _isLoading = false;
        });
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final comment = await VideoService().postComment(_currentVideo.id, text);
    if (comment != null) {
      setState(() {
        _comments.insert(0, comment);
        _commentController.clear();
      });
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _handleReaction(String type) async {
    final success = await VideoService().toggleReaction(_currentVideo.id, type);
    if (success) {
      // Refresh video details to get updated counts and user reaction
      // Or local state update for faster UI response
      setState(() {
        final Map<String, int> newCounts = Map.from(
          _currentVideo.reactionCounts,
        );
        String? newReaction;

        if (_currentVideo.userReaction == type) {
          // Toggle off
          newCounts[type] = (newCounts[type] ?? 1) - 1;
          newReaction = null;
        } else {
          // Toggle on or switch
          if (_currentVideo.userReaction != null) {
            newCounts[_currentVideo.userReaction!] =
                (newCounts[_currentVideo.userReaction!] ?? 1) - 1;
          }
          newCounts[type] = (newCounts[type] ?? 0) + 1;
          newReaction = type;
        }

        _currentVideo = GameVideo(
          id: _currentVideo.id,
          title: _currentVideo.title,
          description: _currentVideo.description,
          videoUrl: _currentVideo.videoUrl,
          thumbnailUrl: _currentVideo.thumbnailUrl,
          streamUrl: _currentVideo.streamUrl,
          duration: _currentVideo.duration,
          fileSize: _currentVideo.fileSize,
          views: _currentVideo.views,
          createdAt: _currentVideo.createdAt,
          reactionCounts: newCounts,
          userReaction: newReaction,
        );
      });
    }
  }

  Future<void> _cleanupResources({
    VideoPlayerController? oldController,
    ChewieController? oldChewie,
  }) async {
    try {
      if (oldChewie != null) {
        oldChewie.dispose();
      }
      if (oldController != null) {
        if (oldController.value.isInitialized) {
          try {
            await oldController.pause();
          } catch (e) {
            print('DEBUG: Pause failed: $e');
          }
        }
        await Future.delayed(const Duration(milliseconds: 400));
        await oldController.dispose();
        // Force a long breather for Android to recycle decoders in its media server
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    } catch (e) {
      print('DEBUG: Resource cleanup error: $e');
    }
  }

  @override
  void dispose() {
    _commentController.dispose();

    // Re-acquire the lock for the disposal phase to protect the NEXT screen
    final previousLock = _globalHardwareLock;
    final completer = Completer<void>();
    _globalHardwareLock = completer.future;

    _runDisposalChain(previousLock, completer);

    super.dispose();
  }

  Future<void> _runDisposalChain(
    Future<void>? previousLock,
    Completer<void> completer,
  ) async {
    try {
      if (previousLock != null) await previousLock;
      await _cleanupResources(
        oldController: _videoPlayerController,
        oldChewie: _chewieController,
      );
    } finally {
      completer.complete();
    }
  }

  Widget _buildReactionButton(String type, String emoji) {
    bool isActive = _currentVideo.userReaction == type;
    int count = _currentVideo.reactionCounts[type] ?? 0;

    return InkWell(
      onTap: () => _handleReaction(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: isActive ? Colors.blue : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: Text(_currentVideo.title),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Column(
        children: [
          // Video Player Area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildErrorWidget()
                : Chewie(controller: _chewieController!),
          ),

          // Content Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Views
                  Text(
                    _currentVideo.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_currentVideo.views} views • ${_currentVideo.createdAt.day}/${_currentVideo.createdAt.month}/${_currentVideo.createdAt.year}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // Reactions Bar
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildReactionButton('like', '👍'),
                        const SizedBox(width: 8),
                        _buildReactionButton('heart', '❤️'),
                        const SizedBox(width: 8),
                        _buildReactionButton('laugh', '😂'),
                        const SizedBox(width: 8),
                        _buildReactionButton('surprised', '😮'),
                        const SizedBox(width: 8),
                        _buildReactionButton('sad', '😢'),
                        const SizedBox(width: 8),
                        _buildReactionButton('angry', '😡'),
                      ],
                    ),
                  ),

                  const Divider(color: Colors.grey, height: 32),

                  // Description
                  if (_currentVideo.description.isNotEmpty) ...[
                    const Text(
                      'Description',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentVideo.description,
                      style: TextStyle(color: Colors.grey[300], fontSize: 14),
                    ),
                    const Divider(color: Colors.grey, height: 32),
                  ],

                  // Comments Header
                  Row(
                    children: [
                      const Text(
                        'Comments',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${_comments.length})',
                        style: TextStyle(color: Colors.grey[400], fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Comments List
                  if (_loadingComments)
                    const Center(child: CircularProgressIndicator())
                  else if (_comments.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No comments yet. Be the first!',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _comments.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blueGrey,
                              child: Text(comment.userName[0].toUpperCase()),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        comment.userName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${comment.createdAt.toLocal()}'.split(
                                          ' ',
                                        )[0],
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    comment.text,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 80), // Space for input field
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.blue),
              onPressed: _postComment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _initializePlayer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
