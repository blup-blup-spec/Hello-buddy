import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result from a phone dial / call execution
class PhoneActionResult {
  final bool success;
  final String contactName;
  final String? phoneNumber;
  final String message;
  final String? error;

  const PhoneActionResult({
    required this.success,
    required this.contactName,
    this.phoneNumber,
    required this.message,
    this.error,
  });
}

/// Service to handle native Android phone calling and contact resolution
class PhoneService {
  static const _channel = MethodChannel('com.hellobuddy/phone');

  /// Call or dial a contact by name or number
  Future<PhoneActionResult> callContact(String nameOrNumber) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const PhoneActionResult(
        success: false,
        contactName: '',
        message: 'Non-Android platform',
      );
    }

    final trimmed = nameOrNumber.trim();
    String? resolvedNumber;
    String resolvedName = trimmed;

    // 1. If it's already a phone number (contains 5+ consecutive digits)
    if (RegExp(r'\d{5,}').hasMatch(trimmed)) {
      resolvedNumber = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
      resolvedName = resolvedNumber;
    }

    // 2. Query Android ContactsContract & Launch Call/Dialer via MethodChannel
    bool launchedViaChannel = false;
    try {
      debugPrint('[PhoneService] Invoking native callContact for: $trimmed');
      final res = await _channel.invokeMethod('callContact', {
        'name': trimmed,
      });

      if (res is Map) {
        final resMap = Map<String, dynamic>.from(res);
        final num = resMap['foundNumber'] as String?;
        final name = resMap['name'] as String?;
        final msg = resMap['message'] as String?;
        if (num != null && num.isNotEmpty) resolvedNumber = num;
        if (name != null && name.isNotEmpty) resolvedName = name;
        launchedViaChannel = resMap['success'] == true;
        if (launchedViaChannel) {
          return PhoneActionResult(
            success: true,
            contactName: resolvedName,
            phoneNumber: resolvedNumber,
            message: msg ?? (resolvedNumber != null ? 'Calling $resolvedName ($resolvedNumber)' : 'Opened Dialer for $resolvedName'),
          );
        }
      }
    } catch (e) {
      debugPrint('[PhoneService] Native callContact error: $e');
    }

    // 3. Fallback: Launch dialer with url_launcher if channel didn't launch
    if (!launchedViaChannel) {
      try {
        final telUri = (resolvedNumber != null && resolvedNumber.isNotEmpty)
            ? Uri.parse('tel:${Uri.encodeComponent(resolvedNumber)}')
            : Uri.parse('tel:');

        debugPrint('[PhoneService] Launching fallback tel URI: $telUri');
        final launched = await launchUrl(
          telUri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          return PhoneActionResult(
            success: true,
            contactName: resolvedName,
            phoneNumber: resolvedNumber,
            message: resolvedNumber != null
                ? 'Dialer opened for "$resolvedName" ($resolvedNumber)'
                : 'Opened Dialer for $resolvedName',
          );
        }
      } catch (e) {
        debugPrint('[PhoneService] Fallback dialer launch failed: $e');
      }
    }

    return PhoneActionResult(
      success: true,
      contactName: resolvedName,
      phoneNumber: resolvedNumber,
      message: 'Dialer initiated for $resolvedName',
    );
  }
}
