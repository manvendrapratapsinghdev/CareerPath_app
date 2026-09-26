import 'dart:convert';

import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/ai_gemini_json.dart';
import 'package:career_path/services/ai_guide_extras.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'k';
}

http.Response _json(Object value) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': jsonEncode(value)},
          ],
        },
      },
    ],
  }),
  200,
);

CareerDataService _careers() => CareerDataService(ApiClient())
  ..initializeWithData(
    [
      StreamModel(id: 'science', name: 'Science', categoryIds: ['engineering']),
    ],
    {
      'engineering': CareerNode(
        id: 'engineering',
        name: 'Engineering',
        intro: 'Build solutions with science.',
      ),
    },
  );

void main() {
  test('trending questions are generated once per day and validated', () async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    final service = AiTrendingService(
      gemini: AiGeminiJson(
        keyService: _FakeKeys(),
        client: MockClient((_) async {
          calls++;
          return _json({
            'questions': [
              'What does an engineer do every day?',
              'far too long a question that just keeps going on and on without '
                  'stopping at all ever?',
            ],
          });
        }),
      ),
      careers: _careers(),
      prefs: await SharedPreferences.getInstance(),
      clock: () => DateTime(2026, 9, 26),
    );

    expect(await service.questions(), ['What does an engineer do every day?']);
    expect(await service.questions(), ['What does an engineer do every day?']);
    expect(calls, 1);
  });

  test('deep dive uses the source record and caches the result', () async {
    var calls = 0;
    late String input;
    final service = AiDeepDiveService(
      gemini: AiGeminiJson(
        keyService: _FakeKeys(),
        client: MockClient((request) async {
          calls++;
          input =
              (((jsonDecode(request.body) as Map)['contents'] as List).first
                      as Map)['parts'][0]['text']
                  as String;
          return _json({
            'intro': 'Engineering builds solutions.',
            'faqs': [
              {'question': 'What is it?', 'answer': 'Applied science.'},
            ],
          });
        }),
      ),
      grounding: LocalAiGroundingService(_careers()),
    );
    const source = AiChatSource(
      sourceId: 'career_node:engineering',
      sourceType: 'career_node',
      title: 'Engineering',
      exploreNodeId: 'engineering',
    );

    final dive = await service.deepDive(source);
    await service.deepDive(source);

    expect(dive.intro, 'Engineering builds solutions.');
    expect(dive.faqs.single, ('What is it?', 'Applied science.'));
    expect(input, startsWith('SOURCE career_node:engineering'));
    expect(calls, 1);
  });

  test('feedback is stored on the device', () async {
    SharedPreferences.setMockInitialValues({});
    final feedback = AiFeedbackService(await SharedPreferences.getInstance());
    await feedback.save(
      messageId: 'm1',
      helpful: false,
      question: 'q',
      answer: 'a',
      reasons: const ['Not accurate'],
    );
    expect(feedback.entries.single['reasons'], ['Not accurate']);
    expect(feedback.entries.single['helpful'], isFalse);
  });

  test('recordBlock extracts one SOURCE block', () {
    const text =
        'HEADER\n\nSOURCE career_node:a\nTitle: A\n\nSOURCE career_node:b\nTitle: B';
    expect(
      AiDeepDiveService.recordBlock(text, 'career_node:a'),
      'SOURCE career_node:a\nTitle: A',
    );
    expect(AiDeepDiveService.recordBlock(text, 'career_node:z'), isNull);
  });
}
