import AVFoundation
import Flutter
import UIKit

public final class LiveAudioPlugin: NSObject, FlutterPlugin {
  private static let sampleRate = 24_000.0
  // Capture and playback must share the same I/O graph. When voice processing
  // runs on a recorder-only engine, iOS treats playback from another engine as
  // "other audio" and ducks the assistant while the microphone is active.
  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let lock = NSLock()
  private var capture = Data()
  private var channel: FlutterMethodChannel!
  private var queuedSeconds = 0.0
  private var queuedFrames: Int64 = 0
  private var pendingBuffers = 0
  private var playerStarted = false
  private var playerFormat: AVAudioFormat?
  private var playerGraphConfigured = false
  private var recorderTapInstalled = false
  private var recorderRunning = false
  private var playerCommunicationMode = false
  private var playerSpeakerRouteApplied = false
  private var processingOptions = NativeAudioProcessingOptions()
  private var voiceProcessingActive = false
  private var preservedOutputVolumeTarget: Float?
  private var appliedPlaybackGain: Float = 1.0
  private var iosOutputVolumeCompensationEnabled = true
  private var iosPlaybackDrainDelayMs = 0
  private var outputVolumeObservation: NSKeyValueObservation?
  private var previousObservedSystemOutputVolume: Float?
  private var suppressOutputVolumeUpdatesUntil = Date.distantPast
  private var diagnosticQueryType = "unknown"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "live_audio/native", binaryMessenger: registrar.messenger())
    let instance = LiveAudioPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public override init() {
    super.init()
    let session = AVAudioSession.sharedInstance()
    previousObservedSystemOutputVolume = session.outputVolume
    outputVolumeObservation = session.observe(
      \.outputVolume,
      options: [.old, .new]
    ) { [weak self] _, change in
      guard let self, let newVolume = change.newValue else { return }
      let previousVolume = change.oldValue ?? self.previousObservedSystemOutputVolume ?? newVolume
      DispatchQueue.main.async { [weak self] in
        self?.handleSystemOutputVolumeChange(
          previousVolume: previousVolume,
          newVolume: newVolume
        )
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(interruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "pcmRecorderStart":
        try startRecorder(arguments: call.arguments)
        result(recorderMetadata())
      case "pcmRecorderRead": result(readRecorder())
      case "pcmRecorderStop": stopRecorder(); result(nil)
      case "pcmAudioStart":
        let arguments = call.arguments as? [String: Any]
        diagnosticQueryType = arguments?["queryType"] as? String ?? "unknown"
        iosOutputVolumeCompensationEnabled =
          arguments?["iosOutputVolumeCompensationEnabled"] as? Bool ?? true
        iosPlaybackDrainDelayMs = max(
          0,
          arguments?["iosPlaybackDrainDelayMs"] as? Int ?? 0
        )
        try startPlayer(communicationMode: arguments?["mode"] as? String == "communication")
        result(nil)
      case "pcmAudioDiagnostics":
        result(audioSessionDiagnostics())
      case "pcmAudioWrite": try writePlayer(call.arguments); result(nil)
      case "pcmAudioPosition": result(playerPosition())
      case "pcmAudioDrainAndStop": drainPlayer(result)
      case "pcmAudioStop": stopPlayer(); result(nil)
      case "audioFocusRequest": result(try configureCommunicationSession())
      case "audioFocusRelease": releaseSession(); result(nil)
      case "restorePlaybackSession":
        try restorePlaybackSession()
        result(nil)
      case "screenAwakeEnable": UIApplication.shared.isIdleTimerDisabled = true; result(nil)
      case "screenAwakeDisable": UIApplication.shared.isIdleTimerDisabled = false; result(nil)
      case "getPlatformVersion": result("iOS " + UIDevice.current.systemVersion)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "VOICE_ASSISTANT_NATIVE", message: error.localizedDescription, details: nil))
    }
  }

  private func configureCommunicationSession() throws -> Bool {
    let session = AVAudioSession.sharedInstance()
    captureInitialSystemOutputVolumeIfNeeded(session, stage: "before_communication_session")
    suppressOutputVolumeTargetUpdates(reason: "communication_session_activation")
    try session.setCategory(.playAndRecord, mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
    try activateSession(session)
    configureVoiceProcessingIfAvailable()
    try routeToBuiltInSpeakerIfNeeded(stage: "configure")
    applyOutputVolumeCompensation(stage: "communication_session_configured")
    scheduleBuiltInSpeakerReapply(stage: "configure")
    return true
  }

  private func configureAssistantPlaybackSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    try activateSession(session)
  }

  /// Returns the process-wide iOS audio session to a normal playback profile
  /// after the voice session's communication/voice-processing session has been
  /// released, so other players share the AVAudioSession cleanly.
  private func restorePlaybackSession() throws {
    let session = AVAudioSession.sharedInstance()
    print(
      "[LIVE_AUDIO_AUDIO_SESSION][RESTORE][BEFORE] " +
      "category=\(session.category.rawValue) mode=\(session.mode.rawValue) " +
      "other_audio_playing=\(session.isOtherAudioPlaying) " +
      "route=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")) " +
      "volume=\(session.outputVolume)"
    )

    playerCommunicationMode = false
    playerSpeakerRouteApplied = false
    playerNode.volume = 1.0
    appliedPlaybackGain = 1.0
    if #available(iOS 13.0, *) {
      do {
        try audioEngine.inputNode.setVoiceProcessingEnabled(false)
      } catch {
        print("[LIVE_AUDIO_AUDIO_SESSION][RESTORE] voice_processing_disable_failed error=\(error)")
      }
    }
    voiceProcessingActive = false

    try configureAssistantPlaybackSession()

    print(
      "[LIVE_AUDIO_AUDIO_SESSION][RESTORE][APPLIED] " +
      "category=\(session.category.rawValue) mode=\(session.mode.rawValue) " +
      "route=\(session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")) " +
      "volume=\(session.outputVolume)"
    )
  }

  private func activateSession(_ session: AVAudioSession) throws {
    try session.setPreferredSampleRate(Self.sampleRate)
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: [])
  }

  private func releaseSession() {
    logOutputVolumeComparison(stage: "session_releasing")
    suppressOutputVolumeTargetUpdates(reason: "communication_session_release")
    playerCommunicationMode = false
    playerSpeakerRouteApplied = false
    playerNode.volume = 1.0
    appliedPlaybackGain = 1.0
    preservedOutputVolumeTarget = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func captureInitialSystemOutputVolumeIfNeeded(
    _ session: AVAudioSession,
    stage: String
  ) {
    guard preservedOutputVolumeTarget == nil else { return }
    preservedOutputVolumeTarget = session.outputVolume
    previousObservedSystemOutputVolume = session.outputVolume
    logOutputVolumeComparison(stage: stage)
  }

  private func suppressOutputVolumeTargetUpdates(
    reason: String,
    duration: TimeInterval = 1.0
  ) {
    let candidate = Date().addingTimeInterval(duration)
    if candidate > suppressOutputVolumeUpdatesUntil {
      suppressOutputVolumeUpdatesUntil = candidate
    }
    print(
      "[LIVE_AUDIO_AUDIO_COMPARE][IOS] decision=volume_tracking_suppressed " +
      "reason=\(reason) duration_ms=\(Int(duration * 1000))"
    )
  }

  private func handleSystemOutputVolumeChange(
    previousVolume: Float,
    newVolume: Float
  ) {
    previousObservedSystemOutputVolume = newVolume
    let delta = newVolume - previousVolume
    guard abs(delta) >= 0.0001,
          iosOutputVolumeCompensationEnabled,
          let currentTarget = preservedOutputVolumeTarget else {
      return
    }
    if Date() < suppressOutputVolumeUpdatesUntil {
      print(
        "[LIVE_AUDIO_AUDIO_COMPARE][IOS] decision=volume_change_ignored " +
        "reason=route_transition old_system_volume=\(formatVolume(previousVolume)) " +
        "new_system_volume=\(formatVolume(newVolume)) " +
        "delta=\(formatVolume(delta)) target=\(formatVolume(currentTarget))"
      )
      return
    }
    let updatedTarget = OutputVolumeCompensation.updatedTarget(
      currentTarget: currentTarget,
      previousSystemVolume: previousVolume,
      newSystemVolume: newVolume
    )
    preservedOutputVolumeTarget = updatedTarget
    print(
      "[LIVE_AUDIO_AUDIO_COMPARE][IOS] decision=user_volume_change " +
      "old_system_volume=\(formatVolume(previousVolume)) " +
      "new_system_volume=\(formatVolume(newVolume)) " +
      "delta=\(formatVolume(delta)) updated_target=\(formatVolume(updatedTarget))"
    )
    applyOutputVolumeCompensation(stage: "user_volume_change")
  }

  private func applyOutputVolumeCompensation(stage: String) {
    let session = AVAudioSession.sharedInstance()
    let targetVolume = preservedOutputVolumeTarget ?? session.outputVolume
    let currentVolume = session.outputVolume
    // A zero target can be captured during an iOS route transition. Do not
    // convert that transient value into a permanent zero player gain. The
    // hardware/system volume still controls silence naturally.
    if iosOutputVolumeCompensationEnabled && targetVolume <= 0.0001 {
      playerNode.volume = 1.0
      appliedPlaybackGain = 1.0
      print(
        "[LIVE_AUDIO_AUDIO_COMPARE][IOS] decision=volume_compensation_skipped " +
        "reason=zero_target stage=\(stage)"
      )
      logOutputVolumeComparison(stage: "\(stage)_zero_target")
      return
    }
    let gain: Float
    if !iosOutputVolumeCompensationEnabled {
      gain = 1.0
    } else {
      // AVAudioSession.outputVolume is read-only. Attenuate only when the
      // active communication route is louder than the volume observed before
      // the voice session activated it; never amplify a quieter route.
      gain = OutputVolumeCompensation.playerGain(
        target: targetVolume,
        currentSystemVolume: currentVolume
      )
    }
    playerNode.volume = gain
    appliedPlaybackGain = gain
    logOutputVolumeComparison(stage: stage)
  }

  private func logOutputVolumeComparison(stage: String) {
    let session = AVAudioSession.sharedInstance()
    let route = session.currentRoute.outputs
      .map { $0.portType.rawValue }
      .joined(separator: ",")
    let target = preservedOutputVolumeTarget.map(formatVolume) ?? "unknown"
    let current = formatVolume(session.outputVolume)
    let gain = formatVolume(appliedPlaybackGain)
    let effective = formatVolume(session.outputVolume * appliedPlaybackGain)
    print(
      "[LIVE_AUDIO_VOLUME_DIAG][IOS] " +
      "stage=\(stage) query_type=\(diagnosticQueryType) " +
      "system_volume=\(current) target_volume=\(target) " +
      "player_gain=\(gain) effective_volume=\(effective) " +
      "recorder_running=\(recorderRunning) player_running=\(playerNode.isPlaying) " +
      "voice_processing=\(voiceProcessingActive) mode=\(session.mode.rawValue) route=\(route)"
    )
    print(
      "[LIVE_AUDIO_AUDIO_COMPARE][IOS] stage=\(stage) " +
      "target_volume=\(target) current_system_volume=\(current) " +
      "player_gain=\(gain) effective_volume=\(effective) " +
      "compensation_enabled=\(iosOutputVolumeCompensationEnabled) " +
      "recorder_running=\(recorderRunning) voice_processing=\(voiceProcessingActive) " +
      "mode=\(session.mode.rawValue) route=\(route)"
    )
  }

  private func audioSessionDiagnostics() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let route = session.currentRoute
    let inputPorts = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
    let outputPorts = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
    let targetText = preservedOutputVolumeTarget.map(formatVolume) ?? "unknown"
    let snapshot: [String: Any] = [
      "systemOutputVolume": session.outputVolume,
      "targetOutputVolume": preservedOutputVolumeTarget ?? NSNull(),
      "playerGain": appliedPlaybackGain,
      "effectiveVolume": session.outputVolume * appliedPlaybackGain,
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "options": session.categoryOptions.rawValue,
      "inputRoute": inputPorts,
      "outputRoute": outputPorts,
      "sampleRate": session.sampleRate,
      "ioBufferDuration": session.ioBufferDuration,
      "inputChannels": session.inputNumberOfChannels,
      "outputChannels": session.outputNumberOfChannels,
      "recorderRunning": recorderRunning,
      "playerRunning": playerNode.isPlaying,
      "voiceProcessing": voiceProcessingActive,
      "queryType": diagnosticQueryType
    ]
    print(
      "[LIVE_AUDIO_VOLUME_DIAG][IOS] stage=session_snapshot " +
      "query_type=\(diagnosticQueryType) " +
      "system_volume=\(formatVolume(session.outputVolume)) " +
      "target_volume=\(targetText) " +
      "effective_volume=\(formatVolume(session.outputVolume * appliedPlaybackGain)) " +
      "category=\(session.category.rawValue) mode=\(session.mode.rawValue) " +
      "input_route=\(inputPorts) output_route=\(outputPorts) " +
      "sample_rate=\(session.sampleRate) input_channels=\(session.inputNumberOfChannels) " +
      "output_channels=\(session.outputNumberOfChannels) " +
      "recorder_running=\(recorderRunning) player_running=\(playerNode.isPlaying) " +
      "voice_processing=\(voiceProcessingActive)"
    )
    return snapshot
  }

  private func formatVolume(_ value: Float) -> String {
    String(format: "%.3f", value)
  }

  private func routeToBuiltInSpeakerIfNeeded(stage: String) throws {
    let session = AVAudioSession.sharedInstance()
    let hasExternalOutput = session.currentRoute.outputs.contains { output in
      switch output.portType {
      case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones,
           .airPlay, .carAudio, .usbAudio:
        return true
      default:
        return false
      }
    }
    if hasExternalOutput { return }
    if session.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
      return
    }
    try? session.overrideOutputAudioPort(.none)
    try session.overrideOutputAudioPort(.speaker)
    print("LiveAudio: speaker route applied stage=\(stage) mode=\(session.mode.rawValue)")
  }

  private func reapplyBuiltInSpeakerIfNeeded(stage: String) {
    do {
      try routeToBuiltInSpeakerIfNeeded(stage: stage)
      applyOutputVolumeCompensation(stage: "\(stage)_volume_checked")
    } catch {
      print("LiveAudio: speaker route reapply failed stage=\(stage) error=\(error)")
    }
  }

  private func scheduleBuiltInSpeakerReapply(stage: String) {
    for delay in [0.08, 0.25, 0.45] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self,
              self.playerCommunicationMode || self.recorderRunning else {
          return
        }
        self.reapplyBuiltInSpeakerIfNeeded(
          stage: "\(stage)_delayed_\(Int(delay * 1000))ms"
        )
      }
    }
  }

  private func startRecorder(arguments: Any?) throws {
    stopRecorder()
    processingOptions = NativeAudioProcessingOptions(arguments: arguments)
    iosOutputVolumeCompensationEnabled =
      processingOptions.iosOutputVolumeCompensationEnabled
    _ = try configureCommunicationSession()
    applyOutputVolumeCompensation(stage: "recorder_options_applied")
    try ensurePlayerGraphConfigured()
    let input = audioEngine.inputNode
    let source = input.outputFormat(forBus: 0)
    guard source.sampleRate > 0, source.channelCount > 0 else {
      throw VoiceError.inputUnavailable
    }
    guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate,
      channels: 1, interleaved: true) else { throw VoiceError.audioFormat }
    input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
      guard let self, let converter = AVAudioConverter(from: source, to: target) else { return }
      let ratio = target.sampleRate / source.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
      guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
      var supplied = false
      var conversionError: NSError?
      converter.convert(to: converted, error: &conversionError) { _, status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied = true; status.pointee = .haveData; return buffer
      }
      guard conversionError == nil, converted.frameLength > 0,
        let pointer = converted.int16ChannelData?.pointee else { return }
      let bytes = Int(converted.frameLength) * MemoryLayout<Int16>.size
      self.lock.lock(); self.capture.append(UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: bytes); self.lock.unlock()
    }
    recorderTapInstalled = true
    do {
      if !audioEngine.isRunning {
        audioEngine.prepare()
        try audioEngine.start()
      }
      recorderRunning = true
      logAudioGraph(stage: "recorder_started")
    } catch {
      stopRecorder()
      throw error
    }
  }

  private func configureMinimumVoiceProcessingDucking(_ input: AVAudioInputNode) {
    guard voiceProcessingActive else { return }
    if #available(iOS 17.0, *) {
      input.voiceProcessingOtherAudioDuckingConfiguration =
        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
          enableAdvancedDucking: false,
          duckingLevel: .min
        )
      print("LiveAudio: voice-processing other-audio ducking=min")
    }
  }

  private func configureVoiceProcessingIfAvailable() {
    guard processingOptions.voiceProcessingEnabled else {
      voiceProcessingActive = false
      return
    }
    guard #available(iOS 13.0, *) else { return }
    let input = audioEngine.inputNode
    do {
      if !input.isVoiceProcessingEnabled {
        try input.setVoiceProcessingEnabled(true)
      }
      voiceProcessingActive = input.isVoiceProcessingEnabled
      configureMinimumVoiceProcessingDucking(input)
      print(
        "[LIVE_AUDIO_AUDIO_SESSION][IOS] voice_processing=\(voiceProcessingActive) " +
        "mode=\(AVAudioSession.sharedInstance().mode.rawValue)"
      )
    } catch {
      voiceProcessingActive = false
      print("LiveAudio: voice processing enable failed error=\(error)")
    }
  }

  private func ensurePlayerGraphConfigured() throws {
    if playerGraphConfigured { return }
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
      sampleRate: Self.sampleRate, channels: 1, interleaved: false) else {
      throw VoiceError.audioFormat
    }
    playerFormat = format
    audioEngine.attach(playerNode)
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    audioEngine.mainMixerNode.outputVolume = 1.0
    playerGraphConfigured = true
  }

  private func hasPendingPlayback() -> Bool {
    lock.lock(); defer { lock.unlock() }
    return pendingBuffers > 0
  }

  private func stopEngineIfIdle() {
    guard !recorderRunning, !playerNode.isPlaying, !hasPendingPlayback() else {
      return
    }
    if audioEngine.isRunning { audioEngine.stop() }
    if #available(iOS 13.0, *), voiceProcessingActive {
      do {
        try audioEngine.inputNode.setVoiceProcessingEnabled(false)
      } catch {
        print("LiveAudio: voice processing disable failed error=\(error)")
      }
    }
    voiceProcessingActive = false
  }

  private func logAudioGraph(stage: String) {
    let session = AVAudioSession.sharedInstance()
    let route = session.currentRoute.outputs
      .map { $0.portType.rawValue }
      .joined(separator: ",")
    print(
      "LiveAudio: graph=shared_full_duplex stage=\(stage) " +
      "engine_running=\(audioEngine.isRunning) recorder_running=\(recorderRunning) " +
      "player_running=\(playerNode.isPlaying) voice_processing=\(voiceProcessingActive) " +
      "mode=\(session.mode.rawValue) route=\(route) output_volume=\(audioEngine.mainMixerNode.outputVolume)"
    )
  }

  private func readRecorder() -> [String: Any]? {
    lock.lock(); let data = capture; capture.removeAll(keepingCapacity: true); lock.unlock()
    guard !data.isEmpty else { return nil }
    var square = 0.0
    data.withUnsafeBytes { raw in
      let values = raw.bindMemory(to: Int16.self)
      for value in values { let sample = Double(value); square += sample * sample }
    }
    let position = playerPosition()
    let routeType = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType.rawValue ?? "UNKNOWN"
    let playbackStarted = position["isPlaying"] as? Bool ?? false
    let playbackQueuedFrames = position["queuedFrames"] as? Int64 ?? 0
    let playbackPlayedFrames = position["playedFrames"] as? Int64 ?? 0
    return ["bytes": FlutterStandardTypedData(bytes: data), "level": square / Double(max(1, data.count / 2)),
      "audioSource": "voice_processing", "sampleRate": 24000, "channelCount": 1,
      "pcmEncoding": "PCM_16BIT", "routeType": routeType,
      "audioGraph": "shared_full_duplex",
      "playbackStarted": playbackStarted,
      "playbackQueuedFrames": playbackQueuedFrames,
      "playbackPlayedFrames": playbackPlayedFrames,
      "voiceProcessing": voiceProcessingActive]
  }

  private func stopRecorder() {
    if recorderTapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      recorderTapInstalled = false
    }
    recorderRunning = false
    lock.lock(); capture.removeAll(); lock.unlock()
    stopEngineIfIdle()
  }

  private func startPlayer(communicationMode: Bool? = nil) throws {
    stopPlayer()
    // An active recorder owns a play-and-record session. Never replace that
    // session with playback-only configuration while the shared graph is
    // capturing, even for replay audio.
    let useCommunicationMode = recorderRunning ||
      (communicationMode ?? playerCommunicationMode)
    playerCommunicationMode = useCommunicationMode
    if useCommunicationMode {
      if recorderRunning {
        reapplyBuiltInSpeakerIfNeeded(stage: "player_reuses_recorder_session")
      } else {
        _ = try configureCommunicationSession()
      }
    } else {
      try configureAssistantPlaybackSession()
    }
    try ensurePlayerGraphConfigured()
    audioEngine.mainMixerNode.outputVolume = 1.0
    applyOutputVolumeCompensation(stage: "player_started")
    if !audioEngine.isRunning {
      audioEngine.prepare()
      try audioEngine.start()
    }
    if useCommunicationMode {
      reapplyBuiltInSpeakerIfNeeded(stage: "player_started")
      scheduleBuiltInSpeakerReapply(stage: "player_started")
    }
    queuedSeconds = 0; queuedFrames = 0; pendingBuffers = 0; playerStarted = false
    playerSpeakerRouteApplied = false
    logAudioGraph(stage: "player_started")
  }

  private func writePlayer(_ arguments: Any?) throws {
    if !audioEngine.isRunning { try startPlayer(communicationMode: playerCommunicationMode) }
    if playerCommunicationMode && !playerSpeakerRouteApplied {
      playerSpeakerRouteApplied = true
      reapplyBuiltInSpeakerIfNeeded(stage: "first_write")
      scheduleBuiltInSpeakerReapply(stage: "first_write")
    }
    applyOutputVolumeCompensation(stage: "player_first_write")
    let data: Data
    if let typed = arguments as? FlutterStandardTypedData { data = typed.data }
    else if let value = arguments as? Data { data = value }
    else { throw VoiceError.invalidBytes }
    guard let format = playerFormat else { throw VoiceError.audioFormat }
    let frames = AVAudioFrameCount(data.count / 2)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
      let target = buffer.floatChannelData?.pointee else { throw VoiceError.audioFormat }
    buffer.frameLength = frames
    data.withUnsafeBytes { raw in
      let samples = raw.bindMemory(to: Int16.self)
      for index in 0..<Int(frames) {
        target[index] = Float(samples[index]) / Float(Int16.max)
      }
    }
    lock.lock(); pendingBuffers += 1; lock.unlock()
    playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      guard let self else { return }
      self.lock.lock(); self.pendingBuffers = max(0, self.pendingBuffers - 1); self.lock.unlock()
    }
    queuedSeconds += Double(frames) / Self.sampleRate
    queuedFrames += Int64(frames)
    if !playerStarted && queuedSeconds >= 0.5 {
      playerNode.play()
      playerStarted = true
      logAudioGraph(stage: "playback_began")
    }
  }

  private func drainPlayer(_ result: @escaping FlutterResult) {
    if !playerStarted && queuedSeconds > 0 {
      playerNode.play()
      playerStarted = true
      logAudioGraph(stage: "playback_began_drain")
    }
    let graceSeconds = Double(iosPlaybackDrainDelayMs) / 1000.0
    let deadline = Date().addingTimeInterval(max(8, queuedSeconds + 5 + graceSeconds))
    var drainedAt: Date?
    func poll() {
      self.lock.lock(); let pending = self.pendingBuffers; self.lock.unlock()
      if pending == 0 {
        if drainedAt == nil { drainedAt = Date() }
        if Date().timeIntervalSince(drainedAt!) >= graceSeconds {
          self.stopPlayer(); result(nil); return
        }
      } else {
        drainedAt = nil
      }
      if Date() >= deadline {
        self.stopPlayer(); result(nil); return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
    }
    poll()
  }

  private func playerPosition() -> [String: Any] {
    var playedFrames: Int64 = 0
    if playerStarted, let renderTime = playerNode.lastRenderTime,
      let playerTime = playerNode.playerTime(forNodeTime: renderTime) {
      playedFrames = max(0, playerTime.sampleTime)
    }
    return [
      "playedFrames": playedFrames,
      "queuedFrames": queuedFrames,
      "sampleRate": Int(Self.sampleRate),
      "isPlaying": playerNode.isPlaying
    ]
  }

  private func stopPlayer() {
    if playerNode.engine != nil { playerNode.stop() }
    lock.lock(); pendingBuffers = 0; lock.unlock()
    queuedSeconds = 0; queuedFrames = 0; playerStarted = false
    playerSpeakerRouteApplied = false
    stopEngineIfIdle()
  }

  private func recorderMetadata() -> [String: Any] {
    ["deviceBrand": "apple", "deviceModel": UIDevice.current.model, "audioSource": "voice_processing",
      "sampleRate": 24000, "channelCount": 1, "pcmEncoding": "PCM_16BIT",
      "audioGraph": "shared_full_duplex"]
      .merging([
        "voiceProcessingRequested": processingOptions.voiceProcessingEnabled,
        "voiceProcessing": voiceProcessingActive,
        "androidSoftwareAec3Requested": processingOptions.androidSoftwareAec3Enabled,
        "platformAecFallbackRequested": processingOptions.platformAecFallbackEnabled,
        "noiseSuppressionRequested": processingOptions.noiseSuppressionEnabled,
        "echoDiagnosticsRequested": processingOptions.echoDiagnosticsEnabled,
        "correctedAecDelayShadowRequested": processingOptions.correctedAecDelayShadowEnabled,
        "correctedAecDelayActiveRequested": processingOptions.correctedAecDelayActiveEnabled,
      ]) { _, new in new }
  }

  @objc private func interruption(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    emitAudioFocusEvent(type == .began ? "began" : "ended")
  }

  @objc private func routeChanged(_ notification: Notification) {
    if playerCommunicationMode || recorderRunning {
      suppressOutputVolumeTargetUpdates(reason: "audio_route_change")
      reapplyBuiltInSpeakerIfNeeded(stage: "route_changed")
      scheduleBuiltInSpeakerReapply(stage: "route_changed")
    }
    emitAudioFocusEvent("route_changed")
  }

  private func emitAudioFocusEvent(_ event: String) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.emitAudioFocusEvent(event) }
      return
    }
    channel.invokeMethod("audioFocusEvent", arguments: event)
  }

  deinit {
    outputVolumeObservation?.invalidate()
    stopRecorder()
    stopPlayer()
    NotificationCenter.default.removeObserver(self)
  }
}

private struct NativeAudioProcessingOptions {
  let voiceProcessingEnabled: Bool
  let androidSoftwareAec3Enabled: Bool
  let platformAecFallbackEnabled: Bool
  let noiseSuppressionEnabled: Bool
  let echoDiagnosticsEnabled: Bool
  let correctedAecDelayShadowEnabled: Bool
  let correctedAecDelayActiveEnabled: Bool
  let iosOutputVolumeCompensationEnabled: Bool

  init(arguments: Any? = nil) {
    let values = arguments as? [String: Any] ?? [:]
    voiceProcessingEnabled = values["voiceProcessingEnabled"] as? Bool ?? true
    androidSoftwareAec3Enabled = values["androidSoftwareAec3Enabled"] as? Bool ?? true
    platformAecFallbackEnabled = values["platformAecFallbackEnabled"] as? Bool ?? true
    noiseSuppressionEnabled = values["noiseSuppressionEnabled"] as? Bool ?? true
    echoDiagnosticsEnabled = values["echoDiagnosticsEnabled"] as? Bool ?? false
    correctedAecDelayShadowEnabled = values["correctedAecDelayShadowEnabled"] as? Bool ?? false
    correctedAecDelayActiveEnabled = values["correctedAecDelayActiveEnabled"] as? Bool ?? false
    iosOutputVolumeCompensationEnabled = values["iosOutputVolumeCompensationEnabled"] as? Bool ?? true
  }
}

private enum VoiceError: LocalizedError {
  case audioFormat, inputUnavailable, invalidBytes
  var errorDescription: String? {
    switch self { case .audioFormat: return "Unable to create the 24 kHz mono PCM format"
    case .inputUnavailable: return "Microphone input format is unavailable"
    case .invalidBytes: return "pcmAudioWrite expects typed PCM bytes" }
  }
}
