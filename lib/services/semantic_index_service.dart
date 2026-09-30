import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';
import '../models/ai_chat.dart';
import 'career_data_service.dart';
import 'gemini_key_service.dart';
import 'institute_catalog_service.dart';
import 'local_ai_grounding_service.dart';

/// One searchable item: its grounding text and chat source.
class SemanticItem {
  final String id;
  final String text;
  final AiChatSource source;

  const SemanticItem({
    required this.id,
    required this.text,
    required this.source,
  });
}

/// Search by meaning over career paths and institutes. Vectors come from
/// `gemini-embedding-001`, are built once in the background (paced to the
/// key's quota) and stored in a binary file on the device.
class SemanticIndexService {
  final GeminiKeyService _keyService;
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final Duration batchPause;
  final Duration retryPause;

  /// Keeps institute hits inside the place a question names, so an Indore
  /// college does not answer a question about Jaipur.
  final InstituteCatalogService? catalog;

  final _items = <String, SemanticItem>{};
  final _vectors = <String, Float32List>{};
  Future<void>? _building;

  SemanticIndexService({
    required GeminiKeyService keyService,
    required Future<Directory> Function() directory,
    http.Client? client,
    this.batchPause = AiProviderConfig.embeddingBatchPause,
    this.retryPause = const Duration(seconds: 30),
    this.catalog,
  }) : _keyService = keyService,
       _directory = directory,
       _client = client ?? http.Client();

  int get indexedCount => _vectors.length;

  /// Items built from Explore career paths and the institute catalog.
  static Future<List<SemanticItem>> itemsFrom(
    CareerDataService careers,
    InstituteCatalogService? catalog,
  ) async {
    await careers.ensureInitialized();
    await catalog?.ensureLoaded();
    return [
      for (final node in careers.getAllNodes())
        SemanticItem(
          id: 'career_node:${node.id}',
          text: [
            'SOURCE career_node:${node.id}',
            'Title: ${node.name}',
            'Explore node id: ${node.id}',
            if (node.intro?.trim().isNotEmpty == true)
              'Description: ${node.intro!.trim()}',
            if (careers.getChildrenOf(node.id).isNotEmpty)
              'Options: ${careers.getChildrenOf(node.id).map((c) => c.name).join(', ')}',
          ].join('\n'),
          source: AiChatSource(
            sourceId: 'career_node:${node.id}',
            sourceType: 'career_node',
            title: node.name,
            exploreNodeId: node.id,
          ),
        ),
      for (final record in catalog?.records ?? const [])
        SemanticItem(
          id: 'institute:${record.institute.id}',
          text:
              'SOURCE institute:${record.institute.id}\n'
              '${InstituteCatalogService.describe(record)}',
          source: AiChatSource(
            sourceId: 'institute:${record.institute.id}',
            sourceType: 'institute',
            title: record.institute.name,
          ),
        ),
    ];
  }

  /// Loads saved vectors and embeds new or changed items. Runs once at a
  /// time and never throws.
  Future<void> build(List<SemanticItem> items) {
    for (final item in items) {
      _items[item.id] = item;
    }
    return _building ??= _build().whenComplete(() => _building = null);
  }

  Future<void> _build() async {
    try {
      final saved = await _load();
      final pending = <SemanticItem>[];
      for (final item in _items.values) {
        final vector = saved[item.id];
        if (vector != null && vector.$1 == _hash(item.text)) {
          _vectors[item.id] = vector.$2;
        } else {
          pending.add(item);
        }
      }
      for (
        var i = 0;
        i < pending.length;
        i += AiProviderConfig.embeddingBatchSize
      ) {
        final batch = pending.sublist(
          i,
          math.min(i + AiProviderConfig.embeddingBatchSize, pending.length),
        );
        final vectors = await _embedWithRetry(
          batch.map((item) => item.text).toList(),
          'RETRIEVAL_DOCUMENT',
        );
        if (vectors == null) break;
        for (var j = 0; j < batch.length && j < vectors.length; j++) {
          _vectors[batch[j].id] = vectors[j];
        }
        await _save();
        if (i + batch.length < pending.length) {
          await Future<void>.delayed(batchPause);
        }
      }
      debugPrint('[AI Guide] semantic index $indexedCount/${_items.length}');
    } on Object catch (error) {
      debugPrint('[AI Guide] semantic index paused (${error.runtimeType})');
    }
  }

  /// Best matches for [query] above the cut-off, as grounding.
  Future<AiGroundingContext> search(String query, String? streamId) async {
    if (_vectors.isEmpty || query.trim().isEmpty) {
      return const AiGroundingContext(text: '', sources: []);
    }
    final vectors = await _embed([query], 'RETRIEVAL_QUERY');
    await catalog?.ensureLoaded();
    final allowed = catalog?.idsInPlace(query);
    // Look further down the list when a place filter will drop some hits.
    final hits =
        nearest(
              vectors.first,
              topK: allowed == null
                  ? AiProviderConfig.semanticTopK
                  : AiProviderConfig.semanticTopK * 3,
            )
            .where((item) => _inPlace(item, allowed))
            .take(AiProviderConfig.semanticTopK)
            .toList(growable: false);
    return AiGroundingContext(
      text: hits.map((item) => item.text).join('\n\n'),
      sources: hits.map((item) => item.source).toList(growable: false),
    );
  }

  /// Career paths always pass; an institute only when [allowed] (the ids in
  /// the named place, or null for no place) has it.
  static bool _inPlace(SemanticItem item, Set<int>? allowed) {
    if (allowed == null || !item.id.startsWith('institute:')) return true;
    final id = int.tryParse(item.id.substring('institute:'.length));
    return id != null && allowed.contains(id);
  }

  @visibleForTesting
  List<SemanticItem> nearest(
    Float32List query, {
    int topK = AiProviderConfig.semanticTopK,
    double cutOff = AiProviderConfig.semanticCutOff,
  }) {
    final scored = <(String, double)>[];
    _vectors.forEach((id, vector) {
      if (vector.length != query.length) return;
      var dot = 0.0;
      for (var i = 0; i < vector.length; i++) {
        dot += vector[i] * query[i];
      }
      if (dot >= cutOff) scored.add((id, dot));
    });
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (id, _) in scored.take(topK))
        if (_items[id] != null) _items[id]!,
    ];
  }

  Future<List<Float32List>?> _embedWithRetry(
    List<String> texts,
    String taskType,
  ) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await _embed(texts, taskType);
      } on GeminiKeyException catch (error) {
        if (error.code != 'gemini_http_429' &&
            error.code != 'gemini_http_503' &&
            error.code != 'embedding_unavailable') {
          rethrow;
        }
        await Future<void>.delayed(retryPause * (attempt + 1));
      }
    }
    return null;
  }

  Future<List<Float32List>> _embed(List<String> texts, String taskType) async {
    final key = await _keyService.getKey();
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(
              ApiUrls.geminiBatchEmbed(AiProviderConfig.embeddingModel),
            ),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'CareerPath/1.0',
              'x-goog-api-key': key,
            },
            body: jsonEncode({
              'requests': [
                for (final text in texts)
                  {
                    'model': 'models/${AiProviderConfig.embeddingModel}',
                    'content': {
                      'parts': [
                        {
                          'text': text.length > 1500
                              ? text.substring(0, 1500)
                              : text,
                        },
                      ],
                    },
                    'taskType': taskType,
                    'outputDimensionality':
                        AiProviderConfig.embeddingDimensions,
                  },
              ],
            }),
          )
          .timeout(AiProviderConfig.generationTimeout);
    } on Exception {
      throw const GeminiKeyException('embedding_unavailable');
    }
    if (response.statusCode != 200) {
      throw GeminiKeyException('gemini_http_${response.statusCode}');
    }
    try {
      return ((jsonDecode(response.body) as Map)['embeddings'] as List)
          .map((item) => _unit((item as Map)['values'] as List))
          .toList(growable: false);
    } on Object {
      throw const GeminiKeyException('invalid_embedding_response');
    }
  }

  static Float32List _unit(List values) {
    final doubles = values.map((v) => (v as num).toDouble()).toList();
    var sum = 0.0;
    for (final v in doubles) {
      sum += v * v;
    }
    final norm = sum == 0 ? 1.0 : math.sqrt(sum);
    return Float32List.fromList([for (final v in doubles) v / norm]);
  }

  // ── Storage: <dir>/ai_semantic_index.{json,bin} ─────────────────────────

  Future<(File, File)> _files() async {
    final dir = await _directory();
    return (
      File('${dir.path}/ai_semantic_index.json'),
      File('${dir.path}/ai_semantic_index.bin'),
    );
  }

  Future<Map<String, (String, Float32List)>> _load() async {
    try {
      final (meta, data) = await _files();
      if (!await meta.exists() || !await data.exists()) return {};
      final entries = (jsonDecode(await meta.readAsString()) as List)
          .cast<Map>();
      final bytes = await data.readAsBytes();
      final floats = Float32List.view(Uint8List.fromList(bytes).buffer);
      const dims = AiProviderConfig.embeddingDimensions;
      final result = <String, (String, Float32List)>{};
      for (var i = 0; i < entries.length; i++) {
        if ((i + 1) * dims > floats.length) break;
        result[entries[i]['id'] as String] = (
          entries[i]['hash'] as String,
          Float32List.fromList(floats.sublist(i * dims, (i + 1) * dims)),
        );
      }
      return result;
    } on Object {
      return {};
    }
  }

  Future<void> _save() async {
    final (meta, data) = await _files();
    final ids = _vectors.keys.toList();
    final floats = Float32List(
      ids.length * AiProviderConfig.embeddingDimensions,
    );
    for (var i = 0; i < ids.length; i++) {
      floats.setAll(
        i * AiProviderConfig.embeddingDimensions,
        _vectors[ids[i]]!,
      );
    }
    await data.writeAsBytes(floats.buffer.asUint8List(), flush: true);
    await meta.writeAsString(
      jsonEncode([
        for (final id in ids) {'id': id, 'hash': _hash(_items[id]?.text ?? '')},
      ]),
      flush: true,
    );
  }

  /// FNV-1a, enough to notice when an item's text changes.
  static String _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  void dispose() => _client.close();
}
