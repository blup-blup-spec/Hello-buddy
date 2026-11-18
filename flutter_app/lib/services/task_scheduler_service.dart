import 'dart:convert';
import 'package:hello_buddy/models/task_model.dart';
import 'package:hello_buddy/services/groq_service.dart';
import 'package:hello_buddy/services/firebase_service.dart';
import 'package:hello_buddy/services/calendar_service.dart';
import 'package:hello_buddy/services/notification_service.dart';

/// Orchestrates task scheduling:
///   1. Reads calendar events + phone notifications
///   2. Sends to Groq for summarization + task extraction
///   3. Saves extracted tasks to Firebase
///   4. Provides task ordering suggestions
class TaskSchedulerService {
  final GroqQwenService _groq;
  final FirebaseService _firebase;
  final CalendarService _calendar;
  final NotificationService _notifications;

  TaskSchedulerService({
    required GroqQwenService groq,
    required FirebaseService firebase,
    required CalendarService calendar,
    required NotificationService notifications,
  })  : _groq = groq,
        _firebase = firebase,
        _calendar = calendar,
        _notifications = notifications;

  /// Run the full import pipeline:
  ///   Calendar + Notifications → Groq → Tasks → Firebase
  ///
  /// Returns the list of newly created tasks.
  Future<List<BuddyTask>> importAndSchedule() async {
    // 1. Read calendar events
    List<CalendarEvent> events = [];
    try {
      events = await _calendar.getTodayEvents();
    } catch (_) {
      // Calendar permission not granted — skip
    }

    // 2. Read notifications
    List<AppNotification> notifs = [];
    try {
      notifs = await _notifications.getRecentNotifications(sinceMinutes: 120);
    } catch (_) {
      // Notification listener not enabled — skip
    }

    // 3. Build prompt for Groq
    final calendarText = _calendar.eventsToPrompt(events);
    final notifText = _notifications.notificationsToPrompt(notifs);

    final prompt = '''You are a study task scheduler for an engineering student.

$calendarText

$notifText

Based on the above, extract actionable study tasks. For each task, provide:
- title (max 20 characters for OLED display)
- deadline (ISO 8601 format, today's date if not specified)
- priority (high, medium, or low)
- estimated_pomodoros (number of 25-minute sessions needed)
- subject (academic subject if identifiable, otherwise null)
- source ("calendar" or "notification")
- alert_tag (short status like "DUE 2PM", "LAB TODAY", etc.)

Respond ONLY with a JSON array. No explanation. Example:
[
  {"title": "DSP Lab Report", "deadline": "2026-09-28T18:00:00", "priority": "high", "estimated_pomodoros": 2, "subject": "ECE 402", "source": "calendar", "alert_tag": "DUE 6PM"},
  {"title": "Reply Prof Email", "deadline": "2026-09-28T17:00:00", "priority": "high", "estimated_pomodoros": 1, "subject": null, "source": "notification", "alert_tag": "URGENT"}
]

If there are no actionable study tasks, respond with: []''';

    // 4. Ask Groq to extract tasks
    final response = await _groq.askStudyTutor(
      subject: 'Task Scheduling',
      userPrompt: prompt,
    );

    // 5. Parse the JSON response
    final tasks = _parseTasksFromGroq(response);

    // 6. Filter out duplicates (by calendarEventId)
    final newTasks = await _filterDuplicates(tasks, events);

    // 7. Save to Firebase
    if (newTasks.isNotEmpty) {
      await _firebase.addTasks(newTasks);
    }

    return newTasks;
  }

  /// Parse Groq's JSON response into BuddyTask list
  List<BuddyTask> _parseTasksFromGroq(String response) {
    try {
      // Extract JSON array from response (Groq might add markdown)
      String jsonStr = response.trim();

      // Remove markdown code fences if present
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '');
        jsonStr = jsonStr.replaceAll(RegExp(r'\n?```$'), '');
      }

      final List<dynamic> parsed = jsonDecode(jsonStr);

      return parsed.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final now = DateTime.now();

        return BuddyTask(
          id: '', // will be assigned by Firebase push()
          title: (map['title'] as String? ?? 'Task').substring(
            0,
            ((map['title'] as String?)?.length ?? 4).clamp(0, 20),
          ),
          source: map['source'] == 'calendar'
              ? TaskSource.calendar
              : map['source'] == 'notification'
                  ? TaskSource.notification
                  : TaskSource.groq,
          deadline: map['deadline'] != null
              ? DateTime.tryParse(map['deadline'])
              : null,
          priority: TaskPriority.values.firstWhere(
            (e) => e.name == (map['priority'] ?? 'medium'),
            orElse: () => TaskPriority.medium,
          ),
          estimatedPomodoros: map['estimated_pomodoros'] ?? 1,
          subject: map['subject'],
          alertTag: map['alert_tag'],
          pushedToOled: true,
          createdAt: now,
        );
      }).toList();
    } catch (e) {
      // Groq returned something unparseable — return empty
      return [];
    }
  }

  /// Filter out tasks that already exist (by calendar event ID)
  Future<List<BuddyTask>> _filterDuplicates(
    List<BuddyTask> tasks,
    List<CalendarEvent> events,
  ) async {
    // For now, return all tasks — dedup logic can be added
    // when we track calendarEventId in Firebase
    return tasks;
  }

  /// Ask Groq to suggest optimal task order
  Future<String> suggestTaskOrder(List<BuddyTask> tasks) async {
    if (tasks.isEmpty) return 'No tasks to schedule!';

    final taskList = tasks.asMap().entries.map((e) {
      final t = e.value;
      return '${e.key + 1}. "${t.title}" '
          '(priority: ${t.priority.name}, '
          'deadline: ${t.deadline?.toString() ?? "none"}, '
          '${t.estimatedPomodoros} pomodoros)';
    }).join('\n');

    return _groq.askStudyTutor(
      subject: 'Task Scheduling',
      userPrompt: '''Here are my study tasks for today:
$taskList

Suggest the optimal order to tackle them. Consider deadlines, priority, and Pomodoro time slots. Be concise — max 3 sentences.''',
    );
  }

  /// Extract a task from a voice/chat command
  /// e.g., "add task: finish DSP assignment by 6pm"
  Future<BuddyTask?> extractTaskFromText(String text) async {
    final prompt = '''Extract a study task from this voice command: "$text"

Respond with a single JSON object:
{"title": "...", "deadline": "ISO 8601 or null", "priority": "high/medium/low", "estimated_pomodoros": N, "subject": "... or null", "alert_tag": "... or null"}

If no task can be extracted, respond with: null''';

    final response = await _groq.askStudyTutor(
      subject: 'Task Extraction',
      userPrompt: prompt,
    );

    try {
      String jsonStr = response.trim();
      if (jsonStr == 'null') return null;

      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceAll(RegExp(r'^```\w*\n?'), '');
        jsonStr = jsonStr.replaceAll(RegExp(r'\n?```$'), '');
      }

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      return BuddyTask(
        id: '',
        title: (map['title'] as String? ?? 'Task').substring(
          0,
          ((map['title'] as String?)?.length ?? 4).clamp(0, 20),
        ),
        source: TaskSource.voice,
        deadline: map['deadline'] != null
            ? DateTime.tryParse(map['deadline'])
            : null,
        priority: TaskPriority.values.firstWhere(
          (e) => e.name == (map['priority'] ?? 'medium'),
          orElse: () => TaskPriority.medium,
        ),
        estimatedPomodoros: map['estimated_pomodoros'] ?? 1,
        subject: map['subject'],
        alertTag: map['alert_tag'],
        pushedToOled: true,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }
}
