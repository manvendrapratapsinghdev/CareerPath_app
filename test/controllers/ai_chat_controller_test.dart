import 'dart:async';
import 'dart:math';

import 'package:career_path/controllers/ai_chat_controller.dart';
import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/services/ai_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiChatRepository extends AiChatRepository {
  final List<AiChatRequest> requests = [];
  Future<AiChatResponse> Function(AiChatRequest request)? handler;

  @override
  Future<AiChatResponse> send(AiChatRequest request) {
    requests.add(request);
    return handler?.call(request) ??
        Future.value(
          AiChatResponse(
            requestId: request.requestId,
            status: AiChatStatus.answered,
            answer: 'Grounded answer',
          ),
        );
  }
}

void main() {
  group('AiChatController', () {
    test(
      'sends trimmed text with locale and optional stream context',
      () async {
        final repository = _FakeAiChatRepository();
        final controller = AiChatController(repository, random: Random(1));

        await controller.sendMessage(
          text: '  Tell me about science  ',
          locale: 'en',
          streamId: 'science',
        );

        expect(repository.requests, hasLength(1));
        expect(repository.requests.single.locale, 'en');
        expect(repository.requests.single.streamId, 'science');
        expect(
          repository.requests.single.messages.single.content,
          'Tell me about science',
        );
        expect(controller.messages, hasLength(2));
        expect(controller.messages.last.content, 'Grounded answer');
        expect(controller.isSending, isFalse);
      },
    );

    test('does not send empty, oversized, or concurrent prompts', () async {
      final repository = _FakeAiChatRepository();
      final completer = Completer<AiChatResponse>();
      repository.handler = (_) => completer.future;
      final controller = AiChatController(repository, random: Random(2));

      await controller.sendMessage(text: '  ', locale: 'en');
      await controller.sendMessage(
        text: 'x' * (AiChatController.maxInputCharacters + 1),
        locale: 'en',
      );
      final pending = controller.sendMessage(text: 'First', locale: 'en');
      await controller.sendMessage(text: 'Second', locale: 'en');

      expect(repository.requests, hasLength(1));
      completer.complete(
        AiChatResponse(
          requestId: repository.requests.single.requestId,
          status: AiChatStatus.answered,
          answer: 'Done',
        ),
      );
      await pending;
    });

    test(
      'maps failures to a retryable error and retries the user prompt',
      () async {
        final repository = _FakeAiChatRepository();
        var attempt = 0;
        repository.handler = (request) async {
          attempt++;
          if (attempt == 1) throw const FormatException('failed');
          return AiChatResponse(
            requestId: request.requestId,
            status: AiChatStatus.answered,
            answer: 'Recovered',
          );
        };
        final controller = AiChatController(repository, random: Random(3));

        await controller.sendMessage(text: 'Help me', locale: 'en');
        expect(controller.messages.last.isError, isTrue);

        await controller.retryLast(locale: 'en');

        expect(repository.requests, hasLength(2));
        expect(repository.requests.last.messages.last.content, 'Help me');
        expect(controller.messages.last.content, 'Recovered');
      },
    );

    test('ignores an in-flight response after stop', () async {
      final repository = _FakeAiChatRepository();
      final completer = Completer<AiChatResponse>();
      repository.handler = (_) => completer.future;
      final controller = AiChatController(repository, random: Random(4));

      final pending = controller.sendMessage(text: 'Question', locale: 'en');
      controller.stop();
      completer.complete(
        AiChatResponse(
          requestId: repository.requests.single.requestId,
          status: AiChatStatus.answered,
          answer: 'Late response',
        ),
      );
      await pending;

      expect(controller.isSending, isFalse);
      expect(
        controller.messages.where(
          (message) => message.content == 'Late response',
        ),
        isEmpty,
      );
    });

    test(
      'new chat clears messages and rotates the ephemeral session',
      () async {
        final repository = _FakeAiChatRepository();
        final controller = AiChatController(repository, random: Random(5));

        await controller.sendMessage(text: 'First chat', locale: 'en');
        final firstSession = repository.requests.single.sessionId;
        controller.startNewChat();
        await controller.sendMessage(text: 'Second chat', locale: 'en');

        expect(controller.messages, hasLength(2));
        expect(repository.requests.last.sessionId, isNot(firstSession));
        expect(
          repository.requests.last.messages.where(
            (message) => message.content == 'First chat',
          ),
          isEmpty,
        );
      },
    );

    test('blocked response disables sending until a new local chat', () async {
      final repository = _FakeAiChatRepository();
      repository.handler = (request) async => AiChatResponse(
        requestId: request.requestId,
        status: AiChatStatus.blocked,
        answer: 'Chat blocked',
        chatBlocked: true,
      );
      final controller = AiChatController(repository, random: Random(6));

      await controller.sendMessage(text: 'Blocked request', locale: 'en');
      await controller.sendMessage(text: 'Ignored request', locale: 'en');
      expect(controller.chatBlocked, isTrue);
      expect(repository.requests, hasLength(1));

      controller.startNewChat();
      expect(controller.chatBlocked, isFalse);
      expect(controller.messages, isEmpty);
    });

    test('sends only the configured bounded history', () async {
      final repository = _FakeAiChatRepository();
      final controller = AiChatController(repository, random: Random(7));

      for (var i = 0; i < 6; i++) {
        await controller.sendMessage(text: 'Question $i', locale: 'en');
      }

      final finalHistory = repository.requests.last.messages;
      expect(finalHistory.length, AiChatController.maxHistoryTurns);
      expect(finalHistory.first.content, 'Grounded answer');
      expect(finalHistory.last.content, 'Question 5');
    });
  });
}
