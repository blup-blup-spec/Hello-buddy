import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/core/widgets/buddy_widgets.dart';
import 'package:hello_buddy/features/auth/login_screen.dart';
import 'package:hello_buddy/models/task_model.dart';
import 'package:hello_buddy/services/auth_service.dart';
import 'package:hello_buddy/services/firebase_service.dart';
import 'package:hello_buddy/services/esp32_service.dart';
import 'package:hello_buddy/services/permission_service.dart';
import 'package:hello_buddy/services/alarm_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  late final _firebase = FirebaseService(_auth);
  final _esp32 = Esp32Service();
  final _permissionService = PermissionService();

  String _robotIp = '192.168.1.100';
  bool _isOnline = false;

  // Permission statuses
  bool _cameraGranted = false;
  bool _micGranted = false;
  bool _calendarGranted = false;
  bool _notificationGranted = false;
  bool _contactsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _listenToRobot();
  }

  Future<void> _checkPermissions() async {
    final camera = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    final calendar = await Permission.calendar.isGranted;
    final notif = await Permission.notification.isGranted;
    final contacts = await Permission.contacts.isGranted;

    if (mounted) {
      setState(() {
        _cameraGranted = camera;
        _micGranted = mic;
        _calendarGranted = calendar;
        _notificationGranted = notif;
        _contactsGranted = contacts;
      });
    }
  }

  void _listenToRobot() {
    _firebase.watchRobotTelemetry().listen((telemetry) {
      if (!mounted) return;
      final ip = telemetry['ip'] as String?;
      final status = telemetry['status'] as String?;
      setState(() {
        if (ip != null && ip.isNotEmpty) _robotIp = ip;
        _isOnline = status == 'ONLINE';
      });
    });
  }

  void _showEditIpDialog() {
    final ipController = TextEditingController(text: _robotIp);
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
            'CONFIG ROBOT IP',
            style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
          ),
          content: TextField(
            controller: ipController,
            decoration: InputDecoration(
              hintText: 'e.g. 192.168.1.45',
              hintStyle: BuddyTheme.bodyFont(fontSize: 13, color: BuddyColors.smoke),
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
              onPressed: () {
                final newIp = ipController.text.trim();
                if (newIp.isNotEmpty) {
                  setState(() => _robotIp = newIp);
                  _esp32.setIp(newIp);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save IP'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSignOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _testTaskPipeline() async {
    try {
      final task = BuddyTask(
        id: '',
        title: 'Test RTDB & OLED Sync',
        priority: TaskPriority.high,
        pushedToOled: true,
        source: TaskSource.manual,
        createdAt: DateTime.now(),
      );
      await _firebase.addTask(task);
      await _esp32.setOledText('Sync Test: SUCCESS');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Task added to /users/default/tasks & pushed to OLED!',
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
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pipeline error: $e'),
            backgroundColor: BuddyColors.coral,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _auth.displayName;
    final email = _auth.email;
    final initials = name.isNotEmpty
        ? (name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase())
        : 'HB';

    return Scaffold(
      backgroundColor: BuddyColors.bone,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
              child: Column(
                children: [
                  _buildUserIdentityCard(initials, name, email),
                  const SizedBox(height: 16),
                  _buildPermissionsCard(),
                  const SizedBox(height: 16),
                  _buildRobotConnectionCard(),
                  const SizedBox(height: 16),
                  _buildAiEngineCard(),
                  const SizedBox(height: 16),
                  _buildDangerZone(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: BuddyColors.lime,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BuddyColors.pitch, width: 2),
                ),
                child: const Icon(Icons.pets, color: BuddyColors.onLime, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'Buddy • Profile & System',
                style: BuddyTheme.displayFont(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: BuddyColors.bone,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserIdentityCard(String initials, String name, String email) {
    return BuddyCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: BuddyColors.carbon,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BuddyColors.pitch, width: 2),
                  boxShadow: const [BoxShadow(color: BuddyColors.pitch, offset: Offset(0, 2))],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: BuddyColors.bone,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: BuddyTheme.displayFont(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: BuddyColors.carbon,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: BuddyColors.lime,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                ),
                child: Text(
                  _auth.isSignedIn ? '🎓 Verified Member' : '⚡ Guest Session',
                  style: BuddyTheme.bodyFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: BuddyColors.onLime,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: BuddyColors.carbon,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                ),
                child: Text(
                  'ESP32-S3 Dual-Core',
                  style: BuddyTheme.captionMono(fontSize: 10, color: BuddyColors.bone),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return BuddyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'APP PERMISSIONS & WORKFLOWS',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      await _permissionService.requestAllPermissions();
                      await _checkPermissions();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: BuddyColors.lime,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: BuddyColors.pitch, width: 1.5),
                      ),
                      child: Text(
                        'GRANT ALL',
                        style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.onLime),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: openAppSettings,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: BuddyColors.bone,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: BuddyColors.pitch, width: 1.5),
                      ),
                      child: Text(
                        'OS SETTINGS',
                        style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.carbon),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.camera_alt_rounded,
            title: 'Camera Access (Diagram & Note Scanning)',
            isGranted: _cameraGranted,
            onRequest: () async {
              await _permissionService.requestCameraPermission();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.mic_rounded,
            title: 'Microphone (Voice Commands & Transcribe)',
            isGranted: _micGranted,
            onRequest: () async {
              await _permissionService.requestMicPermission();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.calendar_month_rounded,
            title: 'Calendar & Timetable (Read/Write)',
            isGranted: _calendarGranted,
            onRequest: () async {
              await _permissionService.requestCalendarPermission();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.notifications_active_rounded,
            title: 'Notifications & Push Reminders',
            isGranted: _notificationGranted,
            onRequest: () async {
              await _permissionService.requestNotificationPermission();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.alarm_rounded,
            title: 'Phone Alarm & Clock (Native Auto-Wake)',
            isGranted: true,
            onRequest: () async {
              await AlarmService().showPhoneAlarms();
            },
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.call_rounded,
            title: 'Phone Calls & Contacts (Dialer Integration)',
            isGranted: _contactsGranted,
            onRequest: () async {
              await _permissionService.requestContactsPermission();
              await _checkPermissions();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRobotConnectionCard() {
    return BuddyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ROBOT BRIDGE & HARDWARE',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              GestureDetector(
                onTap: _showEditIpDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: BuddyColors.bone,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: BuddyColors.pitch, width: 1.5),
                  ),
                  child: Text(
                    'EDIT IP',
                    style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.carbon),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'Hardware Status',
            value: _isOnline ? '● Online (Telemetry Live)' : '○ Searching...',
            valueColor: _isOnline ? BuddyColors.lime : BuddyColors.coral,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Local Robot IP',
            value: _robotIp,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Peripherals',
            value: 'SH1106 OLED • INMP441 • MAX98357A',
          ),
        ],
      ),
    );
  }

  Widget _buildAiEngineCard() {
    return BuddyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI BRAIN & CLOUD ENGINE',
                style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.carbon),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BuddyColors.lime,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: BuddyColors.pitch, width: 1.5),
                ),
                child: Text(
                  'ONLINE ●',
                  style: BuddyTheme.captionMono(fontSize: 9, color: BuddyColors.onLime),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _InfoRow(
            label: 'AI Reasoning Core',
            value: 'openai/gpt-oss-20b',
            valueColor: BuddyColors.lime,
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'Vision & Multimodal',
            value: 'qwen/qwen3.8-27b',
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'Cloud Database',
            value: 'Firebase Realtime (Active)',
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'Music Streaming',
            value: 'Audius Decentralized API',
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return BuddyCard(
      fill: const Color(0xFFFFF0EE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SESSION MANAGEMENT',
            style: BuddyTheme.captionMono(fontSize: 11, color: BuddyColors.coral),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: BuddyPillButton(
              label: 'Sign Out / Switch User',
              fill: BuddyColors.coral,
              textColor: Colors.white,
              onPressed: _handleSignOut,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isGranted;
  final VoidCallback onRequest;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.isGranted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: BuddyColors.carbon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: BuddyTheme.bodyFont(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        GestureDetector(
          onTap: isGranted ? null : onRequest,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isGranted ? BuddyColors.lime : BuddyColors.coral,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: BuddyColors.pitch, width: 1),
            ),
            child: Text(
              isGranted ? 'GRANTED ✓' : 'ALLOW +',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: isGranted ? BuddyColors.onLime : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: BuddyTheme.bodyFont(fontSize: 12, color: BuddyColors.smoke)),
        Flexible(
          child: Text(
            value,
            style: BuddyTheme.bodyFont(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? BuddyColors.carbon,
            ),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
