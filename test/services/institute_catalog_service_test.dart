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

  test('broad searches stay top-only while explicit filters widen them', () {
    final catalog = InstituteCatalogService.withRecords(
      _rows.map(InstituteRecord.fromJson).toList(),
    );

    expect(catalog.hasSpecificSearchFilter('engineering colleges'), isFalse);
    expect(catalog.hasSpecificSearchFilter('engineering colleges in Jaipur'), isTrue);
    expect(catalog.hasSpecificSearchFilter('IIT'), isTrue);
    expect(catalog.hasSpecificSearchFilter('PG courses'), isTrue);
  });

  test('matches the start of words, ignoring dots and punctuation', () {
    final catalog = InstituteCatalogService.withRecords(
      _rows.map(InstituteRecord.fromJson).toList(),
    );
    List<String> names(String query) =>
        catalog.search(query).map((r) => r.institute.name).toList();

    // Dots are ignored ("M.N.I.T" is "mnit") and a word prefix matches
    // ("jod" → Jodhpur), but the middle of a word does not.
    expect(names('M.N.I.T'), ['MNIT Jaipur']);
    expect(names('jod'), ['IIT Jodhpur']);
    expect(names('dhpur'), isEmpty);
    // Course words count too, alongside the city ("B.Tech" is "btech").
    expect(names('btech jodhpur'), ['IIT Jodhpur']);
    // Repeated searches use the same prepared text and give the same result.
    expect(names('jaipur'), ['MNIT Jaipur']);
    expect(names('jaipur'), ['MNIT Jaipur']);
  });

  test('a named city keeps colleges from elsewhere out', () {
    final catalog = InstituteCatalogService.withRecords(
      _rows.map(InstituteRecord.fromJson).toList(),
    );
    // "IIT" matches IIT Jodhpur by name, but the student asked about Jaipur.
    expect(catalog.search('iit jaipur').map((r) => r.institute.name), [
      'MNIT Jaipur',
    ]);
    expect(
      catalog.search('iit').map((r) => r.institute.name),
      contains('IIT Jodhpur'),
    );
  });

  test('a state also matches records that only have its city', () {
    final catalog = InstituteCatalogService.withRecords(
      [
        {'id': 1, 'name': 'Delhi School of Economics', 'city': 'New Delhi'},
        {
          'id': 2,
          'name': 'Jamia Millia Islamia',
          'city': 'New Delhi',
          'state': 'Delhi',
        },
        {
          'id': 3,
          'name': 'IIT Bombay',
          'city': 'Mumbai',
          'state': 'Maharashtra',
        },
        {'id': 4, 'name': 'Chandigarh University', 'city': 'Chandigarh'},
        {'id': 5, 'name': 'Various IITs', 'city': 'Various'},
      ].map(InstituteRecord.fromJson).toList(),
    );
    List<int> ids(String query) =>
        catalog.search(query).map((r) => r.institute.id).toList()..sort();

    // "Delhi" in a college's name is the place, so both Delhi colleges stay.
    expect(ids('colleges in Delhi'), [1, 2]);
    // A subject word keeps only the colleges that match it.
    expect(ids('economics colleges in Delhi'), [1]);
    expect(ids('colleges in Maharashtra'), [3]);
    expect(ids('Chandigarh colleges'), [4]);
    // A record with no state and an unrelated city is still left out.
    expect(ids('IITs in Maharashtra'), [3]);
  });

  group('courses and levels', () {
    Map<String, dynamic> course(int id, String name, String level) => {
      'id': id,
      'name': name,
      'level': level,
    };
    final catalog = InstituteCatalogService.withRecords(
      [
        {
          'id': 1,
          'name': 'Indore Science College',
          'city': 'Indore',
          'state': 'Madhya Pradesh',
          'courses': [
            for (var i = 0; i < 12; i++) course(100 + i, 'BA History $i', 'UG'),
            course(200, 'M.Sc Physics', 'Post Graduate'),
            course(201, 'B.Pharm', 'Undergraduate'),
          ],
        },
        {
          'id': 2,
          'name': 'Indore Arts College',
          'city': 'Indore',
          'state': 'Madhya Pradesh',
          'courses': [course(300, 'BA English', 'ug')],
        },
        {
          'id': 3,
          'name': 'Jaipur Pharmacy College',
          'city': 'Jaipur',
          'state': 'Rajasthan',
          'courses': [
            course(400, 'B.Pharm', 'UG'),
            course(401, 'D.Pharm', 'diploma'),
          ],
        },
      ].map(InstituteRecord.fromJson).toList(),
    );

    test('a level keeps only institutes and courses at that level', () {
      final result = catalog.find('PG courses in Indore');
      expect(result.hits.map((h) => h.record.institute.id), [1]);
      expect(result.hits.single.courses.map((c) => c.name), ['M.Sc Physics']);
      expect(result.totalInstitutes, 1);
      expect(result.totalCourses, 1);

      expect(
        catalog.find('pharmacy diploma').hits.single.courses.map((c) => c.id),
        [401],
      );
      // No PG course in Jaipur: nothing, rather than UG courses.
      expect(catalog.find('PG courses in Jaipur').hits, isEmpty);
    });

    test('every course is searched and the matching one is shown first', () {
      final result = catalog.find('bpharm indore');
      // Only the Indore college that offers B.Pharm, not every Indore one.
      expect(result.hits.map((h) => h.record.institute.id), [1]);
      expect(
        catalog
            .find('colleges in Indore')
            .hits
            .map((h) => h.record.institute.id),
        [2, 1],
      );
      final hit = result.hits.first;
      expect(hit.courses.map((c) => c.id), [201]);
      final text = InstituteCatalogService.describe(
        hit.record,
        matched: hit.courses,
      );
      // B.Pharm is the 14th course, past the 10 that describe() lists.
      expect(text, contains('Matching courses (1): B.Pharm (Undergraduate)'));
      expect(text, contains('Other courses: 13'));
      expect(
        InstituteCatalogService.describe(hit.record),
        isNot(contains('B.Pharm')),
      );
    });

    test('counts every match, not just the ones returned', () {
      final result = catalog.find('bpharm', limit: 1);
      expect(result.hits, hasLength(1));
      expect(result.totalInstitutes, 2);
      expect(result.totalCourses, 2);
    });
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
