enum AiChatRole { user, assistant }

enum AiChatStatus {
  answered,
  insufficientData,
  policyWarning,
  blocked,
  unsupportedLanguage,
  safetySupport,
  error;

  static AiChatStatus fromJson(String? value) {
    return switch (value) {
      'answered' => AiChatStatus.answered,
      'insufficient_data' => AiChatStatus.insufficientData,
      'policy_warning' => AiChatStatus.policyWarning,
      'blocked' => AiChatStatus.blocked,
      'unsupported_language' => AiChatStatus.unsupportedLanguage,
      'safety_support' => AiChatStatus.safetySupport,
      _ => AiChatStatus.error,
    };
  }
}

class AiChatSource {
  final String sourceId;
  final String sourceType;
  final String title;
  final String? exploreNodeId;

  const AiChatSource({
    required this.sourceId,
    required this.sourceType,
    required this.title,
    this.exploreNodeId,
  });

  factory AiChatSource.fromJson(Map<String, dynamic> json) {
    return AiChatSource(
      sourceId: json['sourceId'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      title: json['title'] as String? ?? '',
      exploreNodeId: json['exploreNodeId']?.toString(),
    );
  }
}

/// One titled section of a structured answer (`<Title>…</Title>` body).
class AiAnswerSection {
  final String title;
  final String body;

  const AiAnswerSection({required this.title, required this.body});

  factory AiAnswerSection.fromJson(Map<String, dynamic> json) =>
      AiAnswerSection(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'title': title, 'body': body};
}

class AiChatMessage {
  final String id;
  final AiChatRole role;
  final String content;
  final AiChatStatus? status;
  final List<AiChatSource> sources;
  final List<String> suggestedPrompts;
  final bool isError;

  /// Structured summary behind the answer, when one was produced.
  final List<AiAnswerSection> sections;

  /// True when the turn happened in a voice conversation.
  final bool fromVoice;

  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status,
    this.sources = const [],
    this.suggestedPrompts = const [],
    this.isError = false,
    this.sections = const [],
    this.fromVoice = false,
  });

  Map<String, dynamic> toRequestJson() => {
    'role': role.name,
    'content': content,
  };
}

class AiChatResponse {
  final String requestId;
  final AiChatStatus status;
  final String answer;
  final List<AiChatSource> sources;
  final List<String> suggestedPrompts;
  final bool chatBlocked;
  final String? dataVersion;

  /// Structured summary behind [answer], when the model produced one.
  final List<AiAnswerSection> sections;

  const AiChatResponse({
    required this.requestId,
    required this.status,
    required this.answer,
    this.sources = const [],
    this.suggestedPrompts = const [],
    this.chatBlocked = false,
    this.dataVersion,
    this.sections = const [],
  });

  factory AiChatResponse.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final rawPrompts = json['suggestedPrompts'];
    return AiChatResponse(
      requestId: json['requestId'] as String? ?? '',
      status: AiChatStatus.fromJson(json['status'] as String?),
      answer: json['answer'] as String? ?? '',
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (source) =>
                      AiChatSource.fromJson(Map<String, dynamic>.from(source)),
                )
                .where(
                  (source) =>
                      source.sourceId.isNotEmpty && source.title.isNotEmpty,
                )
                .toList(growable: false)
          : const [],
      suggestedPrompts: rawPrompts is List
          ? rawPrompts.whereType<String>().toList(growable: false)
          : const [],
      chatBlocked: json['chatBlocked'] as bool? ?? false,
      dataVersion: json['dataVersion'] as String?,
      sections: json['sections'] is List
          ? (json['sections'] as List)
                .whereType<Map>()
                .map(
                  (section) => AiAnswerSection.fromJson(
                    Map<String, dynamic>.from(section),
                  ),
                )
                .where((section) => section.body.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}

class AiChatRequest {
  final String requestId;
  final String sessionId;
  final String locale;
  final List<AiChatMessage> messages;
  final String? streamId;
  final String? dataVersion;

  const AiChatRequest({
    required this.requestId,
    required this.sessionId,
    required this.locale,
    required this.messages,
    this.streamId,
    this.dataVersion,
  });

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'sessionId': sessionId,
    'locale': locale,
    if (dataVersion != null) 'dataVersion': dataVersion,
    if (streamId != null) 'profileContext': {'streamId': streamId},
    'messages': messages
        .map((message) => message.toRequestJson())
        .toList(growable: false),
  };
}
