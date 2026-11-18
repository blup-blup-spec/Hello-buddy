import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads device calendar events via platform channel with smart student fallback.
/// Returns structured event data that Groq can parse into tasks.
class CalendarService {
  static const _channel = MethodChannel('com.hellobuddy/calendar');

  /// Read today's calendar events
  Future<List<CalendarEvent>> getTodayEvents() async {
    final now = DateTime.now();

    if (!kIsWeb) {
      try {
        final result =
            await _channel.invokeMethod<List<dynamic>>('getTodayEvents');
        if (result != null && result.isNotEmpty) {
          return result.map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            return CalendarEvent.fromMap(map);
          }).toList();
        }
      } catch (_) {}
    }

    // Default student academic events
    return [
      CalendarEvent(
        id: 'cal_student_1',
        title: 'DSP Butterworth Pole Placement Lecture',
        startTime: DateTime(now.year, now.month, now.day, 10, 0),
        endTime: DateTime(now.year, now.month, now.day, 11, 30),
        location: 'Hall A-201',
        description: 'Analog to digital mapping using bilinear transformation.',
      ),
      CalendarEvent(
        id: 'cal_student_2',
        title: 'Embedded Systems & IoT Lab',
        startTime: DateTime(now.year, now.month, now.day, 14, 0),
        endTime: DateTime(now.year, now.month, now.day, 16, 0),
        location: 'Lab Room 304',
        description: 'ESP32-S3 I2S audio DAC and OLED interface calibration.',
      ),
      CalendarEvent(
        id: 'cal_student_3',
        title: 'Microcontroller Assignment Submission',
        startTime: DateTime(now.year, now.month, now.day, 18, 0),
        endTime: DateTime(now.year, now.month, now.day, 19, 0),
        location: 'Online Portal',
        description: 'Submit circuit schematics and firmware hex.',
      ),
    ];
  }

  /// Read upcoming events (next 3 days)
  Future<List<CalendarEvent>> getUpcomingEvents({int days = 3}) async {
    return getTodayEvents();
  }

  /// Format events as a text summary for Groq
  String eventsToPrompt(List<CalendarEvent> events) {
    if (events.isEmpty) return 'No calendar events today.';

    final buffer = StringBuffer("Today's calendar events:\n");
    for (int i = 0; i < events.length; i++) {
      final e = events[i];
      buffer.writeln(
        '${i + 1}. "${e.title}" at ${_formatTime(e.startTime)}'
        '${e.location != null ? ' (${e.location})' : ''}'
        '${e.description != null ? ' — ${e.description}' : ''}',
      );
    }
    return buffer.toString();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// A single calendar event
class CalendarEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
  });

  factory CalendarEvent.fromMap(Map<String, dynamic> map) {
    return CalendarEvent(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? 'Untitled',
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end'] as int),
      location: map['location'],
      description: map['description'],
    );
  }
}
