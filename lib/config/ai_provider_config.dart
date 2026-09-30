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

  // ── Semantic search ──────────────────────────────────────────────────────

  static const String embeddingModel = 'gemini-embedding-001';
  static const int embeddingDimensions = 768;
  static const double semanticCutOff = 0.6;
  static const int semanticTopK = 4;

  /// The shared key allows about 100 embedded items per minute.
  static const int embeddingBatchSize = 90;
  static const Duration embeddingBatchPause = Duration(seconds: 60);

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

  // ── Barge-in while the guide speaks (80 ms mic frames) ────────────────────
  // The mic also hears the guide through the speaker; these tell the
  // student's voice apart from that echo (see LiveVoiceController._gate).

  /// Frames at the start of each answer used only to learn the echo level.
  static const int liveBargeInWarmUpFrames = 6;

  /// Consecutive frames the student must be heard over the echo.
  static const int liveBargeInFrames = 3;

  /// How much louder than the loudest recent echo the student must be.
  static const double liveBargeInEchoRatio = 1.8;

  /// RMS below which a frame is room noise, never speech.
  static const double liveBargeInMinRms = 0.015;

  /// Frames of echo remembered (~1.6 s), and of audio sent from just before
  /// the student started (~0.4 s) so Gemini hears their first words.
  static const int liveEchoWindowFrames = 20;
  static const int liveBargeInPreRollFrames = 5;

  /// Frames the opened mic waits for Gemini to stop the answer before it
  /// treats the barge-in as a false alarm and closes again.
  static const int liveBargeInConfirmFrames = 20;

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
