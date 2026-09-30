import 'package:career_path/models/book_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a book catalog row and round-trips it', () {
    final record = BookRecord.fromJson({
      'id': 3,
      'title': 'Human Anatomy',
      'author': 'B D Chaurasia',
      'url': null,
      'description': 'Regional and applied anatomy.',
      'node_ids': ['doctor', 'nurse'],
      'node_names': ['Doctor', 'Nurse'],
    });
    expect(record.book.title, 'Human Anatomy');
    expect(record.nodeIds, ['doctor', 'nurse']);

    final restored = BookRecord.fromJson(record.toJson());
    expect(restored.book.author, 'B D Chaurasia');
    expect(restored.book.description, 'Regional and applied anatomy.');
    expect(restored.nodeNames, ['Doctor', 'Nurse']);
  });

  test('a book with no career paths parses with empty lists', () {
    final record = BookRecord.fromJson({'id': 1, 'title': 'Untitled'});
    expect(record.nodeIds, isEmpty);
    expect(record.nodeNames, isEmpty);
    expect(record.book.author, isNull);
  });
}
