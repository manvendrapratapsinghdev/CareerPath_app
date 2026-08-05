import '../config/ai_provider_config.dart';
import '../models/ai_chat.dart';
import '../models/career_node.dart';
import 'career_data_service.dart';

class AiGroundingContext {
  final String text;
  final List<AiChatSource> sources;

  const AiGroundingContext({required this.text, required this.sources});

  bool get isEmpty => sources.isEmpty || text.trim().isEmpty;
}

class LocalAiGroundingService {
  static const _stopWords = {
    'a',
    'about',
    'after',
    'and',
    'are',
    'can',
    'compare',
    'do',
    'find',
    'for',
    'give',
    'i',
    'in',
    'is',
    'list',
    'me',
    'of',
    'or',
    'please',
    'show',
    'tell',
    'the',
    'to',
    'what',
    'which',
    'with',
  };

  static const _careerIntentWords = {
    'book',
    'books',
    'career',
    'careers',
    'college',
    'colleges',
    'course',
    'courses',
    'education',
    'institute',
    'institutes',
    'job',
    'jobs',
    'option',
    'options',
    'path',
    'paths',
    'recommend',
    'school',
    'schools',
    'sector',
    'sectors',
    'suggest',
    'stream',
    'streams',
    'study',
  };

  final CareerDataService _careerDataService;

  const LocalAiGroundingService(this._careerDataService);

  Future<AiGroundingContext> retrieve({
    required String query,
    String? streamId,
  }) async {
    await _careerDataService.ensureInitialized();
    final queryTokens = _tokens(query);
    final hasCareerIntent = queryTokens.any(_careerIntentWords.contains);
    final allNodes = _careerDataService.getAllNodes();
    final scored = <({CareerNode node, int score})>[];

    for (final node in allNodes) {
      final name = node.name.toLowerCase();
      final intro = node.intro?.toLowerCase() ?? '';
      final compactName = _compact(name);
      final compactIntro = _compact(intro);
      var score = 0;
      for (final token in queryTokens) {
        var tokenScore = 0;
        if (name == token || compactName == token) {
          tokenScore = 12;
        } else if (name.contains(token) || compactName.contains(token)) {
          tokenScore = 6;
        } else if (intro.contains(token) || compactIntro.contains(token)) {
          tokenScore = 2;
        }
        score += tokenScore;
      }
      if (score > 0) scored.add((node: node, score: score));
    }

    scored.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return a.node.name.compareTo(b.node.name);
    });

    final selected = <CareerNode>[];
    final selectedIds = <String>{};
    void addNode(CareerNode node) {
      if (selected.length >= AiProviderConfig.maxGroundingNodes) return;
      if (selectedIds.add(node.id)) selected.add(node);
    }

    for (final result in scored) {
      addNode(result.node);
    }

    final lowerQuery = query.toLowerCase();
    final matchingStreams = _careerDataService.getAllStreams().where(
      (stream) =>
          (hasCareerIntent && stream.id == streamId) ||
          lowerQuery.contains(stream.id.toLowerCase()) ||
          lowerQuery.contains(stream.name.toLowerCase()),
    );
    for (final stream in matchingStreams) {
      for (final node in _careerDataService.getCategoriesForStream(stream.id)) {
        addNode(node);
      }
    }

    if (selected.isEmpty && hasCareerIntent) {
      final streams = _careerDataService.getAllStreams();
      for (final stream in streams) {
        if (streamId != null && stream.id != streamId) continue;
        for (final node in _careerDataService.getCategoriesForStream(
          stream.id,
        )) {
          addNode(node);
        }
      }
    }

    if (selected.isEmpty) {
      return const AiGroundingContext(text: '', sources: []);
    }

    final buffer = StringBuffer(
      'CAREERPATH EXPLORE DATA. Use only these records.\n',
    );
    for (final node in selected) {
      buffer
        ..writeln('\nSOURCE career_node:${node.id}')
        ..writeln('Title: ${node.name}')
        ..writeln('Explore node id: ${node.id}')
        ..writeln(
          'Description: ${node.intro?.trim().isNotEmpty == true ? node.intro!.trim() : "No description available."}',
        );

      final children = _careerDataService.getChildrenOf(node.id);
      if (children.isNotEmpty) {
        buffer.writeln(
          'Options: ${children.map((child) => child.name).join(", ")}',
        );
      }
    }

    final detailedNodes = selected
        .where((node) => node.isLeaf)
        .take(AiProviderConfig.maxDetailedNodes);
    for (final node in detailedNodes) {
      final details = await _careerDataService.getLeafDetails(node.id);
      if (details == null) continue;
      buffer.writeln('\nDETAILS FOR career_node:${node.id}');
      if (details.books.isNotEmpty) {
        buffer.writeln(
          'Books: ${details.books.map((book) => book.title).take(12).join(", ")}',
        );
      }
      if (details.institutes.isNotEmpty) {
        buffer.writeln(
          'Institutes: ${details.institutes.map((institute) => institute.name).take(12).join(", ")}',
        );
      }
      if (details.jobSectors.isNotEmpty) {
        buffer.writeln(
          'Job sectors: ${details.jobSectors.map((sector) => sector.name).take(12).join(", ")}',
        );
      }
    }

    var text = buffer.toString();
    if (text.length > AiProviderConfig.maxContextCharacters) {
      text = text.substring(0, AiProviderConfig.maxContextCharacters);
    }
    return AiGroundingContext(
      text: text,
      sources: selected
          .map(
            (node) => AiChatSource(
              sourceId: 'career_node:${node.id}',
              sourceType: 'career_node',
              title: node.name,
              exploreNodeId: node.id,
            ),
          )
          .toList(growable: false),
    );
  }

  Set<String> _tokens(String value) {
    return RegExp(r'[a-z0-9]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  String _compact(String value) {
    return value.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
