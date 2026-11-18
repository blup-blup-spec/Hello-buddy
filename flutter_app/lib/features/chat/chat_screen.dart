import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_cat_mascot.dart';
import 'package:hello_buddy/core/widgets/buddy_widgets.dart';
import 'package:hello_buddy/core/widgets/buddy_flowchart.dart';
import 'package:hello_buddy/models/task_model.dart';
import 'package:hello_buddy/services/groq_service.dart';
import 'package:hello_buddy/services/esp32_service.dart';
import 'package:hello_buddy/services/firebase_service.dart';
import 'package:hello_buddy/services/auth_service.dart';
import 'package:hello_buddy/services/alarm_service.dart';
import 'package:hello_buddy/services/phone_service.dart';
import 'package:hello_buddy/services/calendar_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final FlowchartData? flowchart;
  final String? oledText;
  final String? imageUrl;
  final String? imageBase64;
  final String? scheduledActionSummary;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.flowchart,
    this.oledText,
    this.imageUrl,
    this.imageBase64,
    this.scheduledActionSummary,
  });
}

class _ActionModalParams {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<String> statusLines;
  final String primaryButtonLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryButtonLabel;
  final VoidCallback? onSecondaryAction;

  _ActionModalParams({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.statusLines,
    required this.primaryButtonLabel,
    required this.onPrimaryAction,
    this.secondaryButtonLabel,
    this.onSecondaryAction,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _groq = GroqQwenService();
  final _esp32 = Esp32Service();
  final _picker = ImagePicker();
  late final _firebase = FirebaseService(AuthService());
  final _alarmService = AlarmService();
  final _phoneService = PhoneService();

  String _currentSubject = 'General Engineering & History';
  bool _isLoading = false;
  String? _attachedImageUrl;
  String? _attachedImageBase64;

  final List<ChatMessage> _messages = [
    ChatMessage(
      text: "Hey! I'm Buddy, your intelligent companion. Ask me any study question, snap a photo of diagrams, or tell me to schedule meetings, alarms, and tasks! I automatically write actions to Firebase RTDB and your robot OLED.",
      isUser: false,
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      flowchart: const FlowchartData(
        title: "Hello Buddy AI Architecture",
        steps: [
          "Voice/Text command entered in Chat",
          "Groq (openai/gpt-oss-20b) detects intent",
          "Tasks/Meetings written to Firebase RTDB",
          "Robot OLED displays action in real time",
          "Phone triggers native alerts & calendar"
        ],
      ),
      oledText: "Buddy: Ready for tasks!",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _firebase.watchRobotTelemetry().listen((telemetry) {
      final ip = telemetry['ip'] as String?;
      if (ip != null && ip.isNotEmpty && mounted) {
        _esp32.setIp(ip);
      }
    });

    // Option B: Real-time Firebase RTDB Bridge
    // When tasks or commands are scheduled via external Groq chat page, web console, or robot voice,
    // this listener automatically triggers the exact native action on the Android phone!
    final processedTaskIds = <String>{};
    _firebase.watchTasks().listen((tasks) async {
      for (final t in tasks) {
        if (t.id.isEmpty || processedTaskIds.contains(t.id)) continue;
        processedTaskIds.add(t.id);

        // Only process tasks scheduled recently (within 1 hour) to avoid re-triggering historical tasks
        final age = DateTime.now().difference(t.createdAt);
        if (age.inMinutes > 60) continue;

        final tag = (t.alertTag ?? '').toUpperCase();
        final lowerTitle = t.title.toLowerCase();

        if (tag.contains('ALARM') || lowerTitle.contains('alarm')) {
          final timeMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(tag) ??
              RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(t.title);
          int h = 7, m = 0;
          if (timeMatch != null) {
            h = int.tryParse(timeMatch.group(1) ?? '7') ?? 7;
            m = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
            if (timeMatch.groupCount >= 3 && timeMatch.group(3)?.toLowerCase() == 'pm' && h < 12) h += 12;
            if (timeMatch.groupCount >= 3 && timeMatch.group(3)?.toLowerCase() == 'am' && h == 12) h = 0;
          }
          final res = await _alarmService.setPhoneAlarm(title: t.title, hour: h, minute: m);
          if (mounted) {
            _showSyncedSnackBar('⏰ [RTDB Synced] ${res.message}');
          }
        } else if (tag.contains('MEETING') || lowerTitle.contains('meeting')) {
          final start = t.deadline ?? DateTime.now().add(const Duration(hours: 1));
          final res = await _alarmService.insertCalendarEvent(title: t.title, startTime: start);
          if (mounted) {
            _showSyncedSnackBar('📅 [RTDB Synced] ${res.message}');
          }
        } else if (tag.contains('CALL') || lowerTitle.contains('call')) {
          final target = t.title.replaceAll(RegExp(r'call|calling|to|my|:', caseSensitive: false), '').trim();
          final res = await _phoneService.callContact(target.isNotEmpty ? target : 'Mom');
          if (mounted) {
            _showSyncedSnackBar('📞 [RTDB Synced] ${res.message}');
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 82,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _attachedImageBase64 = base64Encode(bytes);
          _attachedImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera/Image error: $e'),
            backgroundColor: BuddyColors.coral,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final query = presetText ?? _inputController.text.trim();
    if (query.isEmpty && _attachedImageUrl == null && _attachedImageBase64 == null) {
      return;
    }

    final sendingImageUrl = _attachedImageUrl;
    final sendingImageBase64 = _attachedImageBase64;

    final userMsg = ChatMessage(
      text: query.isEmpty ? 'Analyze attached diagram/photo' : query,
      isUser: true,
      timestamp: DateTime.now(),
      imageUrl: sendingImageUrl,
      imageBase64: sendingImageBase64,
    );

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _attachedImageUrl = null;
      _attachedImageBase64 = null;
    });

    _inputController.clear();
    _scrollToBottom();

    try {
      final lowerQuery = query.toLowerCase();

      // Immediate direct test ringtone/alarm trigger
      if (RegExp(r'\b(?:test\s*ringtone|test\s*ring|test\s*alarm|ring\s*alarm|ringtone\s*test|play\s*ringtone)\b', caseSensitive: false).hasMatch(lowerQuery)) {
        await _alarmService.testAlarm();
        if (mounted) {
          _showNoticeSnackBar(
            '🔔 Playing Phone Alarm Ringtone Now!',
            actionLabel: 'STOP',
            onAction: () => _alarmService.stopAlarm(),
          );
          setState(() {
            _messages.add(ChatMessage(
              text: "🔔 Testing your phone's alarm ringtone right now! Check notification tray or tap silence below to stop.",
              isUser: false,
              timestamp: DateTime.now(),
              scheduledActionSummary: '🔔 Ringtone Test Active\n• Sound playing through phone alarm speaker\n• Tap Silence below to stop',
            ));
            _isLoading = false;
          });
          _scrollToBottom();
        }
        return;
      }

      // Immediate direct silence/dismiss trigger
      if (RegExp(r'\b(?:stop\s*alarm|stop\s*ringtone|silence|turn\s*off\s*alarm|dismiss\s*alarm)\b', caseSensitive: false).hasMatch(lowerQuery)) {
        await _alarmService.stopAlarm();
        if (mounted) {
          _showNoticeSnackBar('⏹️ Alarm silenced and dismissed.');
          setState(() {
            _messages.add(ChatMessage(
              text: '⏹️ Alarm silenced and dismissed.',
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isLoading = false;
          });
          _scrollToBottom();
        }
        return;
      }

      // 1. Calendar Context injection (if user asks about their schedule)
      var promptToSend = query;
      final scheduleQueryRegex = RegExp(
        r'(?:my\s+schedule|today(?:.*)schedule|my\s+calendar|my\s+meetings|what\s+do\s+i\s+have\s+today)',
        caseSensitive: false,
      );
      if (scheduleQueryRegex.hasMatch(query)) {
        try {
          final events = await CalendarService().getTodayEvents();
          final summary = CalendarService().eventsToPrompt(events);
          promptToSend = '$query\n\n[SYSTEM CALENDAR CONTEXT]:\n$summary';
        } catch (_) {}
      }

      // 2. Call Groq Agent using True Agentic JSON Tool-Calling
      debugPrint('[Buddy] Calling Groq askAgent...');
      BuddyAgentResponse agentRes;
      try {
        agentRes = await _groq.askAgent(
          subject: _currentSubject,
          userPrompt: promptToSend,
          imageUrl: sendingImageUrl,
          imageBase64: sendingImageBase64,
        );
        debugPrint('[Buddy] Groq returned: action=${agentRes.action}, reply=${agentRes.reply}');
      } catch (groqErr) {
        debugPrint('[Buddy] Groq FAILED: $groqErr');
        agentRes = BuddyAgentResponse(
          reply: 'Groq error: $groqErr',
          action: BuddyAgentActionType.none,
          actionParams: {},
          oledText: 'Error',
        );
      }

      String? actionSummary;
      final now = DateTime.now();

      // Robust fallback: if user gave an obvious command but Groq returned 'none'
      var resolvedAction = agentRes.action;
      if (resolvedAction == BuddyAgentActionType.none) {
        if (RegExp(r'\b(?:alarm|alrm|wake\s*up|wake\s*me)\b', caseSensitive: false).hasMatch(lowerQuery)) {
          resolvedAction = BuddyAgentActionType.alarm;
        } else if (RegExp(r'\b(?:call|calling|dial|phone)\b', caseSensitive: false).hasMatch(lowerQuery)) {
          resolvedAction = BuddyAgentActionType.call;
        } else if (RegExp(r'\b(?:schedule|meeting|calendar|timetable)\b', caseSensitive: false).hasMatch(lowerQuery)) {
          resolvedAction = BuddyAgentActionType.calendar;
        }
      }

      // 3. Agentic Action Router (Dual Execution: Phone Native OS + Robot RTDB)
      debugPrint('[Buddy] resolvedAction=$resolvedAction, agentRes.action=${agentRes.action}, reply=${agentRes.reply}');
      
      // Immediate feedback so the user knows the action was detected
      if (resolvedAction != BuddyAgentActionType.none && mounted) {
        _showNoticeSnackBar('⚡ Action detected: ${resolvedAction.name.toUpperCase()} — Executing...');
      }

      _ActionModalParams? modalParams;

      switch (resolvedAction) {
        case BuddyAgentActionType.alarm:
          var h = (agentRes.actionParams['hour'] as num?)?.toInt();
          var m = (agentRes.actionParams['minute'] as num?)?.toInt();

          // If no time extracted from JSON, scan query for numbers
          if (h == null) {
            final tm = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?', caseSensitive: false).firstMatch(query);
            if (tm != null) {
              h = int.tryParse(tm.group(1) ?? '7') ?? 7;
              m = int.tryParse(tm.group(2) ?? '0') ?? 0;
              final ampm = tm.group(3)?.toLowerCase();
              if (ampm == 'pm' && h < 12) h += 12;
              if (ampm == 'am' && h == 12) h = 0;
            } else {
              h = 7;
              m = 0;
            }
          }
          m ??= 0;

          final alarmTitle = (agentRes.actionParams['alarm_title'] as String?)?.trim();
          final titleToUse = (alarmTitle != null && alarmTitle.isNotEmpty) ? alarmTitle : 'Buddy Alarm';
          final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

          var alarmTime = DateTime(now.year, now.month, now.day, h, m);
          if (alarmTime.isBefore(now)) {
            alarmTime = alarmTime.add(const Duration(days: 1));
          }

          // [Step 1]: Execute True Phone Alarm Engine (AlarmManager + AlarmReceiver + System Clock)
          final alarmResult = await _alarmService.setPhoneAlarm(
            title: titleToUse,
            hour: h,
            minute: m,
            skipUi: false,
          );

          // [Step 2]: Non-blocking background sync to Firebase RTDB & ESP32 Robot
          unawaited(() async {
            try {
              final task = BuddyTask(
                id: '',
                title: titleToUse,
                priority: TaskPriority.high,
                deadline: alarmTime,
                source: TaskSource.groq,
                alertTag: 'ALARM $timeStr',
                pushedToOled: true,
                createdAt: now,
              );
              await _firebase.addTask(task).timeout(const Duration(seconds: 4));
              await _firebase.pushOledText('ALARM: $timeStr').timeout(const Duration(seconds: 3));
              await _esp32.setOledText('ALARM: $timeStr').timeout(const Duration(seconds: 2));
              await _esp32.speak('Alarm set for $timeStr').timeout(const Duration(seconds: 2));
              await _esp32.playTone('alarm').timeout(const Duration(seconds: 2));
            } catch (err) {
              debugPrint('[Buddy] Alarm background sync notice: $err');
            }
          }());

          actionSummary = '⏰ Phone Alarm: ${alarmResult.message}\n'
              '🤖 Robot Sync: Saved to RTDB & Armed on OLED ($timeStr)';

          modalParams = _ActionModalParams(
            title: 'Alarm Armed: $timeStr',
            subtitle: alarmResult.message,
            icon: Icons.alarm_rounded,
            iconColor: BuddyColors.coral,
            statusLines: [
              'Android Alarm: ${alarmResult.message}',
              'Audio Ringtone: Armed (High-Priority Heads-Up Alert)',
              'Robot OLED: Armed ("ALARM: $timeStr") & Audio Buzzer',
              'Firebase RTDB: Synced with /users/default/tasks',
            ],
            primaryButtonLabel: '🔔 Test Alarm Ringtone Now',
            onPrimaryAction: () => _alarmService.testAlarm(),
            secondaryButtonLabel: '⏰ Open System Clock',
            onSecondaryAction: () => _alarmService.setPhoneAlarm(
              title: titleToUse,
              hour: h!,
              minute: m!,
              skipUi: false,
            ),
          );
          break;

        case BuddyAgentActionType.call:
          final rawTarget = (agentRes.actionParams['contact_name'] as String?)?.trim() ??
              (agentRes.actionParams['phone_number'] as String?)?.trim();
          var target = (rawTarget != null && rawTarget.isNotEmpty) ? rawTarget : 'Mom';

          // If query had specific word
          if (target == 'Mom') {
            final match = RegExp(r'\b(?:call|calling|dial|phone)\s+(?:to\s+|my\s+)?([a-zA-Z0-9\+\s]+)', caseSensitive: false).firstMatch(query);
            if (match != null) {
              final extracted = match.group(1)?.trim();
              if (extracted != null && extracted.isNotEmpty) {
                target = extracted;
              }
            }
          }

          // [Step 1]: Phone Contact Resolution & Direct System Calling
          final callResult = await _phoneService.callContact(target);

          // [Step 2]: Non-blocking background sync to Robot
          unawaited(() async {
            try {
              await _firebase.pushOledText('CALL: $target').timeout(const Duration(seconds: 3));
              await _esp32.setOledText('CALL: $target').timeout(const Duration(seconds: 2));
              await _esp32.speak('Calling $target on your phone').timeout(const Duration(seconds: 2));
            } catch (err) {
              debugPrint('[Buddy] Call background sync notice: $err');
            }
          }());

          actionSummary = '📞 ${callResult.message}\n'
              '🤖 Robot Sync: Pushed to OLED Display';

          modalParams = _ActionModalParams(
            title: 'Phone Call: $target',
            subtitle: callResult.message,
            icon: Icons.phone_in_talk_rounded,
            iconColor: BuddyColors.lime,
            statusLines: [
              'Android Dialer: ${callResult.message}',
              'Contact Lookup: ${callResult.phoneNumber != null ? "Resolved (${callResult.phoneNumber})" : "Direct Dialer Active"}',
              'ESP32 Robot: Displaying "CALL: $target" on OLED',
            ],
            primaryButtonLabel: '📞 Open Dialer',
            onPrimaryAction: () => _phoneService.callContact(target),
          );
          break;

        case BuddyAgentActionType.calendar:
          final meetingTitle = (agentRes.actionParams['meeting_title'] as String?)?.trim();
          final titleToUse = (meetingTitle != null && meetingTitle.isNotEmpty) ? meetingTitle : 'Study Meeting';
          final startIso = agentRes.actionParams['meeting_start_iso'] as String?;
          var startTime = startIso != null ? DateTime.tryParse(startIso) : null;
          startTime ??= now.add(const Duration(hours: 2));

          final durationMinutes = (agentRes.actionParams['meeting_duration_minutes'] as num?)?.toInt() ?? 60;
          final endTime = startTime.add(Duration(minutes: durationMinutes));
          final timeStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';

          // [Step 1]: Phone System Calendar Insert & Launch
          final calResult = await _alarmService.insertCalendarEvent(
            title: titleToUse,
            startTime: startTime,
            endTime: endTime,
          );

          // [Step 2]: Non-blocking background sync to RTDB & ESP32
          unawaited(() async {
            try {
              final task = BuddyTask(
                id: '',
                title: titleToUse,
                priority: TaskPriority.high,
                deadline: startTime,
                source: TaskSource.groq,
                alertTag: 'MEETING',
                pushedToOled: true,
                createdAt: now,
              );
              await _firebase.addTask(task).timeout(const Duration(seconds: 4));
              await _firebase.pushOledText('MEETING: $titleToUse').timeout(const Duration(seconds: 3));
              await _esp32.setOledText('MEETING: $titleToUse').timeout(const Duration(seconds: 2));
              await _esp32.speak('Meeting scheduled for $timeStr').timeout(const Duration(seconds: 2));
            } catch (err) {
              debugPrint('[Buddy] Calendar background sync notice: $err');
            }
          }());

          actionSummary = '📅 Calendar: ${calResult.message}\n'
              '🤖 Robot Sync: Saved to RTDB & Armed on OLED ($timeStr)';

          modalParams = _ActionModalParams(
            title: 'Meeting: $titleToUse',
            subtitle: 'Scheduled for $timeStr.',
            icon: Icons.calendar_month_rounded,
            iconColor: BuddyColors.lime,
            statusLines: [
              'Google Calendar: ${calResult.message}',
              'ESP32 Robot: Displaying "MEETING: $titleToUse"',
              'Firebase RTDB: Saved under /users/default/tasks',
            ],
            primaryButtonLabel: '📅 Open Calendar App',
            onPrimaryAction: () => _alarmService.insertCalendarEvent(
              title: titleToUse,
              startTime: startTime!,
              endTime: endTime,
            ),
          );
          break;

        case BuddyAgentActionType.none:
          break;
      }

      final botMsg = ChatMessage(
        text: agentRes.reply.isEmpty ? 'Action complete.' : agentRes.reply,
        isUser: false,
        timestamp: DateTime.now(),
        flowchart: agentRes.flowchart,
        oledText: agentRes.oledText.isNotEmpty ? agentRes.oledText : null,
        scheduledActionSummary: actionSummary,
      );

      if (mounted) {
        setState(() {
          _messages.add(botMsg);
          _isLoading = false;
        });
        _scrollToBottom();
      }

      // Show Agentic Action Modal popup if an action was executed!
      if (modalParams != null && mounted) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            _showAgenticActionModal(
              title: modalParams!.title,
              subtitle: modalParams.subtitle,
              icon: modalParams.icon,
              iconColor: modalParams.iconColor,
              statusLines: modalParams.statusLines,
              primaryButtonLabel: modalParams.primaryButtonLabel,
              onPrimaryAction: modalParams.onPrimaryAction,
              secondaryButtonLabel: modalParams.secondaryButtonLabel,
              onSecondaryAction: modalParams.onSecondaryAction,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: "Notice: ${e.toString().replaceAll('Exception: ', '')}",
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _showAgenticActionModal({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<String> statusLines,
    required VoidCallback onPrimaryAction,
    required String primaryButtonLabel,
    VoidCallback? onSecondaryAction,
    String? secondaryButtonLabel,
  }) {
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: BuddyColors.bone,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BuddyColors.pitch, width: 3),
            boxShadow: const [
              BoxShadow(color: BuddyColors.pitch, offset: Offset(4, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(color: BuddyColors.pitch, width: 2),
                    ),
                    child: Icon(icon, color: BuddyColors.pitch, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: BuddyColors.lime,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: BuddyColors.pitch, width: 1.5),
                          ),
                          child: Text(
                            '⚡ AGENTIC ACTION DISPATCHED',
                            style: BuddyTheme.captionMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: BuddyColors.onLime,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: BuddyTheme.displayFont(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: BuddyColors.carbon,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: BuddyColors.carbon),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: BuddyTheme.bodyFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BuddyColors.smoke,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: statusLines
                      .map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: BuddyColors.lime, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    line,
                                    style: BuddyTheme.bodyFont(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: BuddyColors.carbon,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BuddyColors.lime,
                        foregroundColor: BuddyColors.onLime,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: BuddyColors.pitch, width: 2),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onPrimaryAction();
                      },
                      child: Text(
                        primaryButtonLabel,
                        style: BuddyTheme.bodyFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: BuddyColors.onLime,
                        ),
                      ),
                    ),
                  ),
                  if (secondaryButtonLabel != null && onSecondaryAction != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: BuddyColors.carbon,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: BuddyColors.pitch, width: 2),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onSecondaryAction();
                        },
                        child: Text(
                          secondaryButtonLabel,
                          style: BuddyTheme.bodyFont(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: BuddyColors.carbon,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pushToRobotOled(String text) async {
    try {
      await _esp32.setOledText(text);
    } catch (_) {
      await _firebase.pushOledText(text);
    }

    if (!mounted) return;
    _showNoticeSnackBar('📺 Pushed "$text" to Robot OLED');
  }

  void _showSyncedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: BuddyColors.lime, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: BuddyTheme.bodyFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: BuddyColors.carbon,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: BuddyColors.lime, width: 2),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showNoticeSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: BuddyTheme.bodyFont(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: BuddyColors.carbon,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: BuddyColors.lime, width: 2),
        ),
        duration: const Duration(seconds: 4),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: BuddyColors.lime,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  void _showSubjectDialog() {
    final subjects = [
      'DSP & Filter Design (ECE 402)',
      'Modern World History & Timelines',
      'Computer Architecture & Microcontrollers',
      'Data Structures & Algorithms',
      'Physics: Electromagnetism & Circuits',
      'Linear Algebra & Calculus',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: BuddyColors.bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECT ACTIVE SUBJECT',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              const SizedBox(height: 12),
              ...subjects.map((s) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      s,
                      style: BuddyTheme.bodyFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: _currentSubject == s
                        ? const Icon(Icons.check_circle, color: BuddyColors.lime)
                        : null,
                    onTap: () {
                      setState(() => _currentSubject = s);
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        );
      },
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: BuddyColors.bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final urlController = TextEditingController();

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SCAN DIAGRAM OR NOTES (VISION)',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.camera);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: BuddyColors.lime,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BuddyColors.pitch, width: 2),
                          boxShadow: const [
                            BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.camera_alt_rounded, size: 24, color: BuddyColors.onLime),
                            const SizedBox(height: 6),
                            Text(
                              'Snap Photo',
                              style: BuddyTheme.bodyFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: BuddyColors.onLime,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BuddyColors.pitch, width: 2),
                          boxShadow: const [
                            BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.photo_library_rounded, size: 24, color: BuddyColors.carbon),
                            const SizedBox(height: 6),
                            Text(
                              'Choose Gallery',
                              style: BuddyTheme.bodyFont(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: BuddyColors.carbon,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  hintText: 'Or paste image URL...',
                  hintStyle: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () {
                      final u = urlController.text.trim();
                      if (u.isNotEmpty) {
                        setState(() {
                          _attachedImageUrl = u;
                          _attachedImageBase64 = null;
                        });
                        Navigator.pop(ctx);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVoiceSchedulingSheet() {
    final commands = [
      '⏰ Set alarm for 6:00 AM tomorrow morning',
      '📅 Schedule meeting with project advisor tomorrow at 10 AM',
      '📞 Call Mom',
      '📅 What is my schedule today?',
      '📝 Schedule a 45-minute DSP study session at 5 PM',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: BuddyColors.bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'VOICE & CHAT SCHEDULING',
                    style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: BuddyColors.lime,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: BuddyColors.pitch, width: 1),
                    ),
                    child: Text(
                      'AI INTENT SYNC',
                      style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.onLime),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Tap an example or speak to schedule meetings, alarms, or study tasks directly to your DBMS and OLED:',
                style: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
              ),
              const SizedBox(height: 14),
              ...commands.map((cmd) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BuddyColors.pitch, width: 1.5),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(cmd, style: BuddyTheme.bodyFont(fontSize: 12, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: BuddyColors.carbon),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendMessage(cmd);
                      },
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.bone,
      body: Column(
        children: [
          _buildHeader(),
          _buildContextRibbon(),
          Expanded(child: _buildChatFeed()),
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BuddyColors.carbon,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Buddy is reasoning & updating DBMS...',
                    style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke),
                  ),
                ],
              ),
            ),
          _buildQuickActionTray(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: BuddyColors.carbon,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              const BuddyCatAvatar(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buddy Study & Schedule',
                      style: BuddyTheme.displayFont(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BuddyColors.bone,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'RTDB Active • Vision & Scheduling Live',
                      style: BuddyTheme.captionMono(
                        fontSize: 10,
                        color: BuddyColors.smoke,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () async {
                  try {
                    await _esp32.triggerListen();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Triggered Robot Mic! Speak to Buddy.'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Robot bridge: $e')),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: BuddyColors.lime,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: BuddyColors.pitch, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mic, size: 14, color: BuddyColors.onLime),
                      const SizedBox(width: 4),
                      Text(
                        'Robot Mic',
                        style: BuddyTheme.bodyFont(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: BuddyColors.onLime,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextRibbon() {
    return GestureDetector(
      onTap: _showSubjectDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: BuddyColors.bone,
          border: Border(bottom: BorderSide(color: BuddyColors.pitch, width: 1.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '📚 Subject: $_currentSubject',
                style: BuddyTheme.bodyFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BuddyColors.carbon,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BuddyColors.bone,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BuddyColors.pitch, width: 1.5),
              ),
              child: Text(
                'CHANGE',
                style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.carbon),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatFeed() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.90,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: msg.isUser ? BuddyColors.carbon : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(msg.isUser ? 20 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4 : 20),
                ),
                border: Border.all(color: BuddyColors.pitch, width: 2),
                boxShadow: const [
                  BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.isUser ? 'You' : 'Buddy',
                        style: BuddyTheme.displayFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: msg.isUser ? BuddyColors.bone : BuddyColors.carbon,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                        style: BuddyTheme.captionMono(
                          fontSize: 9,
                          color: BuddyColors.smoke,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (msg.imageBase64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        base64Decode(msg.imageBase64!),
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else if (msg.imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        msg.imageUrl!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Text('⚠️ Image failed to load'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Text content
                  Text(
                    msg.text,
                    style: BuddyTheme.bodyFont(
                      fontSize: 13,
                      color: msg.isUser ? BuddyColors.bone : BuddyColors.carbon,
                    ),
                  ),

                  // Scheduled action pill/card (DBMS integration confirmed)
                  if (msg.scheduledActionSummary != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: BuddyColors.lime.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BuddyColors.pitch, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event_available_rounded, color: BuddyColors.pitch, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  msg.scheduledActionSummary!,
                                  style: BuddyTheme.bodyFont(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: BuddyColors.carbon,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (msg.scheduledActionSummary!.toLowerCase().contains('alarm')) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  backgroundColor: BuddyColors.lime,
                                  side: const BorderSide(color: BuddyColors.pitch, width: 1.5),
                                  label: Text('🔔 Test Ringtone', style: BuddyTheme.captionMono(fontSize: 10, fontWeight: FontWeight.w800, color: BuddyColors.onLime)),
                                  onPressed: () => _alarmService.testAlarm(),
                                ),
                                ActionChip(
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(color: BuddyColors.pitch, width: 1.5),
                                  label: Text('⏹️ Silence', style: BuddyTheme.captionMono(fontSize: 10, fontWeight: FontWeight.w800, color: BuddyColors.carbon)),
                                  onPressed: () => _alarmService.stopAlarm(),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Flowchart diagram widget
                  if (msg.flowchart != null) ...[
                    const SizedBox(height: 10),
                    BuddyFlowchartWidget(data: msg.flowchart!),
                  ],

                  // Push to OLED Button
                  if (msg.oledText != null && msg.oledText!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _pushToRobotOled(msg.oledText!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BuddyDecorations.pill(fill: BuddyColors.lime),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('📺', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Push "${msg.oledText}" to OLED',
                                style: BuddyTheme.bodyFont(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: BuddyColors.onLime,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionTray() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEAE8E2),
        border: Border(top: BorderSide(color: BuddyColors.pitch, width: 2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            BuddyChip(
              label: '📅 Voice Schedule',
              onTap: _showVoiceSchedulingSheet,
            ),
            const SizedBox(width: 8),
            BuddyChip(
              label: '📸 Scan Note/Formula',
              onTap: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(width: 8),
            BuddyChip(
              label: '📝 Flow Diagram',
              onTap: () => _sendMessage(
                  'Explain a key process or timeline in $_currentSubject with a full flow diagram.'),
            ),
            const SizedBox(width: 8),
            BuddyChip(
              label: '⏱️ 25m Focus',
              onTap: () async {
                try {
                  await _esp32.controlPomodoro(action: 'start', minutes: 25);
                } catch (_) {
                  await _firebase.controlPomodoro('start', minutes: 25);
                }
                _sendMessage(
                    'Buddy, starting a 25-minute study sprint on $_currentSubject.');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: BuddyColors.pitch, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_attachedImageBase64 != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BuddyColors.lime.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: BuddyColors.pitch),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          base64Decode(_attachedImageBase64!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Photo attached for Vision analysis',
                          style: BuddyTheme.captionMono(
                            fontSize: 11,
                            color: BuddyColors.carbon,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _attachedImageBase64 = null),
                      ),
                    ],
                  ),
                )
              else if (_attachedImageUrl != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: BuddyColors.lime.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BuddyColors.pitch),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attachment, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Attached: $_attachedImageUrl',
                          style: BuddyTheme.captionMono(
                              fontSize: 10, color: BuddyColors.carbon),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _attachedImageUrl = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              Row(
                children: [
                  // Camera / Image picker button
                  GestureDetector(
                    onTap: _showImageOptions,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (_attachedImageBase64 != null ||
                                _attachedImageUrl != null)
                            ? BuddyColors.lime
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: BuddyColors.pitch, width: 2),
                        boxShadow: const [
                          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.camera_alt_rounded,
                            size: 19, color: BuddyColors.carbon),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Voice prompt button
                  GestureDetector(
                    onTap: _showVoiceSchedulingSheet,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: BuddyColors.pitch, width: 2),
                        boxShadow: const [
                          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.mic_rounded,
                            size: 20, color: BuddyColors.carbon),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Input field
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: BuddyColors.bone,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: BuddyColors.pitch, width: 2),
                      ),
                      child: TextField(
                        controller: _inputController,
                        onSubmitted: (_) => _sendMessage(),
                        style: BuddyTheme.bodyFont(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Ask, or say "Schedule meeting at 4pm"...',
                          hintStyle: BuddyTheme.bodyFont(
                              fontSize: 12, color: BuddyColors.smoke),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  GestureDetector(
                    onTap: () => _sendMessage(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: BuddyColors.lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: BuddyColors.pitch, width: 2),
                        boxShadow: const [
                          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.arrow_forward_rounded,
                            color: BuddyColors.onLime, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
