import 'dart:convert';

import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/guided_ai_chat_repository.dart';
import 'package:career_path/services/live_voice_tools.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'k';
}

http.Response _text(String text) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  }),
  200,
);

const _answer = '''
<Title>Here you go:</Title> Engineering is a Science path.
<Title>Options</Title>
- Computer Science
Questions:
1. What can I study in engineering?
Answers:
1. Computer Science.
''';

class _Gemini {
  String intent = 'career';
  String searchQuery = 'engineering';
  String answer = _answer;
  final calls = <String>[];

  http.Client client() => MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final system =
        ((body['systemInstruction'] as Map)['parts'] as List).first['text']
            as String;
    if (system.contains('You classify questions')) {
      calls.add('intent');
      return _text(jsonEncode({'intent': intent, 'search_query': searchQuery}));
    }
    if (system.contains('using the app')) {
      calls.add('help');
      return _text('<Title>Voice</Title> Tap Talk.');
    }
    calls.add('answer');
    return _text(answer);
  });
}

GuidedAiChatRepository _repo(_Gemini gemini, {DateTime Function()? clock}) {
  final data = CareerDataService(ApiClient())
    ..initializeWithData(
      [
        StreamModel(
          id: 'science',
          name: 'Science',
          categoryIds: ['engineering'],
        ),
      ],
      {
        'engineering': CareerNode(
          id: 'engineering',
          name: 'Engineering',
          intro: 'Study technology.',
        ),
      },
    );
  return GuidedAiChatRepository(
    keyService: _FakeKeys(),
    groundingService: LocalAiGroundingService(data),
    loadAppHelp: () async => 'Tap Talk to speak.',
    client: gemini.client(),
    clock: clock,
  );
}

AiChatRequest _ask(
  String text, {
  String locale = 'en',
  List<String>? history,
}) => AiChatRequest(
  requestId: 'r',
  sessionId: 's',
  locale: locale,
  messages: [
    for (final (i, h) in (history ?? const <String>[]).indexed)
      AiChatMessage(
        id: 'h$i',
        role: i.isEven ? AiChatRole.user : AiChatRole.assistant,
        content: h,
      ),
    AiChatMessage(id: 'q', role: AiChatRole.user, content: text),
  ],
);

void main() {
  test('career questions get sectioned, grounded answers', () async {
    final gemini = _Gemini();
    final response = await _repo(
      gemini,
    ).send(_ask('Tell me about engineering'));

    expect(gemini.calls, ['intent', 'answer']);
    expect(response.status, AiChatStatus.answered);
    expect(response.sections.map((s) => s.title), ['Here you go:', 'Options']);
    expect(response.answer, startsWith('Engineering is a Science path.'));
    expect(response.sources.first.exploreNodeId, 'engineering');
    expect(response.suggestedPrompts, ['What can I study in engineering?']);
  });

  test('repeat questions are served from the one-hour cache', () async {
    final gemini = _Gemini();
    final repo = _repo(gemini);
    await repo.send(_ask('Tell me about engineering'));
    gemini.calls.clear();

    final again = await repo.send(_ask('tell me about Engineering!'));

    expect(gemini.calls, isEmpty);
    expect(again.sections, isNotEmpty);
  });

  test('a suggested follow-up falls back to its stored answer', () async {
    final gemini = _Gemini();
    final repo = _repo(gemini);
    await repo.send(_ask('Tell me about engineering'));
    gemini.answer = "This detail isn't available in CareerPath yet.";

    final response = await repo.send(
      _ask(
        'What can I study in engineering?',
        history: ['Tell me about engineering', 'Engineering is a path.'],
      ),
    );

    expect(response.answer, 'Computer Science.');
  });

  test('off-topic, small talk and app help skip grounding', () async {
    final gemini = _Gemini()..intent = 'off_topic';
    final repo = _repo(gemini);
    expect(
      (await repo.send(_ask('pasta recipe'))).answer,
      LiveVoiceTools.offTopicAnswer,
    );

    gemini.intent = 'app_help';
    final help = await repo.send(_ask('How do I talk?'));
    expect(help.sections.single.title, 'Voice');
    expect(gemini.calls, ['intent', 'intent', 'help']);
  });

  test('Hindi is accepted; other locales are not', () async {
    final gemini = _Gemini();
    final repo = _repo(gemini);
    expect(
      (await repo.send(
        _ask('इंजीनियरिंग के बारे में बताओ', locale: 'hi'),
      )).status,
      AiChatStatus.answered,
    );
    expect(
      (await repo.send(_ask('Tell me', locale: 'ta'))).status,
      AiChatStatus.unsupportedLanguage,
    );
  });

  test('keeps the guardrails and blocks after two abusive messages', () async {
    final repo = _repo(_Gemini());
    expect(
      (await repo.send(_ask('I want to die'))).status,
      AiChatStatus.safetySupport,
    );
    expect(
      (await repo.send(_ask('you are stupid'))).status,
      AiChatStatus.policyWarning,
    );
    final blocked = await repo.send(_ask('stupid again'));
    expect(blocked.status, AiChatStatus.blocked);
    expect(blocked.chatBlocked, isTrue);
  });

  test('limits requests to ten per minute', () async {
    var now = DateTime(2026);
    final repo = _repo(_Gemini()..intent = 'small_talk', clock: () => now);
    for (var i = 0; i < 10; i++) {
      await repo.send(_ask('hello $i'));
    }
    final limited = await repo.send(_ask('hello again'));
    expect(limited.answer, GuidedAiChatRepository.rateLimitAnswer);

    now = now.add(const Duration(minutes: 1));
    expect(
      (await repo.send(_ask('hello later'))).answer,
      LiveVoiceTools.smallTalkAnswer,
    );
  });

  test('no grounding returns the insufficient-data answer', () async {
    final gemini = _Gemini()..searchQuery = 'astronomy telescopes';
    final response = await _repo(gemini).send(_ask('astronomy telescopes'));
    expect(response.status, AiChatStatus.insufficientData);
    expect(gemini.calls, ['intent']);
  });

  test('retries once after a rate limit', () async {
    var calls = 0;
    final data = CareerDataService(ApiClient())
      ..initializeWithData([
        StreamModel(id: 'science', name: 'Science', categoryIds: const []),
      ], const {});
    final repo = GuidedAiChatRepository(
      keyService: _FakeKeys(),
      groundingService: LocalAiGroundingService(data),
      loadAppHelp: () async => '',
      retryDelay: Duration.zero,
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('busy', 429)
            : _text(jsonEncode({'intent': 'small_talk', 'search_query': ''}));
      }),
    );

    final response = await repo.send(_ask('hello'));

    expect(calls, 2);
    expect(response.answer, LiveVoiceTools.smallTalkAnswer);
  });
}
