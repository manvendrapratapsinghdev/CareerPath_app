import 'dart:convert';

import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/voice_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'k';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('requests the chosen voice and decodes its audio', () async {
    late Map<String, dynamic> body;
    final service = VoicePreviewService(
      keyService: _FakeKeys(),
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['x-goog-api-key'], 'k');
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {
                        'mimeType': 'audio/L16;rate=24000',
                        'data': base64Encode([7, 8, 9]),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(await service.fetchSample('Puck'), [7, 8, 9]);
    final voice =
        ((body['generationConfig'] as Map)['speechConfig']
            as Map)['voiceConfig'];
    expect((voice as Map)['prebuiltVoiceConfig'], {'voiceName': 'Puck'});
  });

  test('reports HTTP failures', () async {
    final service = VoicePreviewService(
      keyService: _FakeKeys(),
      client: MockClient((_) async => http.Response('no', 429)),
    );
    await expectLater(
      service.fetchSample('Puck'),
      throwsA(isA<GeminiKeyException>()),
    );
  });
}
