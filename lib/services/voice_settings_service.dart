import 'package:shared_preferences/shared_preferences.dart';

import '../config/ai_provider_config.dart';

/// Voice conversation preferences, stored on the device.
class VoiceSettingsService {
  static const _voiceKey = 'ai_voice_name';
  static const _interruptionsKey = 'ai_voice_interruptions';
  static const _spokenAnswersKey = 'ai_voice_spoken_answers';

  final SharedPreferences _prefs;

  VoiceSettingsService(this._prefs);

  String get voiceName {
    final saved = _prefs.getString(_voiceKey);
    final known = AiProviderConfig.voices.any((voice) => voice.$1 == saved);
    return known ? saved! : AiProviderConfig.defaultVoice;
  }

  bool get interruptions => _prefs.getBool(_interruptionsKey) ?? true;

  bool get spokenAnswers => _prefs.getBool(_spokenAnswersKey) ?? true;

  Future<void> setVoiceName(String name) => _prefs.setString(_voiceKey, name);

  Future<void> setInterruptions(bool value) =>
      _prefs.setBool(_interruptionsKey, value);

  Future<void> setSpokenAnswers(bool value) =>
      _prefs.setBool(_spokenAnswersKey, value);
}
