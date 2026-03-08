import 'dart:convert';
import 'package:chess_game_manika/core/utils/const.dart';
import 'package:chess_game_manika/services/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

/// Represents one notification category and whether the user has blocked it.
class NotificationCategoryPreference {
  final String category; // e.g. 'message', 'invitation', 'system'
  final String label; // e.g. 'Chat Message', 'Game Invitation'
  bool isBlocked;

  NotificationCategoryPreference({
    required this.category,
    required this.label,
    required this.isBlocked,
  });

  factory NotificationCategoryPreference.fromJson(Map<String, dynamic> json) {
    return NotificationCategoryPreference(
      category: json['category'] as String,
      label: json['label'] as String,
      isBlocked: json['is_blocked'] as bool? ?? false,
    );
  }
}

/// Service for fetching and updating per-category notification block preferences.
///
/// HOW TO ADD A NEW CATEGORY:
///   1. Backend (Django): add the tuple to `NOTIFICATION_CATEGORIES` in `call/models.py`
///   2. Backend: add the type→category mapping in `NOTIFICATION_TYPE_TO_CATEGORY`
///      and a title template in `NOTIFICATION_TITLE_TEMPLATES` in `call/notification_utils.py`
///   3. Frontend: Nothing extra needed — this service automatically fetches all
///      categories from the backend and the UI renders them dynamically.
class NotificationPreferenceService {
  static const String _prefsKey = 'notif_blocked_categories';

  static String get _baseUrl =>
      Constants.wsBaseUrl.replaceFirst('wss://', 'https://');

  /// Fetches all category preferences for the logged-in user from the backend.
  static Future<List<NotificationCategoryPreference>> fetchPreferences() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/notifications/preferences/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final prefs = data
            .map((e) => NotificationCategoryPreference.fromJson(e))
            .toList();
        // Cache locally for offline access
        await _cachePreferences(prefs);
        return prefs;
      } else {
        print('[NotifPref] Failed to fetch preferences: ${response.body}');
        return await _loadCachedPreferences();
      }
    } catch (e) {
      print('[NotifPref] Network error fetching preferences: $e');
      return await _loadCachedPreferences();
    }
  }

  /// Updates a single category's blocked state on the backend.
  static Future<bool> updatePreference(String category, bool isBlocked) async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/notifications/preferences/update/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'category': category, 'is_blocked': isBlocked}),
      );

      if (response.statusCode == 200) {
        print('[NotifPref] Updated: $category → isBlocked=$isBlocked');
        // Update local cache
        await _setLocalBlock(category, isBlocked);
        return true;
      } else {
        print('[NotifPref] Backend update failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('[NotifPref] Network error updating preference: $e');
      return false;
    }
  }

  // ─── Local cache (for foreground duplicate-check) ───────────────────────

  /// Returns true if the given category is locally blocked.
  /// Use this inside onMessage listener before showing a local notification.
  static Future<bool> isCategoryBlocked(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList(_prefsKey) ?? [];
    return blocked.contains(category);
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  static Future<void> _cachePreferences(
    List<NotificationCategoryPreference> prefs,
  ) async {
    final sp = await SharedPreferences.getInstance();
    final blocked = prefs
        .where((p) => p.isBlocked)
        .map((p) => p.category)
        .toList();
    await sp.setStringList(_prefsKey, blocked);
  }

  static Future<void> _setLocalBlock(String category, bool isBlocked) async {
    final sp = await SharedPreferences.getInstance();
    final blocked = sp.getStringList(_prefsKey) ?? [];
    if (isBlocked) {
      if (!blocked.contains(category)) blocked.add(category);
    } else {
      blocked.remove(category);
    }
    await sp.setStringList(_prefsKey, blocked);
  }

  static Future<List<NotificationCategoryPreference>>
  _loadCachedPreferences() async {
    final sp = await SharedPreferences.getInstance();
    final blocked = sp.getStringList(_prefsKey) ?? [];
    // We can only reconstruct the blocked list without labels
    return blocked
        .map(
          (cat) => NotificationCategoryPreference(
            category: cat,
            label: cat,
            isBlocked: true,
          ),
        )
        .toList();
  }

  /// Returns true if the given category is locally blocked by checking the OS channel status.
  static Future<bool> isCategoryBlockedLocally(String category) async {
    // 1. Check Global Permission
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return true;

    // 2. Map to channel key
    final String channelKey = category == 'message'
        ? 'chat_channel'
        : '${category}_channel';

    try {
      // 3. Check specific channel status via permissions. Robust for 0.10.x.
      List<dynamic> permissions = await (AwesomeNotifications() as dynamic)
          .checkPermission(channelKey: channelKey);

      // If the list does NOT contain Alert, it means the channel is effectively blocked or disabled
      return !permissions.contains(NotificationPermission.Alert);
    } catch (e) {
      print(
        "[NotifPref] Error checking local channel status for $category: $e",
      );
    }

    // Fallback to local cache if we can't determine OS status
    return await isCategoryBlocked(category);
  }
}
