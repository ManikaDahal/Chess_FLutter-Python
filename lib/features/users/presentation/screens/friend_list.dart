import 'dart:ui';
import 'package:chess_game_manika/core/utils/color_utils.dart';
import 'package:chess_game_manika/core/widgets/blinking_dot.dart';
import 'package:chess_game_manika/features/call/presentation/providers/call_provider.dart';
import 'package:chess_game_manika/features/call/presentation/screens/call_screen.dart';
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';
import 'package:chess_game_manika/features/chat/presentation/screens/chat_page.dart';
import 'package:chess_game_manika/features/invites/presentation/screens/invite_waiting_screen.dart';
import 'package:chess_game_manika/features/invites/services/invite_services.dart';
import 'package:flutter/material.dart';
import 'package:chess_game_manika/core/api/api_services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FriendListScreen extends ConsumerStatefulWidget {
  final int currentUserId;

  const FriendListScreen({
    super.key,
    required this.currentUserId,
  });

  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  
  List<dynamic> _allUsers = [];
  List<dynamic> _friends = [];
  List<dynamic> _pendingInvites = [];
  bool _isLoading = true;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshData();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getUsers(),
        _apiService.getChatRooms(),
        _apiService.getPendingInvites(),
      ]);
      
      if (mounted) {
        setState(() {
          final freshFriends = results[1].map((room) => {
            ...room['other_user'],
            'room_id': room['room_id'],
            'last_message': room['last_message'],
          }).toList();
          
          final friendIds = freshFriends.map((f) => f['id']).toSet();
          
          _friends = freshFriends;
          _allUsers = results[0]
              .where((u) => u['id'] != widget.currentUserId && !friendIds.contains(u['id']))
              .toList();
          _pendingInvites = results[2];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading data: $e")),
        );
      }
    }
  }

  List<dynamic> _getFilteredList(List<dynamic> list) {
    if (_searchController.text.isEmpty) return list;
    final query = _searchController.text.toLowerCase();
    return list.where((user) {
      final username = (user['username'] ?? "").toString().toLowerCase();
      return username.contains(query);
    }).toList();
  }

  void _startChat(int targetUserId) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      final int? roomId = await _apiService.getOrCreateChatRoom(
        widget.currentUserId,
        targetUserId,
      );

      if (roomId != null && mounted) {
        ref.read(chatProvider.notifier).init(roomId, widget.currentUserId);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatPage(roomId: roomId, currentUserId: widget.currentUserId),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  void _startCall(int targetUserId, bool isVideo) {
    final callRoomId = "user_$targetUserId";
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          roomId: callRoomId,
          isIncomingCall: false,
          isInitialVideo: isVideo,
          currentUserId: widget.currentUserId,
          canMinimize: false,
        ),
      ),
    );
  }

  void _playGame(int targetUserId, String username) {
    showModalBottomSheet(
      context: context,
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Invite $username to Play",
              style: const TextStyle(color: whiteColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildGameOption(
                  icon: Icons.grid_4x4_rounded,
                  label: "Chess",
                  color: Colors.orangeAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _sendInvite(targetUserId, username, 'chess');
                  },
                ),
                _buildGameOption(
                  icon: Icons.gesture_rounded,
                  label: "Snake & Ladder",
                  color: Colors.greenAccent,
                  onTap: () {
                    Navigator.pop(context);
                    _sendInvite(targetUserId, username, 'snake');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOption({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 40),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  void _sendInvite(int targetUserId, String username, String type) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      final inviteService = InviteService();
      final int? roomId = await inviteService.sendInvite(targetUserId, gameType: type);

      if (roomId != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InviteWaitingScreen(
              targetUserId: targetUserId,
              targetUserName: username,
              roomId: roomId,
              gameType: type,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  void _sendFriendRequest(int targetUserId, String username) async {
     if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      final int? roomId = await InviteService().sendInvite(targetUserId, gameType: 'friend');
      if (roomId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Friend request sent to $username!"), backgroundColor: accentGreen),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  void _acceptRequest(int inviteId, String type) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      final roomId = await _apiService.acceptInvite(inviteId);
      if (roomId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(type == 'friend' ? "Friend request accepted!" : "Invitation accepted!"),
            backgroundColor: accentGreen,
          ),
        );
        _refreshData(); // Refresh list to reflect new friend or game start
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  void _declineRequest(int inviteId) async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    try {
      await _apiService.declineInvite(inviteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request declined"), backgroundColor: accentRed),
        );
        _refreshData();
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                _buildTabs(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(isFriends: true),
                      _buildList(isDiscover: true),
                      _buildRequestList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isActionInProgress)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [backgroundColor, Color(0xFF16213E)],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Social",
            style: TextStyle(color: whiteColor, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.1),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: primaryYellow),
            onPressed: _refreshData,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: whiteColor),
          decoration: InputDecoration(
            hintText: "Search for players...",
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: primaryYellow, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorColor: primaryYellow,
        indicatorPadding: const EdgeInsets.symmetric(horizontal: -5),
        labelColor: primaryYellow,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: [
          Tab(text: "FRIENDS"),
          Tab(text: "DISCOVER"),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("REQUESTS"),
                if (_pendingInvites.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: accentRed, shape: BoxShape.circle),
                    child: Text(
                      _pendingInvites.length.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList({bool isFriends = false, bool isDiscover = false}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    final list = isFriends ? _friends : _allUsers;
    final filtered = _getFilteredList(list);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: 60, color: Colors.white10),
            const SizedBox(height: 15),
            Text(
              isFriends ? "No active chats yet" : "No users found",
              style: const TextStyle(color: Colors.white24),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 30),
      itemBuilder: (context, index) => _buildUserItem(filtered[index], isFriends),
    );
  }

  Widget _buildRequestList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    if (_pendingInvites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline_rounded, size: 60, color: Colors.white10),
            const SizedBox(height: 15),
            const Text("No pending requests", style: TextStyle(color: Colors.white24)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _pendingInvites.length,
      separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 30),
      itemBuilder: (context, index) {
        final invite = _pendingInvites[index];
        final senderName = invite['sender_name'] ?? "Unknown";
        final type = invite['game_type'] ?? "chess";
        final displayType = type == 'friend' ? "Wants to be your friend" : "Invited you to play $type";

        return Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: primaryColor.withOpacity(0.5),
              child: Text(senderName[0].toUpperCase(), style: const TextStyle(color: primaryYellow)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(senderName, style: const TextStyle(color: whiteColor, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(displayType, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildIconAction(Icons.check_rounded, accentGreen, () => _acceptRequest(invite['id'], type)),
                  _buildIconAction(Icons.close_rounded, accentRed, () => _declineRequest(invite['id'])),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserItem(dynamic user, bool isFriend) {
    final username = user['username'] ?? "Unknown";
    final lastMsg = user['last_message'] as String?;
    final targetUserId = user['id'];

    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: primaryColor.withOpacity(0.5),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : "?",
                style: const TextStyle(color: primaryYellow, fontWeight: FontWeight.bold),
              ),
            ),
            const Positioned(right: 0, bottom: 2, child: BlinkingDot(color: Colors.green, size: 10)),
          ],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: const TextStyle(color: whiteColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (lastMsg != null)
                Text(
                  lastMsg,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (isFriend)
          _buildFriendActions(targetUserId, username)
        else
           _buildDiscoverActions(targetUserId, username),
      ],
    );
  }

  Widget _buildFriendActions(int targetUserId, String username) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIconAction(Icons.chat_bubble_outline_rounded, Colors.blueAccent, () => _startChat(targetUserId)),
        _buildIconAction(Icons.phone_outlined, Colors.greenAccent, () => _startCall(targetUserId, false)),
        _buildIconAction(Icons.videocam_outlined, Colors.purpleAccent, () => _startCall(targetUserId, true)),
        _buildIconAction(Icons.play_arrow_rounded, primaryYellow, () => _playGame(targetUserId, username)),
      ],
    );
  }

  Widget _buildDiscoverActions(int targetUserId, String username) {
     return _buildIconAction(Icons.person_add_outlined, primaryYellow, () => _sendFriendRequest(targetUserId, username));
  }

  Widget _buildIconAction(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
