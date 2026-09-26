import 'dart:convert';

import 'package:career_path/services/gemini_live_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses audio, transcripts and turn completion', () {
    final events = GeminiLiveClient.parse(
      utf8.encode(
        jsonEncode({
          'serverContent': {
            'modelTurn': {
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'audio/pcm;rate=24000',
                    'data': base64Encode([1, 2]),
                  },
                },
              ],
            },
            'outputTranscription': {'text': 'Engineering is '},
            'turnComplete': true,
          },
        }),
      ),
    );

    expect((events[0] as LiveAudio).pcm24k, [1, 2]);
    expect((events[1] as LiveOutputTranscript).text, 'Engineering is ');
    expect(events[2], isA<LiveTurnComplete>());
  });

  test('parses setup, tool calls and interruptions', () {
    expect(
      GeminiLiveClient.parse('{"setupComplete": {}}').single,
      isA<LiveSetupComplete>(),
    );
    final call =
        (GeminiLiveClient.parse(
                  jsonEncode({
                    'toolCall': {
                      'functionCalls': [
                        {
                          'id': 'c1',
                          'name': 'search_careers',
                          'args': {'query': 'B.Tech'},
                        },
                      ],
                    },
                  }),
                ).single
                as LiveToolCall)
            .calls
            .single;
    expect(call.id, 'c1');
    expect(call.args['query'], 'B.Tech');
    expect(
      GeminiLiveClient.parse('{"serverContent": {"interrupted": true}}').single,
      isA<LiveInterrupted>(),
    );
    expect(GeminiLiveClient.parse('not json'), isEmpty);
  });
}
