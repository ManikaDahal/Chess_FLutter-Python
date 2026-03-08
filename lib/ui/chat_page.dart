import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:chess_game_manika/models/chat_model.dart';
import 'package:chess_game_manika/provider/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatefulWidget {
  final int roomId;
  final int currentUserId;
  final bool showBackButton; // New parameter

  const ChatPage({
    required this.roomId,
    required this.currentUserId,
    this.showBackButton = true, // Default to true
    super.key,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    print("ChatPage: initState called for Room ${widget.roomId}");
    // Ensure the provider is initialized for THIS specific room
    final provider = Provider.of<ChatProvider>(context, listen: false);
    provider.init(widget.roomId, widget.currentUserId);
    provider.resetUnreadCount(widget.roomId);
  }

  @override
  void dispose() {
    print("ChatPage: dispose called for Room ${widget.roomId}");
    final provider = Provider.of<ChatProvider>(context, listen: false);
    provider.clearActiveRoom();
    super.dispose();
  }

  /// Format a DateTime to a readable time string like "3:41 PM"
  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Build the message status icon for sent messages
  Widget _buildStatusIcon(MessageStatus status) {
    // print("DEBUG [Room ${widget.roomId}]: Building icon for status: $status");
    switch (status) {
      case MessageStatus.sending:
        return const Icon(
          Icons.access_time_rounded,
          size: 13,
          color: Colors.white60,
        );
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 13, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 13, color: Colors.white70);
      case MessageStatus.seen:
        return const SizedBox.shrink(); // Remove tick per user request
    }
  }

  /// Show a simple reaction picker on long press
  void _showReactionPicker(ChatMessage msg) {
    final emojis = ["❤️", "👍", "🔥", "😂", "😮", "😢"];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 100,
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis
              .map(
                (e) => GestureDetector(
                  onTap: () {
                    Provider.of<ChatProvider>(
                      context,
                      listen: false,
                    ).toggleReaction(widget.roomId, msg.id ?? 0, e);
                    Navigator.pop(context);
                  },
                  child: Text(e, style: const TextStyle(fontSize: 30)),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  /// Build a small row of reactions for a message
  Widget _buildReactionRow(List<MessageReaction> reactions, bool isMe) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Group identical emojis
    final Map<String, int> counts = {};
    for (var r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: counts.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  "${entry.key} ${entry.value > 1 ? entry.value : ''}",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB), // Premium light background
      appBar: AppBar(
        elevation: 0,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: whiteColor,
                  size: 20,
                ),
                onPressed: () {
                  RouteGenerator.navigateToPage(
                    context,
                    Routes.bottomNavBarRoute,
                  );
                },
              )
            : null, // Hide back button if not needed
        title: Consumer<ChatProvider>(
          builder: (_, provider, __) {
            final messages = provider.getMessages(widget.roomId);
            return Column(
              children: [
                Text(
                  "Room #${widget.roomId} (${messages.length})",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Text(
                  "Online",
                  style: TextStyle(fontSize: 12, color: Colors.greenAccent),
                ),
              ],
            );
          },
        ),
        backgroundColor: backgroundColor,
        foregroundColor: whiteColor,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (_, provider, __) {
                final messages = provider.getMessages(widget.roomId);
                print(
                  "ChatPage [Room ${widget.roomId}]: Rebuilding. Messages: ${messages.length}",
                );
                // Scroll to bottom when new messages arrive
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (_, index) {
                    final msg = messages[index];
                    final isMe = msg.userId == widget.currentUserId;
                    if (msg.senderName == "Unknown" || msg.userId <= 0) {
                      print(
                        "DEBUG [Room ${widget.roomId}]: Msg ${msg.id} has senderName=${msg.senderName}, userId=${msg.userId}, isMe=$isMe (currentUserId=${widget.currentUserId})",
                      );
                    }
                    final timeStr = _formatTime(msg.localTimestamp);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 12,
                                bottom: 4,
                              ),
                              child: Text(
                                msg.senderName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          GestureDetector(
                            onLongPress: () => _showReactionPicker(msg),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: const EdgeInsets.only(
                                top: 12,
                                left: 14,
                                right: 14,
                                bottom: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: isMe
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF6A11CB),
                                          Color(0xFF2575FC),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isMe ? null : Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: Radius.circular(isMe ? 20 : 0),
                                  bottomRight: Radius.circular(isMe ? 0 : 20),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.message,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 16,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // ── Timestamp + status row ──
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isMe
                                              ? Colors.white60
                                              : Colors.black38,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 5),
                                        _buildStatusIcon(msg.status),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildReactionRow(msg.reactions, isMe),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: "Type a message...",
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      final text = _controller.text.trim();
                      if (text.isEmpty) return;

                      Provider.of<ChatProvider>(
                        context,
                        listen: false,
                      ).send(widget.roomId, text);

                      _controller.clear();
                      _scrollToBottom();
                    },
                    child: Container(
                      height: 45,
                      width: 45,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                        ),
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
