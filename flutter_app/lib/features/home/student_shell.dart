import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/features/cockpit/cockpit_screen.dart';
import 'package:hello_buddy/features/soundscape/soundscape_screen.dart';
import 'package:hello_buddy/features/chat/chat_screen.dart';
import 'package:hello_buddy/features/profile/profile_screen.dart';
import 'package:hello_buddy/services/firebase_service.dart';
import 'package:hello_buddy/services/auth_service.dart';
import 'package:hello_buddy/services/alarm_service.dart';

/// Bottom navigation shell for the Student panel
class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _currentIndex = 0;
  late final _firebase = FirebaseService(AuthService());
  final _alarmService = AlarmService();
  StreamSubscription? _botActionsSub;

  final _screens = const [
    CockpitScreen(),
    SoundscapeScreen(),
    ChatScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _listenToBotActions();
  }

  @override
  void dispose() {
    _botActionsSub?.cancel();
    super.dispose();
  }

  void _listenToBotActions() {
    _botActionsSub = _firebase.watchBotActions().listen((actions) async {
      for (final action in actions) {
        if (action['executed'] == true) continue;
        final actionId = action['id'] as String? ?? '';
        final type = action['type'] as String? ?? '';
        final title = action['title'] as String? ?? 'Buddy';

        try {
          if (type == 'alarm') {
            final h = (action['hour'] as num?)?.toInt() ?? 7;
            final m = (action['minute'] as num?)?.toInt() ?? 0;
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
              _showFeedbackBanner('⏰ Buddy set your phone alarm for $timeStr ("$title")');
            }
          } else if (type == 'call') {
            final contact = action['contact'] as String? ?? title;
            await _alarmService.makePhoneCall(contact);
            if (actionId.isNotEmpty) {
              await _firebase.markBotActionExecuted(actionId);
            }
            if (mounted) {
              _showFeedbackBanner('📞 Buddy is calling "$contact" on your phone!');
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
              _showFeedbackBanner('📅 Buddy added "$title" to your phone calendar!');
            }
          }
        } catch (e) {
          debugPrint('[StudentShell] Error executing bot action: $e');
        }
      }
    });
  }

  void _showFeedbackBanner(String message) {
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
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: BuddyColors.lime, width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: BuddyColors.carbon,
          border: Border(
            top: BorderSide(color: BuddyColors.pitch, width: 2),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: 'Cockpit',
                  isActive: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Sound',
                  isActive: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.forum_rounded,
                  label: 'Chat',
                  isActive: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isActive: _currentIndex == 3,
                  onTap: () => setState(() => _currentIndex = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: BuddyColors.lime,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: BuddyColors.pitch,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: BuddyColors.onLime, size: 20),
              )
            else
              Icon(icon, color: BuddyColors.smoke, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: BuddyTheme.captionMono(
                fontSize: 10,
                color: isActive ? BuddyColors.lime : BuddyColors.smoke,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
