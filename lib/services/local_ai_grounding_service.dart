import 'package:flutter/foundation.dart';

import '../config/ai_provider_config.dart';
import '../models/ai_chat.dart';
import '../models/career_node.dart';
import '../models/institute_catalog.dart';
import '../models/leaf_details.dart';
import 'career_data_service.dart';
import 'institute_catalog_service.dart';
import 'search_aliases.dart';
import 'search_spell_corrector.dart';

class AiGroundingContext {
  final String text;
  final List<AiChatSource> sources;

  const AiGroundingContext({required this.text, required this.sources});

  bool get isEmpty => sources.isEmpty || text.trim().isEmpty;

  static const empty = AiGroundingContext(text: '', sources: []);

  /// Keyword matches first, then any semantic matches not already present.
  static AiGroundingContext merge(
    AiGroundingContext keyword,
    AiGroundingContext semantic,
  ) {
    if (semantic.isEmpty) return keyword;
    if (keyword.isEmpty) return semantic;
    final seen = keyword.sources.map((s) => s.sourceId).toSet();
    return AiGroundingContext(
      text: '${keyword.text}\n${semantic.text}',
      sources: [
        ...keyword.sources,
        ...semantic.sources.where((s) => seen.add(s.sourceId)),
      ],
    );
  }
}

/// Extra retrieval (for example semantic search) merged into grounding.
typedef ExtraGrounding =
    Future<AiGroundingContext> Function(String query, String? streamId);

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
    // "After 10th / 12th / graduation" is how students ask for options.
    '10th',
    '12th',
    'tenth',
    'twelfth',
    'graduation',
    'streams',
    'study',
  };

  final CareerDataService _careerDataService;

  /// Optional institutes, courses and NIRF rankings.
  final InstituteCatalogService? catalog;

  /// Loads the English word list that enables spelling correction; without
  /// it words are matched exactly as given.
  final Future<String> Function()? loadDictionary;

  /// Loads the alias table ([SearchAliases.asset]); without it
  /// abbreviations are matched only as written.
  final Future<String> Function()? loadAliases;

  LocalAiGroundingService(
    this._careerDataService, {
    this.catalog,
    this.loadDictionary,
    this.loadAliases,
  });

  Future<SearchSpellCorrector?>? _spelling;
  Future<SearchAliases?>? _aliases;

  /// Builds the alias table and spelling corrector ahead of the first
  /// question.
  Future<void> warmUp() async {
    await _careerDataService.ensureInitialized();
    await catalog?.ensureLoaded();
    await _speller();
  }

  Future<AiGroundingContext> retrieve({
    required String query,
    String? streamId,

    /// A broad roundup ("what can I do?"): always include the stream roots.
    bool broad = false,
  }) async {
    await _careerDataService.ensureInitialized();
    await this.catalog?.ensureLoaded();
    // Abbreviations first ("engg" → engineering), then misspelled or
    // misheard words, which would otherwise match nothing below.
    query = (await _aliasTable())?.expand(query) ?? query;
    query = (await _speller())?.correctQuery(query) ?? query;
    final queryTokens = _tokens(query);
    final hasCareerIntent =
        broad || queryTokens.any(_careerIntentWords.contains);
    final allNodes = _careerDataService.getAllNodes();
    final scored = <({CareerNode node, int score})>[];

    for (final node in allNodes) {
      final (:name, :intro, :compactName, :compactIntro) = _nodeText(node);
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

    var institutes = const <InstituteRecord>[];
    var rankings = const <(InstituteRecord, InstituteRanking)>[];
    final catalog = this.catalog;
    if (catalog != null) {
      if (InstituteCatalogService.asksForRankings(query)) {
        rankings = catalog.rankings(query);
      }
      institutes = catalog.search(query, limit: 4);
    }

    if (selected.isEmpty && institutes.isEmpty && rankings.isEmpty) {
      return const AiGroundingContext(text: '', sources: []);
    }

    final buffer = StringBuffer(
      'CAREERPATH EXPLORE DATA. Use only these records.\n',
    );
    // Precise institute and ranking matches go first so they survive the
    // context limit.
    if (rankings.isNotEmpty) {
      buffer.writeln('\nSOURCE nirf_rankings');
      for (final (record, ranking) in rankings) {
        buffer.writeln(
          '${record.institute.name}: ${ranking.label} rank '
          '${ranking.rankLabel}'
          '${ranking.score == null ? '' : ', score ${ranking.score}'}',
        );
      }
    }
    if (institutes.isNotEmpty) {
      buffer.writeln(
        '\nInstitutes: ${institutes.map((r) => r.institute.name).join(", ")}',
      );
      for (final record in institutes) {
        buffer
          ..writeln('\nSOURCE institute:${record.institute.id}')
          ..writeln(InstituteCatalogService.describe(record));
      }
    }
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
      final details = await _leafDetails(node.id);
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
      sources: [
        for (final (record, ranking) in rankings.take(3))
          AiChatSource(
            sourceId:
                'ranking:${record.institute.id}:${ranking.year}:${ranking.category}',
            sourceType: 'ranking',
            title:
                '${record.institute.name} · ${ranking.label} #${ranking.rankLabel}',
          ),
        for (final record in institutes)
          AiChatSource(
            sourceId: 'institute:${record.institute.id}',
            sourceType: 'institute',
            title: record.institute.name,
          ),
        ...selected.map(
          (node) => AiChatSource(
            sourceId: 'career_node:${node.id}',
            sourceType: 'career_node',
            title: node.name,
            exploreNodeId: node.id,
          ),
        ),
      ],
    );
  }

  Future<SearchAliases?> _aliasTable() => _aliases ??= () async {
    final load = loadAliases;
    if (load == null) return null;
    try {
      return SearchAliases.parse(await load());
    } on Object catch (error) {
      debugPrint('[AI Guide] search aliases off (${error.runtimeType})');
      return null;
    }
  }();

  /// Built once, off the UI thread, from the bundled (read-only) data.
  Future<SearchSpellCorrector?> _speller() => _spelling ??= () async {
    final load = loadDictionary;
    if (load == null) return null;
    try {
      final dictionary = await load();
      // Alias keys ("engg", "mbbs") are meant as written.
      final aliasWords = (await _aliasTable())?.keyWords.toList() ?? const [];
      final records = catalog?.records ?? const <InstituteRecord>[];
      return await compute(_buildSpelling, (
        names: [
          for (final stream in _careerDataService.getAllStreams()) stream.name,
          for (final node in _careerDataService.getAllNodes()) node.name,
          for (final record in records) ...[
            record.institute.name,
            record.institute.city ?? '',
            record.institute.district ?? '',
            record.institute.state ?? '',
            (record.institute.institutionType ?? '').replaceAll('_', ' '),
            ...record.categories,
            for (final course in record.courses)
              '${course.name} ${course.specialization ?? ''}',
          ],
        ],
        otherText: [
          for (final node in _careerDataService.getAllNodes()) node.intro ?? '',
          for (final record in records) record.institute.description ?? '',
          ...aliasWords,
        ],
        dictionary: dictionary,
      ));
    } on Object catch (error) {
      // Without the word list, correcting could turn real words into data
      // words, so search exactly as given instead.
      debugPrint('[AI Guide] spelling correction off (${error.runtimeType})');
      return null;
    }
  }();

  static SearchSpellCorrector _buildSpelling(
    ({List<String> names, List<String> otherText, String dictionary}) input,
  ) => SearchSpellCorrector(
    names: input.names,
    otherText: input.otherText,
    dictionary: SearchSpellCorrector.parseDictionary(input.dictionary),
  );

  Set<String> _tokens(String value) {
    return RegExp(r'[a-z0-9]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  /// Lowercase and compact forms of a node's text, built once per node.
  static final _nodeTexts =
      Expando<
        ({String name, String intro, String compactName, String compactIntro})
      >();

  static ({String name, String intro, String compactName, String compactIntro})
  _nodeText(CareerNode node) => _nodeTexts[node] ??= () {
    final name = node.name.toLowerCase();
    final intro = node.intro?.toLowerCase() ?? '';
    return (
      name: name,
      intro: intro,
      compactName: _compact(name),
      compactIntro: _compact(intro),
    );
  }();

  // The bundled data is read-only, so a leaf's details never change; keep
  // them instead of querying the database on every question.
  final _leafCache = <String, Future<LeafDetails?>>{};

  Future<LeafDetails?> _leafDetails(String nodeId) =>
      _leafCache[nodeId] ??= _careerDataService.getLeafDetails(nodeId)
        ..catchError((Object _) {
          _leafCache.remove(nodeId);
          return null;
        });

  static final _nonWord = RegExp(r'[^a-z0-9]+');

  static String _compact(String value) => value.replaceAll(_nonWord, '');
}
