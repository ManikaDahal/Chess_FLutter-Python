import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams [true] when online, [false] when offline.
/// Performs an initial connectivity check, then listens to changes.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final initial = await Connectivity().checkConnectivity();
  yield initial.isNotEmpty &&
      !initial.every((r) => r == ConnectivityResult.none);

  await for (final results in Connectivity().onConnectivityChanged) {
    yield results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
  }
});

/// One-time flag that locks the user into Offline Lobby.
/// Only cleared by explicit user consent via the reconnection dialog.
class OfflineModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setOfflineMode(bool value) => state = value;
}

final offlineModeProvider = NotifierProvider<OfflineModeNotifier, bool>(() {
  return OfflineModeNotifier();
});

