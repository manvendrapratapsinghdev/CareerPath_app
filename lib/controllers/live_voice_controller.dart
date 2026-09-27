import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_audio/live_audio.dart';

import '../config/ai_provider_config.dart';
import '../services/gemini_key_service.dart';
import '../services/gemini_live_client.dart';
import '../services/live_voice_prompts.dart';
import '../services/live_voice_tools.dart';

enum LiveVoiceState {
  off,
  connecting,
  listening,
  thinking,
  speaking,
  reconnecting,
}

/// A finished voice turn.
class VoiceAnswer {
  final String question;
  final String spokenText;
  final VoiceTurn turn;

  const VoiceAnswer({
    required this.question,
    required this.spokenText,
    required this.turn,
  });
}

/// Runs a realtime voice conversation: the phone streams microphone audio to
/// Gemini Live, answers its tool calls from local CareerPath data and plays
/// the spoken reply.
class LiveVoiceController extends ChangeNotifier {
  final GeminiKeyService _keyService;
  final LiveVoiceTools tools;
  final VoiceAssistantAudioBridge _audio;
  final GeminiLiveClient _client;

  /// A spoken question was recognised.
  void Function(String question)? onQuestion;

  /// The assistant finished answering.
  void Function(VoiceAnswer answer)? onAnswer;

  /// The spoken welcome finished; its transcript.
  void Function(String transcript, List<String> starters)? onWelcome;

  /// No answer arrived even after a retry.
  VoidCallback? onUnavailable;

  /// The session ended on its own ('idle' or 'connection_lost').
  void Function(String reason)? onEnded;

  LiveVoiceController({
    required GeminiKeyService keyService,
    required this.tools,
    VoiceAssistantAudioBridge? audio,
    GeminiLiveClient? client,
    Object? Function()? httpClientFactory,
  }) : _keyService = keyService,
       _audio = audio ?? VoiceAssistantAudioBridge(),
       _client =
           client ?? GeminiLiveClient(httpClientFactory: httpClientFactory);

  LiveVoiceState _state = LiveVoiceState.off;
  LiveVoiceState get state => _state;
  bool get isActive => _state != LiveVoiceState.off;

  String _heard = '';
  String _spoken = '';

  /// What the assistant is saying right now.
  String get liveTranscript => _spoken;

  String _voiceName = AiProviderConfig.defaultVoice;
  bool _interruptions = true;
  bool _playAudio = true;
  bool _questionAnnounced = false;
  bool _welcomeActive = false;
  List<String> _welcomeStarters = const [];
  String? _lastQuestion;
  int _retries = 0;

  StreamSubscription<LiveEvent>? _events;
  Timer? _micTimer;
  Timer? _turnTimer;
  Timer? _idleTimer;
  Timer? _drainTimer;
  bool _playerStarted = false;
  bool _reading = false;
  int _playbackGeneration = 0;
  Future<void> _playback = Future.value();

  // Speech produced between search_careers and format_answer is a premature
  // draft: hold it, drop it if format_answer follows, play it otherwise.
  bool _holdSpeech = false;
  final _heldAudio = <Uint8List>[];
  String _heldText = '';

  Future<void> start({
    required String voiceName,
    required bool interruptions,
    required bool playAudio,
    String? welcomeGreeting,
    List<String> welcomeStarters = const [],
  }) async {
    if (isActive) return;
    _voiceName = voiceName;
    _interruptions = interruptions;
    _playAudio = playAudio;
    _retries = 0;
    _setState(LiveVoiceState.connecting);
    try {
      await _audio.requestAudioFocus('continuous');
      await _audio.setScreenAwake(true);
      final welcome = welcomeGreeting == null
          ? null
          : LiveVoicePrompts.welcome(
              greeting: welcomeGreeting,
              starters: welcomeStarters,
            );
      await _connect(sessionContext: welcome);
      await _audio.startRecorder();
      _micTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => unawaited(_pumpMic()),
      );
      _setState(LiveVoiceState.listening);
      _armIdle();
      if (welcome != null) {
        _beginTurn();
        _welcomeActive = true;
        _welcomeStarters = welcomeStarters;
        _client.sendText(LiveVoicePrompts.welcomeTrigger);
        _armTurnTimer();
      }
    } on Object catch (error) {
      debugPrint('[AI Guide voice] start failed (${error.runtimeType})');
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    _micTimer?.cancel();
    _turnTimer?.cancel();
    _idleTimer?.cancel();
    _drainTimer?.cancel();
    _micTimer = null;
    await _events?.cancel();
    _events = null;
    await _client.close();
    try {
      await _audio.stopRecorder();
    } on Object {
      // The recorder may not have started.
    }
    await _stopPlayback();
    try {
      await _audio.setScreenAwake(false);
      await _audio.releaseAudioFocus();
    } on Object {
      // Best effort.
    }
    _heard = '';
    _spoken = '';
    _welcomeActive = false;
    _setState(LiveVoiceState.off);
  }

  Future<void> _connect({String? sessionContext}) async {
    final key = await _keyService.getKey();
    await _events?.cancel();
    await _client.connect(
      apiKey: key,
      setup: LiveVoicePrompts.setup(
        voiceName: _voiceName,
        interruptions: _interruptions,
        sessionContext: sessionContext,
      ),
    );
    _events = _client.events.listen(_onEvent);
  }

  // ── Microphone ───────────────────────────────────────────────────────────

  Future<void> _pumpMic() async {
    if (_reading || !_client.isOpen) return;
    _reading = true;
    try {
      for (final frame in await _audio.readRecorderFrames()) {
        if (!_interruptions && _state == LiveVoiceState.speaking) continue;
        _client.sendAudio(downsample24kTo16k(frame.bytes));
      }
    } on Object catch (error) {
      debugPrint('[AI Guide voice] mic read failed (${error.runtimeType})');
    } finally {
      _reading = false;
    }
  }

  /// Linear 3:2 resampler for 24 kHz → 16 kHz PCM16 little-endian audio.
  static Uint8List downsample24kTo16k(Uint8List input) {
    final samples = ByteData.sublistView(input);
    final inCount = input.length ~/ 2;
    final outCount = inCount * 2 ~/ 3;
    final out = ByteData(outCount * 2);
    for (var i = 0; i < outCount; i++) {
      final position = i * 1.5;
      final index = position.floor();
      final fraction = position - index;
      final a = samples.getInt16(index * 2, Endian.little);
      final b = index + 1 < inCount
          ? samples.getInt16((index + 1) * 2, Endian.little)
          : a;
      out.setInt16(i * 2, (a + (b - a) * fraction).round(), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  // ── Server events ────────────────────────────────────────────────────────

  void _onEvent(LiveEvent event) {
    switch (event) {
      case LiveInputTranscript(:final text):
        if (!_interruptions && _state == LiveVoiceState.speaking) return;
        if (!_questionAnnounced && _heard.isEmpty) _beginTurn();
        _heard += text;
        _armIdle();
        notifyListeners();
      case LiveToolCall(:final calls) when _welcomeActive:
        _client.sendToolResponses([
          for (final call in calls)
            {
              'id': ?call.id,
              'name': call.name,
              'response': {'error': 'no_tools_during_welcome'},
            },
        ]);
      case LiveToolCall(:final calls):
        _turnTimer?.cancel();
        _setState(LiveVoiceState.thinking);
        unawaited(_answerTools(calls));
      case LiveAudio(:final pcm24k) when _holdSpeech:
        _turnTimer?.cancel();
        _heldAudio.add(pcm24k);
      case LiveAudio(:final pcm24k):
        _turnTimer?.cancel();
        _announceQuestion();
        _setState(LiveVoiceState.speaking);
        if (_playAudio) _play(pcm24k);
      case LiveOutputTranscript(:final text) when _holdSpeech:
        _heldText += text;
      case LiveOutputTranscript(:final text):
        _turnTimer?.cancel();
        _announceQuestion();
        _spoken += text;
        notifyListeners();
      case LiveInterrupted():
        unawaited(_stopPlayback());
        _finishTurn();
        _setState(LiveVoiceState.listening);
      case LiveTurnComplete():
        _releaseHeldSpeech();
        _finishTurn();
        _listenAfterPlayback();
      case LiveGoAway():
        unawaited(_reconnect());
      case LiveClosed():
        if (isActive && _state != LiveVoiceState.reconnecting) {
          unawaited(_reconnect());
        }
      case LiveSetupComplete() || LiveToolCallCancellation():
        break;
    }
  }

  Future<void> _answerTools(List<LiveFunctionCall> calls) async {
    final responses = <Map<String, dynamic>>[];
    for (final call in calls) {
      if (call.name == 'format_answer') _discardHeldSpeech();
      final response = await tools.execute(call);
      if (call.name == 'route_query') {
        final question = tools.turn.question;
        if (question != null && question.isNotEmpty) _heard = question;
        _announceQuestion();
      }
      responses.add({'id': ?call.id, 'name': call.name, 'response': response});
      if (call.name == 'search_careers') _holdSpeech = true;
    }
    _client.sendToolResponses(responses);
    _armTurnTimer();
  }

  void _discardHeldSpeech() {
    _holdSpeech = false;
    _heldAudio.clear();
    _heldText = '';
  }

  /// The model never formatted: its held draft is the answer after all.
  void _releaseHeldSpeech() {
    if (!_holdSpeech) return;
    _holdSpeech = false;
    if (_heldText.isNotEmpty) {
      _announceQuestion();
      _spoken += _heldText;
    }
    if (_heldAudio.isNotEmpty) {
      _setState(LiveVoiceState.speaking);
      if (_playAudio) _heldAudio.forEach(_play);
    }
    _heldAudio.clear();
    _heldText = '';
  }

  void _beginTurn() {
    _discardHeldSpeech();
    tools.startTurn();
    _questionAnnounced = false;
    _heard = '';
    _spoken = '';
  }

  void _announceQuestion() {
    if (_questionAnnounced || _welcomeActive) return;
    final question = (tools.turn.question ?? _heard).trim();
    if (question.isEmpty) return;
    _questionAnnounced = true;
    _lastQuestion = question;
    onQuestion?.call(question);
  }

  void _finishTurn() {
    _turnTimer?.cancel();
    final spoken = _spoken.trim();
    if (_welcomeActive) {
      _welcomeActive = false;
      if (spoken.isNotEmpty) {
        tools.remember('What can I ask?', spoken);
        onWelcome?.call(spoken, _welcomeStarters);
      }
      _beginTurn();
      _armIdle();
      return;
    }
    if (!_questionAnnounced && spoken.isEmpty) {
      _beginTurn();
      return;
    }
    _announceQuestion();
    final turn = tools.turn;
    final answer = spoken.isNotEmpty ? spoken : turn.directAnswer ?? '';
    if (answer.isNotEmpty) {
      final question = turn.question ?? _heard;
      tools.remember(question, answer);
      onAnswer?.call(
        VoiceAnswer(question: question, spokenText: answer, turn: turn),
      );
    }
    _retries = 0;
    _beginTurn();
    _armIdle();
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  void _play(Uint8List pcm) {
    final generation = _playbackGeneration;
    _playback = _playback
        .then((_) async {
          if (generation != _playbackGeneration) return;
          if (!_playerStarted) {
            await _audio.startPlayer(mode: PcmPlaybackMode.communication);
            _playerStarted = true;
          }
          await _audio.writePlayer(pcm);
        })
        .catchError((Object error) {
          // A write racing a stop triggered by an interruption or reconnect
          // is expected — the generation has already moved on, so the audio
          // was meant to be discarded, not a real device failure.
          if (generation != _playbackGeneration) return;
          debugPrint('[AI Guide voice] playback failed (${error.runtimeType})');
        });
  }

  Future<void> _stopPlayback() async {
    _playbackGeneration++;
    _drainTimer?.cancel();
    if (!_playerStarted) return;
    _playerStarted = false;
    try {
      await _audio.stopPlayer();
    } on Object {
      // Already stopped.
    }
  }

  void _listenAfterPlayback() {
    _drainTimer?.cancel();
    if (!_playerStarted) {
      _setState(LiveVoiceState.listening);
      return;
    }
    var checks = 0;
    _drainTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) async {
      checks++;
      var playing = false;
      try {
        await _playback;
        final position = await _audio.playbackPosition();
        playing =
            position.isPlaying && position.queuedFrames > position.playedFrames;
      } on Object {
        playing = false;
      }
      if (!playing || checks > 300) {
        timer.cancel();
        if (_state == LiveVoiceState.speaking) {
          _setState(LiveVoiceState.listening);
        }
      }
    });
  }

  // ── Timeouts and reconnects ──────────────────────────────────────────────

  void _armTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = Timer(AiProviderConfig.liveTurnTimeout, () {
      unawaited(_onTurnTimeout());
    });
  }

  Future<void> _onTurnTimeout() async {
    if (_welcomeActive) {
      _welcomeActive = false;
      _beginTurn();
      _setState(LiveVoiceState.listening);
      return;
    }
    final question = _lastQuestion;
    if (_retries == 0 && question != null) {
      _retries++;
      await _reconnect(replay: question);
      return;
    }
    _retries = 0;
    onUnavailable?.call();
    _beginTurn();
    _setState(LiveVoiceState.listening);
  }

  Future<void> _reconnect({String? replay}) async {
    if (!isActive) return;
    _setState(LiveVoiceState.reconnecting);
    await _stopPlayback();
    try {
      await _connect(sessionContext: tools.sessionContext());
      _setState(LiveVoiceState.listening);
      if (replay != null) {
        _beginTurn();
        _client.sendText(replay);
        _armTurnTimer();
      }
    } on Object {
      await stop();
      onEnded?.call('connection_lost');
    }
  }

  void _armIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(AiProviderConfig.liveIdleTimeout, () async {
      if (_state == LiveVoiceState.listening) {
        await stop();
        onEnded?.call('idle');
      } else {
        _armIdle();
      }
    });
  }

  void _setState(LiveVoiceState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
