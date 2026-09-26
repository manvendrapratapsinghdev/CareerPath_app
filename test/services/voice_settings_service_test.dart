import 'package:career_path/config/ai_provider_config.dart';
import 'package:career_path/services/voice_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults, persists choices and ignores unknown voices', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = VoiceSettingsService(
      await SharedPreferences.getInstance(),
    );

    expect(settings.voiceName, AiProviderConfig.defaultVoice);
    expect(settings.interruptions, isTrue);
    expect(settings.spokenAnswers, isTrue);

    await settings.setVoiceName('Puck');
    await settings.setInterruptions(false);
    await settings.setSpokenAnswers(false);
    final reloaded = VoiceSettingsService(
      await SharedPreferences.getInstance(),
    );
    expect(reloaded.voiceName, 'Puck');
    expect(reloaded.interruptions, isFalse);
    expect(reloaded.spokenAnswers, isFalse);

    SharedPreferences.setMockInitialValues({'ai_voice_name': 'NotAVoice'});
    final unknown = VoiceSettingsService(await SharedPreferences.getInstance());
    expect(unknown.voiceName, AiProviderConfig.defaultVoice);
  });
}
