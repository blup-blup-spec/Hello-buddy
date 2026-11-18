# Hello Buddy 🤖

**Hello Buddy** is an ESP32-S3 desktop companion robot with an OLED face, voice assistant, and a companion Flutter Android app. It listens to your voice, responds with AI-generated speech, shows both your question and the reply on its OLED display, sets phone alarms via Firebase, and can be interrupted mid-speech with a double-tap.

---

## 📁 Repository Structure

```
Hello-Buddy/
├── firmware/
│   └── hello_buddy/
│       └── hello_buddy.ino       ← Main ESP32-S3 firmware (latest, all fixes applied)
├── docs/
│   ├── Hello_Buddy_Report.tex        ← Full LaTeX project report
│   ├── Hello_Buddy_PDR.tex           ← Preliminary Design Review
│   ├── Hello_Buddy_User_Manual.tex   ← User manual
│   ├── DESIGN.md                     ← System architecture & design notes
│   └── POSTMORTEM_BUILD_AND_ACTION_ISSUES.md  ← Bugs found & fixed log
└── README.md
```

---

## 🛠️ Hardware

| Component      | Part                    | Pins (ESP32-S3)                        |
|----------------|-------------------------|----------------------------------------|
| MCU            | ESP32-S3 N16R8          | —                                      |
| OLED Display   | SH1106 128×64 (7-pin SPI)| SCK=4, SDA=5, RES=6, DC=7, CS=15      |
| Microphone     | INMP441 (I2S)           | SCK=42, WS=41, SD=40                  |
| Speaker Amp    | MAX98357A (I2S)         | BCLK=39, LRC=38, DIN=48               |
| Touch Sensor   | TTP223 capacitive       | GPIO3                                  |

---

## 🔧 Firmware Setup (`firmware/hello_buddy/hello_buddy.ino`)

### Dependencies (Arduino Library Manager)
- `U8g2` by Oliver Kraus
- `ArduinoJson` by Benoît Blanchon
- ESP32 board package ≥ 3.x (`espressif/arduino-esp32`)

### Configuration

Open `hello_buddy.ino` and fill in your credentials at the top:

```cpp
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

const char* WIT_TOKEN    = "YOUR_WIT_AI_TOKEN";       // wit.ai speech token
const char* GROQ_API_KEY = "YOUR_GROQ_API_KEY";       // groq.com API key
const String VOICERSS_KEY = "YOUR_VOICERSS_KEY";      // voicerss.org key (fallback TTS)

const char* FIREBASE_HOST = "YOUR_PROJECT.firebaseio.com";
```

### Flash Settings (Arduino IDE)
- Board: `ESP32S3 Dev Module`
- Flash Size: `16MB`
- PSRAM: `OPI PSRAM`
- Partition: `Huge APP (3MB No OTA/1MB SPIFFS)`
- Upload Speed: `921600`

---

## 🎤 Features & What Was Fixed

### ✅ OLED Shows Both Q & A
The robot now displays:
1. `Q: <your spoken question>` — immediately after STT transcription
2. `A: <robot reply>` — during TTS speech playback
3. Combined scrolling text — after speech ends

Previously, `updateFace()` was overriding all label updates with "Listening..." / "Speaking..." because it checked `voiceActive` and `vrActive` flags that were always true during voice interaction. **Fixed** by removing those overrides and letting `setLabel()` calls in `doVoice()` control the display directly.

### ✅ Double-Tap Interrupt (Touch Sensor)
Tapping the TTP223 touch sensor **twice within 700 ms** during speech immediately stops playback and re-enters listening mode.

**Single taps are ignored** — this was critical because speaker vibrations were causing false single-tap triggers. The fix uses edge-triggered detection (LOW→HIGH transitions) with a tap counter and 700 ms timeout window inside `playWavFromPsram()`.

### ✅ Alarm / Call Actions Work Directly (No LLM Dependency)
When you say *"set alarm for 7 AM"*, the firmware now:
1. Detects the keyword `alarm` **before** calling the LLM
2. Parses the time directly from speech text (`7 AM`, `8:30 PM`, etc.)
3. Pushes `{ type: "alarm", hour: 7, minute: 0, nonce: millis() }` to Firebase RTDB at `/users/default/bot_actions/`
4. The Flutter companion app picks this up via `onValue` listener and calls `AlarmManager.setAlarmClock()` via MethodChannel

Previously the LLM returned plain text "Okay" instead of JSON, so the action was never parsed or dispatched.

### ✅ OLED No Longer Stuck on "SPEAKING..."
After TTS finishes, the display now updates to the reply text instead of staying frozen on "SPEAKING...".

---

## 📱 Companion App (Flutter + Android)

The Flutter companion app (`hello_buddy_app/`) is **not included** in this repo because it contains Firebase credentials (`google-services.json`) and personal API keys.

**App features:**
- Watches Firebase RTDB `/users/default/bot_actions` in real time
- Dispatches alarms via `AlarmManager.setAlarmClock()` (Kotlin MethodChannel)
- Dispatches phone calls via `ACTION_CALL` intent
- Pomodoro timer, task tracker, weather display

**To run the app yourself:**
1. Create a Firebase project, download `google-services.json` → place in `android/app/`
2. Enable Firebase Realtime Database
3. Set the same `FIREBASE_HOST` in the firmware
4. Run `flutter pub get && flutter run`

---

## 🔑 API Keys You Need

| Service   | Purpose                         | Get it at                        |
|-----------|---------------------------------|----------------------------------|
| Groq      | STT (Whisper) + LLM + TTS      | https://console.groq.com         |
| Wit.ai    | Fallback STT                    | https://wit.ai                   |
| VoiceRSS  | Fallback TTS (WAV)              | https://www.voicerss.org         |
| Firebase  | Robot ↔ App action bridge       | https://console.firebase.google.com |
| Open-Meteo| Weather (free, no key needed)   | https://open-meteo.com           |

---

## 🏗️ System Architecture

```
[INMP441 Mic] → I2S RX → [ESP32-S3] → Groq Whisper STT → Groq LLM
                                                               ↓
[SH1106 OLED] ← updateFace() ← setLabel()         Groq Orpheus TTS
                                                               ↓
[MAX98357A Speaker] ← I2S TX ← playWavFromPsram()         Firebase RTDB
                                                               ↓
                                                    [Flutter App]
                                                               ↓
                                                   Android AlarmManager
```

---

## 📄 License

MIT — free to use, modify, and share. Attribution appreciated.

---

*Built for the Electronic Product Development course (EPD 2026). Hardware + firmware by Ziaur Rahaman.*
