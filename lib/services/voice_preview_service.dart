import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:live_audio/live_audio.dart';

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';
import 'gemini_key_service.dart';

/// Plays a short sample of a Gemini voice so students can pick one. Samples
/// are generated once per voice and kept in memory for the session.
class VoicePreviewService {
  final GeminiKeyService _keyService;
  final http.Client _client;
  final VoiceAssistantAudioBridge _audio;
  final _cache = <String, Uint8List>{};

  VoicePreviewService({
    required GeminiKeyService keyService,
    http.Client? client,
    VoiceAssistantAudioBridge? audio,
  }) : _keyService = keyService,
       _client = client ?? http.Client(),
       _audio = audio ?? VoiceAssistantAudioBridge();

  Future<void> play(String voice) async {
    final pcm = _cache[voice] ??= await fetchSample(voice);
    await stop();
    await _audio.startPlayer();
    await _audio.writePlayer(pcm);
    await _audio.drainPlayer();
  }

  Future<void> stop() async {
    try {
      await _audio.stopPlayer();
    } on Object {
      // Nothing playing.
    }
  }

  /// 24 kHz PCM16 sample of [voice] reading [AiProviderConfig.voicePreviewText].
  Future<Uint8List> fetchSample(String voice) async {
    final key = await _keyService.getKey();
    final response = await _client
        .post(
          Uri.parse(
            ApiUrls.geminiGenerateContent(AiProviderConfig.voicePreviewModel),
          ),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'CareerPath/1.0',
            'x-goog-api-key': key,
          },
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {
                    'text':
                        'Read in a warm, clear, friendly voice, exactly: '
                        '${AiProviderConfig.voicePreviewText}',
                  },
                ],
              },
            ],
            'generationConfig': {
              'responseModalities': ['AUDIO'],
              'speechConfig': {
                'voiceConfig': {
                  'prebuiltVoiceConfig': {'voiceName': voice},
                },
              },
            },
          }),
        )
        .timeout(AiProviderConfig.generationTimeout);
    if (response.statusCode != 200) {
      throw GeminiKeyException('preview_http_${response.statusCode}');
    }
    try {
      final parts =
          (((jsonDecode(response.body) as Map)['candidates'] as List)
                      .first['content']
                  as Map)['parts']
              as List;
      final data = parts
          .whereType<Map>()
          .map((part) => (part['inlineData'] as Map?)?['data'])
          .whereType<String>()
          .first;
      return base64Decode(data);
    } on Object {
      throw const GeminiKeyException('invalid_preview_response');
    }
  }

  void dispose() => _client.close();
}
