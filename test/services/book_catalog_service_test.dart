import 'package:career_path/models/book_record.dart';
import 'package:career_path/services/book_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = <Map<String, dynamic>>[
  {
    'id': 1,
    'title': 'Human Anatomy',
    'author': 'B.D. Chaurasia',
    'description': 'Regional and applied anatomy for medical students.',
    'node_ids': ['doctor'],
    'node_names': ['Doctor (MBBS)'],
  },
  {
    'id': 2,
    'title': 'Concepts of Physics',
    'author': 'H.C. Verma',
    'description': 'Physics for engineering entrance.',
    'node_ids': ['mechanical-engineer'],
    'node_names': ['Mechanical Engineer'],
  },
  {
    'id': 3,
    'title': 'Logo Design Love',
    'author': 'David Airey',
    'description': 'A guide to creating iconic brand identities.',
    'node_ids': ['graphic-designer'],
    'node_names': ['Graphic Designer'],
  },
];

void main() {
  test('loads rows once and searches title, author and career paths', () async {
    var loads = 0;
    final books = BookCatalogService(() async {
      loads++;
      return _rows;
    });
    await Future.wait([books.ensureLoaded(), books.ensureLoaded()]);
    expect(loads, 1);

    List<int> ids(String query) =>
        books.search(query).hits.map((r) => r.book.id).toList();
    expect(ids('books on anatomy'), [1]);
    expect(ids('HC Verma books'), [2]);
    // A career path the book is recommended for.
    expect(ids('books for a graphic designer'), [3]);
    expect(ids('books for doctor'), [1]);
    // A short word must match a whole word: "hc" is not the start of "human".
    expect(ids('books by hc'), [2]);
  });

  test('description-only matches are too loose to count', () {
    final books = BookCatalogService.withRecords(
      _rows.map(BookRecord.fromJson).toList(),
    );
    expect(books.search('books about identities').hits, isEmpty);
    // Book words alone name no subject.
    expect(books.search('books').hits, isEmpty);
    expect(books.search('').total, 0);
  });

  test('counts every match and limits the hits', () {
    final books = BookCatalogService.withRecords(
      _rows.map(BookRecord.fromJson).toList(),
    );
    final result = books.search('books by Verma Airey Chaurasia', limit: 2);
    expect(result.hits, hasLength(2));
    expect(result.total, 3);
  });

  test('knows when a question asks for books', () {
    expect(BookCatalogService.asksForBooks('best books for NEET'), isTrue);
    expect(BookCatalogService.asksForBooks('konsi kitab padhu'), isTrue);
    expect(BookCatalogService.asksForBooks('colleges in Jaipur'), isFalse);
  });

  test('describes a book with its career paths', () {
    final text = BookCatalogService.describe(BookRecord.fromJson(_rows.first));
    expect(text, contains('Title: Human Anatomy'));
    expect(text, contains('Author: B.D. Chaurasia'));
    expect(text, contains('Recommended for: Doctor (MBBS)'));
  });
}
