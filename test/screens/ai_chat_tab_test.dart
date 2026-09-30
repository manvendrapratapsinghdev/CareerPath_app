import 'dart:async';
import 'dart:typed_data';

import 'package:career_path/controllers/live_voice_controller.dart';
import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/screens/ai_chat_tab.dart';
import 'package:career_path/services/ai_chat_repository.dart';
import 'package:career_path/services/ai_voice_services.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/gemini_live_client.dart';
import 'package:career_path/services/live_voice_tools.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:career_path/services/voice_preview_service.dart';
import 'package:career_path/services/voice_settings_service.dart';
import 'package:live_audio/live_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/services/speech_recognition_service.dart';
import 'package:career_path/services/text_to_speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiChatRepository extends AiChatRepository {
  AiChatResponse response;
  final List<AiChatRequest> requests = [];

  _FakeAiChatRepository(this.response);

  @override
  Future<AiChatResponse> send(AiChatRequest request) async {
    requests.add(request);
    return AiChatResponse(
      requestId: request.requestId,
      status: response.status,
      answer: response.answer,
      sources: response.sources,
      suggestedPrompts: response.suggestedPrompts,
      chatBlocked: response.chatBlocked,
      sections: response.sections,
    );
  }
}

class _PendingAiChatRepository extends AiChatRepository {
  final response = Completer<AiChatResponse>();

  @override
  Future<AiChatResponse> send(AiChatRequest request) => response.future;
}

class _FakeSpeechRecognitionService implements SpeechRecognitionService {
  final bool available;
  final Completer<bool>? initializeCompleter;
  SpeechResultCallback? _onResult;
  ValueChanged<String>? _onStatus;
  ValueChanged<String>? _onError;
  String? requestedLocaleId;
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  _FakeSpeechRecognitionService({
    this.available = true,
    this.initializeCompleter,
  });

  @override
  Future<bool> initialize({
    required ValueChanged<String> onStatus,
    required ValueChanged<String> onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    return initializeCompleter?.future ?? available;
  }

  @override
  Future<void> startListening({
    required SpeechResultCallback onResult,
    String? localeId,
  }) async {
    startCount++;
    requestedLocaleId = localeId;
    _onResult = onResult;
  }

  void emitResult(String words, {bool isFinal = false}) {
    _onResult?.call(words, isFinal);
  }

  void emitStatus(String status) => _onStatus?.call(status);

  void emitError() => _onError?.call('test error');

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  void dispose() {}
}

class _FakeTextToSpeechService implements TextToSpeechService {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  ValueChanged<String>? _onError;
  final List<String> spokenTexts = [];
  final List<String> spokenLanguages = [];
  int stopCount = 0;

  @override
  void setHandlers({
    required VoidCallback onStart,
    required VoidCallback onComplete,
    required ValueChanged<String> onError,
  }) {
    _onStart = onStart;
    _onComplete = onComplete;
    _onError = onError;
  }

  @override
  Future<bool> speak(String text, {String language = 'en-US'}) async {
    spokenTexts.add(text);
    spokenLanguages.add(language);
    _onStart?.call();
    return true;
  }

  void complete() => _onComplete?.call();

  void emitError() => _onError?.call('test error');

  @override
  Future<void> stop() async {
    stopCount++;
    _onComplete?.call();
  }

  @override
  void dispose() {}
}

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'test-key';
}

class _FakeVoiceAudio extends VoiceAssistantAudioBridge {
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
  Future<void> writePlayer(Uint8List bytes) async {}
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

class _FakeLiveClient extends GeminiLiveClient {
  final _events = StreamController<LiveEvent>.broadcast();

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
  void sendText(String text) => textsSent.add(text);
  final textsSent = <String>[];
  @override
  void sendAudio(Uint8List pcm16k) {}
  @override
  void sendToolResponses(List<Map<String, dynamic>> responses) {}
  @override
  Future<void> close() async {}

  void emit(LiveEvent event) => _events.add(event);
}

/// Hands back a pre-built [LiveVoiceController] (backed by fakes) instead of
/// constructing a real one, so a voice conversation can be driven in a
/// widget test.
class _FakeVoiceServices extends AiVoiceServices {
  final LiveVoiceController controller;

  _FakeVoiceServices({
    required this.controller,
    required super.keyService,
    required super.grounding,
    required super.settings,
    required super.preview,
  });

  @override
  LiveVoiceController createController({String? Function()? streamId}) =>
      controller;
}

Widget _buildApp({
  required AiChatRepository repository,
  ValueChanged<AiChatSource?>? onOpenExplore,
  SpeechRecognitionService? speechRecognitionService,
  TextToSpeechService? textToSpeechService,
  AiVoiceServices? voiceServices,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('hi')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: AiChatTab(
        repository: repository,
        onOpenExplore: onOpenExplore ?? (_) {},
        speechRecognitionService:
            speechRecognitionService ?? _FakeSpeechRecognitionService(),
        textToSpeechService: textToSpeechService ?? _FakeTextToSpeechService(),
        voiceServices: voiceServices,
      ),
    ),
  );
}

Future<AiVoiceServices> _voiceServices() async {
  SharedPreferences.setMockInitialValues({});
  final keys = GeminiKeyService();
  return AiVoiceServices(
    keyService: keys,
    grounding: LocalAiGroundingService(CareerDataService(ApiClient())),
    settings: VoiceSettingsService(await SharedPreferences.getInstance()),
    preview: VoicePreviewService(keyService: keys),
  );
}

void main() {
  testWidgets('shows polished empty state and starter prompts', (tester) async {
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Answer',
      ),
    );

    await tester.pumpWidget(_buildApp(repository: repository));

    expect(find.text('CareerPath AI Guide'), findsOneWidget);
    expect(find.text('Ask about your career path'), findsAtLeastNWidgets(1));
    expect(
      find.text(
        'Answers use information available in CareerPath Explore. '
        'AI can make errors.',
      ),
      findsOneWidget,
    );
    expect(find.text('What can I do after 12th Science?'), findsOneWidget);
    expect(
      find.text('What career options are available in Computer Science?'),
      findsOneWidget,
    );
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(find.byTooltip('Speak your question'), findsOneWidget);
  });

  testWidgets('speech input keeps typed text and inserts recognized words', (
    tester,
  ) async {
    final speechService = _FakeSpeechRecognitionService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Answer',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: speechService,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Please');
    await tester.tap(find.byTooltip('Speak your question'));
    await tester.pump();

    expect(speechService.startCount, 1);
    expect(speechService.requestedLocaleId, isNull);
    expect(find.byTooltip('Stop listening'), findsOneWidget);
    expect(find.text('Listening...'), findsOneWidget);

    speechService.emitResult('show computer science careers');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Please show computer science careers',
    );

    speechService.emitResult('show computer science careers', isFinal: true);
    await tester.pump();
    expect(find.byTooltip('Stop listening'), findsOneWidget);

    speechService.emitStatus('done');
    await tester.pump();
    expect(find.byTooltip('Speak your question'), findsOneWidget);
  });

  testWidgets('mic becomes active immediately without a loading spinner', (
    tester,
  ) async {
    final initialization = Completer<bool>();
    final speechService = _FakeSpeechRecognitionService(
      initializeCompleter: initialization,
    );
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Answer',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: speechService,
      ),
    );
    await tester.tap(find.byTooltip('Speak your question'));
    await tester.pump();

    expect(find.byTooltip('Stop listening'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    initialization.complete(true);
    await tester.pump();
    expect(speechService.startCount, 1);
  });

  testWidgets('stopping dictation keeps text and ignores late speech results', (
    tester,
  ) async {
    final speechService = _FakeSpeechRecognitionService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Answer',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: speechService,
      ),
    );
    await tester.tap(find.byTooltip('Speak your question'));
    await tester.pump();
    speechService.emitResult('computer science careers');
    await tester.pump();

    await tester.tap(find.byTooltip('Stop listening'));
    await tester.pump();
    speechService.emitResult('late unwanted result', isFinal: true);
    await tester.pump();

    expect(speechService.stopCount, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'computer science careers',
    );
    expect(find.byTooltip('Speak your question'), findsOneWidget);
  });

  testWidgets('unavailable speech input shows a safe recovery message', (
    tester,
  ) async {
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Answer',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: _FakeSpeechRecognitionService(
          available: false,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Speak your question'));
    await tester.pump();

    expect(
      find.text(
        'Voice input is unavailable. Check microphone permission and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('submits prompt and renders answer, source, and follow-up', (
    tester,
  ) async {
    AiChatSource? openedSource;
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'You can explore computer science.',
        sources: [
          AiChatSource(
            sourceId: 'career_node:1',
            sourceType: 'career_node',
            title: 'Computer Science',
            exploreNodeId: '1',
          ),
        ],
        suggestedPrompts: ['Which institutes are listed?'],
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        onOpenExplore: (source) => openedSource = source,
      ),
    );
    await tester.enterText(find.byType(TextField), 'What can I study?');
    await tester.pump();
    final sendButton = find.ancestor(
      of: find.byIcon(Icons.arrow_upward_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(1));
    expect(
      repository.requests.single.messages.single.content,
      'What can I study?',
    );
    expect(find.text('You can explore computer science.'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('Which institutes are listed?'), findsOneWidget);

    await tester.tap(find.text('Computer Science'));
    expect(openedSource?.exploreNodeId, '1');
  });

  testWidgets('reads an AI response aloud and allows playback to stop', (
    tester,
  ) async {
    final textToSpeechService = _FakeTextToSpeechService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'You can explore computer science.',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        textToSpeechService: textToSpeechService,
      ),
    );
    await tester.enterText(find.byType(TextField), 'What can I study?');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Read response aloud'));
    await tester.pump();

    expect(textToSpeechService.spokenTexts, [
      'You can explore computer science.',
    ]);
    expect(find.byTooltip('Stop reading'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop reading'));
    await tester.pump();
    expect(textToSpeechService.stopCount, 1);
    expect(find.byTooltip('Read response aloud'), findsOneWidget);
  });

  testWidgets('automatically reads response when voice contributed to prompt', (
    tester,
  ) async {
    final speechService = _FakeSpeechRecognitionService();
    final textToSpeechService = _FakeTextToSpeechService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Explore computer science careers.',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: speechService,
        textToSpeechService: textToSpeechService,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Please show');
    await tester.tap(find.byTooltip('Speak your question'));
    await tester.pump();
    speechService.emitResult('computer science careers');
    await tester.pump();
    speechService.emitStatus('done');
    await tester.pump();

    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requests, hasLength(1));
    expect(
      repository.requests.single.messages.single.content,
      'Please show computer science careers',
    );
    expect(textToSpeechService.spokenTexts, [
      'Explore computer science careers.',
    ]);
    expect(find.byTooltip('Stop reading'), findsOneWidget);
  });

  testWidgets('does not automatically read response for typed-only prompt', (
    tester,
  ) async {
    final textToSpeechService = _FakeTextToSpeechService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'Explore computer science careers.',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        textToSpeechService: textToSpeechService,
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'Show computer science careers',
    );
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(textToSpeechService.spokenTexts, isEmpty);
  });

  testWidgets('shows an interactive message while exploring career data', (
    tester,
  ) async {
    final repository = _PendingAiChatRepository();

    await tester.pumpWidget(_buildApp(repository: repository));
    await tester.enterText(find.byType(TextField), 'What can I study?');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump();

    expect(find.text('AI is exploring your career path...'), findsOneWidget);

    repository.response.complete(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'A grounded answer',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('insufficient answer offers navigation to Explore', (
    tester,
  ) async {
    var exploreOpened = false;
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.insufficientData,
        answer: 'Sorry, I do not have enough information.',
      ),
    );

    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        onOpenExplore: (_) => exploreOpened = true,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Tell me about astronomy');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Explore'));

    expect(exploreOpened, isTrue);
  });

  testWidgets('new chat requires confirmation and clears messages', (
    tester,
  ) async {
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'response',
        status: AiChatStatus.answered,
        answer: 'A grounded answer',
      ),
    );

    await tester.pumpWidget(_buildApp(repository: repository));
    await tester.enterText(find.byType(TextField), 'A question');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Start a new chat?'), findsOneWidget);

    await tester.tap(find.text('Start new chat'));
    await tester.pumpAndSettle();

    expect(find.text('A question'), findsNothing);
    expect(find.text('A grounded answer'), findsNothing);
    expect(find.text('What can I do after 12th Science?'), findsOneWidget);
  });

  testWidgets('Talk and voice settings appear only with voice services', (
    tester,
  ) async {
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'r',
        status: AiChatStatus.answered,
        answer: 'ok',
      ),
    );
    await tester.pumpWidget(_buildApp(repository: repository));
    expect(find.byTooltip('Start a voice conversation'), findsNothing);

    await tester.pumpWidget(
      _buildApp(repository: repository, voiceServices: await _voiceServices()),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Start a voice conversation'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pumpAndSettle();
    expect(find.text('Voice settings'), findsOneWidget);
  });

  testWidgets('structured answers render their section headings', (
    tester,
  ) async {
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'r',
        status: AiChatStatus.answered,
        answer: 'Engineering is a Science path.',
        sections: [
          AiAnswerSection(
            title: 'Here you go:',
            body: 'Engineering is a path.',
          ),
          AiAnswerSection(title: 'Options', body: '• Computer Science'),
        ],
      ),
    );
    await tester.pumpWidget(_buildApp(repository: repository));
    await tester.enterText(find.byType(TextField), 'Tell me about engineering');
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Options'), findsOneWidget);
    expect(find.text('• Computer Science'), findsOneWidget);
  });

  testWidgets('Hindi UI listens in Hindi and reads Hindi answers in Hindi', (
    tester,
  ) async {
    final speech = _FakeSpeechRecognitionService();
    final tts = _FakeTextToSpeechService();
    final repository = _FakeAiChatRepository(
      const AiChatResponse(
        requestId: 'r',
        status: AiChatStatus.answered,
        answer: 'इंजीनियरिंग एक विज्ञान का रास्ता है।',
      ),
    );
    await tester.pumpWidget(
      _buildApp(
        repository: repository,
        speechRecognitionService: speech,
        textToSpeechService: tts,
        locale: const Locale('hi'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CareerPath AI गाइड'), findsOneWidget);
    await tester.tap(find.byTooltip('अपना सवाल बोलें'));
    await tester.pump();
    expect(speech.requestedLocaleId, 'hi_IN');

    speech.emitResult('इंजीनियरिंग क्या है', isFinal: true);
    await tester.pump();
    await tester.tap(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requests.single.locale, 'hi');
    expect(tts.spokenLanguages, ['hi-IN']);
  });

  testWidgets(
    'voice runs in a strip in place of the message box and streams every '
    'turn into the chat above it',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
      final grounding = LocalAiGroundingService(data);
      final client = _FakeLiveClient();
      final controller = LiveVoiceController(
        keyService: _FakeKeys(),
        tools: LiveVoiceTools(
          grounding: grounding,
          loadAppHelp: () async => '',
        ),
        audio: _FakeVoiceAudio(),
        client: client,
      );
      final repository = _FakeAiChatRepository(
        const AiChatResponse(
          requestId: 'r',
          status: AiChatStatus.answered,
          answer: 'ok',
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          repository: repository,
          voiceServices: _FakeVoiceServices(
            controller: controller,
            keyService: _FakeKeys(),
            grounding: grounding,
            settings: VoiceSettingsService(
              await SharedPreferences.getInstance(),
            ),
            preview: VoicePreviewService(keyService: _FakeKeys()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The mic timer and the orb animation run while voice is active, so
      // `pumpAndSettle` never returns here — advance by fixed steps instead.
      Future<void> settle() => tester.pump(const Duration(milliseconds: 100));
      final panel = find.byTooltip('Type instead');
      LiveToolCall route(String id, String query, String intent) =>
          LiveToolCall([
            LiveFunctionCall(
              id: id,
              name: 'route_query',
              args: {
                'query': query,
                'intent': intent,
                'standalone_query': query,
                'is_follow_up': false,
                'requires_search': true,
                'input_language': 'english',
              },
            ),
          ]);

      await tester.tap(find.byTooltip('Start a voice conversation'));
      await settle();
      // Past the composer → panel transition.
      await tester.pump(const Duration(milliseconds: 300));
      expect(panel, findsOneWidget);
      // The panel replaces the message box.
      expect(find.byType(TextField), findsNothing);
      // No spoken introduction: nothing is sent until the student speaks.
      expect(client.textsSent, isEmpty);

      // The strip holds no text of its own: what the guide says streams
      // into the chat and stays there once spoken.
      client.emit(const LiveOutputTranscript('Hi! Ask me anything.'));
      await settle();
      expect(find.text('Hi! Ask me anything.'), findsOneWidget);
      client.emit(const LiveTurnComplete());
      await settle();
      expect(find.text('Hi! Ask me anything.'), findsOneWidget);

      // The student's words stream into the chat while they speak, and
      // become one question once recognised.
      client.emit(const LiveInputTranscript('hello there'));
      await settle();
      expect(find.text('hello there'), findsOneWidget);
      client.emit(route('1', 'hello there', 'small_talk'));
      await settle();
      expect(find.text('hello there'), findsOneWidget);

      // Spoken-only turns are kept in the chat too.
      client
        ..emit(const LiveOutputTranscript('Happy to chat!'))
        ..emit(const LiveTurnComplete());
      await settle();
      expect(find.text('Happy to chat!'), findsOneWidget);

      // An answer backed by records shows its source chips.
      client.emit(route('2', 'Tell me about engineering', 'career'));
      await settle();
      await settle();
      client.emit(
        const LiveToolCall([
          LiveFunctionCall(
            id: '3',
            name: 'format_answer',
            args: {
              'draft':
                  '<Title>Here you go:</Title> Engineering is about technology.'
                  '\nQuestions:\n1. What can I study?\nAnswers:\n1. Computer '
                  'Science.',
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
      // Past the playback drain, which ends the live bubble.
      await tester.pump(const Duration(milliseconds: 300));

      expect(panel, findsOneWidget);
      expect(find.text('Tell me about engineering'), findsOneWidget);
      expect(find.text('Engineering is about technology.'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Engineering'), findsOneWidget);

      // Nothing found shows the Explore fallback in chat.
      client.emit(route('4', 'Tell me about astronomy telescopes', 'career'));
      await settle();
      await settle();
      client
        ..emit(LiveAudio(Uint8List.fromList([3, 4])))
        ..emit(
          const LiveOutputTranscript("I couldn't find that in CareerPath yet."),
        )
        ..emit(const LiveTurnComplete());
      await settle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(panel, findsOneWidget);
      expect(
        find.text("I couldn't find that in CareerPath yet."),
        findsOneWidget,
      );
      expect(find.text('Open Explore'), findsOneWidget);

      // Ending voice restores the message box; no end-of-call summary.
      await tester.tap(find.byTooltip('End voice conversation'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(controller.isActive, isFalse);
      expect(
        find.text("Here's what we covered — tap to explore further:"),
        findsNothing,
      );
      expect(find.byTooltip('Start a voice conversation'), findsOneWidget);
    },
  );

  testWidgets('keyboard button ends voice and focuses the message box', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final grounding = LocalAiGroundingService(CareerDataService(ApiClient()));
    final controller = LiveVoiceController(
      keyService: _FakeKeys(),
      tools: LiveVoiceTools(grounding: grounding, loadAppHelp: () async => ''),
      audio: _FakeVoiceAudio(),
      client: _FakeLiveClient(),
    );
    await tester.pumpWidget(
      _buildApp(
        repository: _FakeAiChatRepository(
          const AiChatResponse(
            requestId: 'r',
            status: AiChatStatus.answered,
            answer: 'ok',
          ),
        ),
        voiceServices: _FakeVoiceServices(
          controller: controller,
          keyService: _FakeKeys(),
          grounding: grounding,
          settings: VoiceSettingsService(await SharedPreferences.getInstance()),
          preview: VoicePreviewService(keyService: _FakeKeys()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start a voice conversation'));
    // Past the composer → panel transition.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Type instead'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(controller.isActive, isFalse);
    expect(find.byTooltip('Type instead'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode?.hasFocus, isTrue);
  });
}
