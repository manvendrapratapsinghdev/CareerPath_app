import 'dart:async';
import 'dart:typed_data';

import 'package:career_path/controllers/live_voice_controller.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/gemini_live_client.dart';
import 'package:career_path/services/live_voice_tools.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_audio/live_audio.dart';

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'test-key';
}

class _FakeAudio extends VoiceAssistantAudioBridge {
  final played = <Uint8List>[];

  /// Frames the next mic read returns.
  final frames = <Uint8List>[];

  @override
  Future<bool> requestAudioFocus(String mode) async => true;
  @override
  Future<void> releaseAudioFocus() async {}
  @override
  Future<void> setScreenAwake(bool enabled) async {}
  @override
  Future<Map<String, dynamic>> startRecorder({
    String? audioSource,
    NativeAudioProcessingConfig processingConfig =
        const NativeAudioProcessingConfig(),
  }) async => const {};
  @override
  Future<List<PcmCaptureChunk>> readRecorderFrames({
    int frameBytes = 3840,
  }) async {
    final chunks = [for (final f in frames) PcmCaptureChunk(f, 0, const {})];
    frames.clear();
    return chunks;
  }

  @override
  Future<void> stopRecorder() async {}
  @override
  Future<void> startPlayer({
    PcmPlaybackMode mode = PcmPlaybackMode.assistant,
    bool iosOutputVolumeCompensationEnabled = true,
    Duration iosPlaybackDrainDelay = Duration.zero,
    String? queryType,
  }) async {}
  @override
  Future<void> writePlayer(Uint8List bytes) async => played.add(bytes);

  /// The phone is still playing queued answer audio.
  bool playing = false;
  var playerStops = 0;

  @override
  Future<PcmPlaybackPosition> playbackPosition() async => PcmPlaybackPosition(
    playedFrames: 0,
    queuedFrames: playing ? 48000 : 0,
    sampleRate: 24000,
    isPlaying: playing,
  );
  @override
  Future<void> stopPlayer() async => playerStops++;
}

class _FakeClient extends GeminiLiveClient {
  final _events = StreamController<LiveEvent>.broadcast();
  final toolResponses = <List<Map<String, dynamic>>>[];
  var audioSent = 0;

  @override
  Stream<LiveEvent> get events => _events.stream;
  @override
  bool get isOpen => true;
  @override
  Future<void> connect({
    required String apiKey,
    required Map<String, dynamic> setup,
  }) async {}
  @override
  void sendText(String text) {}
  @override
  void sendAudio(Uint8List pcm16k) => audioSent++;
  @override
  void sendToolResponses(List<Map<String, dynamic>> responses) =>
      toolResponses.add(responses);
  @override
  Future<void> close() async {}

  void emit(LiveEvent event) => _events.add(event);
}

LiveVoiceTools _tools({ExtraGrounding? extra}) {
  final data = CareerDataService(ApiClient())
    ..initializeWithData(
      [
        StreamModel(
          id: 'science',
          name: 'Science',
          categoryIds: ['engineering'],
        ),
      ],
      {
        'engineering': CareerNode(
          id: 'engineering',
          name: 'Engineering',
          intro: 'Study technology.',
        ),
      },
    );
  return LiveVoiceTools(
    grounding: LocalAiGroundingService(data),
    loadAppHelp: () async => '',
    extraGrounding: extra,
  );
}

Uint8List _tone(int amplitude) {
  final data = ByteData(480 * 2);
  for (var i = 0; i < 480; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('barge-in while the guide speaks', () {
    late _FakeClient client;
    late _FakeAudio audio;

    // _tone(a) has RMS a / 32768: 3000 ≈ 0.09 (echo left after echo
    // cancellation), 8000 ≈ 0.24 (a student talking over it).
    Future<void> mic(List<Uint8List> frames) async {
      audio.frames.addAll(frames);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    List<Uint8List> repeat(int amplitude, int count) => [
      for (var i = 0; i < count; i++) _tone(amplitude),
    ];

    Future<LiveVoiceController> speaking({bool interruptions = true}) async {
      client = _FakeClient();
      audio = _FakeAudio();
      final controller = LiveVoiceController(
        keyService: _FakeKeys(),
        tools: _tools(),
        audio: audio,
        client: client,
      );
      await controller.start(
        voiceName: 'Leda',
        interruptions: interruptions,
        playAudio: true,
      );
      client.emit(LiveAudio(Uint8List.fromList([1, 2])));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, LiveVoiceState.speaking);
      return controller;
    }

    test('the guide never hears itself, however loud its echo', () async {
      // No echo cancellation (a simulator): loud, uneven echo for 3 s.
      final controller = await speaking();
      await mic([
        for (var i = 0; i < 18; i++) ...[_tone(20000), _tone(9000)],
      ]);
      expect(client.audioSent, 0);
      // Its own words transcribed back are ignored too.
      client.emit(const LiveInputTranscript('the guide talking'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.heardTranscript, isEmpty);
      await controller.stop();
    });

    test(
      'a student talking over the echo cuts in, first words included',
      () async {
        final controller = await speaking();
        await mic([...repeat(3000, 8), ...repeat(8000, 3)]);
        // The three frames of speech plus the five just before them.
        expect(client.audioSent, 8);
        await mic(repeat(8000, 2));
        expect(client.audioSent, 10);

        client.emit(const LiveInputTranscript('wait, what about MBBS'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.heardTranscript, 'wait, what about MBBS');
        client.emit(const LiveInterrupted());
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.listening);
        await mic([_tone(300)]);
        expect(client.audioSent, 11, reason: 'listening: everything flows');
        await controller.stop();
      },
    );

    test('the start of an answer only learns the echo level', () async {
      final controller = await speaking();
      // Loud from the first frame, e.g. the guide's first word.
      await mic(repeat(8000, 6));
      expect(client.audioSent, 0);
      await controller.stop();
    });

    test('a short loud sound is not an interruption', () async {
      final controller = await speaking();
      await mic([...repeat(3000, 8), ...repeat(8000, 2), ...repeat(3000, 4)]);
      expect(client.audioSent, 0);
      await controller.stop();
    });

    test('a barge-in Gemini does not act on closes the mic again', () async {
      final controller = await speaking();
      await mic([...repeat(3000, 8), ...repeat(8000, 3)]);
      expect(client.audioSent, 8);
      // Gemini keeps talking: after the confirmation window, echo is held
      // back again instead of feeding a loop.
      await mic(repeat(3000, 30));
      expect(client.audioSent, 8 + 20);
      await controller.stop();
    });

    test(
      'with good echo cancellation the mic stays open, like before',
      () async {
        // A real phone: the echo left after echo cancellation is ~0.003.
        final controller = await speaking();
        await mic(repeat(100, 10));
        // After ~0.8 s the echo is judged quiet; the held audio goes out...
        expect(client.audioSent, 8);
        // ...and from then on every frame flows, quiet or loud, so Gemini
        // hears the student at once without any gate delay.
        await mic([_tone(300), _tone(3000), _tone(100)]);
        expect(client.audioSent, 11);
        client.emit(const LiveInputTranscript('what about law'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.heardTranscript, 'what about law');
        await controller.stop();
      },
    );

    test('loud echo keeps the gate on for the whole answer', () async {
      final controller = await speaking();
      await mic(repeat(3000, 30));
      expect(client.audioSent, 0);
      await controller.stop();
    });

    group('after Gemini has sent the whole answer', () {
      // Gemini sends audio faster than it plays: turnComplete arrives while
      // the phone still has seconds of the answer queued, and Gemini sends
      // no `interrupted` for a turn it has finished.
      Future<LiveVoiceController> stillPlaying() async {
        final controller = await speaking();
        audio.playing = true;
        client.emit(const LiveTurnComplete());
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.speaking);
        return controller;
      }

      test('with good echo cancellation the student stops the guide', () async {
        final controller = await speaking();
        await mic(repeat(100, 10));
        audio.playing = true;
        client.emit(const LiveTurnComplete());
        await Future<void>.delayed(Duration.zero);
        await mic(repeat(8000, 5));
        client.emit(const LiveInputTranscript('wait, what about law'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.listening);
        expect(audio.playerStops, 1);
        expect(controller.heardTranscript, 'wait, what about law');
        await controller.stop();
      });

      test('over loud echo the mic stays open until the transcript', () async {
        final controller = await stillPlaying();
        await mic([...repeat(3000, 8), ...repeat(8000, 3)]);
        expect(client.audioSent, 8);
        // Past the usual 1.6 s window: no `interrupted` will come, so the
        // mic waits for the student's transcript instead of closing.
        await mic(repeat(8000, 25));
        expect(client.audioSent, 33);
        client.emit(const LiveInputTranscript('what about law'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.listening);
        expect(audio.playerStops, 1);
        await controller.stop();
      });

      test('the guide\'s own words heard back do not stop it', () async {
        final controller = await speaking();
        await mic(repeat(100, 10));
        client.emit(const LiveOutputTranscript('Engineering is a good path.'));
        audio.playing = true;
        client.emit(const LiveTurnComplete());
        await Future<void>.delayed(Duration.zero);
        // Its own words heard back are not the student.
        client.emit(const LiveInputTranscript('engineering'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.speaking);
        expect(audio.playerStops, 0);
        // A word of the student's own is.
        client.emit(const LiveInputTranscript(' law'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, LiveVoiceState.listening);
        await controller.stop();
      });
    });

    test('a loud frame at the echo probe does not keep the gate on', () async {
      final controller = await speaking();
      await mic([...repeat(100, 9), _tone(8000), ...repeat(100, 5)]);
      // The probe moves to the next quiet frame and opens the mic.
      expect(client.audioSent, greaterThan(0));
      await mic([_tone(300)]);
      expect(client.audioSent, greaterThan(1));
      await controller.stop();
    });

    test('with interruptions off the guide is never cut off', () async {
      final controller = await speaking(interruptions: false);
      await mic([...repeat(3000, 8), ...repeat(20000, 10)]);
      expect(client.audioSent, 0);
      await controller.stop();
    });
  });

  test('recognises the guide\'s own words heard back', () {
    const said = [
      'B.Sc. in Operation Theatre Technology prepares you to assist in '
          'surgical procedures.',
    ];
    expect(LiveVoiceController.isOwnEcho('technology operation', said), isTrue);
    expect(
      LiveVoiceController.isOwnEcho('operation theatre technology', said),
      isTrue,
    );
    // A real interruption brings words of its own.
    expect(
      LiveVoiceController.isOwnEcho('stop, tell me about law instead', said),
      isFalse,
    );
    expect(
      LiveVoiceController.isOwnEcho('wait what about surgical nursing', said),
      isFalse,
    );
    // One word is too little to tell.
    expect(LiveVoiceController.isOwnEcho('technology', said), isFalse);
    // Hindi works the same way.
    expect(
      LiveVoiceController.isOwnEcho('इंजीनियरिंग कॉलेज', [
        'अच्छे इंजीनियरिंग कॉलेज जयपुर में',
      ]),
      isTrue,
    );
  });

  group('a barge-in that was really the guide\'s own voice', () {
    late _FakeClient client;
    late _FakeAudio audio;
    late LiveVoiceController controller;
    final questions = <String>[];
    final answers = <VoiceAnswer>[];

    LiveToolCall route(String id, String query) => LiveToolCall([
      LiveFunctionCall(
        id: id,
        name: 'route_query',
        args: {
          'query': query,
          'intent': 'career',
          'standalone_query': query,
          'search_keywords': query,
          'is_follow_up': false,
          'requires_search': true,
          'input_language': 'english',
        },
      ),
    ]);

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      questions.clear();
      answers.clear();
      client = _FakeClient();
      audio = _FakeAudio();
      controller =
          LiveVoiceController(
              keyService: _FakeKeys(),
              tools: _tools(),
              audio: audio,
              client: client,
            )
            ..onQuestion = questions.add
            ..onAnswer = answers.add;
      await controller.start(
        voiceName: 'Leda',
        interruptions: true,
        playAudio: true,
      );
      // The guide is answering...
      client
        ..emit(LiveAudio(Uint8List.fromList([1, 2])))
        ..emit(
          const LiveOutputTranscript(
            'B.Sc. in Operation Theatre Technology prepares you for surgery.',
          ),
        );
      await settle();
    });

    tearDown(() => controller.stop());

    Future<void> bargeIn() async {
      audio.frames.addAll([
        for (var i = 0; i < 8; i++) _tone(3000),
        for (var i = 0; i < 3; i++) _tone(8000),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(client.audioSent, greaterThan(0), reason: 'barge-in opened');
      client.emit(const LiveInterrupted());
      await settle();
    }

    test('is ignored: no question, no answer, silence', () async {
      await bargeIn();
      final played = audio.played.length;
      client.emit(route('9', 'technology operation'));
      await settle();
      await settle();
      final reply = client.toolResponses.last.single['response'] as Map;
      expect(reply['ignored'], isTrue);
      // Whatever Gemini still says for that turn is not played or shown.
      client
        ..emit(LiveAudio(Uint8List.fromList([7, 7])))
        ..emit(const LiveOutputTranscript('Operation theatre technology...'))
        ..emit(const LiveTurnComplete());
      await settle();
      expect(audio.played.length, played);
      expect(
        questions.where((q) => q.contains('technology operation')),
        isEmpty,
      );
      expect(
        answers.map((a) => a.question),
        isNot(contains('technology operation')),
      );
      expect(controller.state, LiveVoiceState.listening);
    });

    test(
      'a barge-in far louder than the echo is never taken for echo',
      () async {
        // Echo 0.03 (weak cancellation), student 0.24: eight times louder.
        audio.frames.addAll([
          for (var i = 0; i < 8; i++) _tone(1000),
          for (var i = 0; i < 3; i++) _tone(8000),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        client.emit(const LiveInterrupted());
        await settle();
        // Even though it reuses the guide's words, it is the student asking.
        client.emit(route('9', 'operation theatre technology'));
        await settle();
        await settle();
        final reply = client.toolResponses.last.single['response'] as Map;
        expect(reply.containsKey('ignored'), isFalse);
        expect(questions.last, 'operation theatre technology');
      },
    );

    test('a real interruption is answered', () async {
      await bargeIn();
      client.emit(route('9', 'stop, tell me about law instead'));
      await settle();
      await settle();
      final reply = client.toolResponses.last.single['response'] as Map;
      expect(reply.containsKey('ignored'), isFalse);
      expect(questions.last, 'stop, tell me about law instead');
    });

    test('a follow-up after the answer ends is never taken for echo', () async {
      client.emit(const LiveTurnComplete());
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      client.emit(route('9', 'operation theatre technology colleges'));
      await settle();
      await settle();
      final reply = client.toolResponses.last.single['response'] as Map;
      expect(reply.containsKey('ignored'), isFalse);
    });
  });

  test('mic audio flows normally while listening', () async {
    final client = _FakeClient();
    final audio = _FakeAudio();
    final controller = LiveVoiceController(
      keyService: _FakeKeys(),
      tools: _tools(),
      audio: audio,
      client: client,
    );
    await controller.start(
      voiceName: 'Leda',
      interruptions: true,
      playAudio: true,
    );
    audio.frames.addAll([_tone(300), _tone(20000)]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(client.audioSent, 2);
    await controller.stop();
  });

  test('mic level is 0 for silence and rises with loudness', () {
    Uint8List tone(int amplitude) {
      final data = ByteData(480 * 2);
      for (var i = 0; i < 480; i++) {
        data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    expect(LiveVoiceController.levelOf(Uint8List(0)), 0);
    expect(LiveVoiceController.levelOf(tone(0)), 0);
    final quiet = LiveVoiceController.levelOf(tone(500));
    final loud = LiveVoiceController.levelOf(tone(8000));
    expect(quiet, greaterThan(0));
    expect(loud, greaterThan(quiet));
    expect(LiveVoiceController.levelOf(tone(32767)), 1);
  });

  test('downsamples 24 kHz PCM16 to 16 kHz', () {
    final input = ByteData(6 * 2);
    for (var i = 0; i < 6; i++) {
      input.setInt16(i * 2, i * 300, Endian.little);
    }

    final output = LiveVoiceController.downsample24kTo16k(
      input.buffer.asUint8List(),
    );
    final samples = ByteData.sublistView(output);

    expect(output.length, 8);
    expect(samples.getInt16(0, Endian.little), 0);
    expect(samples.getInt16(2, Endian.little), 450);
    expect(samples.getInt16(4, Endian.little), 900);
  });

  test('a voice turn reports the question and one answer, dropping a '
      'draft spoken before formatting', () async {
    final client = _FakeClient();
    final audio = _FakeAudio();
    final questions = <String>[];
    final answers = <VoiceAnswer>[];
    final controller =
        LiveVoiceController(
            keyService: _FakeKeys(),
            tools: _tools(),
            audio: audio,
            client: client,
          )
          ..onQuestion = questions.add
          ..onAnswer = answers.add;

    await controller.start(
      voiceName: 'Leda',
      interruptions: true,
      playAudio: true,
    );
    expect(controller.state, LiveVoiceState.listening);

    Future<void> settle() => Future<void>.delayed(Duration.zero);
    client.emit(
      const LiveToolCall([
        LiveFunctionCall(
          id: '1',
          name: 'route_query',
          args: {
            'query': 'Tell me about engineering',
            'intent': 'career',
            'standalone_query': 'engineering',
            'is_follow_up': false,
            'requires_search': true,
            'input_language': 'english',
          },
        ),
      ]),
    );
    await settle();
    client.emit(
      const LiveToolCall([
        LiveFunctionCall(
          id: '2',
          name: 'search_careers',
          args: {'query': 'engineering'},
        ),
      ]),
    );
    await settle();
    // Premature draft: must not be played or shown.
    client
      ..emit(LiveAudio(Uint8List.fromList([9, 9])))
      ..emit(const LiveOutputTranscript('Draft answer. '));
    await settle();
    client.emit(
      const LiveToolCall([
        LiveFunctionCall(
          id: '3',
          name: 'format_answer',
          args: {
            'draft':
                '<Title>Here you go:</Title> Engineering is about technology.'
                '\nQuestions:\n1. What can I study?\nAnswers:\n1. Computer Science.',
          },
        ),
      ]),
    );
    await settle();
    client
      ..emit(LiveAudio(Uint8List.fromList([1, 2])))
      ..emit(const LiveOutputTranscript('Engineering is about technology.'))
      ..emit(const LiveTurnComplete());
    await settle();
    await settle();

    expect(questions, ['Tell me about engineering']);
    expect(answers.single.spokenText, 'Engineering is about technology.');
    expect(answers.single.turn.sources.first.exploreNodeId, 'engineering');
    expect(answers.single.turn.suggestions, ['What can I study?']);
    expect(audio.played, [
      [1, 2],
    ]);
    expect(client.toolResponses, hasLength(3));

    await controller.stop();
    expect(controller.state, LiveVoiceState.off);
  });

  test(
    'records from route_query hold draft speech; no search call needed',
    () async {
      final client = _FakeClient();
      final audio = _FakeAudio();
      final answers = <VoiceAnswer>[];
      final controller = LiveVoiceController(
        keyService: _FakeKeys(),
        tools: _tools(),
        audio: audio,
        client: client,
      )..onAnswer = answers.add;
      await controller.start(
        voiceName: 'Leda',
        interruptions: true,
        playAudio: true,
      );
      Future<void> settle() => Future<void>.delayed(Duration.zero);

      client.emit(
        const LiveToolCall([
          LiveFunctionCall(
            id: '1',
            name: 'route_query',
            args: {
              'query': 'Tell me about engineering',
              'intent': 'career',
              'standalone_query': 'engineering',
              'is_follow_up': false,
              'requires_search': true,
              'input_language': 'english',
            },
          ),
        ]),
      );
      await settle();
      await settle();
      expect(
        client.toolResponses.single.single['response'],
        contains('records'),
      );

      client
        ..emit(LiveAudio(Uint8List.fromList([9, 9])))
        ..emit(const LiveOutputTranscript('Draft. '));
      await settle();
      client.emit(
        const LiveToolCall([
          LiveFunctionCall(
            id: '2',
            name: 'format_answer',
            args: {
              'draft':
                  '<Title>Here you go:</Title> Engineering is technology.'
                  '\nQuestions:\n1. What?\nAnswers:\n1. CS.',
            },
          ),
        ]),
      );
      await settle();
      client
        ..emit(LiveAudio(Uint8List.fromList([1, 2])))
        ..emit(const LiveOutputTranscript('Engineering is technology.'))
        ..emit(const LiveTurnComplete());
      await settle();
      await settle();

      expect(answers.single.spokenText, 'Engineering is technology.');
      expect(audio.played, [
        [1, 2],
      ]);
      await controller.stop();
    },
  );

  test('semantic lookup starts while the student is still speaking', () async {
    final client = _FakeClient();
    final queries = <String>[];
    final controller = LiveVoiceController(
      keyService: _FakeKeys(),
      tools: _tools(
        extra: (q, s) async {
          queries.add(q);
          return AiGroundingContext.empty;
        },
      ),
      audio: _FakeAudio(),
      client: client,
    );
    await controller.start(
      voiceName: 'Leda',
      interruptions: true,
      playAudio: true,
    );
    client
      ..emit(const LiveInputTranscript('tell me about '))
      ..emit(const LiveInputTranscript('engineering colleges'));
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(queries, ['tell me about engineering colleges']);
    await controller.stop();
  });
}
