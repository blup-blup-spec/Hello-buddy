// Task model with all fields needed for Hello Buddy scheduling.
//
// Tasks can come from 4 sources:
//   - CALENDAR: auto-extracted from Google Calendar events
//   - NOTIFICATION: extracted from phone notification summary
//   - MANUAL: user typed it in the cockpit
//   - VOICE: user spoke it via phone mic → Groq parsed it
//   - GROQ: Groq suggested it based on context

enum TaskSource { calendar, notification, manual, voice, groq }

enum TaskPriority { high, medium, low }

class BuddyTask {
  final String id;
  final String title;
  final TaskSource source;
  final DateTime? deadline;
  final TaskPriority priority;
  final int estimatedPomodoros;
  final String? subject;
  final bool isCompleted;
  final bool pushedToOled;
  final String? alertTag;
  final String? calendarEventId;
  final String? notificationSummary;
  final DateTime createdAt;

  const BuddyTask({
    required this.id,
    required this.title,
    this.source = TaskSource.manual,
    this.deadline,
    this.priority = TaskPriority.medium,
    this.estimatedPomodoros = 1,
    this.subject,
    this.isCompleted = false,
    this.pushedToOled = false,
    this.alertTag,
    this.calendarEventId,
    this.notificationSummary,
    required this.createdAt,
  });

  factory BuddyTask.fromJson(String id, Map<String, dynamic> json) {
    return BuddyTask(
      id: id,
      title: json['title'] ?? '',
      source: TaskSource.values.firstWhere(
        (e) => e.name == (json['source'] ?? 'manual'),
        orElse: () => TaskSource.manual,
      ),
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'])
          : null,
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == (json['priority'] ?? 'medium'),
        orElse: () => TaskPriority.medium,
      ),
      estimatedPomodoros: json['estimated_pomodoros'] ?? 1,
      subject: json['subject'],
      isCompleted: json['completed'] ?? false,
      pushedToOled: json['pushed_to_oled'] ?? false,
      alertTag: json['alert_tag'],
      calendarEventId: json['calendar_event_id'],
      notificationSummary: json['notification_summary'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'source': source.name,
        'deadline': deadline?.toIso8601String(),
        'priority': priority.name,
        'estimated_pomodoros': estimatedPomodoros,
        'subject': subject,
        'completed': isCompleted,
        'pushed_to_oled': pushedToOled,
        'alert_tag': alertTag,
        'calendar_event_id': calendarEventId,
        'notification_summary': notificationSummary,
        'created_at': createdAt.toIso8601String(),
      };

  BuddyTask copyWith({
    String? title,
    TaskSource? source,
    DateTime? deadline,
    TaskPriority? priority,
    int? estimatedPomodoros,
    String? subject,
    bool? isCompleted,
    bool? pushedToOled,
    String? alertTag,
  }) {
    return BuddyTask(
      id: id,
      title: title ?? this.title,
      source: source ?? this.source,
      deadline: deadline ?? this.deadline,
      priority: priority ?? this.priority,
      estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
      subject: subject ?? this.subject,
      isCompleted: isCompleted ?? this.isCompleted,
      pushedToOled: pushedToOled ?? this.pushedToOled,
      alertTag: alertTag ?? this.alertTag,
      calendarEventId: calendarEventId,
      notificationSummary: notificationSummary,
      createdAt: createdAt,
    );
  }

  /// Whether the task is overdue
  bool get isOverdue =>
      deadline != null &&
      !isCompleted &&
      deadline!.isBefore(DateTime.now());

  /// Human-readable alert tag
  String get computedAlertTag {
    if (alertTag != null) return alertTag!;
    if (isOverdue) return 'OVERDUE';
    if (deadline != null) {
      final diff = deadline!.difference(DateTime.now());
      if (diff.inHours < 2) return 'DUE SOON';
      if (diff.inHours < 24) return 'DUE TODAY';
    }
    return '';
  }
}

/// Study session model
class StudySession {
  final String id;
  final String? subject;
  final DateTime startTime;
  final int durationMinutes;
  final int pomodoroCount;
  final int distractionCount;

  const StudySession({
    required this.id,
    this.subject,
    required this.startTime,
    this.durationMinutes = 0,
    this.pomodoroCount = 0,
    this.distractionCount = 0,
  });

  factory StudySession.fromJson(String id, Map<String, dynamic> json) {
    return StudySession(
      id: id,
      subject: json['subject'],
      startTime: DateTime.tryParse(json['start_time'] ?? '') ?? DateTime.now(),
      durationMinutes: json['duration_minutes'] ?? 0,
      pomodoroCount: json['pomodoro_count'] ?? 0,
      distractionCount: json['distraction_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'start_time': startTime.toIso8601String(),
        'duration_minutes': durationMinutes,
        'pomodoro_count': pomodoroCount,
        'distraction_count': distractionCount,
      };
}
