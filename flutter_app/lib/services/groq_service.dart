import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Structured Flowchart diagram
class FlowchartData {
  final String title;
  final List<String> steps;

  const FlowchartData({required this.title, required this.steps});
}

/// Agentic action types Buddy can execute
enum BuddyAgentActionType { alarm, call, calendar, none }

/// Full structured response from the Buddy Agent
class BuddyAgentResponse {
  final String reply;
  final BuddyAgentActionType action;
  final Map<String, dynamic> actionParams;
  final String oledText;
  final FlowchartData? flowchart;

  const BuddyAgentResponse({
    required this.reply,
    required this.action,
    required this.actionParams,
    required this.oledText,
    this.flowchart,
  });

  /// Factory from Groq JSON object
  factory BuddyAgentResponse.fromJson(Map<String, dynamic> json) {
    final actionStr = (json['action'] as String? ?? 'none').toLowerCase().trim();
    final actionType = switch (actionStr) {
      'alarm' => BuddyAgentActionType.alarm,
      'call' => BuddyAgentActionType.call,
      'calendar' => BuddyAgentActionType.calendar,
      _ => BuddyAgentActionType.none,
    };

    final params = (json['action_params'] is Map)
        ? Map<String, dynamic>.from(json['action_params'] as Map)
        : <String, dynamic>{};

    FlowchartData? fc;
    if (json['flowchart'] is Map) {
      final fMap = json['flowchart'] as Map;
      final title = fMap['title'] as String? ?? 'Process Flow';
      final stepsRaw = fMap['steps'];
      final steps = <String>[];
      if (stepsRaw is List) {
        for (final s in stepsRaw) {
          if (s != null) steps.add(s.toString());
        }
      }
      if (steps.isNotEmpty) {
        fc = FlowchartData(title: title, steps: steps);
      }
    }

    return BuddyAgentResponse(
      reply: json['reply'] as String? ?? 'I am ready to help!',
      action: actionType,
      actionParams: params,
      oledText: json['oled_text'] as String? ?? 'Buddy: Ready',
      flowchart: fc,
    );
  }
}

/// Groq Cloud API service supporting True Agentic JSON Tool-Calling
class GroqQwenService {
  final String apiKey;
  static const String endpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  // Primary text model — OpenAI GPT-OSS 20B
  static const String textModel = 'openai/gpt-oss-20b';

  // Multimodal vision model — Qwen 3.8 27B
  static const String visionModel = 'qwen/qwen3.8-27b';

  GroqQwenService({
    this.apiKey = 'YOUR_GROQ_API_KEY',
  });

  /// True Agentic API call using Groq structured JSON mode
  Future<BuddyAgentResponse> askAgent({
    required String subject,
    required String userPrompt,
    String? imageBase64,
    String? imageUrl,
    List<Map<String, String>> history = const [],
  }) async {
    final isVision = imageBase64 != null || imageUrl != null;
    final modelToUse = isVision ? visionModel : textModel;

    final systemPrompt = '''You are Buddy, an electric, tactile desktop companion study robot and personal agent.
Domain: Engineering, IoT, Computer Science, DSP, Physics, Math, General Knowledge, and Student Scheduling.
Current Subject: "$subject".

AGENT CAPABILITIES:
You have native phone executor tools:
1. "alarm": Sets an alarm on the user's phone clock and arms the robot alarm buzzer.
2. "call": Calls or dials a contact on the user's phone.
3. "calendar": Schedules a meeting/event in Google Calendar.
4. "none": Regular study tutor conversation, question answering, or problem solving.

OUTPUT FORMAT REQUIREMENTS:
You MUST respond with a single, strictly valid JSON object adhering to this schema:
{
  "reply": "Conversational answer or study explanation (concise, encouraging, clear)",
  "action": "alarm" | "call" | "calendar" | "none",
  "action_params": {
    "hour": <integer 0-23 if alarm>,
    "minute": <integer 0-59 if alarm>,
    "alarm_title": "<short label e.g. Wake up or Study Session>",
    "contact_name": "<name to call e.g. mom, ma, prof, rahul>",
    "phone_number": "<digits if given, otherwise empty>",
    "meeting_title": "<meeting title max 26 chars>",
    "meeting_start_iso": "<ISO 8601 string or YYYY-MM-DDTHH:MM:SS>",
    "meeting_duration_minutes": <integer minutes default 60>
  },
  "oled_text": "<punchy text for ESP32 OLED, max 20 chars>",
  "flowchart": {
    "title": "<diagram title>",
    "steps": ["Step 1", "Step 2", "Step 3"]
  } or null
}

RULES:
- When user says "set alarm at 6am", "wake me up at 7:30", "a alarm setup", "alarm setup", or mentions an alarm even without specifying time, action MUST be "alarm". If no time is specified, default hour=7, minute=0, alarm_title="Morning Alarm".
- When user says "call mom", "calling ma", "phone", "dial", or mentions a call even without a clear name, action MUST be "call". Default contact_name to "Mom" if unspecified.
- When user says "schedule meeting at 10am", "add meeting", "timetable", "schedule", action MUST be "calendar".
- If explaining a concept or timeline, include "flowchart". Otherwise set flowchart to null.
- Output ONLY the JSON object.''';

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      ...history,
    ];

    if (isVision) {
      final contentList = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text': userPrompt.isEmpty
              ? 'Analyze this diagram/photo and extract its concepts.'
              : userPrompt
        },
      ];

      if (imageBase64 != null) {
        contentList.add({
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'},
        });
      } else if (imageUrl != null) {
        contentList.add({
          'type': 'image_url',
          'image_url': {'url': imageUrl},
        });
      }

      messages.add({'role': 'user', 'content': contentList});
    } else {
      messages.add({'role': 'user', 'content': userPrompt});
    }

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': modelToUse,
          'temperature': 0.3,
          'max_tokens': 900,
          'messages': messages,
          'response_format': {'type': 'json_object'},
        }),
      ).timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawContent = data['choices'][0]['message']['content'] as String? ?? '{}';
        debugPrint('[GroqAgent] Received JSON: $rawContent');

        String cleanJson = rawContent.trim();
        if (cleanJson.startsWith('```')) {
          cleanJson = cleanJson.replaceAll(RegExp(r'^```\w*\n?'), '');
          cleanJson = cleanJson.replaceAll(RegExp(r'\n?```$'), '');
        }

        final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
        return BuddyAgentResponse.fromJson(parsed);
      } else {
        throw Exception('Groq API Error (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('[GroqAgent] Error calling Groq: $e');
      // Graceful fallback response
      return BuddyAgentResponse(
        reply: "I had trouble processing that: $e",
        action: BuddyAgentActionType.none,
        actionParams: {},
        oledText: "Error",
        flowchart: null,
      );
    }
  }

  /// Legacy helper for tasks/summaries
  Future<String> askStudyTutor({
    required String subject,
    required String userPrompt,
    String? imageBase64,
    String? imageUrl,
    List<Map<String, String>> history = const [],
  }) async {
    final agentRes = await askAgent(
      subject: subject,
      userPrompt: userPrompt,
      imageBase64: imageBase64,
      imageUrl: imageUrl,
      history: history,
    );
    return agentRes.reply;
  }

  static FlowchartData? extractFlowchart(String response) => null;
  static String? extractOledText(String response) => null;
  static Map<String, dynamic>? extractTaskAction(String response) => null;
}
