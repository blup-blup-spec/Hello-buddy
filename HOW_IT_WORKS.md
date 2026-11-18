# How Hello Buddy Works — Full Technical Deep-Dive

> **Hello Buddy** is an ESP32-S3 desktop companion robot. It hears your voice, thinks using an AI, speaks back, shows what it heard and what it replied on its OLED face, and can dispatch real phone actions (alarms, calls) to your Android phone via Firebase. This document explains every pipeline in detail.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Hardware & Why Each Part Was Chosen](#2-hardware--why-each-part-was-chosen)
3. [Microphone → Audio Capture (I2S RX)](#3-microphone--audio-capture-i2s-rx)
4. [Speech-to-Text: Groq Whisper STT](#4-speech-to-text-groq-whisper-stt)
5. [STT Fallback: Wit.ai](#5-stt-fallback-witai)
6. [LLM Brain: Groq Chat API](#6-llm-brain-groq-chat-api)
7. [Text-to-Speech: Groq Orpheus TTS (Primary)](#7-text-to-speech-groq-orpheus-tts-primary)
8. [TTS Fallback: VoiceRSS WAV](#8-tts-fallback-voicerss-wav)
9. [Audio Playback: I2S TX → MAX98357A Speaker](#9-audio-playback-i2s-tx--max98357a-speaker)
10. [OLED Face Display](#10-oled-face-display)
11. [Touch Sensor: Listening Trigger & Double-Tap Interrupt](#11-touch-sensor-listening-trigger--double-tap-interrupt)
12. [Direct Action Dispatch (Alarm, Call)](#12-direct-action-dispatch-alarm-call)
13. [Firebase Bridge: Robot → Android Phone](#13-firebase-bridge-robot--android-phone)
14. [Flutter App: Receiving & Executing Actions](#14-flutter-app-receiving--executing-actions)
15. [Noise Gate & Audio Quality](#15-noise-gate--audio-quality)
16. [Complete Voice Interaction Flow (Step by Step)](#16-complete-voice-interaction-flow-step-by-step)
17. [Power & Stability Design](#17-power--stability-design)

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HELLO BUDDY ROBOT                            │
│                                                                     │
│  [TTP223 Touch] ──→ handleTouch() ──→ doVoice()                    │
│                                           │                         │
│  [INMP441 Mic] ──I2S RX──→ recordAudio() │                         │
│                                           ▼                         │
│                               Groq Whisper STT ──→ heard (text)    │
│                                           │                         │
│                               [Direct Parsers]                      │
│                               alarm / call / weather                │
│                                    OR                               │
│                               [Groq LLM] ──→ reply (text)          │
│                                           │                         │
│                        setLabel("Q: ...") + setLabel("A: ...")      │
│                                           │                         │
│                               Groq Orpheus TTS ──→ WAV bytes       │
│                               (fallback: VoiceRSS)                  │
│                                           │                         │
│  [MAX98357A Speaker] ←─I2S TX─── playWavFromPsram()                │
│                                                                     │
│  [SH1106 OLED] ←── updateFace() ←── setLabel() ─── drawEye()      │
│                                                                     │
│  [Firebase RTDB] ←── fbPush() ──→ [Flutter App on Phone]           │
│                                        │                            │
│                                   AlarmManager / PhoneCall          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Hardware & Why Each Part Was Chosen

| Component | Part | Reason |
|-----------|------|--------|
| **MCU** | ESP32-S3 N16R8 | Dual-core Xtensa LX7, 16 MB Flash, **8 MB OPI PSRAM** (critical for TTS audio buffer), native USB, WiFi+BT |
| **OLED** | SH1106 128×64 7-pin SPI | 128×64 pixels, low power, software SPI (bit-banged) allows flexible GPIO assignment |
| **Mic** | INMP441 (I2S) | I2S digital output = zero analog noise, clean 16-bit PCM at 16 kHz |
| **Speaker** | MAX98357A I2S DAC+Amp | Mono I2S → 3W Class D amp in one chip, no external amp needed |
| **Touch** | TTP223 capacitive | Simple HIGH/LOW GPIO, works through plastic/wood case, no moving parts |

---

## 3. Microphone → Audio Capture (I2S RX)

### How I2S Works Here

The INMP441 is a **MEMS I2S microphone**. It continuously outputs a 24-bit PCM stream. The ESP32-S3's I2S peripheral reads this stream using three wires:
- **SCK (GPIO 42)** — Bit clock
- **WS (GPIO 41)** — Word select (left/right channel toggle, we use left = mono)
- **SD (GPIO 40)** — Serial data

### What `recordAudio()` Does

```
I2S RX ──→ 32-bit raw samples ──→ right-shift to 16-bit ──→ micBuf (PSRAM)
```

1. Opens an I2S RX channel configured for 16 kHz, 16-bit mono
2. Reads 3 seconds × 16,000 samples/sec × 2 bytes = **96,000 bytes of raw PCM**
3. Applies a **180–3400 Hz bandpass filter** (removes sub-bass rumble and high-frequency hiss)
4. Writes a **44-byte WAV header** at the front of `micBuf` so the buffer is a valid `.wav` file
5. Closes the I2S channel

### Why PSRAM?
The mic buffer alone is 96 KB + 44 bytes header. The TTS buffer (Groq WAV response) can be up to **1 MB**. The ESP32-S3's internal RAM is only ~512 KB total — both buffers live in OPI PSRAM allocated once at boot with `ps_malloc()`.

---

## 4. Speech-to-Text: Groq Whisper STT

### Why Groq?
Groq's LPU (Language Processing Unit) runs **Whisper-large-v3-turbo** with ~300 ms latency for a 3-second clip. Cloud GPU services take 2–5 seconds. For a conversational robot, 300 ms feels instant.

### What Happens (HTTP Multipart Upload)

The ESP32 manually builds a **multipart/form-data HTTP POST** to `api.groq.com/openai/v1/audio/transcriptions` over TLS (WiFiClientSecure, certificate validation skipped for embedded use):

```
POST /openai/v1/audio/transcriptions HTTP/1.1
Host: api.groq.com
Authorization: Bearer YOUR_GROQ_API_KEY
Content-Type: multipart/form-data; boundary=----ESP32BuddyBoundary982341
Content-Length: <total>

------ESP32BuddyBoundary982341
Content-Disposition: form-data; name="model"

whisper-large-v3-turbo
------ESP32BuddyBoundary982341
Content-Disposition: form-data; name="file"; filename="speech.wav"
Content-Type: audio/wav

<raw WAV bytes from PSRAM>
------ESP32BuddyBoundary982341--
```

> **Why manually build multipart?**  
> Arduino's `HTTPClient` doesn't support binary multipart natively. The firmware manually writes the boundary headers, then streams the WAV bytes directly from PSRAM over the TLS socket in chunks. No intermediate String copy — PSRAM → socket directly.

### Response

Groq returns JSON:
```json
{ "text": "set an alarm for seven am" }
```

The firmware reads and parses this, extracts `text`, and that becomes `heard`.

---

## 5. STT Fallback: Wit.ai

If Groq STT fails (network timeout, rate limit), the firmware retries with **Wit.ai** (`api.wit.ai/speech`), which accepts raw audio over HTTPS. Wit.ai is free tier and slightly slower (~800 ms) but independent of Groq. It returns a different JSON format parsed by `extractWitText()`.

---

## 6. LLM Brain: Groq Chat API

### When Is the LLM Called?

**NOT** for alarms or calls — those are handled by direct keyword parsers (see §12). The LLM handles:
- General conversation ("tell me a joke", "what is photosynthesis")
- Calendar events ("add meeting at 3pm tomorrow")
- Task creation ("remind me to study")
- Pomodoro timer ("start a 25-minute focus session")

### Models Used (In Order)
1. **`qwen/qwen3.8-27b`** — primary (fast, reasoning model)
2. **`openai/gpt-oss-20b`** — fallback if primary fails

### System Prompt Strategy

The LLM is told to reply in one of two formats:
- **Plain text** for conversation
- **JSON object** for actions:

```
Alarm:    {"action":"alarm","title":"...","hour":H,"minute":M,"reply":"..."}
Call:     {"action":"call","contact":"...","reply":"..."}
Calendar: {"action":"calendar","title":"...","time":"...","reply":"..."}
Task:     {"action":"task","title":"...","reply":"..."}
Pomodoro: {"action":"pomodoro","minutes":M,"reply":"..."}
```

The firmware scans the LLM reply for `{...}`, attempts JSON parse, and if it finds a valid action, dispatches it. The `reply` field inside the JSON is what gets spoken aloud.

> **Why not rely on LLM for alarms?**  
> LLMs sometimes return plain text ("Okay, alarm set!") instead of JSON, especially under system prompt injection failures. The direct keyword parser guarantees 100% reliability for alarms and calls.

---

## 7. Text-to-Speech: Groq Orpheus TTS (Primary)

This is the most impressive part. Groq hosts **Canopy Labs Orpheus v1** — a neural TTS model that produces **human-quality speech** with natural prosody, breathing, and emotion. 

### API Call

```
POST https://api.groq.com/openai/v1/audio/speech
Authorization: Bearer YOUR_GROQ_API_KEY
Content-Type: application/json

{
  "model": "canopylabs/orpheus-v1-english",
  "input": "Alarm set for 7 AM!",
  "voice": "troy",
  "response_format": "wav"
}
```

**Voice options** available from Orpheus: `tara`, `leah`, `jess`, `leo`, `dan`, `mia`, `zac`, `zoe`, `troy`  
Currently using **`troy`** (male, natural British-American accent).

### Response Streaming Into PSRAM

The Groq server starts sending WAV bytes immediately (streaming). The firmware reads the stream chunk by chunk:

```
Groq TLS socket ──→ stream->readBytes() ──→ ttsBuf (PSRAM)
```

- Up to **1 MB** (TTS_PSRAM_MAX) can be buffered
- The firmware calls `updateFace()` between reads to keep the OLED animating
- Typical Groq Orpheus WAV size: **~200–400 KB** for a 1–2 sentence reply
- Once fully downloaded, `playWavFromPsram()` is called

### Why WAV format (not MP3)?

The ESP32-S3's I2S peripheral directly outputs **PCM samples**. WAV is uncompressed PCM + a header. The firmware skips the 44-byte header, reads 16-bit samples, scales them, and feeds them directly to I2S TX. No decoder library needed.  
MP3 would require a software decoder (uses ~40 KB RAM and significant CPU).

---

## 8. TTS Fallback: VoiceRSS WAV

If Groq TTS fails (server busy, timeout, auth error), the firmware falls back to **VoiceRSS** — an HTTP (not HTTPS) TTS API that returns standard WAV:

```
GET http://api.voicerss.org/?key=YOUR_KEY&hl=en-us&c=WAV&f=16khz_16bit_mono&src=Hello+World
```

VoiceRSS is lower quality (robotic voice) but runs on plain HTTP so it's faster and more reliable on slow WiFi. The returned WAV is played identically via `playWavFromPsram()`.

---

## 9. Audio Playback: I2S TX → MAX98357A Speaker

### How `playWavFromPsram()` Works

```
ttsBuf (PSRAM)
  │
  ├─ findRiffOffset()  ← finds "RIFF" header in case of partial stream
  ├─ findDataOffset()  ← finds "data" chunk to skip the 44-byte header
  │
  └─ for each 512-sample chunk:
       ├─ scale by SPEAKER_VOLUME (0.50f)   ← 50% amplitude
       ├─ clip to int16 range [-32768, 32767]
       ├─ duplicate sample for L+R channels (stereo output from mono source)
       ├─ i2s_channel_write() → MAX98357A
       └─ check for double-tap interrupt
```

### Volume at 50% — Why?

The MAX98357A at full volume on a 5V supply draws **~800 mA peaks** at loud audio. The ESP32-S3's USB power rail (500 mA from PC) or a cheap powerbank drops below 4.5 V under this load, causing a **brownout reset**. At 50% amplitude (25% power), peak draw stays under 300 mA — stable on any USB source.

The `findRiffOffset()` function handles a quirk where Groq's streaming response sometimes has a few garbage bytes before the `RIFF` magic — the function scans for `RIFF` rather than assuming offset 0.

---

## 10. OLED Face Display

### Hardware: SH1106 128×64 via Software SPI

The SH1106 uses **4-wire SPI** (SCK, MOSI/SDA, CS, DC + RST). The firmware uses U8g2's **software SPI** driver because the ESP32-S3's hardware SPI was already in conflict with the I2S peripheral GPIO mapping.

Software SPI is bit-banged in CPU cycles but at 20 FPS (50 ms frames) this is imperceptible.

### Eyes: Parametric Vector Rendering

Each eye is defined by an `EyeParams` struct:
```cpp
struct EyeParams {
  float w, h, radius, slopeTop, slopeBot, offsetY, pupilScale;
};
```

8 preset expressions (Happy, Sad, Focused, Excited, Angry, Confused, Sleepy, Neutral) are defined as constant structs. When switching expressions:
1. The current interpolated eye state is frozen
2. `eyeTgt` is set to the new expression
3. Each frame, `lerpEye()` smoothly interpolates over 300 ms (TRANS_MS)

### Natural Idle Behaviors
- **Blinking**: random interval 2–6 seconds, 150 ms close/open animation
- **Saccades**: random look-direction shifts every 1–4 seconds (look offsets applied to pupils)
- **Scroll text**: long labels scroll across the bottom bar at 60 ms per pixel step

### Label Display During Voice

| Phase | OLED Label |
|-------|-----------|
| Touch detected | `LISTENING...` |
| Recording | `LISTENING...` |
| STT running | `THINKING...` |
| Transcription done | `Q: <what you said>` (shown 1.2 s) |
| TTS playing | `A: <robot reply>` (stays during speech) |
| After speech | `<question> | <reply>` (scrolling) |

---

## 11. Touch Sensor: Listening Trigger & Double-Tap Interrupt

The TTP223 capacitive sensor outputs:
- `LOW` = not touched
- `HIGH` = finger detected

### Single Touch → Start Listening

The touch handler uses **edge-triggered detection with debounce**:
1. Detects `LOW → HIGH` rising edge
2. Requires the HIGH to be held for ≥ 80 ms (filters out spurious EMI spikes)
3. Cooldown of 800 ms between triggers
4. Calls `doVoice()` once confirmed

### Double-Tap → Interrupt Speech

Inside `playWavFromPsram()` (the audio playback loop), every audio chunk checks for a double-tap:

```
Tap 1 (rising edge) → record timestamp t1, tapCount = 1
Tap 2 (rising edge) within 700ms of t1 → interruptFlag = true → break audio loop
```

After `playTTS()` returns (early because of break), `doVoice()` checks `interruptFlag`:
```cpp
if (interruptFlag) {
    interruptFlag = false;
    doVoice();  // Immediately restart listening
    return;
}
```

> **Why not single-tap to interrupt?**  
> The MAX98357A speaker vibrates the entire robot chassis. This mechanical vibration is picked up by the TTP223 sensor as false touches, triggering constant interrupts during speech. Double-tap with a 700 ms window requires two **distinct intentional taps** — speaker vibrations happen at audio frequencies (100s of Hz) but can't produce two clean rising-edge events 50–700 ms apart.

---

## 12. Direct Action Dispatch (Alarm, Call)

### Why Bypass the LLM for Alarms?

LLMs are probabilistic. Even with a perfect system prompt, models occasionally return:
- `"Okay, I'll set that alarm for you!"` (plain text, no JSON)
- `{"action": "set_alarm", ...}` (wrong key name)
- Thinking tokens mixed in (`<think>...</think>{"action":...}`)

A single failure means the user's alarm never gets set — with no error message. The direct parser **always** works.

### Alarm Parser

```
Input: "set alarm for seven thirty pm"

1. Detect: lc.indexOf("alarm") != -1 → YES
2. Parse AM/PM: indexOf(" pm") → isPM = true
3. Find first digit sequence: "7" → hour = 7
4. Check for colon: ":" found → minute = 30
5. Apply PM: hour 7 + 12 = 19
6. Push to Firebase: { type:"alarm", hour:19, minute:30, nonce:millis() }
7. Reply: "Alarm set for 7:30 PM!"
```

Handles: `"7 am"`, `"7:30 pm"`, `"seven"`, `"wake me up at 8"`, `"alarm at half past six"`

The `nonce: millis()` field is critical — Firebase's `onValue` listener only fires when data changes. Without a unique nonce, saying "alarm for 7 AM" twice in a row would not trigger the Flutter listener the second time.

### Call Parser

```
Input: "call mom please"

1. Detect: lc.indexOf("call ") != -1 → YES
2. Extract contact: everything after "call " → "mom please"
3. Strip filler words: ["please","now","for me"] → "mom"
4. Push to Firebase: { type:"call", contact:"mom", nonce:millis() }
5. Reply: "Calling mom now!"
```

---

## 13. Firebase Bridge: Robot → Android Phone

### Why Firebase?

The robot is on WiFi but can't directly communicate with an Android phone (different network, no open port). Firebase Realtime Database acts as a **message broker**:

```
ESP32 (WiFi) ──HTTPS POST──→ Firebase RTDB ──WebSocket──→ Flutter App (phone)
```

### Database Path

```
/users/default/bot_actions/{auto-id}
  {
    "type": "alarm",
    "hour": 7,
    "minute": 0,
    "executed": false,
    "timestamp": 1731945000,
    "nonce": 847382
  }
```

The firmware uses `POST` (not `PUT`) to `/bot_actions.json` — Firebase generates a unique push ID (`-NxKj3...`) automatically, so multiple actions don't overwrite each other.

### Telemetry (Every 30 Seconds)

The robot also pushes status to `/users/default/robot/telemetry`:
```json
{
  "expression": 0,
  "task_count": 2,
  "pomodoro_active": false,
  "pomodoro_remaining": 0,
  "uptime_s": 3847,
  "ip": "192.168.1.105",
  "status": "ONLINE"
}
```

The Flutter app reads this to show the robot's live state in the cockpit screen.

---

## 14. Flutter App: Receiving & Executing Actions

### Firebase Listener (`firebase_service.dart`)

```dart
Stream<DatabaseEvent> watchBotActions() {
  return _robotRef.child('bot_actions')
      .limitToLast(15)
      .onValue;
}
```

This is a **WebSocket stream** — Firebase keeps a persistent connection and delivers new children instantly (< 100 ms latency from robot to phone).

### Action Dispatch (`student_shell.dart`)

When a new `bot_actions` child arrives:
1. Check `type`
2. If `alarm` → call `AlarmService.setPhoneAlarm(hour, minute, title)`
3. If `call` → call `AlarmService.makePhoneCall(contact)`
4. If `calendar` → call `CalendarService.createEvent(...)`

### Kotlin MethodChannel → Native Alarm (`MainActivity.kt`)

The Flutter `AlarmService` calls a Kotlin MethodChannel (`com.hellobuddy/alarm`) which runs:

```kotlin
// Sets a real Android alarm (shows in Clock app)
val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
alarmManager.setAlarmClock(
    AlarmManager.AlarmClockInfo(triggerTime, pendingIntent),
    pendingIntent
)
// Also fires ACTION_SET_ALARM intent (shows up in system Clock app)
val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
    putExtra(AlarmClock.EXTRA_HOUR, hour)
    putExtra(AlarmClock.EXTRA_MINUTES, minute)
    putExtra(AlarmClock.EXTRA_MESSAGE, title)
    putExtra(AlarmClock.EXTRA_SKIP_UI, true)
}
startActivity(intent)
```

> **Requirement**: The Flutter app must be running (background is fine, but not force-killed). Go to **Settings → Apps → Hello Buddy → Battery → Unrestricted** to allow background operation.

---

## 15. Noise Gate & Audio Quality

### Noise Gate

Before sending audio to Groq STT, the firmware computes the **average amplitude**:

```cpp
long long nrg = 0;
for (size_t i = 0; i < nSamples; i++) nrg += abs(samples[i]);
long long avgAmp = nrg / nSamples;

if (avgAmp < 120) {
    // Silent room / ambient noise — skip STT call
    setLabel("TOO QUIET");
    return;
}
```

Threshold of 120 (out of 32767 max) rejects:
- Empty room silence (avgAmp ~ 20–40)
- AC/fan background noise (avgAmp ~ 60–90)
- Light keyboard typing (avgAmp ~ 80–110)

A human speaking at normal volume produces avgAmp ~ 400–3000.

### DSP Bandpass Filter (180–3400 Hz)

Applied during recording:
- **High-pass at 180 Hz**: removes low-frequency mechanical vibration, power hum, HVAC
- **Low-pass at 3400 Hz**: removes high-frequency electrical noise above telephone speech range

Human speech fundamentals: 85–255 Hz (male), 165–255 Hz (female). Harmonics carry intelligibility up to ~3400 Hz. The filter preserves 100% of speech while killing noise.

---

## 16. Complete Voice Interaction Flow (Step by Step)

```
User double-taps sensor
        │
        ▼
handleTouch() ── edge detected, 80ms hold confirmed
        │
        ▼
doVoice()
  │
  ├─ setLabel("LISTENING...")
  ├─ setExprIdx(2) [Focused eyes]
  ├─ playTone("chime") [3-tone beep: user knows mic is on]
  │
  ├─ recordAudio() [3 sec I2S capture → PSRAM]
  ├─ Compute avgAmp
  │   └─ if < 120 → "TOO QUIET" → return
  │
  ├─ setLabel("THINKING...")
  ├─ setExprIdx(5) [Excited eyes]
  │
  ├─ groqSTT(micBuf) [~300ms → Groq Whisper]
  │   └─ if fail → witSTT(micBuf) [~800ms fallback]
  │
  ├─ setLabel("Q: " + heard) [Show question on OLED, 1.2s]
  │
  ├─ Parse heard:
  │   ├─ "alarm"/"wake up" → Direct alarm parser → Firebase → reply
  │   ├─ "call "          → Direct call parser → Firebase → reply
  │   ├─ "weather"        → fetchWeather() (Open-Meteo API) → reply
  │   └─ anything else   → askGroq() [Groq LLM, ~500ms] → reply
  │                            └─ Parse JSON action if present
  │
  ├─ logVoice(heard, reply) → Firebase voice_logs
  ├─ setLabel("A: " + reply)
  ├─ setExprIdx(0) [Happy eyes]
  │
  ├─ playTTS(reply)
  │   ├─ Groq Orpheus TTS → WAV → PSRAM [~1-3 sec download]
  │   ├─ playWavFromPsram() [I2S TX → speaker]
  │   │   └─ [During playback: check for double-tap → interruptFlag]
  │   └─ if Groq fails → VoiceRSS fallback
  │
  ├─ if interruptFlag → doVoice() [recursive: restart listening]
  │
  └─ setLabel(heard + " | " + reply) [scrolling idle display]
     voiceActive = false
     idleFace()
```

**Total latency** (typical, good WiFi):
- Record: 3,000 ms (fixed)
- Groq STT: ~300 ms
- Groq LLM (if needed): ~500 ms
- Groq TTS download: ~1,500 ms
- **Total: ~5.3 seconds from tap to speaking**

---

## 17. Power & Stability Design

### PSRAM Allocation Strategy

```cpp
// At boot — allocated once, never freed
micBuf = (uint8_t*) ps_malloc(SAMPLE_RATE * 2 * RECORD_SECS + WAV_HDR);  // ~96 KB
ttsBuf = (uint8_t*) ps_malloc(TTS_PSRAM_MAX);                              // 1 MB
```

Allocating once at boot:
- Avoids heap fragmentation from repeated malloc/free
- Guarantees both buffers always exist (boot fails cleanly if PSRAM isn't detected)

### OLED Contrast at 110

The SH1106 at full contrast (255) draws ~15 mA. At 110, it draws ~6 mA. On a shared 5V/500 mA USB bus with the ESP32, the speaker amp, and the mic, this 9 mA saving is meaningful and also prevents pixel burn-in on a continuously-on display.

### I2S Channel Management

The I2S peripheral is shared between mic (RX) and speaker (TX) but the ESP32-S3 supports them on different channel handles. The firmware:
1. Opens the **RX channel** only during `recordAudio()`, then closes it
2. Opens the **TX channel** only inside `playWavFromPsram()`, then closes it

This ensures they never conflict and frees the DMA buffers between uses.

### WiFi Reconnection

The main loop checks `WiFi.status()` before every HTTPS call. If disconnected, it reconnects. Firebase and Groq calls are wrapped in timeout guards (8–20 seconds) so a network failure doesn't hang the robot indefinitely.

---

## Quick Reference: APIs Used

| API | Endpoint | Purpose | Latency |
|-----|----------|---------|---------|
| **Groq Whisper** | `api.groq.com/openai/v1/audio/transcriptions` | Speech → Text | ~300 ms |
| **Groq Chat** | `api.groq.com/openai/v1/chat/completions` | Text → AI Reply | ~500 ms |
| **Groq Orpheus TTS** | `api.groq.com/openai/v1/audio/speech` | Text → Speech WAV | ~1–3 s |
| **Wit.ai** | `api.wit.ai/speech` | STT Fallback | ~800 ms |
| **VoiceRSS** | `api.voicerss.org` | TTS Fallback | ~1 s |
| **Open-Meteo** | `api.open-meteo.com/v1/forecast` | Weather (free) | ~300 ms |
| **Firebase RTDB** | `*.firebaseio.com/users/default/...` | Robot → Phone bridge | <100 ms |

---

*Document generated for Hello Buddy v3.0 — ESP32-S3 N16R8 Firmware*  
*Author: Ziaur Rahaman — EPD 2026*
