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
  }) async => const [];
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
  @override
  Future<PcmPlaybackPosition> playbackPosition() async =>
      const PcmPlaybackPosition(
        playedFrames: 0,
        queuedFrames: 0,
        sampleRate: 24000,
        isPlaying: false,
      );
  @override
  Future<void> stopPlayer() async {}
}

class _FakeClient extends GeminiLiveClient {
  final _events = StreamController<LiveEvent>.broadcast();
  final toolResponses = <List<Map<String, dynamic>>>[];

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
  void sendAudio(Uint8List pcm16k) {}
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
