import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads Android notifications via NotificationListenerService.
///
/// Android requires:
/// 1. A NotificationListenerService subclass in Kotlin/Java
/// 2. User manually enables the app in Settings → Notification Access
///
/// This service reads the cached notifications from the native side.
class NotificationService {
  static const _channel = MethodChannel('com.hellobuddy/notifications');

  /// Get recent notifications (last N minutes)
  Future<List<AppNotification>> getRecentNotifications({
    int sinceMinutes = 60,
  }) async {
    if (kIsWeb) {
      final now = DateTime.now();
      return [
        AppNotification(
          packageName: 'com.google.android.apps.classroom',
          appName: 'Google Classroom',
          title: 'Embedded Systems Assignment 3',
          text: 'Due tonight at 11:59 PM — Submit firmware code and circuit schematic.',
          timestamp: now.subtract(const Duration(minutes: 25)),
        ),
        AppNotification(
          packageName: 'com.instructure.candroid',
          appName: 'Canvas Student',
          title: 'Digital Signal Processing Quiz',
          text: 'Quiz 2 will open tomorrow morning at 09:00 AM.',
          timestamp: now.subtract(const Duration(minutes: 50)),
        ),
      ];
    }

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getRecentNotifications',
        {'since_minutes': sinceMinutes},
      );
      if (result == null) return [];

      return result.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return AppNotification.fromMap(map);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Format notifications as a text summary for Groq
  String notificationsToPrompt(List<AppNotification> notifications) {
    if (notifications.isEmpty) return 'No new notifications.';

    // Group by app
    final grouped = <String, List<AppNotification>>{};
    for (final n in notifications) {
      grouped.putIfAbsent(n.appName, () => []).add(n);
    }

    final buffer = StringBuffer('Recent phone notifications:\n');
    for (final entry in grouped.entries) {
      buffer.writeln('From ${entry.key}:');
      for (final n in entry.value) {
        buffer.writeln('  - ${n.title}: ${n.text}');
      }
    }
    return buffer.toString();
  }
}

/// A single notification captured from the Android notification shade
class AppNotification {
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final DateTime timestamp;

  const AppNotification({
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    required this.timestamp,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      packageName: map['package'] ?? '',
      appName: map['app_name'] ?? 'Unknown',
      title: map['title'] ?? '',
      text: map['text'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as int?) ?? 0,
      ),
    );
  }
}
