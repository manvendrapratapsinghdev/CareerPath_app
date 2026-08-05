import 'dart:convert';

import 'package:career_path/config/ai_provider_config.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_ai_chat_repository.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CareerDataService _careerService() {
  final service = CareerDataService(ApiClient());
  service.initializeWithData(
    [
      StreamModel(id: 'science', name: 'Science', categoryIds: ['engineering']),
    ],
    {
      'engineering': CareerNode(
        id: 'engineering',
        name: 'Engineering',
        intro: 'Engineering applies science and technology.',
        childIds: const ['computer-science'],
      ),
      'computer-science': CareerNode(
        id: 'computer-science',
        name: 'Computer Science',
        intro: 'Software and computing.',
      ),
    },
  );
  return service;
}

GeminiKeyService _keyService() {
  return GeminiKeyService(
    client: MockClient(
      (_) async => http.Response('{"g_api_key":"test-key"}', 200),
    ),
  );
}

AiChatRequest _request(
  String content, {
  String locale = 'en',
  String sessionId = 'session-1',
}) {
  return AiChatRequest(
    requestId: 'request-1',
    sessionId: sessionId,
    locale: locale,
    streamId: 'science',
    messages: [
      AiChatMessage(id: 'message-1', role: AiChatRole.user, content: content),
    ],
  );
}

void main() {
  test(
    'calls Gemini directly with local context and validates sources',
    () async {
      late http.Request captured;
      final geminiClient = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'status': 'answered',
                        'answer': 'Engineering applies science and technology.',
                        'sourceIds': ['career_node:engineering'],
                        'suggestedPrompts': ['Show related options'],
                      }),
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final repository = GeminiAiChatRepository(
        keyService: _keyService(),
        groundingService: LocalAiGroundingService(_careerService()),
        client: geminiClient,
        model: 'test-model',
      );

      final response = await repository.send(
        _request('Tell me about engineering'),
      );

      expect(captured.url.host, 'generativelanguage.googleapis.com');
      expect(captured.url.path, contains('/models/test-model:generateContent'));
      expect(captured.headers['user-agent'], 'CareerPath/1.0');
      expect(captured.headers['x-goog-api-key'], 'test-key');
      expect(captured.body, contains('SOURCE career_node:engineering'));
      expect(captured.body, isNot(contains('g_api_key')));
      expect(
        (jsonDecode(captured.body)['generationConfig']
            as Map<String, dynamic>)['maxOutputTokens'],
        AiProviderConfig.maxOutputTokens,
      );
      expect(
        ((jsonDecode(captured.body)['generationConfig']
                as Map<String, dynamic>)['thinkingConfig']
            as Map<String, dynamic>)['thinkingBudget'],
        0,
      );
      expect(response.status, AiChatStatus.answered);
      expect(response.sources.single.exploreNodeId, 'engineering');
    },
  );

  test('does not call Gemini when Explore has no supporting data', () async {
    var geminiCalled = false;
    final repository = GeminiAiChatRepository(
      keyService: _keyService(),
      groundingService: LocalAiGroundingService(_careerService()),
      client: MockClient((_) async {
        geminiCalled = true;
        return http.Response('{}', 200);
      }),
    );

    final response = await repository.send(_request('Weather tomorrow'));

    expect(geminiCalled, isFalse);
    expect(response.status, AiChatStatus.insufficientData);
    expect(response.answer, GeminiAiChatRepository.insufficientAnswer);
  });

  test('warns once and blocks repeated abusive language locally', () async {
    final repository = GeminiAiChatRepository(
      keyService: _keyService(),
      groundingService: LocalAiGroundingService(_careerService()),
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    final first = await repository.send(_request('This is stupid'));
    final second = await repository.send(_request('You are an idiot'));

    expect(first.status, AiChatStatus.policyWarning);
    expect(second.status, AiChatStatus.blocked);
    expect(second.chatBlocked, isTrue);
  });

  test('a new session cannot bypass an active local chat block', () async {
    final repository = GeminiAiChatRepository(
      keyService: _keyService(),
      groundingService: LocalAiGroundingService(_careerService()),
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    await repository.send(_request('This is stupid'));
    await repository.send(_request('You are an idiot'));
    final response = await repository.send(
      _request('Tell me about engineering', sessionId: 'new-session'),
    );

    expect(response.status, AiChatStatus.blocked);
    expect(response.chatBlocked, isTrue);
  });

  test('returns student safety support without calling Gemini', () async {
    var geminiCalled = false;
    final repository = GeminiAiChatRepository(
      keyService: _keyService(),
      groundingService: LocalAiGroundingService(_careerService()),
      client: MockClient((_) async {
        geminiCalled = true;
        return http.Response('{}', 200);
      }),
    );

    final response = await repository.send(_request('I want to die'));

    expect(response.status, AiChatStatus.safetySupport);
    expect(geminiCalled, isFalse);
  });

  test('rejects a model source that was not in local retrieval', () async {
    final repository = GeminiAiChatRepository(
      keyService: _keyService(),
      groundingService: LocalAiGroundingService(_careerService()),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'status': 'answered',
                        'answer': 'Invented answer',
                        'sourceIds': ['career_node:not-retrieved'],
                      }),
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      ),
    );

    final response = await repository.send(
      _request('Tell me about engineering'),
    );

    expect(response.status, AiChatStatus.insufficientData);
    expect(response.answer, GeminiAiChatRepository.insufficientAnswer);
  });
}
