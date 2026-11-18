import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime permission manager using permission_handler package.
/// Requests camera, microphone, calendar, notifications at onboarding.
class PermissionService {
  /// Request a single permission, return true if granted
  Future<bool> requestPermission(Permission perm) async {
    final status = await perm.request();
    return status.isGranted;
  }

  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    return requestPermission(Permission.camera);
  }

  /// Request microphone permission
  Future<bool> requestMicPermission() async {
    return requestPermission(Permission.microphone);
  }

  /// Request calendar read+write permission
  Future<bool> requestCalendarPermission() async {
    final status = await Permission.calendar.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return status.isGranted;
  }

  /// Request notification permission (Android 13+)
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return status.isGranted;
  }

  /// Request contacts permission
  Future<bool> requestContactsPermission() async {
    final status = await Permission.contacts.request();
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return status.isGranted;
  }

  /// Request all permissions needed at onboarding
  Future<Map<String, bool>> requestAllPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.calendar,
      Permission.contacts,
      Permission.notification,
    ].request();

    return {
      'camera': statuses[Permission.camera]?.isGranted ?? false,
      'microphone': statuses[Permission.microphone]?.isGranted ?? false,
      'calendar': statuses[Permission.calendar]?.isGranted ?? false,
      'contacts': statuses[Permission.contacts]?.isGranted ?? false,
      'notification': statuses[Permission.notification]?.isGranted ?? false,
    };
  }

  /// Show a dialog explaining why permissions are needed, then request them
  static Future<void> showPermissionOnboarding(BuildContext context) async {
    final service = PermissionService();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Buddy Needs Access'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To work fully, Buddy needs:'),
            SizedBox(height: 12),
            _PermRow(icon: Icons.camera_alt, text: 'Camera — scan diagrams & notes'),
            SizedBox(height: 8),
            _PermRow(icon: Icons.mic, text: 'Microphone — voice commands'),
            SizedBox(height: 8),
            _PermRow(icon: Icons.calendar_today, text: 'Calendar — read your schedule'),
            SizedBox(height: 8),
            _PermRow(icon: Icons.notifications, text: 'Notifications — study reminders'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await service.requestAllPermissions();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
