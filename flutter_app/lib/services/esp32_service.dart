import 'dart:convert';
import 'package:http/http.dart' as http;

/// Local WiFi HTTP client for the ESP32-S3 Hello Buddy Companion.
///
/// Communicates directly with the HTTP server running on the ESP32-S3
/// (endpoints defined in hello_buddy.ino).
class Esp32Service {
  String _ip;
  String _baseUrl;

  Esp32Service({String ip = '192.168.1.100'})
      : _ip = ip,
        _baseUrl = 'http://$ip';

  String get ip => _ip;
  String get baseUrl => _baseUrl;

  /// Update ESP32 IP address (from user input or Firebase telemetry)
  void setIp(String newIp) {
    _ip = newIp.trim().replaceAll('http://', '').replaceAll('/', '');
    _baseUrl = 'http://$_ip';
  }

  /// Get device status
  Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/status'),
    ).timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Status failed: ${response.statusCode}');
  }

  /// Set face expression:
  /// 0 = Happy, 1 = Sad, 2 = Focused, 3 = Angry,
  /// 4 = Sleepy, 5 = Excited, 6 = Neutral, 7 = Confused
  Future<void> setEmotion(int state) async {
    await http.post(
      Uri.parse('$_baseUrl/emotion'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'state': state}),
    ).timeout(const Duration(seconds: 4));
  }

  /// Push text to robot OLED display status bar
  Future<void> setOledText(String text) async {
    final clean = text.length > 28 ? text.substring(0, 28) : text;
    await http.post(
      Uri.parse('$_baseUrl/oled'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': clean}),
    ).timeout(const Duration(seconds: 4));
  }

  /// Start or stop Pomodoro timer on the robot
  Future<void> controlPomodoro({
    required String action, // "start" or "stop"
    int minutes = 25,
  }) async {
    await http.post(
      Uri.parse('$_baseUrl/pomodoro'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action, 'minutes': minutes}),
    ).timeout(const Duration(seconds: 4));
  }

  /// Trigger voice interaction on robot (robot starts listening with its INMP441 mic)
  Future<void> triggerListen() async {
    await http.post(
      Uri.parse('$_baseUrl/listen'),
    ).timeout(const Duration(seconds: 4));
  }

  /// Play audio tone on robot speaker ("chime" or "alert")
  Future<void> playTone(String type) async {
    await http.post(
      Uri.parse('$_baseUrl/tone'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'type': type}),
    ).timeout(const Duration(seconds: 4));
  }

  /// Speak arbitrary text through the robot speaker via Google TTS
  Future<void> speak(String text) async {
    await http.post(
      Uri.parse('$_baseUrl/speak'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    ).timeout(const Duration(seconds: 6));
  }

  /// Ping robot to check if online
  Future<bool> isOnline() async {
    try {
      await getStatus();
      return true;
    } catch (_) {
      return false;
    }
  }
}
