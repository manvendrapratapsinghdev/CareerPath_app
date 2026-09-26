class AiProviderConfig {
  AiProviderConfig._();

  static const String provider = 'gemini';

  static const String model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  static const Duration keyTimeout = Duration(seconds: 8);
  static const Duration generationTimeout = Duration(seconds: 20);
  static const int maxContextCharacters = 18000;
  static const int maxGroundingNodes = 14;
  static const int maxDetailedNodes = 5;
  static const int maxOutputTokens = 1200;

  // ── Voice conversation (Gemini Live) ─────────────────────────────────────

  static const String liveModel = String.fromEnvironment(
    'GEMINI_LIVE_MODEL',
    defaultValue: 'gemini-3.1-flash-live-preview',
  );
  static const String voicePreviewModel = 'gemini-3.1-flash-tts-preview';
  static const String defaultVoice = 'Leda';
  static const double liveTemperature = 0.7;
  static const int liveInputSampleRate = 16000;
  static const Duration liveConnectTimeout = Duration(seconds: 20);
  static const Duration liveTurnTimeout = Duration(seconds: 20);
  static const Duration liveIdleTimeout = Duration(seconds: 60);
  static const int liveMemoryTurns = 3;

  static const String voicePreviewText =
      'Hi! I am your CareerPath guide. After Science, you can explore '
      'engineering, medicine, pure sciences and design. Ask me about any '
      'career and I will explain it simply.';

  /// Gemini's prebuilt voices with their style.
  static const List<(String, String)> voices = [
    ('Zephyr', 'Bright'),
    ('Puck', 'Upbeat'),
    ('Charon', 'Informative'),
    ('Kore', 'Firm'),
    ('Fenrir', 'Excitable'),
    ('Leda', 'Youthful'),
    ('Orus', 'Firm'),
    ('Aoede', 'Breezy'),
    ('Callirrhoe', 'Easy-going'),
    ('Autonoe', 'Bright'),
    ('Enceladus', 'Breathy'),
    ('Iapetus', 'Clear'),
    ('Umbriel', 'Easy-going'),
    ('Algieba', 'Smooth'),
    ('Despina', 'Smooth'),
    ('Erinome', 'Clear'),
    ('Algenib', 'Gravelly'),
    ('Rasalgethi', 'Informative'),
    ('Laomedeia', 'Upbeat'),
    ('Achernar', 'Soft'),
    ('Alnilam', 'Firm'),
    ('Schedar', 'Even'),
    ('Gacrux', 'Mature'),
    ('Pulcherrima', 'Forward'),
    ('Achird', 'Friendly'),
    ('Zubenelgenubi', 'Casual'),
    ('Vindemiatrix', 'Gentle'),
    ('Sadachbia', 'Lively'),
    ('Sadaltager', 'Knowledgeable'),
    ('Sulafat', 'Warm'),
  ];
}
