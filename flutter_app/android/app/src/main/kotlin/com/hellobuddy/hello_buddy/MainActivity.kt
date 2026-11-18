package com.hellobuddy.hello_buddy

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Vibrator
import android.os.VibrationEffect
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

/**
 * True In-App Alarm Engine (following leanh153/Android-Alarm architecture)
 * Plays loud alarm sound, vibrates phone, and posts heads-up ringing notification
 * with one-tap DISMISS button when scheduled time arrives.
 */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        const val CHANNEL_ID = "buddy_alarm_channel"
        const val ACTION_ALARM_TRIGGER = "com.hellobuddy.ACTION_ALARM_TRIGGER"
        const val ACTION_DISMISS = "com.hellobuddy.ACTION_DISMISS_ALARM"
        var ringtone: Ringtone? = null
        var vibrator: Vibrator? = null

        fun stopAlarm() {
            try {
                ringtone?.stop()
                ringtone = null
            } catch (_: Exception) {}
            try {
                vibrator?.cancel()
                vibrator = null
            } catch (_: Exception) {}
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "Hello Buddy Alarm"
        val hour = intent.getIntExtra("hour", 0)
        val minutes = intent.getIntExtra("minutes", 0)
        val timeStr = String.format("%02d:%02d", hour, minutes)

        if (intent.action == ACTION_DISMISS) {
            stopAlarm()
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(1001)
            Log.d("HelloBuddy", "Alarm dismissed by user")
            return
        }

        Log.d("HelloBuddy", "AlarmReceiver ringing alarm: $title at $timeStr")

        // 1. Play Alarm Ringtone (loud alarm audio stream)
        try {
            var alarmUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (alarmUri == null) alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (alarmUri == null) alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ringtone = RingtoneManager.getRingtone(context.applicationContext, alarmUri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }
            ringtone?.play()
        } catch (e: Exception) {
            Log.e("HelloBuddy", "Ringtone error: ${e.message}")
        }

        // 2. Vibrate phone
        try {
            vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 400, 800, 400, 1000), 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(longArrayOf(0, 800, 400, 800, 400, 1000), 0)
            }
        } catch (e: Exception) {
            Log.e("HelloBuddy", "Vibrator error: ${e.message}")
        }

        // 3. Heads-Up Ringing Notification with DISMISS button
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Hello Buddy Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarm ringing alerts for Hello Buddy"
                enableVibration(true)
                enableLights(true)
            }
            nm.createNotificationChannel(channel)
        }

        val dismissIntent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_DISMISS
        }
        val dismissPending = PendingIntent.getBroadcast(
            context,
            1002,
            dismissIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val appIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val appPending = PendingIntent.getActivity(
            context,
            1003,
            appIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("⏰ $title ($timeStr)")
            .setContentText("Wake up! Your Hello Buddy alarm is ringing.")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(appPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "DISMISS ALARM", dismissPending)
            .setOngoing(true)
            .build()

        nm.notify(1001, notification)
    }
}

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "HelloBuddy"
    }

    private val PERM_CHANNEL = "com.hellobuddy/permissions"
    private val CAL_CHANNEL = "com.hellobuddy/calendar"
    private val NOTIF_CHANNEL = "com.hellobuddy/notifications"
    private val VOICE_CHANNEL = "com.hellobuddy/voice"
    private val ALARM_CHANNEL = "com.hellobuddy/alarm"
    private val PHONE_CHANNEL = "com.hellobuddy/phone"

    private val REQUEST_CALENDAR = 1001
    private val REQUEST_MIC = 1002
    private val REQUEST_NOTIF = 1003

    private var pendingResult: MethodChannel.Result? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val audioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            var soundUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (soundUri == null) soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val channel = NotificationChannel(
                AlarmReceiver.CHANNEL_ID,
                "Hello Buddy Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alarm alerts for Hello Buddy"
                enableVibration(true)
                enableLights(true)
                setSound(soundUri, audioAttr)
            }
            nm.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        // ── Permission Channel ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCalendar" -> {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR)
                            == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            pendingResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.READ_CALENDAR),
                                REQUEST_CALENDAR
                            )
                        }
                    }
                    "requestMicrophone" -> {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                            == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            pendingResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.RECORD_AUDIO),
                                REQUEST_MIC
                            )
                        }
                    }
                    "requestNotification" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                                == PackageManager.PERMISSION_GRANTED) {
                                result.success(true)
                            } else {
                                pendingResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQUEST_NOTIF
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    "isNotificationListenerEnabled" -> {
                        val enabled = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners"
                        )
                        result.success(enabled?.contains(packageName) == true)
                    }
                    "openNotificationListenerSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Calendar Channel ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTodayEvents" -> {
                        try {
                            val events = readCalendarEvents(0)
                            result.success(events)
                        } catch (e: Exception) {
                            Log.e(TAG, "getTodayEvents error: ${e.message}")
                            result.error("CALENDAR_ERROR", e.message, null)
                        }
                    }
                    "getUpcomingEvents" -> {
                        val days = call.argument<Int>("days") ?: 3
                        try {
                            val events = readCalendarEvents(days)
                            result.success(events)
                        } catch (e: Exception) {
                            Log.e(TAG, "getUpcomingEvents error: ${e.message}")
                            result.error("CALENDAR_ERROR", e.message, null)
                        }
                    }
                    "insertCalendarEvent" -> {
                        Log.d(TAG, "insertCalendarEvent called with args: title=${call.argument<String>("title")}, start=${call.argument<Any>("start")}, end=${call.argument<Any>("end")}")
                        val title = call.argument<String>("title") ?: "Buddy Meeting"
                        // FIX: Use Number instead of Long — Dart int comes as Integer on Android
                        val startMs = (call.argument<Number>("start"))?.toLong() ?: System.currentTimeMillis()
                        val endMs = (call.argument<Number>("end"))?.toLong() ?: (startMs + 3600000L)
                        val description = call.argument<String>("description") ?: ""
                        val location = call.argument<String>("location") ?: ""

                        Log.d(TAG, "Calendar event: title=$title, startMs=$startMs, endMs=$endMs")

                        var directInsertSuccess = false
                        // 1. Direct ContentResolver Database Write (Permanent into Phone Calendar)
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR)
                            == PackageManager.PERMISSION_GRANTED) {
                            try {
                                var calId: Long = 1
                                val calCursor = contentResolver.query(
                                    CalendarContract.Calendars.CONTENT_URI,
                                    arrayOf(CalendarContract.Calendars._ID),
                                    null, null, null
                                )
                                calCursor?.use {
                                    if (it.moveToFirst()) {
                                        calId = it.getLong(0)
                                    }
                                }

                                val values = ContentValues().apply {
                                    put(CalendarContract.Events.DTSTART, startMs)
                                    put(CalendarContract.Events.DTEND, endMs)
                                    put(CalendarContract.Events.TITLE, title)
                                    put(CalendarContract.Events.DESCRIPTION, description)
                                    put(CalendarContract.Events.EVENT_LOCATION, location)
                                    put(CalendarContract.Events.CALENDAR_ID, calId)
                                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                                }
                                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                                if (uri != null) {
                                    directInsertSuccess = true
                                    Log.d(TAG, "Calendar event inserted directly: $uri")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Direct calendar insert failed: ${e.message}")
                            }
                        } else {
                            Log.w(TAG, "WRITE_CALENDAR permission not granted")
                        }

                        // 2. Also trigger System Calendar Intent so it displays on screen
                        try {
                            val intent = Intent(Intent.ACTION_INSERT).apply {
                                data = CalendarContract.Events.CONTENT_URI
                                putExtra(CalendarContract.Events.TITLE, title)
                                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
                                putExtra(CalendarContract.Events.DESCRIPTION, description)
                                putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            runOnUiThread {
                                Toast.makeText(applicationContext, "📅 Meeting '$title' added to Calendar!", Toast.LENGTH_LONG).show()
                            }
                            Log.d(TAG, "Calendar intent launched")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Calendar intent failed: ${e.message}")
                            if (directInsertSuccess) {
                                result.success(true)
                            } else {
                                result.error("CALENDAR_ERROR", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Alarm Channel (Native Android Clock System) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlarm" -> {
                        val title = call.argument<String>("title") ?: "Buddy Alarm"
                        val hour = call.argument<Int>("hour") ?: 8
                        val minutes = call.argument<Int>("minutes") ?: 0
                        val skipUi = call.argument<Boolean>("skipUi") ?: false

                        Log.d(TAG, "setAlarm called: title=$title, hour=$hour, min=$minutes, skipUi=$skipUi")

                        var alarmRegistered = false
                        val cal = Calendar.getInstance().apply {
                            set(Calendar.HOUR_OF_DAY, hour)
                            set(Calendar.MINUTE, minutes)
                            set(Calendar.SECOND, 0)
                            set(Calendar.MILLISECOND, 0)
                            if (before(Calendar.getInstance())) {
                                add(Calendar.DAY_OF_YEAR, 1)
                            }
                        }

                        // 1. True In-App Alarm Engine (AlarmManager -> AlarmReceiver Broadcast)
                        try {
                            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                            if (alarmManager != null) {
                                val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
                                    action = AlarmReceiver.ACTION_ALARM_TRIGGER
                                    putExtra("title", title)
                                    putExtra("hour", hour)
                                    putExtra("minutes", minutes)
                                }
                                val broadcastPi = PendingIntent.getBroadcast(
                                    this,
                                    hour * 100 + minutes,
                                    alarmIntent,
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
                                )

                                val showIntent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(AlarmClock.ACTION_SHOW_ALARMS)
                                val showPi = PendingIntent.getActivity(
                                    this,
                                    hour * 100 + minutes,
                                    showIntent,
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
                                )

                                val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    alarmManager.canScheduleExactAlarms()
                                } else {
                                    true
                                }

                                if (canExact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                    alarmManager.setAlarmClock(
                                        AlarmManager.AlarmClockInfo(cal.timeInMillis, showPi),
                                        broadcastPi
                                    )
                                } else if (canExact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    alarmManager.setExactAndAllowWhileIdle(
                                        AlarmManager.RTC_WAKEUP,
                                        cal.timeInMillis,
                                        broadcastPi
                                    )
                                } else {
                                    alarmManager.set(
                                        AlarmManager.RTC_WAKEUP,
                                        cal.timeInMillis,
                                        broadcastPi
                                    )
                                }
                                alarmRegistered = true
                                Log.d(TAG, "AlarmManager setAlarm successfully registered for ${cal.time} (canExact=$canExact)")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "AlarmManager setAlarmClock failed: ${e.message}")
                        }

                        // 2. Also configure System Clock App via Intent / OEM packages
                        var systemClockOpened = false
                        try {
                            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(AlarmClock.EXTRA_MESSAGE, title)
                                putExtra(AlarmClock.EXTRA_HOUR, hour)
                                putExtra(AlarmClock.EXTRA_MINUTES, minutes)
                                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            systemClockOpened = true
                            Log.d(TAG, "ACTION_SET_ALARM intent launched")
                        } catch (e: Exception) {
                            val clockPackages = arrayOf(
                                "com.google.android.deskclock",
                                "com.sec.android.app.clockpackage",
                                "com.miui.deskclock",
                                "com.coloros.alarm",
                                "com.oneplus.deskclock",
                                "com.heytap.alarm",
                                "com.android.deskclock"
                            )
                            for (pkg in clockPackages) {
                                val launchIntent = packageManager.getLaunchIntentForPackage(pkg)
                                if (launchIntent != null) {
                                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    try {
                                        startActivity(launchIntent)
                                        systemClockOpened = true
                                        Log.d(TAG, "Opened Clock package: $pkg")
                                        break
                                    } catch (_: Exception) {}
                                }
                            }
                        }

                        val timeFormatted = String.format("%02d:%02d", hour, minutes)

                        // 3. Instant Native UI Feedback on Phone (Toast + Notification Tray)
                        runOnUiThread {
                            Toast.makeText(applicationContext, "⏰ Alarm Armed for $timeFormatted!", Toast.LENGTH_LONG).show()
                        }
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val notifIntent = Intent(this, AlarmReceiver::class.java).apply {
                                action = AlarmReceiver.ACTION_ALARM_TRIGGER
                                putExtra("title", title)
                                putExtra("hour", hour)
                                putExtra("minutes", minutes)
                            }
                            val testPi = PendingIntent.getBroadcast(
                                this,
                                9999,
                                notifIntent,
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
                            )
                            val notif = NotificationCompat.Builder(this, AlarmReceiver.CHANNEL_ID)
                                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                                .setContentTitle("⏰ Alarm Armed: $timeFormatted")
                                .setContentText("$title — Android AlarmManager Active")
                                .setPriority(NotificationCompat.PRIORITY_HIGH)
                                .setAutoCancel(true)
                                .addAction(android.R.drawable.ic_media_play, "TEST RING NOW", testPi)
                                .build()
                            nm.notify(1005, notif)
                        } catch (ne: Exception) {
                            Log.e(TAG, "Notification post error: ${ne.message}")
                        }

                        result.success(mapOf(
                            "success" to true,
                            "message" to "Alarm armed for $timeFormatted (Ringtone & AlarmManager Active)",
                            "registered" to alarmRegistered,
                            "clockOpened" to systemClockOpened
                        ))
                    }
                    "testAlarm" -> {
                        val alarmIntent = Intent(this, AlarmReceiver::class.java).apply {
                            action = AlarmReceiver.ACTION_ALARM_TRIGGER
                            putExtra("title", "Test Alarm Ringtone")
                            putExtra("hour", Calendar.getInstance().get(Calendar.HOUR_OF_DAY))
                            putExtra("minutes", Calendar.getInstance().get(Calendar.MINUTE))
                        }
                        sendBroadcast(alarmIntent)
                        runOnUiThread {
                            Toast.makeText(applicationContext, "🔔 Playing Alarm Ringtone Now...", Toast.LENGTH_SHORT).show()
                        }
                        result.success(true)
                    }
                    "stopAlarm" -> {
                        AlarmReceiver.stopAlarm()
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(1001)
                        nm.cancel(1005)
                        runOnUiThread {
                            Toast.makeText(applicationContext, "⏹️ Alarm Silenced", Toast.LENGTH_SHORT).show()
                        }
                        result.success(true)
                    }
                    "setTimer" -> {
                        val length = call.argument<Int>("length") ?: 1500
                        val message = call.argument<String>("message") ?: "Buddy Timer"
                        val skipUi = call.argument<Boolean>("skipUi") ?: false
                        try {
                            val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                                putExtra(AlarmClock.EXTRA_LENGTH, length)
                                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("TIMER_ERROR", e.message, null)
                        }
                    }
                    "showAlarms" -> {
                        try {
                            val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ALARM_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Notification Channel (stub) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRecentNotifications" -> {
                        result.success(emptyList<Map<String, Any>>())
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Phone / Call Channel (Native Android Telephony) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dial" -> {
                        val number = call.argument<String>("number") ?: ""
                        Log.d(TAG, "dial called: number=$number")
                        try {
                            val intent = Intent(Intent.ACTION_DIAL).apply {
                                data = Uri.parse("tel:${Uri.encode(number)}")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Dial error: ${e.message}")
                            result.error("DIAL_ERROR", e.message, null)
                        }
                    }
                    "callContact" -> {
                        val name = call.argument<String>("name") ?: ""
                        Log.d(TAG, "callContact called: name=$name")
                        try {
                            var foundNumber: String? = null
                            var foundName: String = name

                            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS)
                                == PackageManager.PERMISSION_GRANTED) {
                                try {
                                    val searchTerms = when (name.lowercase().trim()) {
                                        "ma", "mom", "mother", "mummy", "maa" -> arrayOf("%mom%", "%ma%", "%mother%", "%mummy%", "%maa%")
                                        "dad", "father", "papa", "pop" -> arrayOf("%dad%", "%father%", "%papa%")
                                        else -> arrayOf("%$name%", "$name%")
                                    }

                                    for (term in searchTerms) {
                                        val cursor: Cursor? = contentResolver.query(
                                            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                                            arrayOf(
                                                ContactsContract.CommonDataKinds.Phone.NUMBER,
                                                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                                            ),
                                            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                                            arrayOf(term),
                                            null
                                        )
                                        cursor?.use {
                                            if (it.moveToFirst()) {
                                                foundNumber = it.getString(0)
                                                foundName = it.getString(1)
                                                Log.d(TAG, "Contact found: $foundName -> $foundNumber")
                                            }
                                        }
                                        if (foundNumber != null) break
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Contact search error: ${e.message}")
                                }
                            } else {
                                Log.w(TAG, "READ_CONTACTS permission not granted")
                            }

                            val targetNumber = if (!foundNumber.isNullOrEmpty()) {
                                foundNumber
                            } else if (name.matches(Regex(".*\\d{5,}.*"))) {
                                name.replace(Regex("[^0-9\\+]"), "")
                            } else {
                                null
                            }

                            if (targetNumber != null && ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
                                == PackageManager.PERMISSION_GRANTED) {
                                val callIntent = Intent(Intent.ACTION_CALL).apply {
                                    data = Uri.parse("tel:${Uri.encode(targetNumber)}")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(callIntent)
                                Log.d(TAG, "ACTION_CALL launched for $targetNumber")
                            } else {
                                val dialIntent = Intent(Intent.ACTION_DIAL).apply {
                                    data = if (targetNumber != null) Uri.parse("tel:${Uri.encode(targetNumber)}") else Uri.parse("tel:")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(dialIntent)
                                Log.d(TAG, "ACTION_DIAL launched (fallback) for $targetNumber")
                            }

                            runOnUiThread {
                                val callLabel = if (targetNumber != null) "Calling $foundName ($targetNumber)..." else "Opening Dialer for $name..."
                                Toast.makeText(applicationContext, "📞 $callLabel", Toast.LENGTH_LONG).show()
                            }

                            result.success(mapOf(
                                "success" to true,
                                "foundNumber" to (targetNumber ?: ""),
                                "name" to foundName
                            ))
                        } catch (e: Exception) {
                            Log.e(TAG, "callContact error: ${e.message}")
                            result.error("CALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Voice Channel (stub) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> result.success(null)
                    "stopListening" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingResult?.success(granted)
        pendingResult = null
    }

    // ── Calendar Reader ──
    private fun readCalendarEvents(daysAhead: Int): List<Map<String, Any?>> {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR)
            != PackageManager.PERMISSION_GRANTED) {
            return emptyList()
        }

        val events = mutableListOf<Map<String, Any?>>()

        val now = Calendar.getInstance()
        val startMs = now.timeInMillis

        val end = Calendar.getInstance()
        if (daysAhead == 0) {
            end.set(Calendar.HOUR_OF_DAY, 23)
            end.set(Calendar.MINUTE, 59)
            end.set(Calendar.SECOND, 59)
        } else {
            end.add(Calendar.DAY_OF_YEAR, daysAhead)
        }
        val endMs = end.timeInMillis

        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DESCRIPTION
        )

        val selection = "${CalendarContract.Events.DTSTART} >= ? AND " +
                "${CalendarContract.Events.DTSTART} <= ?"
        val selectionArgs = arrayOf(startMs.toString(), endMs.toString())
        val sortOrder = "${CalendarContract.Events.DTSTART} ASC"

        val cursor: Cursor? = contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )

        cursor?.use {
            while (it.moveToNext()) {
                events.add(
                    mapOf(
                        "id" to it.getLong(0).toString(),
                        "title" to it.getString(1),
                        "start" to it.getLong(2),
                        "end" to (it.getLong(3).takeIf { v -> v > 0 } ?: it.getLong(2) + 3600000),
                        "location" to it.getString(4),
                        "description" to it.getString(5)
                    )
                )
            }
        }

        return events
    }
}
