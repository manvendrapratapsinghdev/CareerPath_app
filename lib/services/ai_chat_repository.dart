import '../models/ai_chat.dart';

abstract class AiChatRepository {
  Future<AiChatResponse> send(AiChatRequest request);

  void dispose() {}
}

class UnavailableAiChatRepository extends AiChatRepository {
  @override
  Future<AiChatResponse> send(AiChatRequest request) {
    throw StateError('AI provider is not configured');
  }
}
