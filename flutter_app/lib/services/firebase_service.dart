import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:hello_buddy/models/task_model.dart';
import 'package:hello_buddy/services/auth_service.dart';

/// Firebase Realtime Database service.
///
/// Matches the ESP32 firmware path:
///   FIREBASE_USER_PATH = "/users/default"
///
/// Structure:
///   users/default/
///     tasks/
///       {taskId}: { title, completed, source, created_at, ... }
///     robot/
///       telemetry: { expression, task_count, pomodoro_active, uptime_s, ip, status }
///       commands:  { emotion_state, oled_text, pomodoro_action, ... }
///     voice_logs/
///       {logId}: { heard, replied, timestamp }
class FirebaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final AuthService _auth;

  FirebaseService(this._auth);

  /// Database reference pointing to the shared robot user branch
  DatabaseReference get _robotRef => _db.ref('users/default');

  // ====================== TASKS ======================

  /// Stream of all tasks (real-time updates from Firebase)
  Stream<List<BuddyTask>> watchTasks() {
    return _robotRef.child('tasks').onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <BuddyTask>[];

      final Map<dynamic, dynamic> data;
      if (value is Map) {
        data = value;
      } else {
        return <BuddyTask>[];
      }

      final list = <BuddyTask>[];
      data.forEach((k, v) {
        if (v is Map) {
          try {
            list.add(BuddyTask.fromJson(
              k.toString(),
              Map<String, dynamic>.from(v),
            ));
          } catch (e) {
            debugPrint('Error parsing task $k: $e');
          }
        }
      });

      // Sort: incomplete first, high priority first, then deadline
      list.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        final priOrder = {'high': 0, 'medium': 1, 'low': 2};
        final priA = priOrder[a.priority.name] ?? 1;
        final priB = priOrder[b.priority.name] ?? 1;
        if (priA != priB) return priA.compareTo(priB);
        if (a.deadline != null && b.deadline != null) {
          return a.deadline!.compareTo(b.deadline!);
        }
        return 0;
      });

      return list;
    });
  }

  /// Add a new task (immediately visible to ESP32 on its next poll)
  Future<String> addTask(BuddyTask task) async {
    final ref = _robotRef.child('tasks').push();
    await ref.set(task.toJson());
    return ref.key ?? '';
  }

  /// Add multiple tasks at once
  Future<void> addTasks(List<BuddyTask> tasks) async {
    for (final task in tasks) {
      await addTask(task);
    }
  }

  /// Toggle completion of a task
  Future<void> toggleTask(String taskId, bool isCompleted) async {
    await _robotRef.child('tasks/$taskId').update({
      'completed': isCompleted,
    });
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    await _robotRef.child('tasks/$taskId').remove();
  }

  // ====================== ROBOT TELEMETRY & COMMANDS ======================

  /// Stream robot telemetry (live status, expression, IP, uptime, pomodoro)
  Stream<Map<String, dynamic>> watchRobotTelemetry() {
    return _robotRef.child('robot/telemetry').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    });
  }

  /// Stream live voice logs (what the robot heard and replied)
  Stream<List<Map<String, dynamic>>> watchVoiceLogs() {
    return _robotRef.child('voice_logs').limitToLast(20).onValue.map((event) {
      final val = event.snapshot.value;
      if (val == null || val is! Map) return [];
      final logs = <Map<String, dynamic>>[];
      val.forEach((k, v) {
        if (v is Map) {
          logs.add(Map<String, dynamic>.from(v));
        }
      });
      logs.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      return logs;
    });
  }

  /// Push text to robot OLED via Firebase command buffer
  Future<void> pushOledText(String text) async {
    await _robotRef.child('robot/commands').update({
      'oled_text': text,
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Set robot emotion via Firebase (0=Happy, 1=Sad, 2=Focused, 3=Angry, 4=Sleepy, 5=Excited, 6=Neutral, 7=Confused)
  Future<void> setRobotEmotion(int emotionIndex) async {
    await _robotRef.child('robot/commands').update({
      'emotion_state': emotionIndex,
      'timestamp': ServerValue.timestamp,
    });
  }

  /// Control Pomodoro via Firebase
  Future<void> controlPomodoro(String action, {int minutes = 25}) async {
    await _robotRef.child('robot/commands').update({
      'pomodoro_action': action,
      'minutes': minutes,
      'timestamp': ServerValue.timestamp,
    });
  }

  // ====================== BOT TO APP ACTIONS (BIDIRECTIONAL) ======================

  /// Watch actions generated by the robot (alarms, calendar events)
  Stream<List<Map<String, dynamic>>> watchBotActions() {
    return _robotRef.child('bot_actions').limitToLast(15).onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null || value is! Map) return [];
      final list = <Map<String, dynamic>>[];
      value.forEach((k, v) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          m['id'] = k.toString();
          list.add(m);
        }
      });
      list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      return list;
    });
  }

  /// Mark bot action as executed on the phone so it does not trigger again
  Future<void> markBotActionExecuted(String actionId) async {
    await _robotRef.child('bot_actions/$actionId').update({
      'executed': true,
      'executed_at': ServerValue.timestamp,
    });
  }
}
