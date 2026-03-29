import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/utils/route_const.dart';
import 'package:chess_game_manika/core/utils/route_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



class ChatPage extends ConsumerStatefulWidget {
  final int roomId;
  final int currentUserId;
  final bool showBackButton;
  /// Optional: the other participant's display name.
  /// When provided it is shown immediately without waiting for messages.
  final String? recipientName;

  const ChatPage({
    required this.roomId,
    required this.currentUserId,
    this.showBackButton = true,
    this.recipientName,
    super.key,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}


class _ChatPageState extends ConsumerState<ChatPage> {

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(chatProvider.notifier);
      // Seed the recipient name immediately if we already know it
      if (widget.recipientName != null) {
        notifier.setRoomParticipant(widget.roomId, widget.recipientName!);
      }
      notifier.init(widget.roomId, widget.currentUserId);
      notifier.resetUnreadCount(widget.roomId);
    });
  }


  @override
  void dispose() {
    print("ChatPage: dispose called for Room ${widget.roomId}");
    ref.read(chatProvider.notifier).clearActiveRoom();
    super.dispose();
  }

  Widget _buildMessageStatus(String? status, {bool hasServerId = false}) {
    // Messages confirmed by server (have an id) are at minimum 'delivered'
    final effectiveStatus = (hasServerId && (status == null || status == 'sent'))
        ? 'delivered'
        : status;

    IconData icon;
    Color color;

    switch (effectiveStatus) {
      case 'seen':
      case 'opened':
        icon = Icons.done_all;
        color = const Color(0xFF90CAF9); // light blue = seen
        break;
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.white70; // double tick white = delivered
        break;
      default: // 'sent'
        icon = Icons.done;
        color = Colors.white54; // single tick = just sent
    }

    return Icon(icon, size: 14, color: color);
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
        backgroundColor: backgroundColor,
        foregroundColor: whiteColor,
        centerTitle: true,
        title: Consumer(
          builder: (context, ref, child) {
            final provider = ref.watch(chatProvider);
            final isLoading = provider.loadingRooms[widget.roomId] ?? false;

            // Priority order:
            // 1. Already seeded in roomParticipants (covers recipientName + history)
            // 2. Fallback: scan messages for other user's name
            String? resolvedName = provider.roomParticipants[widget.roomId];

            if (resolvedName == null) {
              final messages = provider.getMessages(widget.roomId);
              for (final m in messages) {
                if (m.userId != widget.currentUserId) {
                  resolvedName = m.senderName;
                  break;
                }
              }
            }

            // Show spinner only while first loading AND name still unknown
            if (resolvedName == null && isLoading) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Opening...',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              );
            }

            return Text(
              resolvedName ?? 'Chat',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            );
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final provider = ref.watch(chatProvider);
                final isLoading = provider.loadingRooms[widget.roomId] ?? false;

                if (isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6A11CB),
                    ),
                  );
                }

                final messages = provider.getMessages(widget.roomId);
                
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
                          Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: 15,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(height: 4),
                                    _buildMessageStatus(
                                      msg.status,
                                      hasServerId: msg.id != null,
                                    ),
                                  ],
                                ],
                              ),
                          ),
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

                      ref.read(chatProvider.notifier).send(widget.roomId, text);

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
