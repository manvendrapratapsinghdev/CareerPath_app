import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';
import 'gemini_key_service.dart';

/// Small helper for one-shot Gemini calls that return a JSON object.
class AiGeminiJson {
  final GeminiKeyService _keyService;
  final http.Client _client;

  AiGeminiJson({required GeminiKeyService keyService, http.Client? client})
    : _keyService = keyService,
      _client = client ?? http.Client();

  Future<Map<String, dynamic>> generate({
    required String instruction,
    required String input,
    required Map<String, dynamic> schema,
    int maxOutputTokens = 700,
  }) async {
    final key = await _keyService.getKey();
    final model = AiProviderConfig.model;
    final response = await _client
        .post(
          Uri.parse(ApiUrls.geminiGenerateContent(model)),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'CareerPath/1.0',
            'x-goog-api-key': key,
          },
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': instruction},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': input},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.2,
              'maxOutputTokens': maxOutputTokens,
              if (model.startsWith('gemini-2.5'))
                'thinkingConfig': {'thinkingBudget': 0},
              if (model.startsWith('gemini-3'))
                'thinkingConfig': {'thinkingLevel': 'minimal'},
              'responseMimeType': 'application/json',
              'responseSchema': schema,
            },
          }),
        )
        .timeout(AiProviderConfig.generationTimeout);
    if (response.statusCode != 200) {
      throw GeminiKeyException('gemini_http_${response.statusCode}');
    }
    try {
      final parts =
          ((((jsonDecode(response.body) as Map)['candidates'] as List).first
                      as Map)['content']
                  as Map)['parts']
              as List;
      final text = parts
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      return jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      throw const GeminiKeyException('invalid_gemini_json');
    }
  }
}
