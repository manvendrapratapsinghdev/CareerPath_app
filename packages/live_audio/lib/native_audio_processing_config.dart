/// Native capture processing switches. All voice processing is on by
/// default (echo cancellation, noise suppression).
class NativeAudioProcessingConfig {
  const NativeAudioProcessingConfig({
    this.voiceProcessingEnabled = true,
    this.androidSoftwareAec3Enabled = true,
    this.platformEchoCancellationFallbackEnabled = true,
    this.noiseSuppressionEnabled = true,
    this.echoDiagnosticsEnabled = false,
    this.correctedAecDelayShadowEnabled = false,
    this.correctedAecDelayActiveEnabled = false,
    this.iosOutputVolumeCompensationEnabled = true,
    this.iosPlaybackDrainDelay = Duration.zero,
  });

  final bool voiceProcessingEnabled;
  final bool androidSoftwareAec3Enabled;
  final bool platformEchoCancellationFallbackEnabled;
  final bool noiseSuppressionEnabled;
  final bool echoDiagnosticsEnabled;
  final bool correctedAecDelayShadowEnabled;
  final bool correctedAecDelayActiveEnabled;
  final bool iosOutputVolumeCompensationEnabled;
  final Duration iosPlaybackDrainDelay;
}
