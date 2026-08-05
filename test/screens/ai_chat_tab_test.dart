import 'dart:async';

import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/screens/ai_chat_tab.dart';
import 'package:career_path/services/ai_chat_repository.dart';
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

Widget _buildApp({
  required AiChatRepository repository,
  ValueChanged<AiChatSource?>? onOpenExplore,
  SpeechRecognitionService? speechRecognitionService,
  TextToSpeechService? textToSpeechService,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
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
      ),
    ),
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
}
