import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_chat.dart';
import '../services/ai_chat_repository.dart';
import '../services/gemini_key_service.dart';

enum AiChatLoadState { idle, sending }

class AiChatController extends ChangeNotifier {
  static const int maxInputCharacters = 500;
  static const int maxHistoryTurns = 8;
  static const int maxHistoryCharacters = 6000;

  final AiChatRepository _repository;
  final Random _random;
  final List<AiChatMessage> _messages = [];

  late String _sessionId;
  AiChatLoadState _loadState = AiChatLoadState.idle;
  bool _chatBlocked = false;
  int _generation = 0;
  String? _dataVersion;

  AiChatController(this._repository, {Random? random})
    : _random = random ?? Random.secure() {
    _sessionId = _newId();
  }

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  AiChatLoadState get loadState => _loadState;
  bool get isSending => _loadState == AiChatLoadState.sending;
  bool get chatBlocked => _chatBlocked;
  bool get hasMessages => _messages.isNotEmpty;

  Future<void> sendMessage({
    required String text,
    required String locale,
    String? streamId,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty ||
        normalized.runes.length > maxInputCharacters ||
        isSending ||
        _chatBlocked) {
      return;
    }

    final requestGeneration = ++_generation;
    final requestId = _newId();
    _messages.add(
      AiChatMessage(id: _newId(), role: AiChatRole.user, content: normalized),
    );
    _loadState = AiChatLoadState.sending;
    notifyListeners();

    try {
      final response = await _repository.send(
        AiChatRequest(
          requestId: requestId,
          sessionId: _sessionId,
          locale: locale,
          messages: _boundedHistory(),
          streamId: streamId,
          dataVersion: _dataVersion,
        ),
      );
      if (requestGeneration != _generation) return;

      _dataVersion = response.dataVersion ?? _dataVersion;
      _chatBlocked =
          response.chatBlocked || response.status == AiChatStatus.blocked;
      _messages.add(
        AiChatMessage(
          id: _newId(),
          role: AiChatRole.assistant,
          content: response.answer,
          status: response.status,
          sources: response.sources,
          suggestedPrompts: response.suggestedPrompts,
        ),
      );
    } on Exception catch (error) {
      if (requestGeneration != _generation) return;
      final failure = error is GeminiKeyException
          ? error.code
          : error.runtimeType.toString();
      debugPrint('[AI Guide] Request unavailable ($failure)');
      _messages.add(
        AiChatMessage(
          id: _newId(),
          role: AiChatRole.assistant,
          content: '',
          status: AiChatStatus.error,
          isError: true,
        ),
      );
    } finally {
      if (requestGeneration == _generation) {
        _loadState = AiChatLoadState.idle;
        notifyListeners();
      }
    }
  }

  Future<void> retryLast({required String locale, String? streamId}) async {
    if (isSending || _chatBlocked || _messages.isEmpty) return;

    if (_messages.last.isError) {
      _messages.removeLast();
    }
    final lastUserIndex = _messages.lastIndexWhere(
      (message) => message.role == AiChatRole.user,
    );
    if (lastUserIndex < 0) {
      notifyListeners();
      return;
    }

    final prompt = _messages[lastUserIndex].content;
    _messages.removeRange(lastUserIndex, _messages.length);
    await sendMessage(text: prompt, locale: locale, streamId: streamId);
  }

  void stop() {
    if (!isSending) return;
    _generation++;
    _loadState = AiChatLoadState.idle;
    notifyListeners();
  }

  void startNewChat() {
    _generation++;
    _messages.clear();
    _loadState = AiChatLoadState.idle;
    _sessionId = _newId();
    _dataVersion = null;
    _chatBlocked = false;
    // The backend remains authoritative and can re-apply an active temporary
    // safety block to the new ephemeral chat.
    notifyListeners();
  }

  List<AiChatMessage> _boundedHistory() {
    final result = <AiChatMessage>[];
    var characters = 0;

    for (final message in _messages.reversed) {
      if (result.length >= maxHistoryTurns) break;
      final messageCharacters = message.content.runes.length;
      if (characters + messageCharacters > maxHistoryCharacters &&
          result.isNotEmpty) {
        break;
      }
      result.add(message);
      characters += messageCharacters;
    }
    return result.reversed.toList(growable: false);
  }

  String _newId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = List.generate(
      3,
      (_) => _random.nextInt(1 << 32).toRadixString(36),
    ).join();
    return '$timestamp-$random';
  }
}
