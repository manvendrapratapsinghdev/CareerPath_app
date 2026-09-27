import 'package:career_path/models/career_node.dart';
import 'package:career_path/models/institute_catalog.dart';
import 'package:career_path/models/stream_model.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/services/local_ai_grounding_service.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = <Map<String, dynamic>>[
  {
    'id': 42,
    'name': 'IIT Jodhpur',
    'city': 'Jodhpur',
    'state': 'Rajasthan',
    'website': 'https://iitj.ac.in',
    'courses': [
      {
        'id': 501,
        'name': 'B.Tech Computer Science',
        'level': 'Undergraduate',
        'duration': '4 years',
        'eligibility': '10+2 with PCM',
        'career_slugs': ['computer-science'],
      },
    ],
    'rankings': [
      {
        'system': 'NIRF',
        'year': 2025,
        'category': 'Engineering',
        'rank': 28,
        'score': 58.1,
      },
    ],
    'categories': ['IIT'],
  },
  {
    'id': 7,
    'name': 'MNIT Jaipur',
    'city': 'Jaipur',
    'state': 'Rajasthan',
    'rankings': [
      {
        'system': 'NIRF',
        'year': 2025,
        'category': 'Engineering',
        'rank_band': '51-100',
      },
    ],
  },
  {
    'id': 9,
    'name': 'Udaipur Arts College',
    'city': 'Udaipur',
    'state': 'Rajasthan',
    'courses': [
      {'id': 502, 'name': 'BA', 'level': 'Undergraduate'},
    ],
  },
  {
    'id': 11,
    'name': 'Lucknow University',
    'city': 'Lucknow',
    'state': 'Uttar Pradesh',
    'courses': [
      {'id': 503, 'name': 'BA', 'level': 'Undergraduate'},
    ],
  },
];

void main() {
  test('parses catalog rows and round-trips records', () {
    final record = InstituteRecord.fromJson(_rows.first);
    expect(record.courses.single.careerSlugs, ['computer-science']);
    expect(record.rankings.single.rankLabel, '28');
    final restored = InstituteRecord.fromJson(record.toJson());
    expect(restored.institute.name, 'IIT Jodhpur');
    expect(restored.rankings.single.score, 58.1);
  });

  test('searches by name, city and course; ranks best first', () async {
    final catalog = InstituteCatalogService(() async => _rows);
    await catalog.ensureLoaded();

    expect(catalog.search('Tell me about IIT Jodhpur').first.institute.id, 42);
    expect(catalog.search('colleges in Jaipur').single.institute.id, 7);
    expect(
      catalog
          .rankings('NIRF engineering rankings')
          .map((p) => p.$1.institute.id),
      [42, 7],
    );
    expect(catalog.rankings('MNIT Jaipur rank').single.$2.rankLabel, '51-100');
    expect(InstituteCatalogService.asksForRankings('show NIRF list'), isTrue);
    expect(
      InstituteCatalogService.describe(catalog.records.first),
      contains('B.Tech Computer Science (Undergraduate, 4 years'),
    );
  });

  test('search only returns the state named in the query', () async {
    final catalog = InstituteCatalogService(() async => _rows);
    await catalog.ensureLoaded();

    final upResults = catalog.search('colleges in Uttar Pradesh that offer BA');
    expect(upResults.map((r) => r.institute.id), [11]);

    final abbreviated = catalog.search('BA colleges in UP');
    expect(abbreviated.map((r) => r.institute.id), [11]);

    final rajasthanResults = catalog.search('BA colleges in Rajasthan');
    expect(rajasthanResults.map((r) => r.institute.id), isNot(contains(11)));
    expect(rajasthanResults, isNotEmpty);
  });

  test('grounding adds institutes and rankings with sources', () async {
    final data = CareerDataService(ApiClient())
      ..initializeWithData(
        [StreamModel(id: 'science', name: 'Science', categoryIds: const [])],
        {'engineering': CareerNode(id: 'engineering', name: 'Engineering')},
      );
    final grounding = LocalAiGroundingService(
      data,
      catalog: InstituteCatalogService(() async => _rows),
    );

    final result = await grounding.retrieve(query: 'IIT Jodhpur NIRF ranking');

    expect(result.text, contains('SOURCE nirf_rankings'));
    expect(result.text, contains('Institutes: IIT Jodhpur'));
    expect(result.text, contains('SOURCE institute:42'));
    expect(result.sources.first.sourceType, 'ranking');
    expect(result.sources.map((s) => s.sourceId), contains('institute:42'));
  });
}
