import 'package:flutter_riverpod/legacy.dart'; // Added for ChangeNotifierProvider legacy API in Riverpod 3.0
import 'package:chess_game_manika/features/chat/presentation/providers/chat_provider.dart';

final chatProvider = ChangeNotifierProvider<ChatProvider>((ref) {
  return ChatProvider();
});
