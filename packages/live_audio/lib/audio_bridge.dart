import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'native_audio_processing_config.dart';

class PcmCaptureChunk {
  const PcmCaptureChunk(this.bytes, this.level, this.metadata);
  final Uint8List bytes;
  final double level;
  final Map<String, dynamic> metadata;
}

class PcmPlaybackPosition {
  const PcmPlaybackPosition({
    required this.playedFrames,
    required this.queuedFrames,
    required this.sampleRate,
    required this.isPlaying,
  });

  final int playedFrames;
  final int queuedFrames;
  final int sampleRate;
  final bool isPlaying;
}

enum PcmPlaybackMode { assistant, communication }

class VoiceAssistantAudioBridge {
  VoiceAssistantAudioBridge() {
    _channel.setMethodCallHandler(_nativeCall);
  }
  static const _channel = MethodChannel('live_audio/native');
  final _interruptions = StreamController<String>.broadcast();
  Uint8List _captureRemainder = Uint8List(0);
  Stream<String> get interruptions => _interruptions.stream;

  Future<Object?> _nativeCall(MethodCall call) async {
    if (call.method == 'audioFocusEvent') {
      _interruptions.add(call.arguments?.toString() ?? 'unknown');
    }
    return null;
  }

  Future<Map<String, dynamic>> startRecorder({
    String? audioSource,
    NativeAudioProcessingConfig processingConfig =
        const NativeAudioProcessingConfig(),
  }) async {
    _captureRemainder = Uint8List(0);
    final value = await _channel.invokeMethod<Object?>('pcmRecorderStart', {
      'audioSource': ?audioSource,
      'voiceProcessingEnabled': processingConfig.voiceProcessingEnabled,
      'androidSoftwareAec3Enabled': processingConfig.androidSoftwareAec3Enabled,
      'platformAecFallbackEnabled':
          processingConfig.platformEchoCancellationFallbackEnabled,
      'noiseSuppressionEnabled': processingConfig.noiseSuppressionEnabled,
      'echoDiagnosticsEnabled': processingConfig.echoDiagnosticsEnabled,
      'correctedAecDelayShadowEnabled':
          processingConfig.correctedAecDelayShadowEnabled,
      'correctedAecDelayActiveEnabled':
          processingConfig.correctedAecDelayActiveEnabled,
      'iosOutputVolumeCompensationEnabled':
          processingConfig.iosOutputVolumeCompensationEnabled,
    });
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  Future<PcmCaptureChunk?> readRecorder() async {
    final value = await _channel.invokeMethod<Object?>('pcmRecorderRead');
    if (value is Uint8List) {
      if (value.isEmpty) return null;
      final metrics = _pcmMetrics(value);
      return PcmCaptureChunk(value, metrics['level']!, metrics);
    }
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final bytes = map['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    map.remove('bytes');
    final metrics = _pcmMetrics(bytes);
    map.addAll(metrics);
    return PcmCaptureChunk(bytes, metrics['level']!, map);
  }

  /// Returns fixed 80 ms PCM frames and preserves any partial native read.
  ///
  /// Native capture may return several frames after the Dart isolate has been
  /// busy. Splitting and processing the entire batch prevents that backlog from
  /// turning into a permanent delay between speaking and server delivery.
  Future<List<PcmCaptureChunk>> readRecorderFrames({
    int frameBytes = 3840,
  }) async {
    final captured = await readRecorder();
    if (captured == null) return const [];
    final combined = Uint8List(
      _captureRemainder.length + captured.bytes.length,
    );
    combined.setRange(0, _captureRemainder.length, _captureRemainder);
    combined.setRange(
      _captureRemainder.length,
      combined.length,
      captured.bytes,
    );
    final completeBytes = combined.length - (combined.length % frameBytes);
    if (completeBytes == 0) {
      _captureRemainder = combined;
      return const [];
    }
    final frames = <PcmCaptureChunk>[];
    for (var offset = 0; offset < completeBytes; offset += frameBytes) {
      final bytes = Uint8List.sublistView(
        combined,
        offset,
        offset + frameBytes,
      );
      final metrics = _pcmMetrics(bytes);
      final metadata = Map<String, dynamic>.from(captured.metadata)
        ..addAll(metrics);
      frames.add(PcmCaptureChunk(bytes, metrics['level']!, metadata));
    }
    _captureRemainder = Uint8List.sublistView(combined, completeBytes);
    return frames;
  }

  Future<void> stopRecorder() async {
    _captureRemainder = Uint8List(0);
    await _channel.invokeMethod('pcmRecorderStop');
  }

  /// Returns a sanitized native audio-session snapshot for diagnostics.
  ///
  /// iOS provides the session/route/volume values. Platforms that do not
  /// implement this diagnostic method return an empty map so observability
  /// never changes the audio path.
  Future<Map<String, dynamic>> readAudioDiagnostics() async {
    try {
      final value = await _channel.invokeMethod<Object?>('pcmAudioDiagnostics');
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  Future<void> startPlayer({
    PcmPlaybackMode mode = PcmPlaybackMode.assistant,
    bool iosOutputVolumeCompensationEnabled = true,
    Duration iosPlaybackDrainDelay = Duration.zero,
    String? queryType,
  }) => _channel.invokeMethod('pcmAudioStart', {
    'mode': mode.name,
    'iosOutputVolumeCompensationEnabled': iosOutputVolumeCompensationEnabled,
    'iosPlaybackDrainDelayMs': iosPlaybackDrainDelay.inMilliseconds,
    if (queryType != null && queryType.trim().isNotEmpty)
      'queryType': queryType.trim(),
  });
  Future<void> writePlayer(Uint8List bytes) =>
      _channel.invokeMethod('pcmAudioWrite', bytes);
  Future<PcmPlaybackPosition> playbackPosition() async {
    final value = await _channel.invokeMethod<Object?>('pcmAudioPosition');
    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return PcmPlaybackPosition(
      playedFrames: (map['playedFrames'] as num?)?.toInt() ?? 0,
      queuedFrames: (map['queuedFrames'] as num?)?.toInt() ?? 0,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 24000,
      isPlaying: map['isPlaying'] == true,
    );
  }

  Future<void> drainPlayer() => _channel.invokeMethod('pcmAudioDrainAndStop');
  Future<void> stopPlayer() => _channel.invokeMethod('pcmAudioStop');

  /// Restores the shared iOS audio session to normal playback mode before
  /// another player starts playback.
  ///
  /// Android does not implement this method; callers should treat a missing
  /// method as a no-op so the existing Android audio path remains unchanged.
  static Future<void> restorePlaybackSession() async {
    await _channel.invokeMethod('restorePlaybackSession');
  }

  Future<bool> requestAudioFocus(String mode) async =>
      await _channel.invokeMethod<bool>('audioFocusRequest', {'mode': mode}) ??
      false;
  Future<void> releaseAudioFocus() =>
      _channel.invokeMethod('audioFocusRelease');
  Future<void> setScreenAwake(bool enabled) => _channel.invokeMethod(
    enabled ? 'screenAwakeEnable' : 'screenAwakeDisable',
  );

  Map<String, double> _pcmMetrics(Uint8List bytes) {
    if (bytes.length < 2) {
      return const {
        'level': 0,
        'rms': 0,
        'peakAbsolute': 0,
        'zeroCrossingRate': 0,
        'clippingRatio': 0,
      };
    }
    var squareSum = 0.0;
    var peakAbsolute = 0;
    var clippedSamples = 0;
    var zeroCrossings = 0;
    int? previousSample;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little);
      final absolute = sample.abs();
      squareSum += sample * sample;
      if (absolute > peakAbsolute) peakAbsolute = absolute;
      if (absolute >= 32700) clippedSamples++;
      if (previousSample != null && ((sample >= 0) != (previousSample >= 0))) {
        zeroCrossings++;
      }
      previousSample = sample;
    }
    final sampleCount = bytes.length ~/ 2;
    final level = squareSum / sampleCount;
    return {
      // `level` is retained for detector compatibility; it is mean-square
      // energy. `rms` is the human-readable amplitude diagnostic.
      'level': level,
      'rms': math.sqrt(level),
      'peakAbsolute': peakAbsolute.toDouble(),
      'zeroCrossingRate': zeroCrossings / math.max(1, sampleCount - 1),
      'clippingRatio': clippedSamples / sampleCount,
    };
  }

  Future<void> dispose() async {
    await _interruptions.close();
  }
}
