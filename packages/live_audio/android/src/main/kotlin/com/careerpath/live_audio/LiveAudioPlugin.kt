package com.careerpath.live_audio

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max

class LiveAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        const val SAMPLE_RATE = 24000
        const val CHANNEL_NAME = "live_audio/native"
    }

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var recorder: AudioRecord? = null
    private var recorderSource = MediaRecorder.AudioSource.VOICE_RECOGNITION
    private var acousticEchoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var softwareEchoCanceler: WebRtcAec3Processor? = null
    private var player: AudioTrack? = null
    @Volatile private var playerBytes = 0L
    @Volatile private var playerStarted = false
    private var playerCommunicationMode = false
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private var focusRequest: AudioFocusRequest? = null
    private var communicationRouteRequested: String? = null
    private var communicationRouteSelected = false
    private var communicationMediaFallback = false
    private var processingOptions = NativeAudioProcessingOptions()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pcmRecorderStart" -> startRecorder(
                    call.argument<String>("audioSource"),
                    NativeAudioProcessingOptions.from(call.arguments),
                    result,
                )
                "pcmRecorderRead" -> readRecorder(result)
                "pcmRecorderStop" -> { stopRecorder(); result.success(null) }
                "pcmAudioStart" -> {
                    startPlayer(call.argument<String>("mode") == "communication")
                    result.success(null)
                }
                "pcmAudioWrite" -> writePlayer(call.arguments as? ByteArray, result)
                "pcmAudioPosition" -> result.success(playerPosition())
                "pcmAudioDrainAndStop" -> drainPlayer(result)
                "pcmAudioStop" -> { stopPlayer(); result.success(null) }
                "audioFocusRequest" -> result.success(requestFocus(call.argument<String>("mode") ?: "continuous"))
                "audioFocusRelease" -> { releaseFocus(); result.success(null) }
                "screenAwakeEnable" -> { keepAwake(true); result.success(null) }
                "screenAwakeDisable" -> { keepAwake(false); result.success(null) }
                "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("VOICE_ASSISTANT_NATIVE", error.message, null)
        }
    }

    @Suppress("MissingPermission")
    private fun startRecorder(
        requested: String?,
        options: NativeAudioProcessingOptions,
        result: MethodChannel.Result,
    ) {
        stopRecorder()
        processingOptions = options
        val sources = linkedSetOf<Int>()
        when (requested) {
            "VOICE_COMMUNICATION" -> sources.add(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
            "VOICE_RECOGNITION" -> sources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            "MIC" -> sources.add(MediaRecorder.AudioSource.MIC)
        }
        if (Build.MANUFACTURER.equals("samsung", true)) sources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
        sources.add(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
        sources.add(MediaRecorder.AudioSource.VOICE_RECOGNITION)
        sources.add(MediaRecorder.AudioSource.MIC)
        val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT)
        val allocatedBufferBytes = max(minimum * 4, SAMPLE_RATE * 2)
        var selected: AudioRecord? = null
        for (source in sources) {
            try {
                val candidate = AudioRecord(source, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, allocatedBufferBytes)
                if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                    selected = candidate; recorderSource = source; break
                }
                candidate.release()
            } catch (_: Throwable) { }
        }
        if (selected == null) { result.error("RECORDER_INIT", "No compatible AudioRecord source", null); return }
        recorder = selected
        softwareEchoCanceler = if (options.androidSoftwareAec3Enabled) {
            WebRtcAec3Processor.createOrNull()
        } else {
            null
        }
        enableCaptureEffects(selected.audioSessionId)
        selected.startRecording()
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        result.success(mapOf(
            "deviceBrand" to Build.MANUFACTURER,
            "deviceModel" to Build.MODEL,
            "androidApi" to Build.VERSION.SDK_INT,
            "requestedAudioSource" to requested,
            "audioSource" to sourceName(recorderSource),
            "audioSessionId" to selected.audioSessionId,
            "sampleRate" to selected.sampleRate,
            "channelCount" to 1,
            "pcmEncoding" to "PCM_16BIT",
            "minimumBufferBytes" to minimum,
            "allocatedBufferBytes" to allocatedBufferBytes,
            "audioMode" to audioModeName(manager.mode),
            "communicationRouteRequested" to communicationRouteRequested,
            "communicationRouteSelected" to communicationRouteSelected,
            "communicationOutputDevice" to communicationDeviceMetadata(manager),
            "recordingInputDevice" to audioDeviceMetadata(selected.routedDevice),
            "playbackUsage" to "VOICE_COMMUNICATION",
            "audioFocusUsage" to "VOICE_COMMUNICATION",
            "acousticEchoCancellationAvailable" to AcousticEchoCanceler.isAvailable(),
            "acousticEchoCancellation" to (acousticEchoCanceler?.enabled == true),
            "noiseSuppressionAvailable" to NoiseSuppressor.isAvailable(),
            "noiseSuppression" to (noiseSuppressor?.enabled == true),
            "voiceProcessingRequested" to options.voiceProcessingEnabled,
            "androidSoftwareAec3Requested" to options.androidSoftwareAec3Enabled,
            "platformAecFallbackRequested" to options.platformAecFallbackEnabled,
            "noiseSuppressionRequested" to options.noiseSuppressionEnabled,
            "echoDiagnosticsRequested" to options.echoDiagnosticsEnabled,
            "correctedAecDelayShadowRequested" to options.correctedAecDelayShadowEnabled,
            "correctedAecDelayActiveRequested" to options.correctedAecDelayActiveEnabled,
        ) + (softwareEchoCanceler?.metadata() ?: mapOf(
            "softwareEchoCancellation" to false,
            "softwareEchoCancellationEngine" to "ANDROID_PLATFORM_FALLBACK"
        )))
    }

    private fun enableCaptureEffects(audioSessionId: Int) {
        releaseCaptureEffects()
        if (processingOptions.noiseSuppressionEnabled && NoiseSuppressor.isAvailable()) {
            try {
                noiseSuppressor = NoiseSuppressor.create(audioSessionId)?.apply { enabled = true }
            } catch (_: Throwable) { noiseSuppressor = null }
        }
        if (processingOptions.platformAecFallbackEnabled &&
            softwareEchoCanceler == null &&
            recorderSource == MediaRecorder.AudioSource.VOICE_COMMUNICATION &&
            AcousticEchoCanceler.isAvailable()) {
            try {
                acousticEchoCanceler = AcousticEchoCanceler.create(audioSessionId)?.apply { enabled = true }
            } catch (_: Throwable) { acousticEchoCanceler = null }
        }
    }

    private fun releaseCaptureEffects() {
        try { acousticEchoCanceler?.release() } catch (_: Throwable) {}
        try { noiseSuppressor?.release() } catch (_: Throwable) {}
        acousticEchoCanceler = null
        noiseSuppressor = null
    }

    private fun readRecorder(result: MethodChannel.Result) {
        val active = recorder
        if (active == null || active.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            result.success(null); return
        }
        val buffer = ByteArray(4096)
        val captured = ByteArrayOutputStream()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            while (captured.size() < 32768) {
                val count = active.read(buffer, 0, buffer.size, AudioRecord.READ_NON_BLOCKING)
                if (count <= 0) break
                captured.write(buffer, 0, count - (count % 2))
                if (count < buffer.size) break
            }
        } else {
            val count = active.read(buffer, 0, buffer.size)
            if (count > 0) captured.write(buffer, 0, count - (count % 2))
        }
        if (captured.size() == 0) { result.success(null); return }
        val rawBytes = captured.toByteArray()
        val aec3 = softwareEchoCanceler
        val bytes = if (aec3 != null && aec3.isOperational) {
            aec3.processCapture(rawBytes, currentAudioBufferDelayMs())
        } else {
            rawBytes
        }
        if (aec3 != null && !aec3.isOperational) {
            enablePlatformEchoCancellationIfPossible()
        }
        if (bytes.isEmpty()) { result.success(null); return }
        val playedFrames = player?.playbackHeadPosition?.toLong() ?: 0L
        val queuedFrames = playerBytes / 2L
        val playbackIsStarted = playerStarted &&
            player?.playState == AudioTrack.PLAYSTATE_PLAYING
        var squareSum = 0.0
        var i = 0
        while (i + 1 < bytes.size) {
            val sample = ((bytes[i + 1].toInt() shl 8) or (bytes[i].toInt() and 0xff)).toShort().toDouble()
            squareSum += sample * sample; i += 2
        }
        result.success(mapOf("bytes" to bytes, "level" to squareSum / max(1, bytes.size / 2),
            "audioSource" to sourceName(recorderSource), "sampleRate" to SAMPLE_RATE,
            "channelCount" to 1, "pcmEncoding" to "PCM_16BIT",
            "communicationRouteRequested" to communicationRouteRequested,
            "communicationOutputDevice" to communicationDeviceMetadata(
                context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            ),
            "playbackStarted" to playbackIsStarted,
            "playbackQueuedFrames" to queuedFrames,
            "playbackPlayedFrames" to playedFrames,
            "audioBufferDelayMs" to currentAudioBufferDelayMs(),
            "platformEchoCancellation" to (acousticEchoCanceler?.enabled == true),
            "noiseSuppression" to (noiseSuppressor?.enabled == true)) +
            (aec3?.metadata() ?: mapOf("softwareEchoCancellation" to false)))
    }

    private fun stopRecorder() {
        val active = recorder
        recorder = null
        if (active != null) {
            try { if (active.recordingState == AudioRecord.RECORDSTATE_RECORDING) active.stop() } catch (_: Throwable) {}
            active.release()
        }
        try { softwareEchoCanceler?.close() } catch (_: Throwable) {}
        softwareEchoCanceler = null
        releaseCaptureEffects()
        processingOptions = NativeAudioProcessingOptions()
    }

    private fun startPlayer(communicationMode: Boolean = playerCommunicationMode) {
        stopPlayer()
        playerCommunicationMode = communicationMode
        val minimum = AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT)
        val attributes = when {
            communicationMode && !communicationMediaFallback -> communicationAudioAttributes()
            communicationMode -> mediaPlaybackAudioAttributes()
            else -> assistantPlaybackAudioAttributes()
        }
        val format = AudioFormat.Builder().setSampleRate(SAMPLE_RATE).setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
        player = AudioTrack(attributes, format, max(minimum * 4, SAMPLE_RATE * 2),
            AudioTrack.MODE_STREAM, AudioManager.AUDIO_SESSION_ID_GENERATE)
        playerBytes = 0; playerStarted = false
    }

    private fun writePlayer(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty()) { result.success(null); return }
        if (player == null) startPlayer()
        val active = player ?: run { result.error("PLAYER_INIT", "AudioTrack unavailable", null); return }
        audioExecutor.execute {
            try {
                softwareEchoCanceler?.analyzeRender(bytes)
                var offset = 0
                while (offset < bytes.size) {
                    val written = active.write(bytes, offset, bytes.size - offset, AudioTrack.WRITE_BLOCKING)
                    if (written <= 0) throw IllegalStateException("AudioTrack write failed: $written")
                    offset += written; playerBytes += written
                    if (!playerStarted && playerBytes >= SAMPLE_RATE) { active.play(); playerStarted = true }
                }
                activity?.runOnUiThread { result.success(null) } ?: result.success(null)
            } catch (error: Throwable) {
                activity?.runOnUiThread { result.error("PLAYER_WRITE", error.message, null) }
                    ?: result.error("PLAYER_WRITE", error.message, null)
            }
        }
    }

    private fun drainPlayer(result: MethodChannel.Result) {
        val active = player
        if (active == null) { result.success(null); return }
        audioExecutor.execute {
            try {
                if (!playerStarted && playerBytes > 0) { active.play(); playerStarted = true }
                val expectedFrames = playerBytes / 2
                val remainingFrames = max(0L,
                    expectedFrames - active.playbackHeadPosition.toLong())
                val remainingMs = remainingFrames * 1000L / SAMPLE_RATE
                val deadline = System.currentTimeMillis() + remainingMs + 5000L
                while (active.playState == AudioTrack.PLAYSTATE_PLAYING &&
                    active.playbackHeadPosition.toLong() < expectedFrames && System.currentTimeMillis() < deadline) {
                    Thread.sleep(20)
                }
            } catch (_: Throwable) { } finally {
                stopPlayer()
                activity?.runOnUiThread { result.success(null) } ?: result.success(null)
            }
        }
    }

    private fun playerPosition(): Map<String, Any> {
        val active = player
        return mapOf(
            "playedFrames" to (active?.playbackHeadPosition?.toLong() ?: 0L),
            "queuedFrames" to (playerBytes / 2L),
            "sampleRate" to SAMPLE_RATE,
            "isPlaying" to (active?.playState == AudioTrack.PLAYSTATE_PLAYING)
        )
    }

    private fun currentAudioBufferDelayMs(): Int {
        val active = player ?: return 25
        if (!playerStarted) return 25
        val queuedFrames = max(0L, playerBytes / 2L - active.playbackHeadPosition.toLong())
        // Include a small acoustic/device path allowance in addition to the
        // PCM still queued in AudioTrack.
        return (queuedFrames * 1000L / SAMPLE_RATE + 25L).coerceIn(0L, 500L).toInt()
    }

    private fun enablePlatformEchoCancellationIfPossible() {
        val active = recorder ?: return
        if (acousticEchoCanceler != null ||
            !processingOptions.platformAecFallbackEnabled ||
            recorderSource != MediaRecorder.AudioSource.VOICE_COMMUNICATION ||
            !AcousticEchoCanceler.isAvailable()) return
        try {
            acousticEchoCanceler = AcousticEchoCanceler.create(active.audioSessionId)?.apply {
                enabled = true
            }
        } catch (_: Throwable) {
            acousticEchoCanceler = null
        }
    }

    @Synchronized private fun stopPlayer() {
        val active = player ?: return
        player = null; playerStarted = false; playerBytes = 0
        try { active.pause(); active.flush(); active.stop() } catch (_: Throwable) {}
        active.release()
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        val name = when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> "focus_gain"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "can_duck"
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "focus_lost_transient"
            else -> "focus_lost"
        }
        channel.invokeMethod("audioFocusEvent", name)
    }

    private fun requestFocus(mode: String): Boolean {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        configureCommunicationRoute(manager, enabled = mode == "continuous")
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(communicationAudioAttributes())
                .setOnAudioFocusChangeListener(focusListener).build()
            focusRequest = request
            manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(focusListener, AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
        if (!granted) {
            configureCommunicationRoute(manager, enabled = false)
            communicationMediaFallback = true
        }
        return granted
    }

    private fun releaseFocus() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) focusRequest?.let { manager.abandonAudioFocusRequest(it) }
        else { @Suppress("DEPRECATION") manager.abandonAudioFocus(focusListener) }
        focusRequest = null
        configureCommunicationRoute(manager, enabled = false)
    }

    private fun communicationAudioAttributes() = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private fun assistantPlaybackAudioAttributes() = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private fun mediaPlaybackAudioAttributes() = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    @Suppress("DEPRECATION")
    private fun configureCommunicationRoute(manager: AudioManager, enabled: Boolean) {
        if (!enabled) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try { manager.clearCommunicationDevice() } catch (_: Throwable) {}
            }
            manager.isSpeakerphoneOn = false
            manager.mode = AudioManager.MODE_NORMAL
            communicationRouteRequested = null
            communicationRouteSelected = false
            communicationMediaFallback = false
            return
        }

        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        communicationRouteRequested = "BUILTIN_SPEAKER"
        communicationRouteSelected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val speaker = manager.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            }
            speaker != null && try {
                manager.setCommunicationDevice(speaker)
            } catch (_: Throwable) {
                false
            }
        } else {
            manager.isSpeakerphoneOn = true
            manager.isSpeakerphoneOn
        }
        communicationMediaFallback = !communicationRouteSelected
        if (communicationMediaFallback) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try { manager.clearCommunicationDevice() } catch (_: Throwable) {}
            }
            manager.mode = AudioManager.MODE_NORMAL
            manager.isSpeakerphoneOn = true
        }
    }

    private fun communicationDeviceMetadata(manager: AudioManager): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return mapOf(
                "type" to if (manager.isSpeakerphoneOn) "BUILTIN_SPEAKER" else "SYSTEM_DEFAULT",
                "selected" to manager.isSpeakerphoneOn
            )
        }
        return audioDeviceMetadata(manager.communicationDevice)
    }

    private fun audioDeviceMetadata(device: AudioDeviceInfo?): Map<String, Any?>? {
        if (device == null) return null
        return mapOf(
            "id" to device.id,
            "type" to audioDeviceTypeName(device.type),
            "productName" to device.productName?.toString(),
            "isSource" to device.isSource,
            "isSink" to device.isSink
        )
    }

    private fun audioDeviceTypeName(type: Int) = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "BUILTIN_EARPIECE"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "BUILTIN_SPEAKER"
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BLUETOOTH_SCO"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BLUETOOTH_A2DP"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB_DEVICE"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB_HEADSET"
        else -> "TYPE_$type"
    }

    private fun audioModeName(mode: Int) = when (mode) {
        AudioManager.MODE_NORMAL -> "NORMAL"
        AudioManager.MODE_RINGTONE -> "RINGTONE"
        AudioManager.MODE_IN_CALL -> "IN_CALL"
        AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION"
        else -> "MODE_$mode"
    }

    private fun keepAwake(enabled: Boolean) = activity?.runOnUiThread {
        if (enabled) activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun sourceName(source: Int) = when (source) {
        MediaRecorder.AudioSource.VOICE_COMMUNICATION -> "VOICE_COMMUNICATION"
        MediaRecorder.AudioSource.VOICE_RECOGNITION -> "VOICE_RECOGNITION"
        else -> "MIC"
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopRecorder(); stopPlayer(); releaseFocus(); channel.setMethodCallHandler(null); audioExecutor.shutdownNow()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
}
