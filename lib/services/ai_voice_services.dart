import 'package:flutter/services.dart';

import '../controllers/live_voice_controller.dart';
import 'gemini_key_service.dart';
import 'live_voice_tools.dart';
import 'local_ai_grounding_service.dart';
import 'voice_preview_service.dart';
import 'voice_settings_service.dart';

/// Everything the AI Guide needs for voice conversations, created once in
/// main.dart and passed down to the AI Guide tab.
class AiVoiceServices {
  static const _appHelpAsset = 'assets/data/ai_guide_help.txt';

  final GeminiKeyService keyService;
  final LocalAiGroundingService grounding;
  final VoiceSettingsService settings;
  final VoicePreviewService preview;
  final Object? Function()? httpClientFactory;

  const AiVoiceServices({
    required this.keyService,
    required this.grounding,
    required this.settings,
    required this.preview,
    this.httpClientFactory,
  });

  LiveVoiceController createController({String? Function()? streamId}) =>
      LiveVoiceController(
        keyService: keyService,
        httpClientFactory: httpClientFactory,
        tools: LiveVoiceTools(
          grounding: grounding,
          loadAppHelp: () => rootBundle.loadString(_appHelpAsset),
          streamId: streamId,
        ),
      );
}
