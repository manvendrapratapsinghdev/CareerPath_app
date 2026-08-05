import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef SpeechResultCallback =
    void Function(String recognizedWords, bool isFinal);

abstract class SpeechRecognitionService {
  Future<bool> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  });

  Future<void> startListening({
    required SpeechResultCallback onResult,
    String? localeId,
  });

  Future<void> stop();

  Future<void> cancel();

  void dispose();
}

class DeviceSpeechRecognitionService implements SpeechRecognitionService {
  final SpeechToText _speechToText;

  DeviceSpeechRecognitionService({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();

  @override
  Future<bool> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  }) {
    return _speechToText.initialize(
      onStatus: onStatus,
      onError: (error) => onError(error.errorMsg),
      options: [SpeechToText.androidNoBluetooth, SpeechToText.iosNoBluetooth],
    );
  }

  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    String? localeId,
  }) async {
    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      listenOptions: SpeechListenOptions(
        autoPunctuation: true,
        cancelOnError: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 60),
        localeId: localeId,
      ),
    );
  }

  @override
  Future<void> stop() => _speechToText.stop();

  @override
  Future<void> cancel() => _speechToText.cancel();

  @override
  void dispose() {
    unawaited(_speechToText.cancel());
  }
}
