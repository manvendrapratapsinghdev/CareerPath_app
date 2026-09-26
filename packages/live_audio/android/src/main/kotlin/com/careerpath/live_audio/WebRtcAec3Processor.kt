package com.careerpath.live_audio

import android.util.Log
import cn.enaium.webrtc.aec3.Aec3AudioBuffer
import cn.enaium.webrtc.aec3.Aec3Config
import cn.enaium.webrtc.aec3.Aec3EchoControl
import cn.enaium.webrtc.aec3.Aec3Environment
import cn.enaium.webrtc.aec3.Aec3Factory
import cn.enaium.webrtc.aec3.createAec3AudioBuffer
import cn.enaium.webrtc.aec3.createAec3Config
import cn.enaium.webrtc.aec3.createAec3EchoControl
import cn.enaium.webrtc.aec3.createAec3Environment
import cn.enaium.webrtc.aec3.createAec3FactoryWithConfig
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

/**
 * Software acoustic echo cancellation for the plugin's 24 kHz mono PCM path.
 *
 * AEC3 consumes 10 ms frames at a WebRTC-native rate. The app/server contract
 * stays at 24 kHz; only the private render and capture copies are converted to
 * 48 kHz before AEC and the cleaned capture is converted back to 24 kHz.
 */
internal class WebRtcAec3Processor private constructor() : AutoCloseable {
    companion object {
        private const val TAG = "LiveAudioAec3"
        private const val INPUT_SAMPLE_RATE = 24_000
        private const val PROCESSING_SAMPLE_RATE = 48_000
        private const val CHANNELS = 1
        private const val INPUT_FRAME_SAMPLES = INPUT_SAMPLE_RATE / 100
        private const val INPUT_FRAME_BYTES = INPUT_FRAME_SAMPLES * 2
        private const val PROCESSING_FRAME_SAMPLES = PROCESSING_SAMPLE_RATE / 100
        private const val DEFAULT_DELAY_MS = 25

        fun createOrNull(): WebRtcAec3Processor? = try {
            WebRtcAec3Processor().also {
                Log.i(TAG, "initialized inputRate=$INPUT_SAMPLE_RATE processingRate=$PROCESSING_SAMPLE_RATE frameMs=10")
            }
        } catch (error: Throwable) {
            Log.e(TAG, "initialization_failed fallback=android_aec reason=${error.javaClass.simpleName}:${error.message}")
            null
        }
    }

    private val lock = Any()
    private val config: Aec3Config = createAec3Config().apply {
        setDelayDefaultDelay(DEFAULT_DELAY_MS)
        setFilterInitialStateSeconds(0.5f)
        setFilterConservativeInitialPhase(false)
    }
    private val environment: Aec3Environment = createAec3Environment()
    private val factory: Aec3Factory = createAec3FactoryWithConfig(config)
    private val echoControl: Aec3EchoControl = createAec3EchoControl(
        factory,
        environment,
        PROCESSING_SAMPLE_RATE,
        CHANNELS,
        CHANNELS,
    )
    private val renderBuffer: Aec3AudioBuffer = createAec3AudioBuffer(PROCESSING_SAMPLE_RATE, CHANNELS)
    private val captureBuffer: Aec3AudioBuffer = createAec3AudioBuffer(PROCESSING_SAMPLE_RATE, CHANNELS)
    private var renderRemainder = ByteArray(0)
    private var captureRemainder = ByteArray(0)
    private var closed = false
    private var failed = false
    private var renderFrames = 0L
    private var captureFrames = 0L
    private var lastDelayMs = DEFAULT_DELAY_MS
    private var lastMetrics: Map<String, Any> = emptyMap()

    init {
        echoControl.setAudioBufferDelay(DEFAULT_DELAY_MS)
    }

    val isOperational: Boolean
        get() = synchronized(lock) { !closed && !failed }

    /** Feeds the exact PCM that is about to be written to AudioTrack. */
    fun analyzeRender(bytes: ByteArray) = synchronized(lock) {
        if (closed || failed || bytes.isEmpty()) return@synchronized
        try {
            val combined = append(renderRemainder, bytes)
            var offset = 0
            while (combined.size - offset >= INPUT_FRAME_BYTES) {
                val input = pcm16Frame(combined, offset)
                renderBuffer.writeChannel(0, upsample24kTo48k(input))
                echoControl.analyzeRender(renderBuffer)
                renderFrames++
                offset += INPUT_FRAME_BYTES
            }
            renderRemainder = combined.copyOfRange(offset, combined.size)
        } catch (error: Throwable) {
            fail("render", error)
        }
    }

    /**
     * Cleans microphone PCM. Complete 10 ms frames are returned; a partial
     * frame is retained for the next native read so no microphone audio drops.
     */
    fun processCapture(bytes: ByteArray, audioBufferDelayMs: Int): ByteArray = synchronized(lock) {
        if (closed || failed || bytes.isEmpty()) return@synchronized bytes
        try {
            val requestedDelay = audioBufferDelayMs.coerceIn(0, 500)
            if (requestedDelay != lastDelayMs) {
                echoControl.setAudioBufferDelay(requestedDelay)
                lastDelayMs = requestedDelay
            }
            val combined = append(captureRemainder, bytes)
            val output = ByteArrayOutputStream(combined.size)
            var offset = 0
            while (combined.size - offset >= INPUT_FRAME_BYTES) {
                val input = pcm16Frame(combined, offset)
                captureBuffer.writeChannel(0, upsample24kTo48k(input))
                echoControl.analyzeCapture(captureBuffer)
                echoControl.processCapture(captureBuffer, false)
                writePcm16(output, downsample48kTo24k(captureBuffer.readChannel(0)))
                captureFrames++
                offset += INPUT_FRAME_BYTES
                if (captureFrames % 100L == 0L) updateMetrics()
            }
            captureRemainder = combined.copyOfRange(offset, combined.size)
            output.toByteArray()
        } catch (error: Throwable) {
            fail("capture", error)
            // Do not lose the current microphone read when software AEC fails.
            val fallback = append(captureRemainder, bytes)
            captureRemainder = ByteArray(0)
            fallback
        }
    }

    fun metadata(): Map<String, Any> = synchronized(lock) {
        mapOf(
            "softwareEchoCancellation" to (!closed && !failed),
            "softwareEchoCancellationEngine" to "WebRTC_AEC3",
            "aec3InputSampleRate" to INPUT_SAMPLE_RATE,
            "aec3ProcessingSampleRate" to PROCESSING_SAMPLE_RATE,
            "aec3RenderFrames" to renderFrames,
            "aec3CaptureFrames" to captureFrames,
            "aec3AudioBufferDelayMs" to lastDelayMs,
        ) + lastMetrics
    }

    private fun updateMetrics() {
        val metrics = echoControl.getMetrics()
        lastMetrics = mapOf(
            "aec3EchoReturnLoss" to metrics.echoReturnLoss,
            "aec3EchoReturnLossEnhancement" to metrics.echoReturnLossEnhancement,
            "aec3EstimatedDelayMs" to metrics.delayMs,
        )
        Log.i(
            TAG,
            "metrics renderFrames=$renderFrames captureFrames=$captureFrames " +
                "bufferDelayMs=$lastDelayMs estimatedDelayMs=${metrics.delayMs} " +
                "erl=${metrics.echoReturnLoss} erle=${metrics.echoReturnLossEnhancement}",
        )
    }

    private fun fail(stage: String, error: Throwable) {
        failed = true
        Log.e(TAG, "runtime_failed stage=$stage fallback=raw_capture reason=${error.javaClass.simpleName}:${error.message}")
    }

    override fun close() = synchronized(lock) {
        if (closed) return@synchronized
        closed = true
        runCatching { renderBuffer.close() }
        runCatching { captureBuffer.close() }
        runCatching { echoControl.close() }
        runCatching { factory.close() }
        runCatching { environment.close() }
        runCatching { config.close() }
        renderRemainder = ByteArray(0)
        captureRemainder = ByteArray(0)
    }

    private fun pcm16Frame(bytes: ByteArray, offset: Int): ShortArray {
        val result = ShortArray(INPUT_FRAME_SAMPLES)
        for (index in result.indices) {
            val byteIndex = offset + index * 2
            result[index] = (((bytes[byteIndex + 1].toInt() and 0xff) shl 8) or
                (bytes[byteIndex].toInt() and 0xff)).toShort()
        }
        return result
    }

    private fun upsample24kTo48k(input: ShortArray): FloatArray {
        val output = FloatArray(PROCESSING_FRAME_SAMPLES)
        for (index in input.indices) {
            val current = input[index] / 32768.0f
            val next = if (index + 1 < input.size) input[index + 1] / 32768.0f else current
            output[index * 2] = current
            output[index * 2 + 1] = (current + next) * 0.5f
        }
        return output
    }

    private fun downsample48kTo24k(input: FloatArray): ShortArray {
        val output = ShortArray(INPUT_FRAME_SAMPLES)
        for (index in output.indices) {
            val first = input[index * 2]
            val second = input[index * 2 + 1]
            output[index] = (((first + second) * 0.5f) * 32767.0f)
                .roundToInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }
        return output
    }

    private fun writePcm16(output: ByteArrayOutputStream, samples: ShortArray) {
        for (sample in samples) {
            val value = sample.toInt()
            output.write(value and 0xff)
            output.write((value ushr 8) and 0xff)
        }
    }

    private fun append(first: ByteArray, second: ByteArray): ByteArray {
        if (first.isEmpty()) return second.copyOf()
        if (second.isEmpty()) return first.copyOf()
        return ByteArray(first.size + second.size).also {
            first.copyInto(it, 0)
            second.copyInto(it, first.size)
        }
    }
}
