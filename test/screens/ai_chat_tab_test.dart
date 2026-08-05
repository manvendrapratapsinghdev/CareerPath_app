import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/screens/ai_chat_tab.dart';
import 'package:career_path/services/ai_chat_repository.dart';
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

Widget _buildApp({
  required AiChatRepository repository,
  ValueChanged<AiChatSource?>? onOpenExplore,
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
