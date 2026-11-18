import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

/// Result from an alarm or calendar execution
class NativeActionResult {
  final bool success;
  final String message;
  final String? error;

  const NativeActionResult({
    required this.success,
    required this.message,
    this.error,
  });
}

/// Service to execute native Android alarms and calendar events
class AlarmService {
  static const _alarmChannel = MethodChannel('com.hellobuddy/alarm');
  static const _calChannel = MethodChannel('com.hellobuddy/calendar');
  static const _phoneChannel = MethodChannel('com.hellobuddy/phone');

  /// Trigger phone call to a contact (e.g. "Maa", "Mom")
  Future<NativeActionResult> makePhoneCall(String contactName) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const NativeActionResult(
        success: false,
        message: 'Non-Android platform',
        error: 'Platform not supported',
      );
    }
    debugPrint('[AlarmService] Calling contact: $contactName');
    try {
      final res = await _phoneChannel.invokeMethod('callContact', {'name': contactName});
      if (res is Map && res['success'] == true) {
        return NativeActionResult(
          success: true,
          message: 'Calling $contactName...',
        );
      }
      return NativeActionResult(
        success: false,
        message: 'Could not place call to $contactName',
      );
    } catch (e) {
      debugPrint('[AlarmService] makePhoneCall error: $e');
      return NativeActionResult(
        success: false,
        message: 'Failed to call $contactName',
        error: e.toString(),
      );
    }
  }

  /// Set a native Android alarm on the phone
  /// Strategy:
  ///   1. Launch AndroidIntent (AlarmClock.ACTION_SET_ALARM) -> Pops or sets in System Clock
  ///   2. Also invoke MethodChannel -> Sets AlarmManager exact alarm on device
  Future<NativeActionResult> setPhoneAlarm({
    required String title,
    required int hour,
    required int minute,
    bool skipUi = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const NativeActionResult(
        success: false,
        message: 'Non-Android platform',
        error: 'Platform not supported',
      );
    }

    final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    debugPrint('[AlarmService] Setting alarm: $title at $timeStr');

    bool registered = false;
    String message = 'Alarm armed for $timeStr';
    String? error;

    // 1. Primary: Native MethodChannel -> True AlarmManager AlarmClock Engine + OEM System Clock
    try {
      final mcResult = await _alarmChannel.invokeMethod('setAlarm', {
        'title': title,
        'hour': hour,
        'minutes': minute,
        'skipUi': skipUi,
      });
      if (mcResult is Map) {
        registered = mcResult['success'] == true;
        message = mcResult['message'] as String? ?? message;
      } else if (mcResult == true) {
        registered = true;
      }
    } catch (e) {
      debugPrint('[AlarmService] MethodChannel setAlarm error: $e');
      error = e.toString();
    }

    // 2. Secondary fallback: direct AndroidIntent
    if (!registered) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.SET_ALARM',
          arguments: <String, dynamic>{
            'android.intent.extra.alarm.MESSAGE': title,
            'android.intent.extra.alarm.HOUR': hour,
            'android.intent.extra.alarm.MINUTES': minute,
            'android.intent.extra.alarm.SKIP_UI': skipUi,
          },
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        registered = true;
        message = 'Clock app opened for $timeStr';
      } catch (e2) {
        debugPrint('[AlarmService] AndroidIntent fallback failed: $e2');
        error = '$error | $e2';
      }
    }

    return NativeActionResult(
      success: registered,
      message: registered ? message : 'Alarm configured for $timeStr',
      error: error,
    );
  }

  /// Test the alarm ringtone and vibration immediately
  Future<void> testAlarm() async {
    try {
      await _alarmChannel.invokeMethod('testAlarm');
    } catch (_) {}
  }

  /// Stop currently ringing alarm
  Future<void> stopAlarm() async {
    try {
      await _alarmChannel.invokeMethod('stopAlarm');
    } catch (_) {}
  }

  /// Open system alarm clock app
  Future<void> showPhoneAlarms() async {
    try {
      await _alarmChannel.invokeMethod('showAlarms');
    } catch (_) {}
  }

  /// Insert event into Android Calendar
  Future<NativeActionResult> insertCalendarEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const NativeActionResult(
        success: false,
        message: 'Non-Android platform',
      );
    }

    final end = endTime ?? startTime.add(const Duration(hours: 1));
    bool opened = false;
    String? error;

    // 1. Launch ACTION_INSERT intent so Calendar app opens with event
    try {
      debugPrint('[AlarmService] Launching Calendar ACTION_INSERT: title=$title start=${startTime.millisecondsSinceEpoch}');
      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: <String, dynamic>{
          'title': title,
          'description': description ?? 'Hello Buddy Meeting',
          'eventLocation': location ?? '',
          'beginTime': startTime.millisecondsSinceEpoch,
          'endTime': end.millisecondsSinceEpoch,
        },
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      opened = true;
    } catch (e) {
      error = e.toString();
      debugPrint('[AlarmService] Calendar ACTION_INSERT failed: $e');
    }

    // 2. Also write direct via ContentResolver through MethodChannel
    try {
      await _calChannel.invokeMethod('insertCalendarEvent', {
        'title': title,
        'start': startTime.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'description': description ?? '',
        'location': location ?? '',
      });
      opened = true;
    } catch (e) {
      debugPrint('[AlarmService] Direct calendar DB insert failed: $e');
    }

    return NativeActionResult(
      success: opened,
      message: opened ? 'Calendar Event Created: "$title"' : 'Could not open Calendar',
      error: error,
    );
  }
}
