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
}
