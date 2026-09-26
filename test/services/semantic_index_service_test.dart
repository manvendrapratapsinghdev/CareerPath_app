import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/gemini_key_service.dart';
import 'package:career_path/services/semantic_index_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeKeys extends GeminiKeyService {
  @override
  Future<String> getKey() async => 'k';
}

/// Embeds "engineering…" texts on axis 0 and everything else on axis 1.
http.Client _embedder(List<int> calls) => MockClient((request) async {
  calls.add(1);
  final requests = (jsonDecode(request.body) as Map)['requests'] as List;
  return http.Response(
    jsonEncode({
      'embeddings': [
        for (final r in requests)
          {
            'values': [
              for (var i = 0; i < 768; i++)
                ((r['content']['parts'][0]['text'] as String)
                            .toLowerCase()
                            .contains('engineering')
                        ? i == 0
                        : i == 1)
                    ? 1.0
                    : 0.0,
            ],
          },
      ],
    }),
    200,
  );
});

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('semantic'));
  tearDown(() => dir.delete(recursive: true));

  Future<List<SemanticItem>> items() => SemanticIndexService.itemsFrom(
    CareerDataService(ApiClient())..initializeWithData(
      [StreamModel(id: 'science', name: 'Science', categoryIds: const [])],
      {
        'engineering': CareerNode(id: 'engineering', name: 'Engineering'),
        'law': CareerNode(id: 'law', name: 'Law', intro: 'Legal careers.'),
      },
    ),
    null,
  );

  test('finds items by meaning and saves vectors for reuse', () async {
    final calls = <int>[];
    final index = SemanticIndexService(
      keyService: _FakeKeys(),
      directory: () async => dir,
      client: _embedder(calls),
      batchPause: Duration.zero,
    );
    await index.build(await items());
    expect(index.indexedCount, 2);

    final result = await index.search('engineering colleges', null);
    expect(result.sources.single.exploreNodeId, 'engineering');
    expect(result.text, contains('SOURCE career_node:engineering'));

    calls.clear();
    final reloaded = SemanticIndexService(
      keyService: _FakeKeys(),
      directory: () async => dir,
      client: _embedder(calls),
    );
    await reloaded.build(await items());
    expect(reloaded.indexedCount, 2);
    expect(calls, isEmpty, reason: 'vectors come from the saved file');
  });

  test('nearest respects the cut-off', () async {
    final index = SemanticIndexService(
      keyService: _FakeKeys(),
      directory: () async => dir,
      client: _embedder([]),
      batchPause: Duration.zero,
    );
    await index.build(await items());
    final unrelated = Float32List(768)..[5] = 1;
    expect(index.nearest(unrelated), isEmpty);
  });

  test(
    'an empty index returns empty grounding without calling Gemini',
    () async {
      final calls = <int>[];
      final index = SemanticIndexService(
        keyService: _FakeKeys(),
        directory: () async => dir,
        client: _embedder(calls),
      );
      expect((await index.search('anything', null)).isEmpty, isTrue);
      expect(calls, isEmpty);
    },
  );
}
