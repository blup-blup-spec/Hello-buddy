import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Voice input service using the phone's microphone.
///
/// Uses the `speech_to_text` MethodChannel to capture and transcribe
/// voice input directly on the phone.
///
/// Flow:
///   1. User taps mic button
///   2. Phone mic starts recording
///   3. Audio is transcribed locally (Android SpeechRecognizer)
///      OR sent to Groq Whisper API
///   4. Transcribed text is returned
///
/// For Groq Whisper: use the `record` package to capture audio,
/// then send the file to Groq's audio transcription endpoint.
/// For on-device: use Android's built-in SpeechRecognizer.
class VoiceService {
  static const _channel = MethodChannel('com.hellobuddy/voice');

  bool _isListening = false;
  final _textController = StreamController<String>.broadcast();

  /// Whether currently listening
  bool get isListening => _isListening;

  /// Stream of transcribed text results
  Stream<String> get onResult => _textController.stream;

  /// Start listening via Android SpeechRecognizer
  Future<void> startListening() async {
    if (_isListening) return;

    if (kIsWeb) {
      _isListening = true;
      // In web demo mode, simulate quick transcription
      Future.delayed(const Duration(seconds: 1), () {
        if (_isListening) {
          _textController.add("Review DSP Chapter 4 Butterworth Filters");
          _isListening = false;
        }
      });
      return;
    }

    try {
      _isListening = true;
      _channel.setMethodCallHandler(_handlePlatformCallback);
      await _channel.invokeMethod('startListening', {'language': 'en-IN'});
    } catch (e) {
      _isListening = false;
      throw Exception('Voice input failed: $e');
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _channel.invokeMethod('stopListening');
    } finally {
      _isListening = false;
    }
  }

  /// Handle callbacks from the native side
  Future<dynamic> _handlePlatformCallback(MethodCall call) async {
    switch (call.method) {
      case 'onResult':
        final text = call.arguments as String? ?? '';
        if (text.isNotEmpty) {
          _textController.add(text);
        }
        break;
      case 'onError':
        _isListening = false;
        break;
      case 'onDone':
        _isListening = false;
        break;
    }
  }

  /// One-shot listen: start, wait for result, stop
  /// Returns the transcribed text or null on failure/timeout
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<String?>();

    StreamSubscription<String>? sub;
    Timer? timer;

    sub = onResult.listen((text) {
      if (!completer.isCompleted) {
        completer.complete(text);
        sub?.cancel();
        timer?.cancel();
        stopListening();
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
        sub?.cancel();
        stopListening();
      }
    });

    await startListening();
    return completer.future;
  }

  void dispose() {
    _textController.close();
  }
}
