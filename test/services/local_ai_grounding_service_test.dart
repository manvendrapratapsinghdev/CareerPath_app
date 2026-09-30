import 'package:career_path/models/ai_chat.dart';
import 'package:career_path/models/book_record.dart';
import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/institute_catalog.dart';
import 'package:career_path/models/leaf_details.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/book_catalog_service.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';

CareerDataService _careerService() {
  final service = CareerDataService(ApiClient());
  service.initializeWithData(
    [
      StreamModel(id: 'science', name: 'Science', categoryIds: ['engineering']),
    ],
    {
      'engineering': CareerNode(
        id: 'engineering',
        name: 'Engineering',
        intro: 'Study technology and solve practical problems.',
        childIds: const ['computer-science'],
      ),
      'computer-science': CareerNode(
        id: 'computer-science',
        name: 'Computer Science',
        intro: 'Learn software, algorithms, and computing.',
      ),
      'bsc-computer-science': CareerNode(
        id: 'bsc-computer-science',
        name: 'B.Sc Computer Science',
        intro: 'An undergraduate computer science course.',
      ),
      'precision-farming': CareerNode(
        id: 'precision-farming',
        name: 'AgriTech / Precision Farming Specialist',
      ),
      'novelist': CareerNode(id: 'novelist', name: 'Author / Novelist'),
      'journalist': CareerNode(id: 'journalist', name: 'Broadcast Journalist'),
    },
  );
  return service;
}

void main() {
  group('institute answers', () {
    InstituteCatalogService catalog() => InstituteCatalogService.withRecords([
      for (var i = 0; i < 10; i++)
        InstituteRecord.fromJson({
          'id': i,
          'name': 'Jaipur College $i',
          'city': 'Jaipur',
          'state': 'Rajasthan',
          'courses': [
            {'id': 100 + i, 'name': 'B.Pharm', 'level': 'UG'},
          ],
        }),
      InstituteRecord.fromJson({
        'id': 50,
        'name': 'Indore Arts College',
        'city': 'Indore',
        'state': 'Madhya Pradesh',
        'courses': [
          {'id': 500, 'name': 'BA English', 'level': 'UG'},
        ],
      }),
    ]);

    test('a narrowed question gets more colleges and a match count', () async {
      final grounding = LocalAiGroundingService(
        _careerService(),
        catalog: catalog(),
      );
      final result = await grounding.retrieve(query: 'bpharm in jaipur');
      expect(
        result.sources.where((s) => s.sourceType == 'institute'),
        hasLength(8),
      );
      expect(
        result.text,
        contains(
          'MATCH SUMMARY: 10 institutes in Jaipur match, with 10 matching '
          'courses; showing 8.',
        ),
      );
      final levels = await grounding.retrieve(query: 'UG courses in Indore');
      expect(
        levels.text,
        contains('1 institute in Indore with UG courses matches'),
      );
    });

    test('a place with no colleges gets an honest coverage note', () async {
      final grounding = LocalAiGroundingService(
        _careerService(),
        catalog: catalog(),
      );
      final none = await grounding.retrieve(query: 'colleges in Kerala');
      // The guide learns why, and which states are covered...
      expect(none.text, contains('CareerPath has no institutes in Kerala'));
      expect(none.text, contains('Rajasthan (10), Madhya Pradesh (1)'));
      // ...and cites no college from elsewhere.
      expect(none.sources.where((s) => s.sourceType == 'institute'), isEmpty);

      // With nothing else to cite, the result is empty but keeps the note.
      final bare = await grounding.retrieve(query: 'Kerala');
      expect(bare.isEmpty, isTrue);
      expect(bare.text, contains('no institutes in Kerala'));

      final noCourse = await grounding.retrieve(query: 'PG courses in Indore');
      expect(
        noCourse.text,
        contains('CareerPath lists 1 institute in Indore, but none offer'),
      );

      // A found place has no note.
      final found = await grounding.retrieve(query: 'colleges in Indore');
      expect(found.text, isNot(contains('COVERAGE')));
    });

    test('the coverage note survives a semantic-only merge', () {
      const note = AiGroundingContext(text: 'COVERAGE: none', sources: []);
      const semantic = AiGroundingContext(
        text: 'SOURCE career_node:x',
        sources: [
          AiChatSource(sourceId: 'x', sourceType: 'career_node', title: 'X'),
        ],
      );
      final merged = AiGroundingContext.merge(note, semantic);
      expect(merged.text, startsWith('COVERAGE: none'));
      expect(merged.sources, semantic.sources);
    });
  });

  test(
    'a question about books finds books with a chip to their path',
    () async {
      final grounding = LocalAiGroundingService(
        _careerService(),
        books: BookCatalogService.withRecords([
          BookRecord.fromJson({
            'id': 5,
            'title': 'Introduction to Algorithms',
            'author': 'Cormen',
            'node_ids': ['computer-science'],
            'node_names': ['Computer Science'],
          }),
        ]),
      );

      final result = await grounding.retrieve(query: 'books on algorithms');
      expect(result.text, contains('SOURCE book:5'));
      expect(result.text, contains('Author: Cormen'));
      final chip = result.sources.firstWhere((s) => s.sourceType == 'book');
      expect(chip.exploreNodeId, 'computer-science');

      // Without a book word, books are not searched.
      final plain = await grounding.retrieve(query: 'algorithms');
      expect(plain.text, isNot(contains('SOURCE book:')));
    },
  );

  test('retrieves matching bundled Explore nodes with source IDs', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'Tell me about engineering',
      streamId: 'science',
    );

    expect(result.isEmpty, isFalse);
    expect(result.text, contains('SOURCE career_node:engineering'));
    expect(result.text, contains('Computer Science'));
    expect(result.sources.first.exploreNodeId, 'engineering');
  });

  test('uses selected stream roots for a general career request', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'Suggest a career option',
      streamId: 'science',
    );

    expect(
      result.sources.map((source) => source.exploreNodeId),
      contains('engineering'),
    );
  });

  test('"what can I do after twelfth" returns the stream options', () async {
    final grounding = LocalAiGroundingService(_careerService());

    for (final query in ['what can I do after twelfth', 'options after 12th']) {
      final result = await grounding.retrieve(query: query);
      expect(result.isEmpty, isFalse, reason: query);
      expect(result.text, contains('SOURCE career_node:engineering'));
    }
  });

  test(
    'a broad question gets the stream roots even without keywords',
    () async {
      final grounding = LocalAiGroundingService(_careerService());

      final plain = await grounding.retrieve(query: 'what should I do');
      final broad = await grounding.retrieve(
        query: 'what should I do',
        broad: true,
      );

      expect(plain.isEmpty, isTrue);
      expect(broad.text, contains('SOURCE career_node:engineering'));
    },
  );

  test('misspelled words still find their records', () async {
    final grounding = LocalAiGroundingService(
      _careerService(),
      loadDictionary: () async => 'mother\nplace',
    );

    final result = await grounding.retrieve(query: 'enginering');

    expect(result.text, contains('SOURCE career_node:engineering'));
  });

  test('abbreviations find their records and are not "corrected"', () async {
    final grounding = LocalAiGroundingService(
      _careerService(),
      loadDictionary: () async => 'mother\nplace',
      loadAliases: () async =>
          '{"engg": ["engineering"], "cse": ["computer science"]}',
    );

    expect(
      (await grounding.retrieve(query: 'engg')).text,
      contains('SOURCE career_node:engineering'),
    );
    expect(
      (await grounding.retrieve(query: 'cse jobs')).text,
      contains('SOURCE career_node:computer-science'),
    );
  });

  test('a broken alias table falls back to the words as written', () async {
    final grounding = LocalAiGroundingService(
      _careerService(),
      loadAliases: () async => 'not json',
    );
    expect((await grounding.retrieve(query: 'engg')).isEmpty, isTrue);
    expect(
      (await grounding.retrieve(query: 'engineering')).text,
      contains('SOURCE career_node:engineering'),
    );
  });

  test('without the word list, words are matched exactly', () async {
    for (final grounding in [
      LocalAiGroundingService(_careerService()),
      LocalAiGroundingService(
        _careerService(),
        loadDictionary: () async => throw Exception('missing asset'),
      ),
    ]) {
      expect((await grounding.retrieve(query: 'enginering')).isEmpty, isTrue);
      expect(
        (await grounding.retrieve(query: 'engineering')).text,
        contains('SOURCE career_node:engineering'),
      );
    }
  });

  test('leaf details are read once, not on every question', () async {
    final data = _CountingCareerData();
    final grounding = LocalAiGroundingService(data);

    for (var i = 0; i < 3; i++) {
      await grounding.retrieve(query: 'computer science');
    }

    expect(data.detailReads['computer-science'], 1);
  });

  test('Hinglish filler words do not match inside names', () async {
    final data = CareerDataService(ApiClient())
      ..initializeWithData(
        [
          StreamModel(
            id: 'science',
            name: 'Science',
            categoryIds: ['blockchain', 'doctor', 'lab'],
          ),
        ],
        {
          'blockchain': CareerNode(
            id: 'blockchain',
            name: 'Blockchain Developer',
          ),
          'doctor': CareerNode(id: 'doctor', name: 'Doctor (MBBS)'),
          'lab': CareerNode(id: 'lab', name: 'Medical Laboratory Technology'),
        },
      );
    final grounding = LocalAiGroundingService(
      data,
      loadDictionary: () async => 'mother',
      loadAliases: () async => '{"doctor": ["medical"]}',
    );

    // "hai" is inside "blockchain"; it must not pull that career in.
    final plain = await grounding.retrieve(query: 'doctor banna hai');
    expect(
      plain.sources.map((s) => s.exploreNodeId),
      isNot(contains('blockchain')),
    );
    expect(plain.sources.first.exploreNodeId, 'doctor');

    // A misspelled alias is corrected first, then expanded.
    final misspelled = await grounding.retrieve(query: 'docter banna hai');
    expect(
      misspelled.sources.map((s) => s.exploreNodeId),
      containsAll(['doctor', 'lab']),
    );
    expect(
      misspelled.sources.map((s) => s.exploreNodeId),
      isNot(contains('blockchain')),
    );
  });

  test('returns no context for an unrelated request', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'What is the weather tomorrow?',
      streamId: 'science',
    );

    expect(result.isEmpty, isTrue);
  });

  test('matches compact course aliases such as BSC to B.Sc', () async {
    final grounding = LocalAiGroundingService(_careerService());

    final result = await grounding.retrieve(
      query: 'List colleges for BSC',
      streamId: 'science',
    );

    expect(result.sources.first.exploreNodeId, 'bsc-computer-science');
    expect(
      result.sources.map((source) => source.exploreNodeId),
      isNot(contains('novelist')),
    );
  });
}

/// Counts leaf-detail reads over the same test data.
class _CountingCareerData extends CareerDataService {
  _CountingCareerData() : super(ApiClient()) {
    final source = _careerService();
    initializeWithData(source.getAllStreams(), {
      for (final node in source.getAllNodes()) node.id: node,
    });
  }

  final detailReads = <String, int>{};

  @override
  Future<LeafDetails?> getLeafDetails(
    String nodeId, {
    bool forceRefresh = false,
  }) async {
    detailReads[nodeId] = (detailReads[nodeId] ?? 0) + 1;
    return null;
  }
}
