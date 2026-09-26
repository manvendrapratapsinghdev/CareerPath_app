/// Local safety checks shared by typed chat and voice conversations, so a
/// spoken question gets the same protection as a typed one.
class AiGuardrails {
  const AiGuardrails._();

  static const safetySupportAnswer =
      'I’m really sorry you’re feeling this way. Please stop and tell a '
      'trusted adult, parent, teacher, counselor, or local emergency service '
      'right now. You deserve immediate support, and you should not handle '
      'this alone.';
  static const promptInjectionAnswer =
      'I can’t reveal private instructions or credentials. I can help with '
      'career and education questions using CareerPath Explore data.';

  static final _abusivePattern = RegExp(
    r'\b(fuck|fucking|shit|bitch|bastard|asshole|idiot|stupid|slut|whore)\b',
    caseSensitive: false,
  );
  static final _safetySupportPattern = RegExp(
    r'\b(suicide|kill myself|self harm|self-harm|want to die)\b',
    caseSensitive: false,
  );
  static final _promptInjectionPattern = RegExp(
    r'(reveal|show|print).*(system prompt|api key|secret|instructions)|'
    r'(ignore|bypass).*(instructions|rules|guardrails)',
    caseSensitive: false,
  );

  static bool needsSafetySupport(String text) =>
      _safetySupportPattern.hasMatch(text);

  static bool isPromptInjection(String text) =>
      _promptInjectionPattern.hasMatch(text);

  static bool isAbusive(String text) => _abusivePattern.hasMatch(text);
}
