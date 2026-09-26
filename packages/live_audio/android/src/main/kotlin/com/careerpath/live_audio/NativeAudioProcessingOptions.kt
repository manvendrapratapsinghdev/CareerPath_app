package com.careerpath.live_audio

internal data class NativeAudioProcessingOptions(
    val voiceProcessingEnabled: Boolean = true,
    val androidSoftwareAec3Enabled: Boolean = true,
    val platformAecFallbackEnabled: Boolean = true,
    val noiseSuppressionEnabled: Boolean = true,
    val echoDiagnosticsEnabled: Boolean = false,
    val correctedAecDelayShadowEnabled: Boolean = false,
    val correctedAecDelayActiveEnabled: Boolean = false,
) {
    companion object {
        fun from(arguments: Any?): NativeAudioProcessingOptions {
            val values = arguments as? Map<*, *> ?: return NativeAudioProcessingOptions()
            return NativeAudioProcessingOptions(
                voiceProcessingEnabled = values.boolean("voiceProcessingEnabled", true),
                androidSoftwareAec3Enabled = values.boolean("androidSoftwareAec3Enabled", true),
                platformAecFallbackEnabled = values.boolean("platformAecFallbackEnabled", true),
                noiseSuppressionEnabled = values.boolean("noiseSuppressionEnabled", true),
                echoDiagnosticsEnabled = values.boolean("echoDiagnosticsEnabled", false),
                correctedAecDelayShadowEnabled = values.boolean("correctedAecDelayShadowEnabled", false),
                correctedAecDelayActiveEnabled = values.boolean("correctedAecDelayActiveEnabled", false),
            )
        }

        private fun Map<*, *>.boolean(key: String, defaultValue: Boolean): Boolean =
            this[key] as? Boolean ?: defaultValue
    }
}
