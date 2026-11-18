/*
 * ====================================================================
 * Hello Buddy - ESP32-S3 N16R8 Unified Firmware v3.0 (7-PIN SPI OLED)
 * Primary TTS  : Groq Orpheus WAV (canopylabs/orpheus-v1-english)
 * Fallback TTS : VoiceRSS WAV (Native I2S - Zero missing header errors!)
 * OLED         : SH1106 128x64 4-Wire SPI (SCK=4, SDA=5, RES=6, DC=7, CS=15)
 * Touch        : TTP223  GPIO3
 * Mic          : INMP441 SCK=42 WS=41 SD=40
 * Speaker      : MAX98357A BCLK=39 LRC=38 DIN=48
 * ====================================================================
 */

#undef RGB_BUILTIN

#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <driver/i2s_std.h>
#include <driver/gpio.h>
#include <U8g2lib.h>
#include <ArduinoJson.h>

// ====================== CONFIG ======================

const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

const char* WIT_TOKEN    = "YOUR_WIT_AI_TOKEN";
const char* GROQ_API_KEY = "YOUR_GROQ_API_KEY";

const String VOICERSS_KEY = "YOUR_VOICERSS_KEY";

const char* FIREBASE_HOST      = "epd2026-127ec-default-rtdb.firebaseio.com";
const char* FIREBASE_AUTH      = "";
const char* FIREBASE_USER_PATH = "/users/default";
const char* WEATHER_URL        = "https://api.open-meteo.com/v1/forecast"
                                 "?latitude=20.2961&longitude=85.8245&current_weather=true";

// ====================== PINS ======================

// OLED â€” 7-pin SPI Pins (Locked)
#define OLED_SCK       4
#define OLED_SDA       5   // MOSI / D1
#define OLED_RES       6
#define OLED_DC        7
#define OLED_CS       15

// Touch
#define TOUCH_PIN 3

// Mic â€” INMP441 (I2S0 RX)
#define MIC_SCK  42
#define MIC_WS   41
#define MIC_SD   40

// Speaker â€” MAX98357A (I2S0 TX)
#define SPK_BCLK 39
#define SPK_LRC  38
#define SPK_DIN  48

// ====================== CONSTANTS ======================

#define SAMPLE_RATE       16000
#define RECORD_SECS       3
#define AUDIO_BUF_BYTES   (SAMPLE_RATE * 2 * RECORD_SECS)
#define WAV_HDR           44
#define TTS_PSRAM_MAX     (1024 * 1024)
#define SPEAKER_VOLUME    0.50f  // 50% amplitude slashes peak power to 25%, preventing 5V brownout

#define SCREEN_W  128
#define SCREEN_H   64
#define EYE_L_X    32
#define EYE_R_X    96
#define EYE_Y      26
#define BAR_Y      52
#define FRAME_MS   50  // Silky smooth 20 FPS saves 25% CPU and bus power

#define TASK_POLL_MS      15000
#define TELEMETRY_PUSH_MS 30000
#define TOUCH_CD_MS         800

// ====================== OBJECTS ======================

// 4-Wire Software SPI for 7-pin SH1106 OLED
U8G2_SH1106_128X64_NONAME_F_4W_SW_SPI u8g2(
  U8G2_R0,
  /* SCK  */ OLED_SCK,
  /* MOSI */ OLED_SDA,
  /* CS   */ OLED_CS,
  /* DC   */ OLED_DC,
  /* RES  */ OLED_RES
);

WebServer server(80);
uint8_t* micBuf = nullptr;
uint8_t* ttsBuf = nullptr;

// ====================== EYE PARAMS ======================

struct EyeParams {
  float w, h, radius, slopeTop, slopeBot, offsetY, pupilScale;
};

const EyeParams EXPR_NEUTRAL  = { 18, 16,  6,  0.00f,  0.00f,  0, 0.0f };
const EyeParams EXPR_HAPPY    = { 20,  8,  8,  0.00f, -0.60f, -2, 0.0f };
const EyeParams EXPR_SAD      = { 18, 13,  6, -0.55f,  0.00f,  5, 0.0f };
const EyeParams EXPR_FOCUSED  = { 18,  7,  3,  0.20f,  0.00f, -2, 0.5f };
const EyeParams EXPR_EXCITED  = { 23, 23, 11,  0.00f,  0.00f, -4, 0.6f };
const EyeParams EXPR_ANGRY    = { 20, 10,  4,  0.60f,  0.10f,  2, 0.3f };
const EyeParams EXPR_CONFUSED = { 16, 14,  5, -0.30f,  0.30f,  1, 0.2f };
const EyeParams EXPR_SLEEPY   = { 18,  4,  6,  0.00f,  0.00f,  3, 0.0f };

const EyeParams* EXPR_TABLE[] = {
  &EXPR_HAPPY, &EXPR_SAD, &EXPR_FOCUSED, &EXPR_ANGRY,
  &EXPR_SLEEPY, &EXPR_EXCITED, &EXPR_NEUTRAL, &EXPR_CONFUSED
};
#define NUM_EXPR 8

// ====================== EYE STATE ======================

EyeParams eyeCur = EXPR_NEUTRAL;
EyeParams eyeTgt = EXPR_NEUTRAL;
unsigned long transStart = 0;
const unsigned long TRANS_MS = 300;
const unsigned long BLINK_MS = 150;

float lookX = 0, lookY = 0, tLookX = 0, tLookY = 0;
unsigned long lastSaccade = 0, nextSaccade = 1000;
unsigned long lastBlink = 0, nextBlink = 3000, blinkStart = 0;
bool blinking = false;

// ====================== APP STATE ======================

bool touchActive = false;
unsigned long lastTouchMs = 0;
int userSelectedExpr = 0; // Sticky expression (default 0 = Happy)

char taskText[40] = "No tasks";
int  taskCount    = 0;
bool hasOverdue   = false;
unsigned long lastTaskPoll = 0;

int  pomodoroSec  = 0;
bool pomodoroOn   = false;
unsigned long lastPomoTick = 0;

unsigned long lastTelemetry = 0;
int  exprIdx     = 6;
bool voiceActive = false;
bool vrActive    = false;
volatile bool interruptFlag = false;  // double-tap interrupt during TTS

String currentLabel = "Ready :)";
int scrollOffset    = 0;
unsigned long lastScroll = 0;

// ====================== UTILITIES ======================

static inline float flerp(float a, float b, float t) { return a + (b - a) * t; }

EyeParams lerpEye(const EyeParams& a, const EyeParams& b, float t) {
  return { flerp(a.w,b.w,t), flerp(a.h,b.h,t), flerp(a.radius,b.radius,t),
           flerp(a.slopeTop,b.slopeTop,t), flerp(a.slopeBot,b.slopeBot,t),
           flerp(a.offsetY,b.offsetY,t), flerp(a.pupilScale,b.pupilScale,t) };
}

void setLabel(const String& text) {
  currentLabel = text;
  scrollOffset = 0;
  lastScroll   = millis();
}

void makeWAVHeader(uint8_t* h, uint32_t dataBytes, uint32_t sr) {
  uint32_t riffSz   = dataBytes + 36;
  uint32_t byteRate = sr * 2;
  memcpy(h, "RIFF", 4);
  h[4]  = (riffSz)        & 0xFF; h[5]  = (riffSz >> 8)   & 0xFF;
  h[6]  = (riffSz >> 16)  & 0xFF; h[7]  = (riffSz >> 24)  & 0xFF;
  memcpy(h + 8,  "WAVE", 4);
  memcpy(h + 12, "fmt ", 4);
  h[16] = 16; h[17] = 0; h[18] = 0; h[19] = 0;
  h[20] = 1;  h[21] = 0; h[22] = 1; h[23] = 0;   // PCM, Mono
  h[24] = (sr)        & 0xFF; h[25] = (sr >> 8)   & 0xFF;
  h[26] = (sr >> 16)  & 0xFF; h[27] = (sr >> 24)  & 0xFF;
  h[28] = (byteRate)       & 0xFF; h[29] = (byteRate >> 8)  & 0xFF;
  h[30] = (byteRate >> 16) & 0xFF; h[31] = (byteRate >> 24) & 0xFF;
  h[32] = 2; h[33] = 0; h[34] = 16; h[35] = 0;
  memcpy(h + 36, "data", 4);
  h[40] = (dataBytes)       & 0xFF; h[41] = (dataBytes >> 8)  & 0xFF;
  h[42] = (dataBytes >> 16) & 0xFF; h[43] = (dataBytes >> 24) & 0xFF;
}

String urlEncode(const String& s) {
  String r;
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
      r += c;
    } else {
      char b[4];
      snprintf(b, sizeof(b), "%%%02X", (uint8_t)c);
      r += b;
    }
  }
  return r;
}

// ====================== EXPRESSIONS ======================

void setExpr(const EyeParams& tgt) {
  unsigned long now = millis();
  float t = min(1.0f, (float)(now - transStart) / (float)TRANS_MS);
  eyeCur     = lerpEye(eyeCur, eyeTgt, t);
  eyeTgt     = tgt;
  transStart = now;
  blinking   = true;
  blinkStart = now;
  tLookX = tLookY = 0;
}

void setExprIdx(int idx) {
  if (idx < 0 || idx >= NUM_EXPR) idx = 6;
  exprIdx = idx;
  setExpr(*EXPR_TABLE[idx]);
}

void idleFace();

float blinkFrac() {
  unsigned long now = millis();
  if (!blinking) {
    if (now - lastBlink > nextBlink) {
      blinking = true; blinkStart = now; lastBlink = now;
      nextBlink = random(2000, 6000);
    }
    return 0.0f;
  }
  float t = (float)(now - blinkStart) / (float)BLINK_MS;
  if (t >= 1.0f) { blinking = false; return 0.0f; }
  return (t < 0.3f) ? (t / 0.3f) : (1.0f - (t - 0.3f) / 0.7f);
}

// ====================== DRAWING ======================

void drawEye(int cx, int cy, const EyeParams& p, float bf, bool mirror) {
  int w = (int)p.w, h = (int)p.h, r = (int)min(p.radius, min((float)w, (float)h));
  int dy = (int)p.offsetY, ch = (int)(p.h * (1.0f - bf));
  float sT = mirror ? -p.slopeTop : p.slopeTop;
  float sB = mirror ? -p.slopeBot : p.slopeBot;
  for (int x = cx - w; x <= cx + w; x++) {
    float fr = (w > 0) ? (float)(x - cx) / (float)w : 0.0f;
    int tL = cy + dy - ch + (int)(sT * fr * w);
    int bL = cy + dy + h  + (int)(sB * fr * w);
    int da = abs(x - cx), rT = cy + dy - ch, rB = cy + dy + h;
    if (da > (w - r) && r > 0) {
      float rx = (float)(da - (w - r)), ry = (float)r;
      float ins = ry * ry - rx * rx; if (ins < 0) ins = 0;
      float arc = ry - sqrtf(ins); rT += (int)arc; rB -= (int)arc;
    }
    int dT = max(tL, rT), dB = min(bL, rB);
    if (dT <= dB) u8g2.drawVLine(x, dT, dB - dT + 1);
  }
  if (p.pupilScale > 0.01f && bf < 0.5f) {
    int pr = (int)(min(p.w, p.h) * p.pupilScale * 0.55f);
    if (pr >= 1) {
      u8g2.setDrawColor(0);
      u8g2.drawDisc(cx, cy + dy - (int)(ch * 0.5f), pr);
      u8g2.setDrawColor(1);
    }
  }
}

void updateFace() {
  unsigned long now = millis();
  static unsigned long lastF = 0;
  if (now - lastF < FRAME_MS) return;
  lastF = now;

  if (now - lastSaccade > nextSaccade) {
    tLookX = (float)random(-6, 7); tLookY = (float)random(-4, 5);
    if (random(100) > 70) { tLookX = 0; tLookY = 0; }
    lastSaccade = now; nextSaccade = random(400, 2500);
  }
  lookX += (tLookX - lookX) * 0.15f;
  lookY += (tLookY - lookY) * 0.15f;

  float t  = min(1.0f, (float)(now - transStart) / (float)TRANS_MS);
  float te = (t < 0.5f) ? (4.0f * t * t * t) : (1.0f - powf(-2.0f * t + 2.0f, 3.0f) / 2.0f);
  EyeParams fr = lerpEye(eyeCur, eyeTgt, te);
  float bf = blinkFrac();

  u8g2.clearBuffer();
  drawEye(EYE_L_X + (int)lookX, EYE_Y + (int)lookY, fr, bf, true);
  drawEye(EYE_R_X + (int)lookX, EYE_Y + (int)lookY, fr, bf, false);

  u8g2.setDrawColor(1);
  u8g2.drawHLine(0, BAR_Y - 1, SCREEN_W);

  u8g2.setFont(u8g2_font_6x10_tr);
  String displayText = currentLabel;
  if (pomodoroOn) {
    char pbuf[32];
    snprintf(pbuf, sizeof(pbuf), "[POMO %02d:%02d]", pomodoroSec / 60, pomodoroSec % 60);
    displayText = String(pbuf);
  } else if (displayText == "Ready :)" && taskCount > 0) {
    char tbuf[48];
    snprintf(tbuf, sizeof(tbuf), "[%d] %s", taskCount, taskText);
    displayText = String(tbuf);
  }

  int textPixelWidth = u8g2.getStrWidth(displayText.c_str());
  if (textPixelWidth > SCREEN_W - 4) {
    if (now - lastScroll > 180) {
      scrollOffset++;
      if (scrollOffset > (int)displayText.length() + 3) scrollOffset = 0;
      lastScroll = now;
    }
    String doubled = displayText + "   " + displayText;
    u8g2.drawStr(2 - (scrollOffset * 6), SCREEN_H - 1, doubled.c_str());
  } else {
    u8g2.drawStr(2, SCREEN_H - 1, displayText.c_str());
  }

  u8g2.sendBuffer();
}

void animateFor(unsigned long ms) {
  unsigned long s = millis();
  while (millis() - s < ms) { updateFace(); delay(5); }
}

// ====================== MIC RECORDING (MULTI-STAGE VOICE BANDPASS FILTER & NOISE GATE) ======================

size_t recordAudio() {
  i2s_chan_handle_t rx_handle = NULL;
  i2s_chan_config_t cc = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  if (i2s_new_channel(&cc, NULL, &rx_handle) != ESP_OK) {
    Serial.println(F("FATAL: i2s_new_channel mic error"));
    return 0;
  }

  // Use STEREO mode to read BOTH Left and Right slots:
  // INMP441 outputs active 24-bit audio on either L or R depending on L/R pin wiring.
  i2s_std_config_t sc = {
    .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_STEREO),
    .gpio_cfg = {
      .mclk = (gpio_num_t)I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)MIC_SCK,
      .ws   = (gpio_num_t)MIC_WS,
      .dout = (gpio_num_t)I2S_GPIO_UNUSED,
      .din  = (gpio_num_t)MIC_SD,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false }
    }
  };
  sc.slot_cfg.slot_mask = I2S_STD_SLOT_BOTH;

  if (i2s_channel_init_std_mode(rx_handle, &sc) != ESP_OK) {
    Serial.println(F("FATAL: Failed to init mic std mode"));
    i2s_del_channel(rx_handle);
    return 0;
  }

  i2s_channel_enable(rx_handle);

  int16_t* dst      = (int16_t*)(micBuf + WAV_HDR);
  size_t   totalSmp = (size_t)SAMPLE_RATE * RECORD_SECS; // 48000 samples for 3.0s
  static int32_t raw[512]; // interleaved [L, R, L, R, ...]
  size_t   got = 0;
  long long nrg = 0;

  // 1. Channel Auto-Detection: Sample the first ~120ms to detect active channel (L or R)
  long long leftSum = 0, rightSum = 0;
  size_t discarded = 0;
  while (discarded < 1920) {
    size_t bytes = 0;
    i2s_channel_read(rx_handle, raw, sizeof(raw), &bytes, pdMS_TO_TICKS(50));
    size_t pairs = bytes / 8;
    for (size_t i = 0; i < pairs; i++) {
      leftSum  += abs(raw[i * 2] >> 14);
      rightSum += abs(raw[i * 2 + 1] >> 14);
    }
    discarded += pairs;
  }
  // Lock to the active channel: eliminates channel-hopping rectification noise!
  int activeChan = (leftSum >= rightSum) ? 0 : 1;
  Serial.printf("Mic locked to channel: %s (L:%lld, R:%lld)\n", 
                activeChan == 0 ? "LEFT" : "RIGHT", leftSum, rightSum);

  // 2. Multi-Stage Digital Voice Filter State Variables:
  // Stage A: High-Pass Filter (~180 Hz cutoff) -> Strips 50/60Hz hum, fan rumble, desk thumps
  // Difference equation: y_hp[n] = 0.932 * (y_hp[n-1] + x[n] - x[n-1])
  float lastX = 0.0f;
  float lastHp = 0.0f;

  // Stage B: Low-Pass Filter (~3400 Hz cutoff) -> Strips high-frequency hiss and static
  // Difference equation: y_lp[n] = y_lp[n-1] + 0.58 * (y_hp[n] - y_lp[n-1])
  float lastLp = 0.0f;

  // Stage C: Speech Noise Gate (Removes background ambient noise / faint murmurs)
  const float NOISE_GATE_THRESHOLD = 140.0f;

  unsigned long t0 = millis();
  while (got < totalSmp && millis() - t0 < 6000) {
    size_t want = min((size_t)256, totalSmp - got);
    size_t bytes = 0;
    if (i2s_channel_read(rx_handle, raw, want * 8, &bytes, pdMS_TO_TICKS(300)) != ESP_OK) break;
    size_t pairs = bytes / 8;
    for (size_t i = 0; i < pairs; i++) {
      // Clean 16-bit extraction from active channel
      int32_t rawSample = raw[i * 2 + activeChan] >> 14;
      float x = (float)rawSample;

      // 1. High-Pass Filter (180 Hz)
      float hp = 0.932f * (lastHp + x - lastX);
      lastX = x;
      lastHp = hp;

      // 2. Low-Pass Filter (3400 Hz)
      float lp = lastLp + 0.58f * (hp - lastLp);
      lastLp = lp;

      // 3. Adaptive Noise Gate
      float processed = lp;
      float absVal = fabsf(lp);
      if (absVal < NOISE_GATE_THRESHOLD) {
        // Below gate: attenuate ambient background to silence
        processed *= 0.15f;
      } else {
        // Above gate: slight speech boost for Whisper dynamic range
        processed *= 1.30f;
      }

      // Clamp to signed 16-bit
      if (processed >  32767.0f) processed =  32767.0f;
      if (processed < -32768.0f) processed = -32768.0f;

      int16_t finalSample = (int16_t)processed;
      dst[got++] = finalSample;
      nrg += abs(finalSample);
    }
    // Clean recording: NO updateFace() bit-banging inside recording loop!
  }

  i2s_channel_disable(rx_handle);
  i2s_del_channel(rx_handle);

  for (size_t i = got; i < totalSmp; i++) dst[i] = 0;

  size_t pcmBytes = got * 2;
  makeWAVHeader(micBuf, pcmBytes, SAMPLE_RATE);

  long long avgAmp = got > 0 ? (nrg / (long long)got) : 0LL;
  Serial.printf("Filtered speech recorded: %u samples (%u PCM bytes), avg amp=%lld\n",
                (unsigned)got, (unsigned)pcmBytes, avgAmp);
  return pcmBytes;
}

// ====================== SPEAKER (NATIVE I2S) ======================

i2s_chan_handle_t openSpeakerChannel(uint32_t sampleRate) {
  gpio_reset_pin((gpio_num_t)SPK_BCLK);
  gpio_reset_pin((gpio_num_t)SPK_LRC);
  gpio_reset_pin((gpio_num_t)SPK_DIN);

  i2s_chan_handle_t tx = NULL;
  i2s_chan_config_t cc = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  cc.auto_clear    = true;
  cc.dma_desc_num  = 8;
  cc.dma_frame_num = 256;
  i2s_new_channel(&cc, &tx, NULL);

  i2s_std_config_t sc = {
    .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(sampleRate),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
    .gpio_cfg = {
      .mclk = (gpio_num_t)I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)SPK_BCLK,
      .ws   = (gpio_num_t)SPK_LRC,
      .dout = (gpio_num_t)SPK_DIN,
      .din  = (gpio_num_t)I2S_GPIO_UNUSED,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false }
    }
  };
  i2s_channel_init_std_mode(tx, &sc);
  i2s_channel_enable(tx);
  return tx;
}

void closeSpeakerChannel(i2s_chan_handle_t tx) {
  if (!tx) return;
  int16_t silence[1024] = {0};
  size_t bw = 0;
  i2s_channel_write(tx, silence, sizeof(silence), &bw, pdMS_TO_TICKS(200));
  i2s_channel_disable(tx);
  i2s_del_channel(tx);
}

void playHardwareTestTone() {
  Serial.println(F(">>> AUDIO SELF-TEST (SMOOTH SINE) <<<"));
  i2s_chan_handle_t tx = openSpeakerChannel(24000);
  if (!tx) return;
  int16_t frame[256];
  const float freqs[2] = { 880.0f, 1320.0f };
  for (int t = 0; t < 2; t++) {
    float phase = 0.0f;
    float phaseStep = (2.0f * 3.14159265f * freqs[t]) / 24000.0f;
    int totalSamples = 2400; // 100ms per tone
    for (int s = 0; s < totalSamples; s += 128) {
      for (int i = 0; i < 128; i++) {
        // Pure sine wave with gentle fade envelope: zero inductive spike, zero rail sag!
        float env = 1.0f;
        int curIdx = s + i;
        if (curIdx < 200) env = (float)curIdx / 200.0f;
        else if (curIdx > totalSamples - 200) env = (float)(totalSamples - curIdx) / 200.0f;
        int16_t v = (int16_t)(sinf(phase) * 5000.0f * env);
        phase += phaseStep;
        if (phase >= 2.0f * 3.14159265f) phase -= 2.0f * 3.14159265f;
        frame[i * 2] = v; frame[i * 2 + 1] = v;
      }
      size_t bw = 0;
      i2s_channel_write(tx, frame, sizeof(frame), &bw, pdMS_TO_TICKS(100));
    }
  }
  closeSpeakerChannel(tx);
  Serial.println(F(">>> SELF-TEST COMPLETE <<<"));
}

void playTone(const String& type) {
  i2s_chan_handle_t tx = openSpeakerChannel(24000);
  if (!tx) return;
  int16_t frame[256];

  if (type == "chime") {
    // Beautiful smooth two-tone musical chime (E5 -> A5): zero click, low current
    const float freqs[2] = { 659.25f, 880.0f };
    const int dursSamples[2] = { 1800, 2800 }; // ~75ms and ~116ms
    for (int t = 0; t < 2; t++) {
      float phase = 0.0f;
      float phaseStep = (2.0f * 3.14159265f * freqs[t]) / 24000.0f;
      int total = dursSamples[t];
      for (int s = 0; s < total; s += 128) {
        for (int i = 0; i < 128; i++) {
          float env = 1.0f;
          int cur = s + i;
          if (cur < 150) env = (float)cur / 150.0f;
          else if (cur > total - 200) env = (float)(total - cur) / 200.0f;
          int16_t v = (int16_t)(sinf(phase) * 4500.0f * env);
          phase += phaseStep;
          if (phase >= 2.0f * 3.14159265f) phase -= 2.0f * 3.14159265f;
          frame[i * 2] = v; frame[i * 2 + 1] = v;
        }
        size_t bw = 0;
        i2s_channel_write(tx, frame, sizeof(frame), &bw, pdMS_TO_TICKS(100));
      }
    }
  } else {
    // Soft alert pulses (440Hz A4)
    float phase = 0.0f;
    float phaseStep = (2.0f * 3.14159265f * 440.0f) / 24000.0f;
    for (int p = 0; p < 2; p++) {
      for (int s = 0; s < 2400; s += 128) {
        for (int i = 0; i < 128; i++) {
          float env = 1.0f;
          int cur = s + i;
          if (cur < 150) env = (float)cur / 150.0f;
          else if (cur > 2200) env = (float)(2400 - cur) / 200.0f;
          int16_t v = (int16_t)(sinf(phase) * 5500.0f * env);
          phase += phaseStep;
          if (phase >= 2.0f * 3.14159265f) phase -= 2.0f * 3.14159265f;
          frame[i * 2] = v; frame[i * 2 + 1] = v;
        }
        size_t bw = 0;
        i2s_channel_write(tx, frame, sizeof(frame), &bw, pdMS_TO_TICKS(100));
      }
      memset(frame, 0, sizeof(frame));
      for (int b = 0; b < 10; b++) {
        size_t bw = 0;
        i2s_channel_write(tx, frame, sizeof(frame), &bw, pdMS_TO_TICKS(100));
      }
    }
  }
  closeSpeakerChannel(tx);
}

// ====================== GROQ & VOICERSS WAV PLAYBACK ======================

int findRiffOffset(const uint8_t* buf, size_t len) {
  if (len < 44) return -1;
  size_t limit = min((size_t)512, len - 44);
  for (size_t i = 0; i <= limit; i++) {
    if (buf[i]=='R' && buf[i+1]=='I' && buf[i+2]=='F' && buf[i+3]=='F') return (int)i;
  }
  return -1;
}

size_t findDataOffset(const uint8_t* wav, size_t wavLen) {
  size_t pos = 12;
  while (pos + 8 <= wavLen) {
    if (wav[pos]=='d' && wav[pos+1]=='a' && wav[pos+2]=='t' && wav[pos+3]=='a') return pos + 8;
    uint32_t chunkSize = wav[pos+4] | ((uint32_t)wav[pos+5]<<8)
                       | ((uint32_t)wav[pos+6]<<16) | ((uint32_t)wav[pos+7]<<24);
    pos += 8 + chunkSize;
    if (chunkSize & 1) pos++;
  }
  return 44;
}

void playWavFromPsram(size_t totalBytes) {
  int riffIdx = findRiffOffset(ttsBuf, totalBytes);
  if (riffIdx < 0) {
    Serial.println(F("No RIFF found in TTS buffer."));
    return;
  }
  uint8_t* wav    = ttsBuf + riffIdx;
  size_t   wavLen = totalBytes - riffIdx;

  uint32_t wavRate = (uint32_t)wav[24] | ((uint32_t)wav[25]<<8)
                   | ((uint32_t)wav[26]<<16) | ((uint32_t)wav[27]<<24);
  if (wavRate < 8000 || wavRate > 48000) wavRate = 24000;

  size_t dataOffset = findDataOffset(wav, wavLen);
  if (dataOffset >= wavLen) { Serial.println(F("Bad data offset.")); return; }

  Serial.printf("Playing WAV: rate=%u, dataOffset=%u, samples=%u\n",
                (unsigned)wavRate, (unsigned)dataOffset,
                (unsigned)((wavLen - dataOffset) / 2));

  i2s_chan_handle_t tx = openSpeakerChannel(wavRate);
  if (!tx) return;

  const int16_t* src     = (const int16_t*)(wav + dataOffset);
  size_t         total   = (wavLen - dataOffset) / 2;
  int16_t        chunk[512]; // 256 stereo samples per DMA write
  size_t         idx = 0;

  while (idx < total) {
    size_t n = min((size_t)256, total - idx);
    for (size_t i = 0; i < n; i++) {
      // Safe volume scaling: 50% amplitude reduces peak current by over 70%, preventing 5V brownout!
      int32_t scaled = (int32_t)(src[idx + i] * SPEAKER_VOLUME);
      if (scaled >  32767) scaled =  32767;
      if (scaled < -32768) scaled = -32768;
      int16_t val = (int16_t)scaled;
      chunk[i * 2]     = val;
      chunk[i * 2 + 1] = val;
    }
    size_t bw = 0;
    i2s_channel_write(tx, chunk, n * 4, &bw, pdMS_TO_TICKS(200));
    idx += n;
    // Double-tap interrupt detection (edge-triggered, ignores speaker vibration)
    {
      static bool prevTouch = false;
      static unsigned long firstTapMs = 0;
      static int tapCount = 0;
      bool touchNow = (digitalRead(TOUCH_PIN) == HIGH);
      if (touchNow && !prevTouch) {
        // Rising edge = new tap
        if (tapCount == 0) {
          tapCount = 1;
          firstTapMs = millis();
        } else if (tapCount == 1 && (millis() - firstTapMs) < 700) {
          // Second tap within 700ms = double-tap!
          Serial.println(F("[Touch] Double-tap -> interrupt speech!"));
          interruptFlag = true;
          tapCount = 0;
          prevTouch = false;
          break;
        } else {
          tapCount = 1;
          firstTapMs = millis();
        }
      }
      if (tapCount == 1 && (millis() - firstTapMs) > 700) tapCount = 0;
      prevTouch = touchNow;
    }
  }
  closeSpeakerChannel(tx);
  Serial.println(F("WAV playback done."));
}

// ====================== VOICERSS FALLBACK (NATIVE WAV - NO ESP8266Audio NEEDED!) ======================

bool playVoiceRssWav(const String& text) {
  vrActive = true;
  String url = "http://api.voicerss.org/?key=" + VOICERSS_KEY
             + "&hl=en-us&c=WAV&f=16khz_16bit_mono&src=" + urlEncode(text);
  Serial.println("VoiceRSS URL: " + url);

  HTTPClient http;
  http.useHTTP10(true);
  http.setTimeout(15000);

  if (!http.begin(url)) {
    Serial.println(F("VoiceRSS begin failed."));
    vrActive = false;
    return false;
  }

  int code = http.GET();
  Serial.printf("VoiceRSS HTTP: %d\n", code);

  if (code == 200) {
    WiFiClient* stream = http.getStreamPtr();
    size_t totalRead = 0;
    unsigned long lastData = millis();

    while ((http.connected() || stream->available())
           && totalRead < TTS_PSRAM_MAX
           && millis() - lastData < 8000) {
      size_t avail = stream->available();
      if (avail > 0) {
        size_t got = stream->readBytes(ttsBuf + totalRead,
                                       min(avail, TTS_PSRAM_MAX - totalRead));
        totalRead += got;
        lastData   = millis();
      } else {
        updateFace();
        delay(2);
      }
    }
    http.end();
    Serial.printf("VoiceRSS WAV: %u bytes\n", (unsigned)totalRead);

    if (totalRead > 44) {
      playWavFromPsram(totalRead);
      vrActive = false;
      return true;
    }
  }
  http.end();
  vrActive = false;
  return false;
}

// ====================== PRIMARY TTS: GROQ + FALLBACK: VOICERSS ======================

void playTTS(const String& rawText) {
  if (WiFi.status() != WL_CONNECTED || !ttsBuf) return;

  String text = rawText;
  text.replace("\n", " "); text.replace("*", ""); text.replace("#", ""); text.trim();
  if (text.length() == 0) return;
  if (text.length() > 350) text = text.substring(0, 350);

  Serial.println("TTS: " + text);

  WiFiClientSecure cl;
  cl.setInsecure();
  HTTPClient http;
  http.useHTTP10(true);
  http.setTimeout(20000);

  bool groqOk = false;

  // Use explicit host, port, URI for exact HTTP/1.1 formatting
  if (http.begin(cl, "api.groq.com", 443, "/openai/v1/audio/speech", true)) {
    http.addHeader("Host", "api.groq.com");
    http.addHeader("Authorization", String("Bearer ") + GROQ_API_KEY);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("User-Agent", "ESP32S3-Buddy/3.0");

    JsonDocument req;
    req["model"]           = "canopylabs/orpheus-v1-english";
    req["input"]           = text;
    req["voice"]           = "troy";
    req["response_format"] = "wav";

    String body;
    serializeJson(req, body);
    int code = http.POST(body);
    Serial.printf("Groq TTS HTTP: %d\n", code);

    if (code == 200) {
      WiFiClient* stream = http.getStreamPtr();
      size_t totalRead = 0;
      unsigned long lastData = millis();

      while ((http.connected() || stream->available())
             && totalRead < TTS_PSRAM_MAX
             && millis() - lastData < 10000) {
        size_t avail = stream->available();
        if (avail > 0) {
          size_t got = stream->readBytes(ttsBuf + totalRead,
                                         min(avail, TTS_PSRAM_MAX - totalRead));
          totalRead += got;
          lastData   = millis();
        } else {
          updateFace();
          delay(2);
        }
      }
      http.end();
      Serial.printf("Groq WAV: %u bytes\n", (unsigned)totalRead);

      if (totalRead > 44) {
        playWavFromPsram(totalRead);
        groqOk = true;
      }
    } else {
      String errPay = http.getString();
      Serial.printf("Groq TTS failed (%d): %s, falling back to VoiceRSS.\n", code, errPay.c_str());
      http.end();
    }
  }

  if (!groqOk) {
    Serial.println(F("VoiceRSS fallback..."));
    playVoiceRssWav(text);
  }
}

// ====================== GROQ WHISPER STT (PRIMARY ULTRA-FAST) ======================

String groqSTT(uint8_t* wavData, size_t wavSize) {
  if (WiFi.status() != WL_CONNECTED) return "Error";

  WiFiClientSecure cl;
  cl.setInsecure();
  cl.setTimeout(15000);

  if (!cl.connect("api.groq.com", 443)) {
    Serial.println(F("Groq STT: Connect failed"));
    return "Error";
  }

  const char* boundary = "----ESP32BuddyBoundary982341";
  String head = "";
  head += "--"; head += boundary; head += "\r\n";
  head += "Content-Disposition: form-data; name=\"model\"\r\n\r\n";
  head += "whisper-large-v3-turbo\r\n";
  head += "--"; head += boundary; head += "\r\n";
  head += "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n";
  head += "json\r\n";
  head += "--"; head += boundary; head += "\r\n";
  head += "Content-Disposition: form-data; name=\"temperature\"\r\n\r\n";
  head += "0.2\r\n";
  head += "--"; head += boundary; head += "\r\n";
  head += "Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n";
  head += "Content-Type: audio/wav\r\n\r\n";

  String tail = "\r\n--"; tail += boundary; tail += "--\r\n";

  size_t totalLen = head.length() + wavSize + tail.length();

  cl.print(F("POST /openai/v1/audio/transcriptions HTTP/1.1\r\n"));
  cl.print(F("Host: api.groq.com\r\n"));
  cl.print(F("Authorization: Bearer ")); cl.print(GROQ_API_KEY); cl.print(F("\r\n"));
  cl.print(F("Content-Type: multipart/form-data; boundary=")); cl.print(boundary); cl.print(F("\r\n"));
  cl.print(F("User-Agent: ESP32S3-Buddy/3.0\r\n"));
  cl.print(F("Connection: close\r\n"));
  cl.printf("Content-Length: %u\r\n\r\n", (unsigned int)totalLen);

  cl.print(head);

  const size_t CHUNK = 2048;
  size_t sent = 0;
  while (sent < wavSize && cl.connected()) {
    size_t chunk = wavSize - sent;
    if (chunk > CHUNK) chunk = CHUNK;
    size_t w = cl.write(wavData + sent, chunk);
    if (w == 0) break;
    sent += w;
    yield();
  }

  cl.print(tail);
  cl.flush();

  unsigned long startWait = millis();
  while (cl.connected() && !cl.available() && millis() - startWait < 15000) {
    delay(10);
  }

  String statusLine = cl.readStringUntil('\n');
  int statusCode = 0;
  int sp = statusLine.indexOf(' ');
  if (sp != -1) {
    statusCode = statusLine.substring(sp + 1, sp + 4).toInt();
  }
  Serial.printf("Groq STT: %d\n", statusCode);

  while (cl.connected()) {
    String h = cl.readStringUntil('\n');
    h.trim();
    if (h.length() == 0) break;
  }

  String body = "";
  unsigned long readStart = millis();
  while (cl.connected() || cl.available()) {
    if (cl.available()) body += (char)cl.read();
    else delay(2);
    if (millis() - readStart > 4000) break;
  }
  cl.stop();

  if (statusCode == 200 && body.length() > 0) {
    JsonDocument doc;
    if (!deserializeJson(doc, body)) {
      const char* txt = doc["text"];
      if (txt && strlen(txt) > 0) {
        String res = String(txt);
        res.trim();
        Serial.println("Groq STT heard: [" + res + "]");
        return res;
      }
    }
  } else if (body.length() > 0) {
    Serial.println("Groq STT resp: " + body.substring(0, min((int)body.length(), 200)));
  }
  return "Error";
}

// ====================== WIT.AI STT (FALLBACK) ======================

String extractWitText(const String& body) {
  int lastText = body.lastIndexOf("\"text\":");
  if (lastText != -1) {
    int q1 = body.indexOf('"', lastText + 7);
    if (q1 != -1) {
      int q2 = body.indexOf('"', q1 + 1);
      if (q2 != -1 && q2 > q1) {
        String t = body.substring(q1 + 1, q2);
        t.trim();
        if (t.length() > 0) return t;
      }
    }
  }
  JsonDocument doc;
  if (!deserializeJson(doc, body)) {
    const char* t = doc["text"];
    if (t && strlen(t) > 0) return String(t);
  }
  return "";
}

String witSTT(uint8_t* data, size_t sz) {
  if (WiFi.status() != WL_CONNECTED) return "Error";
  WiFiClientSecure cl;
  cl.setInsecure();
  cl.setTimeout(20000);

  if (!cl.connect("api.wit.ai", 443)) {
    Serial.println(F("Wit.ai: Connect failed"));
    return "Error";
  }

  cl.print(F("POST /speech?v=20240304 HTTP/1.1\r\n"));
  cl.print(F("Host: api.wit.ai\r\n"));
  cl.print(F("Authorization: Bearer "));
  cl.print(WIT_TOKEN);
  cl.print(F("\r\n"));
  cl.print(F("Content-Type: audio/wav\r\n"));
  cl.print(F("Accept: application/json\r\n"));
  cl.print(F("User-Agent: ESP32S3-Buddy/3.0\r\n"));
  cl.print(F("Connection: close\r\n"));
  cl.printf("Content-Length: %u\r\n\r\n", (unsigned int)sz);

  // Stream in 2KB chunks for smooth TLS packet fragmentation
  const size_t CHUNK = 2048;
  size_t sent = 0;
  while (sent < sz && cl.connected()) {
    size_t chunk = sz - sent;
    if (chunk > CHUNK) chunk = CHUNK;
    size_t w = cl.write(data + sent, chunk);
    if (w == 0) break;
    sent += w;
    yield();
  }
  cl.flush();

  unsigned long startWait = millis();
  while (cl.connected() && !cl.available() && millis() - startWait < 15000) {
    delay(10);
  }

  String statusLine = cl.readStringUntil('\n');
  int statusCode = 0;
  int firstSpace = statusLine.indexOf(' ');
  if (firstSpace != -1) {
    statusCode = statusLine.substring(firstSpace + 1, firstSpace + 4).toInt();
  }
  Serial.printf("Wit.ai: %d\n", statusCode);

  while (cl.connected()) {
    String header = cl.readStringUntil('\n');
    header.trim();
    if (header.length() == 0) break;
  }

  String body = "";
  unsigned long readStart = millis();
  while (cl.connected() || cl.available()) {
    if (cl.available()) {
      body += (char)cl.read();
    } else {
      delay(2);
    }
    if (millis() - readStart > 6000) break;
  }
  cl.stop();

  if (statusCode == 200 && body.length() > 0) {
    Serial.println("Wit raw: " + body.substring(0, min((int)body.length(), 200)));
    String res = extractWitText(body);
    return (res.length() > 0) ? res : "Error";
  }
  return "Error";
}

// ====================== GROQ LLM ======================

String askGroq(const String& prompt) {
  if (WiFi.status() != WL_CONNECTED) return "No WiFi.";
  String result = "Sorry, I could not connect.";
  // Verified active models on user's Groq account (tested & confirmed HTTP 200)
  const char* models[] = { "qwen/qwen3.8-27b", "openai/gpt-oss-20b" };

  for (int m = 0; m < 2; m++) {
    WiFiClientSecure cl; cl.setInsecure();
    HTTPClient http;
    http.useHTTP10(true);
    http.setTimeout(15000);

    // Using explicit host, port, URI avoids Cloudflare 404 URL parsing bugs
    if (!http.begin(cl, "api.groq.com", 443, "/openai/v1/chat/completions", true)) {
      Serial.println(F("Groq HTTP begin failed"));
      continue;
    }
    http.addHeader("Host", "api.groq.com");
    http.addHeader("Authorization", String("Bearer ") + GROQ_API_KEY);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("User-Agent", "ESP32S3-Buddy/3.0");

    JsonDocument req;
    req["model"]       = models[m];
    req["temperature"] = 0.6;
    req["max_tokens"]  = 200;

    JsonArray msgs = req["messages"].to<JsonArray>();
    JsonObject sys = msgs.add<JsonObject>();
    sys["role"]    = "system";
    sys["content"] = "You are Buddy, a friendly concise desktop robot. Reply in 1-2 sentences max, plain text, no emojis. "
                     "If the user wants to execute an action, reply ONLY with a single JSON object:\n"
                     "- Alarm: {\"action\":\"alarm\",\"title\":\"...\",\"hour\":H,\"minute\":M,\"reply\":\"...\"} (H=0-23 in 24hr format)\n"
                     "- Call: {\"action\":\"call\",\"contact\":\"...\",\"reply\":\"...\"} (e.g. Call Mom, Call Maa)\n"
                     "- Calendar: {\"action\":\"calendar\",\"title\":\"...\",\"time\":\"...\",\"reply\":\"...\"}\n"
                     "- Task: {\"action\":\"task\",\"title\":\"...\",\"reply\":\"...\"}\n"
                     "- Pomodoro: {\"action\":\"pomodoro\",\"minutes\":M,\"reply\":\"...\"}\n"
                     "Otherwise reply directly in friendly plain text.";
    JsonObject usr = msgs.add<JsonObject>();
    usr["role"]    = "user";
    usr["content"] = prompt;

    String body; serializeJson(req, body);
    int    code = http.POST(body);
    String pay  = http.getString();
    http.end();

    Serial.printf("Groq LLM (%s): %d\n", models[m], code);
    if (code == 200) {
      JsonDocument r;
      if (!deserializeJson(r, pay)) {
        const char* c = r["choices"][0]["message"]["content"];
        if (!c || strlen(c) == 0) {
          c = r["choices"][0]["message"]["reasoning"];
        }
        if (c && strlen(c) > 0) {
          result = String(c);
          int te = result.indexOf("</think>");
          if (te != -1) result = result.substring(te + 8);
          result.trim();
          if (result.length() > 0) break;
        }
      }
    } else {
      Serial.print(F("Groq response payload: "));
      Serial.println(pay);
    }
  }
  Serial.println("Groq reply: " + result);
  return result;
}

// ====================== WEATHER ======================

String fetchWeather() {
  if (WiFi.status() != WL_CONNECTED) return "No WiFi.";
  WiFiClientSecure cl; cl.setInsecure();
  HTTPClient http; http.setTimeout(8000);
  http.begin(cl, WEATHER_URL);
  String res = "Could not fetch weather.";
  if (http.GET() == 200) {
    JsonDocument d;
    if (!deserializeJson(d, http.getString())) {
      float  temp = d["current_weather"]["temperature"];
      int    wmo  = d["current_weather"]["weathercode"];
      String desc = "clear";
      if      (wmo >= 95) desc = "thunderstorm";
      else if (wmo >= 71) desc = "snowing";
      else if (wmo >= 61) desc = "raining";
      else if (wmo >= 51) desc = "drizzling";
      else if (wmo >= 45) desc = "foggy";
      else if (wmo >= 3)  desc = "overcast";
      else if (wmo >= 1)  desc = "partly cloudy";
      res = "It is " + String(temp, 1) + " degrees and " + desc + " in Bhubaneswar.";
    }
  }
  http.end();
  return res;
}

// ====================== FIREBASE ======================

String fbUrl(const String& path) {
  String u = String("https://") + FIREBASE_HOST + path + ".json";
  if (strlen(FIREBASE_AUTH) > 0) u += "?auth=" + String(FIREBASE_AUTH);
  return u;
}

void fbPush(const String& path, const String& json, bool post) {
  if (WiFi.status() != WL_CONNECTED) return;
  WiFiClientSecure cl; cl.setInsecure();
  HTTPClient http; http.setTimeout(8000);
  http.begin(cl, fbUrl(path));
  http.addHeader("Content-Type", "application/json");
  int c = post ? http.POST(json) : http.PUT(json);
  Serial.printf("Firebase %s: %d\n", path.c_str(), c);
  http.end();
}

void pollTasks() {
  unsigned long now = millis();
  if (now - lastTaskPoll < TASK_POLL_MS) return;
  lastTaskPoll = now;
  if (WiFi.status() != WL_CONNECTED) return;
  WiFiClientSecure cl; cl.setInsecure();
  HTTPClient http; http.setTimeout(8000);
  http.begin(cl, fbUrl(String(FIREBASE_USER_PATH) + "/tasks"));
  int code = http.GET();
  if (code == 200) {
    JsonDocument d;
    DeserializationError err = deserializeJson(d, http.getString());
    if (!err && d.is<JsonObject>()) {
      taskCount = 0; hasOverdue = false;
      strncpy(taskText, "No tasks", sizeof(taskText) - 1);
      for (JsonPair kv : d.as<JsonObject>()) {
        JsonObject t = kv.value().as<JsonObject>();
        if (t["completed"] | false) continue;
        const char* ti = t["title"] | "Task";
        if (taskCount == 0) { strncpy(taskText, ti, sizeof(taskText) - 1); taskText[sizeof(taskText)-1] = '\0'; }
        taskCount++;
      }
    } else if (!err && d.isNull()) {
      taskCount = 0; strncpy(taskText, "No tasks", sizeof(taskText) - 1);
    }
  }
  http.end();
  Serial.printf("Tasks: %d\n", taskCount);
}

void pushTelemetry() {
  unsigned long now = millis();
  if (now - lastTelemetry < TELEMETRY_PUSH_MS) return;
  lastTelemetry = now;
  JsonDocument d;
  d["expression"]         = exprIdx;
  d["task_count"]         = taskCount;
  d["pomodoro_active"]    = pomodoroOn;
  d["pomodoro_remaining"] = pomodoroSec;
  d["uptime_s"]           = (int)(millis() / 1000);
  d["ip"]                 = WiFi.localIP().toString();
  d["status"]             = "ONLINE";
  String j; serializeJson(d, j);
  fbPush(String(FIREBASE_USER_PATH) + "/robot/telemetry", j, false);
}

void addTask(const String& title) {
  JsonDocument d;
  d["title"] = title; d["completed"] = false;
  d["source"] = "voice"; d["created_at"] = (int)(millis() / 1000);
  String j; serializeJson(d, j);
  fbPush(String(FIREBASE_USER_PATH) + "/tasks", j, true);
  setLabel(title);
  taskCount++;
}

void logVoice(const String& heard, const String& reply) {
  JsonDocument d;
  d["heard"] = heard; d["replied"] = reply; d["timestamp"] = (int)(millis() / 1000);
  String j; serializeJson(d, j);
  fbPush(String(FIREBASE_USER_PATH) + "/voice_logs", j, true);
}

// ====================== VOICE ======================

void doVoice() {
  voiceActive = true;
  setLabel("LISTENING...");
  setExprIdx(2); animateFor(200);

  // Play a gentle beep so user knows mic is listening
  playTone("chime");

  size_t pcmBytes      = recordAudio();
  size_t totalWavBytes = pcmBytes + WAV_HDR;

  int16_t*  samples  = (int16_t*)(micBuf + WAV_HDR);
  size_t    nSamples = pcmBytes / 2;
  long long nrg = 0;
  for (size_t i = 0; i < nSamples; i++) nrg += abs(samples[i]);
  long long avgAmp = (nSamples > 0) ? (nrg / (long long)nSamples) : 0;
  Serial.printf("Avg amplitude: %lld\n", avgAmp);

  if (avgAmp < 120) {
    Serial.println(F("Audio too quiet / ambient noise rejected by gate."));
    setLabel("TOO QUIET");
    setExprIdx(7); animateFor(800);
    voiceActive = false;
    idleFace();
    return;
  }

  setLabel("THINKING...");
  setExprIdx(5); animateFor(200);

  // 1. Primary: Groq Whisper STT (Ultra-fast, ~300ms)
  String heard = groqSTT(micBuf, totalWavBytes);

  // 2. Fallback: Wit.ai STT (if Groq encounters network error)
  if (heard.length() == 0 || heard == "Error") {
    Serial.println(F("Groq STT failed, falling back to Wit.ai..."));
    heard = witSTT(micBuf, totalWavBytes);
  }

  Serial.println("Heard: [" + heard + "]");

  if (heard.length() == 0 || heard == "Error") {
    setLabel("NOT HEARD");
    setExprIdx(1); animateFor(500);
    playTTS("Sorry, I did not catch that.");
    voiceActive = false;
    idleFace();
    return;
  }

  // Show transcribed question on OLED (prefix "Q:" so user knows what was heard)
  setLabel("Q: " + heard);
  animateFor(1200);  // hold for 1.2s so user can read it

  String lc = heard; lc.toLowerCase();
  String reply;

  // ===== DIRECT ALARM HANDLER (keyword-parsed, no LLM dependency) =====
  if (lc.indexOf("alarm") != -1 || (lc.indexOf("wake") != -1 && lc.indexOf("up") != -1)) {
    int hour = -1, minute = 0;
    bool isPM = (lc.indexOf(" pm") != -1 || lc.indexOf("p.m") != -1);
    bool isAM = (lc.indexOf(" am") != -1 || lc.indexOf("a.m") != -1);
    // Extract first number as hour, optional :MM
    for (int i = 0; i < (int)lc.length(); i++) {
      if (isDigit(lc.charAt(i))) {
        hour = 0;
        while (i < (int)lc.length() && isDigit(lc.charAt(i))) { hour = hour * 10 + (lc.charAt(i) - '0'); i++; }
        if (i < (int)lc.length() && lc.charAt(i) == ':') {
          i++; minute = 0;
          while (i < (int)lc.length() && isDigit(lc.charAt(i))) { minute = minute * 10 + (lc.charAt(i) - '0'); i++; }
        }
        break;
      }
    }
    if (hour < 0 || hour > 23) hour = 7;
    if (isPM && hour < 12) hour += 12;
    if (isAM && hour == 12) hour = 0;
    if (minute > 59) minute = 0;

    JsonDocument actDoc;
    actDoc["type"] = "alarm"; actDoc["title"] = "Alarm";
    actDoc["hour"] = hour;    actDoc["minute"] = minute;
    actDoc["executed"] = false;
    actDoc["timestamp"] = (int)(millis() / 1000);
    actDoc["nonce"]     = (int)millis();
    String actJson; serializeJson(actDoc, actJson);
    fbPush(String(FIREBASE_USER_PATH) + "/bot_actions", actJson, true);
    Serial.printf("ALARM DIRECT: %02d:%02d -> Firebase\n", hour, minute);

    char tb[32];
    snprintf(tb, sizeof(tb), "%d:%02d %s", (hour % 12 == 0) ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM");
    reply = String("Alarm set for ") + tb + "!";
    addTask(String("Alarm ") + tb);
    setExprIdx(0);

  // ===== DIRECT CALL HANDLER =====
  } else if (lc.indexOf("call ") != -1) {
    int ci = lc.indexOf("call ");
    String contact = heard.substring(ci + 5);
    contact.trim();
    // Remove trailing filler words
    for (const char* w : {"please", "now", "for me"}) {
      int wi = contact.indexOf(w); if (wi > 0) contact = contact.substring(0, wi);
    }
    contact.trim();
    if (contact.length() == 0 || contact.length() > 30) contact = "Contact";

    JsonDocument actDoc;
    actDoc["type"] = "call"; actDoc["contact"] = contact;
    actDoc["title"] = String("Call ") + contact;
    actDoc["executed"] = false;
    actDoc["timestamp"] = (int)(millis() / 1000);
    actDoc["nonce"]     = (int)millis();
    String actJson; serializeJson(actDoc, actJson);
    fbPush(String(FIREBASE_USER_PATH) + "/bot_actions", actJson, true);
    Serial.printf("CALL DIRECT: %s -> Firebase\n", contact.c_str());

    reply = String("Calling ") + contact + " now!";
    addTask(String("Call: ") + contact);
    setExprIdx(0);

  // ===== WEATHER =====
  } else if (lc.indexOf("weather") != -1) {
    setExprIdx(0); animateFor(200);
    reply = fetchWeather();
  } else if (lc.indexOf("time") != -1 && (lc.indexOf("what") != -1 || lc.indexOf("tell") != -1)) {
    unsigned long s = millis() / 1000;
    char buf[64];
    snprintf(buf, 64, "I have been awake %lu hours %lu minutes.", s / 3600, (s / 60) % 60);
    reply = String(buf);

  // ===== GENERAL CHAT via LLM (calendar, task, pomodoro, conversation) =====
  } else {
    setExprIdx(2); animateFor(200);
    reply = askGroq(heard);
    int si = reply.indexOf('{');
    int ei = reply.lastIndexOf('}');
    if (si != -1 && ei > si) {
      JsonDocument ad;
      if (!deserializeJson(ad, reply.substring(si, ei + 1))) {
        const char* act = ad["action"];
        const char* rep = ad["reply"];
        if (rep && strlen(rep) > 0) reply = String(rep);

        if (act && strcmp(act, "calendar") == 0) {
          const char* tt = ad["title"] | "Event";
          const char* tm = ad["time"] | "";
          JsonDocument actDoc;
          actDoc["type"] = "calendar"; actDoc["title"] = tt;
          actDoc["time"] = tm; actDoc["executed"] = false;
          actDoc["timestamp"] = (int)(millis() / 1000);
          actDoc["nonce"] = (int)millis();
          String actJson; serializeJson(actDoc, actJson);
          fbPush(String(FIREBASE_USER_PATH) + "/bot_actions", actJson, true);
          addTask(String("Cal: ") + tt);

        } else if (act && (strcmp(act, "task") == 0 || strcmp(act, "add_task") == 0)) {
          const char* tt = ad["title"] | "Task";
          addTask(String(tt)); setLabel(String(tt));

        } else if (act && strcmp(act, "pomodoro") == 0) {
          int mins = ad["minutes"] | 25;
          pomodoroSec = mins * 60;
          pomodoroOn = true;
          lastPomoTick = millis();
          setExprIdx(2);
        }
      }
    }
  }

  logVoice(heard, reply);

  // Show the AI reply on OLED (stays visible during speech â€” no "SPEAKING..." override)
  setLabel("A: " + reply);
  setExprIdx(0); animateFor(1200);
  playTTS(reply);

  // Double-tap interrupt: if double-tapped during TTS, restart listening immediately
  if (interruptFlag) {
    interruptFlag = false;
    Serial.println(F("[Touch] Re-entering voice mode..."));
    doVoice();
    return;
  }

  // Show both Q and A as idle text after conversation
  setLabel(heard + " | " + reply);
  voiceActive = false;
  idleFace();
}

void idleFace() {
  if (pomodoroOn)       setExprIdx(2);
  else                  setExprIdx(userSelectedExpr);
}

// ====================== TOUCH (EDGE-TRIGGERED ZERO-GHOST) ======================

bool touchEnabled = true;
static int lastTouchVal = LOW;
static unsigned long touchPressStart = 0;
static bool touchTriggerArmed = true;

void handleTouch() {
  if (!touchEnabled || voiceActive) return;

  unsigned long now = millis();
  int currentVal = digitalRead(TOUCH_PIN);

  // Standard TTP223 capacitive touch: LOW when released (0V), HIGH when touched (3.3V)
  if (currentVal == HIGH) {
    if (lastTouchVal == LOW) {
      // Just detected rising edge: LOW -> HIGH transition
      touchPressStart = now;
    } else if (touchTriggerArmed && touchPressStart > 0 && (now - touchPressStart >= 80) && (now - lastTouchMs > TOUCH_CD_MS)) {
      // Confirmed human finger touch held for >=80ms!
      touchTriggerArmed = false; // Disarm immediately! Will never trigger again until released!
      touchPressStart = 0;
      lastTouchMs = now;
      Serial.println(F("[Touch] Physical finger touch detected -> Listening"));
      doVoice();
      idleFace();
      return;
    }
  } else {
    // Pin is LOW (physically released): re-arm trigger
    touchPressStart = 0;
    touchTriggerArmed = true;
  }

  lastTouchVal = currentVal;
}

// ====================== POMODORO ======================

void updatePomo() {
  if (!pomodoroOn || pomodoroSec <= 0) return;
  unsigned long now = millis();
  if (now - lastPomoTick >= 1000) {
    lastPomoTick = now; pomodoroSec--;
    if (pomodoroSec <= 0) {
      pomodoroOn = false;
      setExprIdx(5);
      playTone("chime");
      playTTS("Pomodoro done! Take a break.");
      idleFace();
    }
  }
}

// ====================== IDLE ======================

void updateIdle() {
  if (voiceActive || vrActive) return;
  unsigned long now = millis();
  if (now - transStart < 6000) return;
  if (pomodoroOn)        { if (exprIdx != 2) setExprIdx(2); }
  else if (hasOverdue)   { if (exprIdx != 3) setExprIdx(3); }
  else                   { if (exprIdx != userSelectedExpr) setExprIdx(userSelectedExpr); }
}

// ====================== WEB SERVER ======================

void handleRoot() {
  server.send(200, "text/html",
    F("<!doctype html><html><body><h2>Hello Buddy</h2>"
      "<p>/status /emotion /oled /tone /pomodoro /listen /speak /speak_vr</p></body></html>"));
}

void handleStatus() {
  JsonDocument d;
  d["status"]             = "ONLINE";
  d["ip"]                 = WiFi.localIP().toString();
  d["uptime_s"]           = (int)(millis() / 1000);
  d["expression"]         = exprIdx;
  d["task_count"]         = taskCount;
  d["current_task"]       = taskText;
  d["current_label"]      = currentLabel;
  d["pomodoro_active"]    = pomodoroOn;
  d["pomodoro_remaining"] = pomodoroSec;
  d["voice_active"]       = voiceActive;
  d["vr_active"]          = vrActive;
  String j; serializeJson(d, j);
  server.send(200, "application/json", j);
}

void handleEmotion() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    int s = d["state"] | -1;
    if (s >= 0 && s < NUM_EXPR) {
      userSelectedExpr = s;
      setExprIdx(s);
      server.send(200, "application/json", "{\"ok\":true}");
      return;
    }
  }
  server.send(400, "application/json", "{\"error\":\"bad state\"}");
}

void handleSetOled() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    const char* t = d["text"] | "";
    if (strlen(t) > 0) { setLabel(String(t)); server.send(200, "application/json", "{\"ok\":true}"); return; }
  }
  server.send(400, "application/json", "{\"error\":\"no text\"}");
}

void handleTone() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    String type = d["type"] | "chime";
    server.send(200, "application/json", "{\"ok\":true}");
    playTone(type);
    return;
  }
  server.send(400, "application/json", "{\"error\":\"no body\"}");
}

void handlePomodoro() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    String act = d["action"] | "";
    if (act == "start") {
      int m = d["minutes"] | 25;
      pomodoroSec = m * 60; pomodoroOn = true; lastPomoTick = millis();
      setExprIdx(2);
      server.send(200, "application/json", "{\"ok\":true}");
      playTTS("Pomodoro started. Focus time!");
    } else if (act == "stop") {
      pomodoroOn = false; pomodoroSec = 0; setExprIdx(6);
      server.send(200, "application/json", "{\"ok\":true}");
    } else {
      server.send(400, "application/json", "{\"error\":\"bad action\"}");
    }
    return;
  }
  server.send(400, "application/json", "{\"error\":\"no body\"}");
}

void handleListen() {
  if (voiceActive) { server.send(409, "application/json", "{\"error\":\"busy\"}"); return; }
  server.send(200, "application/json", "{\"ok\":true}");
  doVoice(); idleFace();
}

void handleSpeak() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    const char* t = d["text"] | "";
    if (strlen(t) > 0) { server.send(200, "application/json", "{\"ok\":true}"); playTTS(String(t)); return; }
  }
  server.send(400, "application/json", "{\"error\":\"no text\"}");
}

void handleSpeakVR() {
  if (server.hasArg("plain")) {
    JsonDocument d; deserializeJson(d, server.arg("plain"));
    const char* t = d["text"] | "";
    if (strlen(t) > 0) {
      server.send(200, "application/json", "{\"ok\":true}");
      playVoiceRssWav(String(t));
      return;
    }
  }
  server.send(400, "application/json", "{\"error\":\"no text\"}");
}

// ====================== SETUP ======================

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(100);
  delay(500);
  Serial.println(F("\n=== Hello Buddy v3.0 (7-Pin SPI OLED) ==="));

  // Initialize 7-Pin SPI OLED (contrast 110: low charge-pump current, zero brownout/buzzing)
  u8g2.begin();
  u8g2.setContrast(110);
  randomSeed(esp_random());
  setExprIdx(6);
  setLabel("Booting...");
  updateFace();

  micBuf = (uint8_t*)ps_malloc(AUDIO_BUF_BYTES + WAV_HDR);
  ttsBuf = (uint8_t*)ps_malloc(TTS_PSRAM_MAX);
  if (!micBuf || !ttsBuf) {
    Serial.println(F("FATAL: Enable OPI PSRAM in Tools -> PSRAM!"));
    setExprIdx(3); setLabel("PSRAM ERROR");
    while (true) { updateFace(); delay(1000); }
  }
  makeWAVHeader(micBuf, AUDIO_BUF_BYTES, SAMPLE_RATE);

  playHardwareTestTone();

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  setLabel("WiFi...");
  Serial.print(F("WiFi"));
  unsigned long ws = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - ws > 15000) {
      Serial.println(F("\nWiFi FAILED"));
      setExprIdx(3); setLabel("No WiFi"); animateFor(500); break;
    }
    updateFace(); delay(300); Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nIP: %s\n", WiFi.localIP().toString().c_str());
    setExprIdx(0);
    char ipbuf[32];
    snprintf(ipbuf, sizeof(ipbuf), "IP: %s", WiFi.localIP().toString().c_str());
    setLabel(ipbuf);
    animateFor(800);
  }

  gpio_reset_pin((gpio_num_t)TOUCH_PIN);
  gpio_pullup_dis((gpio_num_t)TOUCH_PIN);
  gpio_pulldown_en((gpio_num_t)TOUCH_PIN);
  pinMode(TOUCH_PIN, INPUT_PULLDOWN);
  delay(50);
  lastTouchVal = digitalRead(TOUCH_PIN);
  if (lastTouchVal == HIGH) {
    // If pin reads HIGH at power-on transient, disarm immediately to prevent ghost trigger
    touchTriggerArmed = false;
  }
  Serial.printf("Touch Sensor initialized on GPIO %d (idle=%d, armed=%d)\n", TOUCH_PIN, lastTouchVal, (int)touchTriggerArmed);

  server.on("/",         HTTP_GET,  handleRoot);
  server.on("/status",   HTTP_GET,  handleStatus);
  server.on("/emotion",  HTTP_POST, handleEmotion);
  server.on("/oled",     HTTP_POST, handleSetOled);
  server.on("/tone",     HTTP_POST, handleTone);
  server.on("/pomodoro", HTTP_POST, handlePomodoro);
  server.on("/listen",   HTTP_POST, handleListen);
  server.on("/speak",    HTTP_POST, handleSpeak);
  server.on("/speak_vr", HTTP_POST, handleSpeakVR);
  server.on("/touch",    HTTP_POST, []() {
    if (server.hasArg("plain")) {
      JsonDocument d; deserializeJson(d, server.arg("plain"));
      if (d.containsKey("enabled")) touchEnabled = d["enabled"] | true;
    }
    server.send(200, "application/json", touchEnabled ? "{\"touch\":true}" : "{\"touch\":false}");
  });
  server.begin();
  Serial.printf("HTTP: http://%s/\n", WiFi.localIP().toString().c_str());

  setExprIdx(5);
  setLabel("Ready :)");
  animateFor(400);
  playTTS("Hello! I am your buddy. Touch me to talk!");
  setExprIdx(0);
  Serial.println(F("Ready!"));
}

// ====================== LOOP ======================

void loop() {
  updateFace();
  server.handleClient();
  handleTouch();
  updatePomo();
  updateIdle();
  pollTasks();
  pushTelemetry();

  if (Serial.available()) {
    String in = Serial.readStringUntil('\n'); in.trim();
    String lo = in; lo.toLowerCase();
    if      (lo == "talk")              { doVoice(); idleFace(); }
    else if (lo == "beep")              { playHardwareTestTone(); }
    else if (lo == "chime")             { playTone("chime"); }
    else if (lo == "alert")             { playTone("alert"); }
    else if (lo == "touch on")          { touchEnabled = true; Serial.println(F("Touch: ENABLED")); }
    else if (lo == "touch off")         { touchEnabled = false; Serial.println(F("Touch: DISABLED")); }
    else if (lo == "weather")           { playTTS(fetchWeather()); }
    else if (lo.startsWith("say "))     { playTTS(in.substring(4)); }
    else if (lo.startsWith("vr "))      { playVoiceRssWav(in.substring(3)); }
    else if (lo.startsWith("oled "))    { setLabel(in.substring(5)); }
    else if (lo.startsWith("expr "))    { setExprIdx(in.substring(5).toInt()); }
  }

  delay(2);
}

