# Postmortem & Troubleshooting Guide: Hello Buddy Phone Actions & Stale APK Builds

> **Date:** November 2, 2026  
> **Project:** Hello Buddy (Flutter + Android Native + Firebase + Groq)  
> **Subject:** Why phone actions (Alarms, Calls, Calendar) appeared completely non-functional, why APK rebuilds showed no progress, and how to prevent it.

---

## 1. Executive Summary: What Happened?

When testing phone actions (e.g. typing `"set alarm for 7 am"` or `"test ringtone"`), the app showed a generic chat bubble:
```
✅ Scheduled ALARM: "Morning Alarm"
• Saved to Firebase RTDB (/users/default/tasks)
• Pushed to Robot OLED
```
No native phone alarms rang, the Android clock didn't open, the dialer didn't trigger, and no action modal appeared. Even after updating the code and rebuilding the APK multiple times, the device kept behaving **identically**.

### The Core Root Causes:
1. **The "Phantom Build" Bug (Stale Dart Kernel Cache):** Flutter's internal Dart compiler cache (`.dart_tool/flutter_build` and `kernel_blob.bin`) was frozen on a snapshot from **01-11-2026 07:20:30**. Every new APK built by Gradle was quietly repackaging that 18-hour-old Dart binary. The new code was never actually running on the phone.
2. **Masked Dart Syntax Errors:** Because the Dart compiler was skipped by the build cache, multiple latent syntax errors (an extra closing brace in `chat_screen.dart`, unclosed block in `phone_service.dart`, missing method in `alarm_service.dart`) were completely silent.
3. **Intent Detection Fall-through:** Phrases like `"test ringtone"` had no immediate regex interceptor, so they went to Groq LLM as general conversation instead of triggering hardware tests.
4. **Android Audio Stream Routing:** Without `AudioAttributes.USAGE_ALARM`, ringtone audio was routed to the media/notification stream and muted whenever the device was in Silent or Vibrate mode.
5. **Static Android Version Code:** `versionCode` was left at `1`, which can prevent Android Package Manager from overwriting cached code upon reinstallation.

---

## 2. Deep Dive: Technical Breakdown

### Problem A: The Stale `kernel_blob.bin` Trap
In Flutter apps, Dart code is compiled into a kernel bytecode binary (`kernel_blob.bin`) stored in:
- `hello_buddy_app/.dart_tool/flutter_build/<hash>/app.dill`
- `hello_buddy_app/build/app/intermediates/flutter/debug/flutter_assets/kernel_blob.bin`

When running raw Gradle (`gradlew assembleDebug`) instead of `flutter build apk --debug`, the build system checks `.filecache` fingerprints. If the fingerprint check fails to detect an external edit or considers `compileFlutterBuildDebug` `UP-TO-DATE`, **it does not recompile Dart**. 

**Evidence discovered during investigation:**
- APK modified timestamp: `02-11-2026 01:17:08`
- `kernel_blob.bin` timestamp inside the APK: `01-11-2026 07:20:30` (18 hours old!)

**The Fix:**
Delete stale intermediate artifacts before critical builds:
```powershell
Remove-Item -Recurse -Force hello_buddy_app\.dart_tool\flutter_build
Remove-Item -Recurse -Force hello_buddy_app\build\app\intermediates\flutter
```
And always build using the Flutter CLI:
```powershell
flutter build apk --debug
```

---

### Problem B: Silent Syntax Errors Masked by the Cache
Because the compiler was not running, syntax errors in the modified files were invisible until the cache was wiped:
1. **Extra brace in `chat_screen.dart` (line 824):**
   ```dart
       );
     }
     } // <-- This extra brace closed the _ChatScreenState class prematurely!
     
     Future<void> _pushToRobotOled(...) ... // Became orphaned top-level code!
   ```
   This broke `build(BuildContext context)`, state variables, and method channel triggers.
2. **Dangling `else {` in `phone_service.dart` (line 45):**
   Left the native method channel invocation unclosed.
3. **Missing method in `alarm_service.dart`:**
   `profile_screen.dart` called `AlarmService().showPhoneAlarms()`, but the method did not exist in the service.
4. **Invalid Color Constant:**
   `BuddyColors.butter` was referenced, but only `lime`, `bone`, `carbon`, `smoke`, and `coral` exist in `buddy_colors.dart`.

**The Fix:**
All syntax errors were corrected and validated with:
```powershell
flutter analyze lib/features/chat/chat_screen.dart lib/services/phone_service.dart lib/services/alarm_service.dart
```

---

### Problem C: Hardware Test vs. AI Chat Routing
When testing `"test ringtone"`, Groq responded politely:
> *"Sure thing! 🎶 Let's give that ringtone a quick test run. If you'd like to schedule a reminder..."*

Groq treated it as conversational text because:
- The keyword `"test ringtone"` did not contain `"alarm"` or `"call"`.
- The system prompt taught the AI to format tasks for the robot rather than execute immediate phone hardware tests.

**The Fix:**
Added **instant direct command interception** at the entry of `_sendMessage`:
```dart
final lowerQuery = query.toLowerCase();

// Immediate ringtone test (bypasses LLM delay, rings phone immediately)
if (RegExp(r'\b(?:test\s*ringtone|test\s*ring|test\s*alarm|ring\s*alarm|ringtone\s*test|play\s*ringtone)\b').hasMatch(lowerQuery)) {
  await _alarmService.testAlarm();
  // Show SnackBar with STOP button + heads-up ringing notification
  return;
}

// Immediate silence trigger
if (RegExp(r'\b(?:stop\s*alarm|stop\s*ringtone|silence|turn\s*off\s*alarm|dismiss\s*alarm)\b').hasMatch(lowerQuery)) {
  await _alarmService.stopAlarm();
  return;
}
```

---

### Problem D: Xiaomi / MIUI / HyperOS Audio Stream Mismatch
On modern Android (especially Xiaomi / HyperOS):
- Playing a Ringtone using `Ringtone.play()` defaults to the **Notification** or **Media** audio stream.
- If the device volume is muted or on vibrate, the alarm sound is completely silent.
- Standard broadcast receivers can be restricted by Xiaomi's aggressive battery optimizer if Autostart is off.

**The Fix:**
In `MainActivity.kt`:
1. Explicitly assign `AudioAttributes.USAGE_ALARM` to the ringtone player:
   ```kotlin
   if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
       ringtone?.audioAttributes = AudioAttributes.Builder()
           .setUsage(AudioAttributes.USAGE_ALARM)
           .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
           .build()
   }
   ringtone?.play()
   ```
2. Configure the notification channel with `NotificationManager.IMPORTANCE_HIGH` and `USAGE_ALARM`.
3. Set `AlarmManager.setAlarmClock(...)` which triggers Android's official alarm clock icon in the status bar and overrides Doze / App Standby.

---

### Problem E: Android Version Code Caching
`pubspec.yaml` had `version: 1.0.0+1`. When installing a new APK over an existing installation with the exact same `versionCode`:
- Android Package Manager might skip updating internal application caches or fail silently.

**The Fix:**
- Bumped to `version: 1.0.1+2` in `pubspec.yaml`
- Set `flutter.versionCode=2` and `flutter.versionName=1.0.1` in `android/local.properties`
- Advised uninstalling previous build before installing new debug APK.

---

## 3. Checklist for Next Time (How to Prevent This)

Whenever modifying phone action features or compiling APKs, follow this 5-step checklist:

| Step | Action | Command / Check |
|---|---|---|
| **1. Verify Dart Syntax** | Always run analyzer before compiling | `flutter analyze lib/...` |
| **2. Clean Build Cache** | If code changes don't appear in the APK | Delete `.dart_tool/flutter_build` and `build/app/intermediates/flutter` |
| **3. Bump Version Code** | Ensure Android recognizes the APK as new | Bump `versionCode` in `pubspec.yaml` and `local.properties` |
| **4. Build via Flutter CLI** | Never rely solely on `gradlew assembleDebug` for Dart changes | `flutter build apk --debug` |
| **5. Verify APK Bytecode** | Confirm the APK actually contains the new strings | Check `kernel_blob.bin` timestamp or search strings inside `build/.../flutter_assets/kernel_blob.bin` |

---

## 4. Current Working Artifacts

- **Latest Verified Debug APK:**  
  `hello_buddy_app\build\app\outputs\flutter-apk\app-debug.apk`
- **Build Timestamp:** `02-11-2026 01:52:16`
- **Size:** `169 MB`
- **Supported Phone Actions:**
  - `test ringtone` / `test alarm` -> Instant audio playback via alarm speaker + Heads-up notification + SnackBar with STOP button.
  - `stop alarm` / `silence` -> Kills ringtone and cancels notification.
  - `set alarm for 7 am` -> Registers `AlarmManager.setAlarmClock`, launches system Clock app, shows native Toast, opens Action Modal dialog.
  - `call mom` -> Native dialer/call launch with contact lookup.
  - `schedule meeting at 3 pm` -> Calendar contract insertion + system calendar opening.

