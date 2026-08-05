import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

abstract class TextToSpeechService {
  void setHandlers({
    required VoidCallback onStart,
    required VoidCallback onComplete,
    required ValueChanged<String> onError,
  });

  Future<bool> speak(String text, {String language = 'en-US'});

  Future<void> stop();

  void dispose();
}

class DeviceTextToSpeechService implements TextToSpeechService {
  final FlutterTts _flutterTts;

  DeviceTextToSpeechService({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  @override
  void setHandlers({
    required VoidCallback onStart,
    required VoidCallback onComplete,
    required ValueChanged<String> onError,
  }) {
    _flutterTts
      ..setStartHandler(onStart)
      ..setCompletionHandler(onComplete)
      ..setCancelHandler(onComplete)
      ..setErrorHandler((message) => onError(message.toString()));
  }

  @override
  Future<bool> speak(String text, {String language = 'en-US'}) async {
    await _flutterTts.stop();
    await _flutterTts.setLanguage(language);
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1);
    await _flutterTts.setVolume(1);
    final result = await _flutterTts.speak(text);
    return result == 1;
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }

  @override
  void dispose() {
    unawaited(_flutterTts.stop());
  }
}
