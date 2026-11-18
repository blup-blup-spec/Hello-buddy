import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_cat_mascot.dart';
import 'package:hello_buddy/core/widgets/buddy_widgets.dart';
import 'package:hello_buddy/models/task_model.dart';
import 'package:hello_buddy/services/firebase_service.dart';
import 'package:hello_buddy/services/auth_service.dart';
import 'package:hello_buddy/services/esp32_service.dart';
import 'package:hello_buddy/services/alarm_service.dart';
import 'package:hello_buddy/services/task_scheduler_service.dart';
import 'package:hello_buddy/services/calendar_service.dart';
import 'package:hello_buddy/services/notification_service.dart';
import 'package:hello_buddy/services/groq_service.dart';

class CockpitScreen extends StatefulWidget {
  const CockpitScreen({super.key});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  late final _firebase = FirebaseService(AuthService());
  final _esp32 = Esp32Service();
  final _alarmService = AlarmService();

  int _modeIndex = 0; // 0=Focus, 1=Friendly, 2=Sleep, 3=Alert
  int _selectedDay = (DateTime.now().weekday - 1).clamp(0, 6);
  bool _showAllWeek = false;
  bool _showCompletedOnly = false;

  // Live robot telemetry
  bool _isOnline = false;
  String _robotIp = 'Searching...';
  String _currentExprName = 'Happy';
  int _uptimeSec = 0;

  // Focus sprint timer
  int _timerSeconds = 25 * 60;
  bool _timerRunning = false;
  Timer? _timer;

  StreamSubscription? _telemetrySub;
  StreamSubscription? _botActionsSub;

  @override
  void initState() {
    super.initState();
    _startTimerTicker();
    _listenToTelemetry();
    _listenToBotActions();
  }

  void _listenToBotActions() {
    _botActionsSub = _firebase.watchBotActions().listen((actions) async {
      for (final action in actions) {
        if (action['executed'] == true) continue;
        final actionId = action['id'] as String? ?? '';
        final type = action['type'] as String? ?? '';
        final title = action['title'] as String? ?? 'Buddy';

        if (type == 'alarm') {
          final h = action['hour'] as int? ?? 7;
          final m = action['minute'] as int? ?? 0;
          await _alarmService.setPhoneAlarm(
            title: title,
            hour: h,
            minute: m,
            skipUi: true,
          );
          if (actionId.isNotEmpty) {
            await _firebase.markBotActionExecuted(actionId);
          }
          if (mounted) {
            final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
            _showFeedbackSnackBar('⏰ Buddy set your phone alarm for $timeStr ("$title")');
          }
        } else if (type == 'calendar') {
          final timeStr = (action['time'] as String? ?? '').toLowerCase();
          final now = DateTime.now();
          DateTime eventDate = now.add(const Duration(days: 1));
          if (timeStr.contains('today')) {
            eventDate = now;
          }
          final start = DateTime(eventDate.year, eventDate.month, eventDate.day, 10, 0);
          await _alarmService.insertCalendarEvent(
            title: title,
            startTime: start,
            description: 'Scheduled by Buddy Voice Assistant',
          );
          if (actionId.isNotEmpty) {
            await _firebase.markBotActionExecuted(actionId);
          }
          if (mounted) {
            _showFeedbackSnackBar('📅 Buddy added "$title" to your phone calendar!');
          }
        }
      }
    });
  }

  void _listenToTelemetry() {
    _telemetrySub = _firebase.watchRobotTelemetry().listen((telemetry) {
      if (!mounted) return;
      final ip = telemetry['ip'] as String?;
      final status = telemetry['status'] as String?;
      final uptime = telemetry['uptime_s'] as int? ?? 0;
      final exprIdx = telemetry['expression'] as int? ?? 6;
      final pomoActive = telemetry['pomodoro_active'] as bool? ?? false;
      final pomoRemain = telemetry['pomodoro_remaining'] as int? ?? 0;

      final exprNames = ['Happy', 'Sad', 'Focused', 'Angry', 'Sleepy', 'Excited', 'Neutral', 'Confused'];

      setState(() {
        _isOnline = status == 'ONLINE';
        if (ip != null && ip.isNotEmpty) {
          _robotIp = ip;
          _esp32.setIp(ip);
        }
        _uptimeSec = uptime;
        if (exprIdx >= 0 && exprIdx < exprNames.length) {
          _currentExprName = exprNames[exprIdx];
        }
        if (pomoActive && pomoRemain > 0) {
          _timerSeconds = pomoRemain;
          _timerRunning = true;
        }
      });
    });
  }

  void _startTimerTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_timerRunning && _timerSeconds > 0) {
        setState(() => _timerSeconds--);
      } else if (_timerSeconds <= 0 && _timerRunning) {
        setState(() => _timerRunning = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _telemetrySub?.cancel();
    _botActionsSub?.cancel();
    super.dispose();
  }

  String get _timerDisplay {
    final m = _timerSeconds ~/ 60;
    final s = _timerSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _setRobotEmotion(int mode) async {
    // 0=Focus (expr 2), 1=Friendly (expr 0), 2=Sleep (expr 4), 3=Alert (expr 3)
    final exprMap = [2, 0, 4, 3];
    final targetExpr = exprMap[mode.clamp(0, 3)];

    setState(() => _modeIndex = mode);

    try {
      await _esp32.setEmotion(targetExpr);
    } catch (_) {
      await _firebase.setRobotEmotion(targetExpr);
    }
  }

  Future<void> _togglePomodoro() async {
    final newRunning = !_timerRunning;
    setState(() => _timerRunning = newRunning);

    final action = newRunning ? 'start' : 'stop';
    try {
      await _esp32.controlPomodoro(action: action, minutes: _timerSeconds ~/ 60);
    } catch (_) {
      await _firebase.controlPomodoro(action, minutes: _timerSeconds ~/ 60);
    }
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    TaskPriority selectedPriority = TaskPriority.high;

    showModalBottomSheet(
      context: context,
      backgroundColor: BuddyColors.bone,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ADD STUDY TASK',
                        style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
                      ),
                      Text(
                        'Syncs with Robot OLED',
                        style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.smoke),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: BuddyTheme.bodyFont(fontSize: 14, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'e.g. Read DSP Chapter 4 (max 28 chars)',
                      hintStyle: BuddyTheme.bodyFont(fontSize: 13, color: BuddyColors.smoke),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Priority: ', style: BuddyTheme.bodyFont(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      ...TaskPriority.values.map((p) {
                        final isSel = selectedPriority == p;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p.name.toUpperCase()),
                            selected: isSel,
                            selectedColor: BuddyColors.lime,
                            labelStyle: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isSel ? BuddyColors.onLime : BuddyColors.carbon,
                            ),
                            onSelected: (v) {
                              if (v) setModalState(() => selectedPriority = p);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: BuddyPillButton(
                      label: 'Add & Push to OLED →',
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isNotEmpty) {
                          final task = BuddyTask(
                            id: '',
                            title: title.length > 28 ? title.substring(0, 28) : title,
                            priority: selectedPriority,
                            pushedToOled: true,
                            source: TaskSource.manual,
                            createdAt: DateTime.now(),
                          );
                          await _firebase.addTask(task);
                          await _firebase.pushOledText(task.title);
                          try {
                            await _esp32.setOledText(task.title);
                          } catch (_) {}
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncCalendarTasks() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📅 Reading schedule & extracting tasks via Groq...'),
        backgroundColor: BuddyColors.carbon,
      ),
    );
    try {
      final scheduler = TaskSchedulerService(
        groq: GroqQwenService(),
        firebase: _firebase,
        calendar: CalendarService(),
        notifications: NotificationService(),
      );
      final tasks = await scheduler.importAndSchedule();
      if (!mounted) return;
      _showFeedbackSnackBar('✅ Synced ${tasks.length} tasks from calendar to Firebase & OLED!');
    } catch (e) {
      if (!mounted) return;
      _showFeedbackSnackBar('Sync notice: $e', isSuccess: false);
    }
  }

  void _showFeedbackSnackBar(
    String message, {
    bool isSuccess = true,
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
          side: BorderSide(
            color: isSuccess ? BuddyColors.lime : BuddyColors.coral,
            width: 2,
          ),
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

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(month - 1).clamp(0, 11)];
  }

  void _showSpeakDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: BuddyColors.bone,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: BuddyColors.pitch, width: 2),
          ),
          title: Text(
            'SPEAK ON ROBOT',
            style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
          ),
          content: TextField(
            controller: textController,
            decoration: InputDecoration(
              hintText: 'Type text for MAX98357A speaker...',
              hintStyle: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: BuddyTheme.bodyFont(color: BuddyColors.smoke)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BuddyColors.lime,
                foregroundColor: BuddyColors.onLime,
              ),
              onPressed: () async {
                final txt = textController.text.trim();
                if (txt.isNotEmpty) {
                  try {
                    await _esp32.speak(txt);
                  } catch (e) {
                    debugPrint('Speak error: $e');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Speak 🔊'),
            ),
          ],
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
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                children: [
                  _buildRobotDeck(),
                  const SizedBox(height: 16),
                  _buildStudyAgenda(),
                  const SizedBox(height: 16),
                  _buildFocusTimer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final uptimeM = _uptimeSec ~/ 60;
    return Container(
      decoration: const BoxDecoration(
        color: BuddyColors.carbon,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 4)),
        ],
        border: Border(bottom: BorderSide(color: BuddyColors.pitch, width: 2)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'COMPANION DASHBOARD',
                      style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _isOnline ? BuddyColors.lime : BuddyColors.coral,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: BuddyColors.pitch, width: 1.5),
                        ),
                        child: Text(
                          _isOnline ? 'ONLINE ●' : 'OFFLINE ○',
                          style: BuddyTheme.captionMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _isOnline ? BuddyColors.onLime : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 95),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: BuddyColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: BuddyColors.smoke.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'IP: $_robotIp',
                          style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const BuddyCatAvatar(size: 48),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Buddy • Desktop Sentinel',
                        style: BuddyTheme.displayFont(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: BuddyColors.bone,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _isOnline ? BuddyColors.lime : BuddyColors.smoke,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Face: $_currentExprName • Uptime: ${uptimeM}m',
                            style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.smoke),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRobotDeck() {
    return BuddyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, size: 18, color: BuddyColors.carbon),
                  const SizedBox(width: 8),
                  Text(
                    'ROBOT EXPRESSION & AUDIO',
                    style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          BuddySegmentedControl(
            labels: const ['🎯 Focus', '😊 Happy', '💤 Sleep', '😠 Alert'],
            selectedIndex: _modeIndex,
            onChanged: _setRobotEmotion,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ActionButton(
                label: '🎤 Mic Listen',
                onTap: () async {
                  try {
                    await _esp32.triggerListen();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Triggered Robot Mic! Speak to Buddy.')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: '🔔 Chime',
                onTap: () async {
                  try {
                    await _esp32.playTone('chime');
                  } catch (_) {}
                },
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: '📢 Speak Text',
                isPrimary: true,
                onTap: _showSpeakDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudyAgenda() {
    final now = DateTime.now();
    // Monday of the active week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekDays = List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return DateTime(d.year, d.month, d.day);
    });
    final dayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return StreamBuilder<List<BuddyTask>>(
      stream: _firebase.watchTasks(),
      builder: (context, snapshot) {
        final allTasks = snapshot.data ?? [];
        final activeTasks = allTasks.where((t) => !t.isCompleted).toList();
        final completedTasks = allTasks.where((t) => t.isCompleted).toList();

        // Tasks count per day for the 7-day indicators
        int taskCountForDay(DateTime d) {
          return activeTasks.where((t) {
            final tDate = t.deadline ?? t.createdAt;
            return tDate.year == d.year && tDate.month == d.month && tDate.day == d.day;
          }).length;
        }

        // Active list depending on To-Do / Done tab
        final listSource = _showCompletedOnly ? completedTasks : activeTasks;

        // Apply Day or All-Week Filter
        List<BuddyTask> displayTasks;
        if (_showAllWeek) {
          displayTasks = List.from(listSource);
          displayTasks.sort((a, b) {
            final da = a.deadline ?? a.createdAt;
            final db = b.deadline ?? b.createdAt;
            return db.compareTo(da);
          });
        } else {
          final targetDay = weekDays[_selectedDay.clamp(0, 6)];
          displayTasks = listSource.where((t) {
            final tDate = t.deadline ?? t.createdAt;
            return tDate.year == targetDay.year && tDate.month == targetDay.month && tDate.day == targetDay.day;
          }).toList();
        }

        final activeDay = weekDays[_selectedDay.clamp(0, 6)];
        final dayTitle = _showAllWeek
            ? "THIS WEEK'S AGENDA (${allTasks.length} TOTAL)"
            : "${dayLabels[_selectedDay.clamp(0, 6)]}, ${activeDay.day} ${_monthName(activeDay.month)}";

        return BuddyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Title & Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      dayTitle,
                      style: BuddyTheme.captionMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: BuddyColors.carbon,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _showAllWeek = !_showAllWeek),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _showAllWeek ? BuddyColors.lime : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: BuddyColors.pitch, width: 1.5),
                          ),
                          child: Text(
                            _showAllWeek ? '📅 7-DAY VIEW' : '📅 ALL WEEK',
                            style: BuddyTheme.captionMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: _showAllWeek ? BuddyColors.onLime : BuddyColors.carbon,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _showAddTaskDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: BuddyColors.lime,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: BuddyColors.pitch, width: 1.5),
                          ),
                          child: Text(
                            '+ ADD',
                            style: BuddyTheme.captionMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: BuddyColors.onLime,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _syncCalendarTasks,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: BuddyColors.pitch, width: 1.5),
                          ),
                          child: Text(
                            '📅 SYNC',
                            style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.carbon),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Dynamic 7-Day Week Strip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(7, (i) {
                    final day = weekDays[i];
                    final isSelected = !_showAllWeek && _selectedDay == i;
                    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                    final count = taskCountForDay(day);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedDay = i;
                            _showAllWeek = false;
                          });
                        },
                        child: Column(
                          children: [
                            Text(
                              dayLabels[i],
                              style: BuddyTheme.captionMono(
                                fontSize: 9,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? BuddyColors.pitch : (isToday ? BuddyColors.carbon : BuddyColors.smoke),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 38,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? BuddyColors.lime
                                    : (isToday ? Colors.white : Colors.transparent),
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected || isToday
                                    ? Border.all(color: BuddyColors.pitch, width: 2)
                                    : Border.all(color: BuddyColors.smoke.withValues(alpha: 0.25), width: 1),
                                boxShadow: isSelected
                                    ? const [
                                        BoxShadow(
                                          color: BuddyColors.pitch,
                                          offset: Offset(0, 2),
                                          blurRadius: 0,
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: BuddyTheme.displayFont(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? BuddyColors.onLime : BuddyColors.carbon,
                                    ),
                                  ),
                                  if (count > 0)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.only(top: 2),
                                      decoration: BoxDecoration(
                                        color: isSelected ? BuddyColors.onLime : BuddyColors.coral,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // Segmented Filter Tabs: To-Do vs Completed
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showCompletedOnly = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_showCompletedOnly ? BuddyColors.carbon : BuddyColors.bone,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BuddyColors.pitch, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '📌 To-Do (${activeTasks.length})',
                          style: BuddyTheme.captionMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: !_showCompletedOnly ? Colors.white : BuddyColors.carbon,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showCompletedOnly = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _showCompletedOnly ? BuddyColors.carbon : BuddyColors.bone,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BuddyColors.pitch, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '✅ Done (${completedTasks.length})',
                          style: BuddyTheme.captionMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _showCompletedOnly ? Colors.white : BuddyColors.carbon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Task List Content
              if (displayTasks.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          _showCompletedOnly ? '🎯' : '🌱',
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showCompletedOnly
                              ? 'No completed tasks yet. Finish a task to see it here!'
                              : (_showAllWeek
                                  ? 'No tasks scheduled this week! Tap + ADD or tell Buddy.'
                                  : 'Nothing scheduled for ${dayLabels[_selectedDay.clamp(0, 6)]}! Tap + ADD or switch to ALL WEEK.'),
                          textAlign: TextAlign.center,
                          style: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...displayTasks.map((task) => _RealTaskItem(
                      task: task,
                      onToggle: () async {
                        final newStatus = !task.isCompleted;
                        await _firebase.toggleTask(task.id, newStatus);
                        if (newStatus) {
                          try {
                            await _esp32.setOledText('DONE: ${task.title}').timeout(const Duration(seconds: 2));
                          } catch (_) {}
                          _showFeedbackSnackBar(
                            '🎉 Marked "${task.title}" as complete!',
                            actionLabel: 'UNDO',
                            onAction: () => _firebase.toggleTask(task.id, false),
                          );
                        } else {
                          _showFeedbackSnackBar('Restored "${task.title}" to active tasks');
                        }
                      },
                      onDelete: () async {
                        await _firebase.deleteTask(task.id);
                        _showFeedbackSnackBar('🗑️ Deleted "${task.title}"');
                      },
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFocusTimer() {
    return BuddyCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _timerDisplay,
                  style: BuddyTheme.displayFont(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: BuddyColors.carbon,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _timerRunning ? BuddyColors.lime : BuddyColors.bone,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: BuddyColors.pitch, width: 1.5),
                  ),
                  child: Text(
                    _timerRunning ? 'FOCUS SPRINT ACTIVE' : 'TIMER PAUSED',
                    style: BuddyTheme.captionMono(
                      fontSize: 10,
                      color: _timerRunning ? BuddyColors.onLime : BuddyColors.carbon,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: _togglePomodoro,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BuddyDecorations.pill(fill: _timerRunning ? Colors.white : BuddyColors.lime),
                  child: Text(
                    _timerRunning ? '⏸ Pause' : '▶ Start',
                    style: BuddyTheme.bodyFont(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _timerRunning ? BuddyColors.carbon : BuddyColors.onLime,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  setState(() => _timerSeconds += 5 * 60);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BuddyDecorations.pill(fill: Colors.white),
                  child: Text(
                    '+5m Break',
                    style: BuddyTheme.bodyFont(fontSize: 13, fontWeight: FontWeight.w700, color: BuddyColors.carbon),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({required this.label, required this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          decoration: BuddyDecorations.cardSmall(
            fill: isPrimary ? BuddyColors.lime : Colors.white,
            radius: 12,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: BuddyTheme.bodyFont(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isPrimary ? BuddyColors.onLime : BuddyColors.carbon,
            ),
          ),
        ),
      ),
    );
  }
}

class _RealTaskItem extends StatelessWidget {
  final BuddyTask task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RealTaskItem({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lowerTitle = task.title.toLowerCase();
    final tag = (task.alertTag ?? '').toLowerCase();

    // Determine category icon and accent
    IconData categoryIcon = Icons.task_alt_rounded;
    Color categoryBg = BuddyColors.lime.withValues(alpha: 0.35);
    Color categoryColor = BuddyColors.pitch;

    if (lowerTitle.contains('alarm') || tag.contains('alarm')) {
      categoryIcon = Icons.alarm_rounded;
      categoryBg = BuddyColors.coral.withValues(alpha: 0.18);
      categoryColor = BuddyColors.coral;
    } else if (lowerTitle.contains('call') || tag.contains('call')) {
      categoryIcon = Icons.phone_in_talk_rounded;
      categoryBg = BuddyColors.lime.withValues(alpha: 0.4);
      categoryColor = BuddyColors.pitch;
    } else if (lowerTitle.contains('meet') || lowerTitle.contains('class') || tag.contains('meeting')) {
      categoryIcon = Icons.calendar_month_rounded;
      categoryBg = Colors.amber.withValues(alpha: 0.25);
      categoryColor = Colors.brown;
    }

    // Extract formatted time string
    String timeLabel = '';
    if (task.alertTag != null && task.alertTag!.isNotEmpty) {
      final m = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM)?)', caseSensitive: false).firstMatch(task.alertTag!);
      if (m != null) timeLabel = m.group(1)!;
    }
    if (timeLabel.isEmpty && task.deadline != null) {
      final h = task.deadline!.hour % 12 == 0 ? 12 : task.deadline!.hour % 12;
      final m = task.deadline!.minute.toString().padLeft(2, '0');
      final ampm = task.deadline!.hour >= 12 ? 'PM' : 'AM';
      timeLabel = '$h:$m $ampm';
    }
    if (timeLabel.isEmpty) {
      final m = RegExp(r'(\d{1,2}(?::\d{2})?\s*(?:am|pm))', caseSensitive: false).firstMatch(task.title);
      if (m != null) timeLabel = m.group(1)!.toUpperCase();
    }

    final date = task.deadline ?? task.createdAt;
    final dateStr = '${date.day}/${date.month}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: task.isCompleted ? const Color(0xFFF7F6F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.isCompleted ? BuddyColors.smoke.withValues(alpha: 0.4) : BuddyColors.pitch,
          width: 1.5,
        ),
        boxShadow: task.isCompleted
            ? null
            : const [
                BoxShadow(
                  color: BuddyColors.pitch,
                  offset: Offset(0, 2),
                  blurRadius: 0,
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Tactile Checkbox Button
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: task.isCompleted ? BuddyColors.lime : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: BuddyColors.pitch,
                  width: 2,
                ),
              ),
              child: task.isCompleted
                  ? const Icon(Icons.check_rounded, size: 16, color: BuddyColors.onLime)
                  : Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: task.priority == TaskPriority.high ? BuddyColors.coral : BuddyColors.smoke,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Category Icon Pill
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: categoryBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(categoryIcon, size: 15, color: categoryColor),
          ),
          const SizedBox(width: 8),

          // 3. Task Title and Meta Information
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  style: BuddyTheme.bodyFont(
                    fontSize: 13,
                    fontWeight: task.isCompleted ? FontWeight.w500 : FontWeight.w700,
                    color: task.isCompleted ? BuddyColors.smoke : BuddyColors.carbon,
                  ).copyWith(
                    decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: BuddyColors.smoke,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (timeLabel.isNotEmpty) ...[
                      Text(
                        '⏰ $timeLabel',
                        style: BuddyTheme.captionMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: task.isCompleted ? BuddyColors.smoke : BuddyColors.carbon,
                        ),
                      ),
                    ],
                    Text(
                      dateStr,
                      style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.smoke),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: BuddyColors.bone,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.source == TaskSource.groq ? '🤖 AI' : (task.source == TaskSource.calendar ? '📅 CAL' : '📱 USER'),
                        style: BuddyTheme.captionMono(fontSize: 8, color: BuddyColors.smoke),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. Interactive "MARK DONE" Capsule Button
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? BuddyColors.lime
                    : (task.priority == TaskPriority.high ? BuddyColors.coral : BuddyColors.bone),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: BuddyColors.pitch, width: 1.5),
              ),
              child: Text(
                task.isCompleted ? 'DONE ✓' : 'MARK DONE',
                style: BuddyTheme.captionMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: task.isCompleted
                      ? BuddyColors.onLime
                      : (task.priority == TaskPriority.high ? Colors.white : BuddyColors.carbon),
                ),
              ),
            ),
          ),

          // 5. Delete Action
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 15, color: BuddyColors.smoke),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            splashRadius: 14,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
