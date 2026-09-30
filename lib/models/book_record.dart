import 'book.dart';

/// A book with the career paths it is recommended for (from `node_books`).
class BookRecord {
  final Book book;

  /// Explore node ids (career path slugs), in the order of [nodeNames].
  final List<String> nodeIds;
  final List<String> nodeNames;

  const BookRecord({
    required this.book,
    this.nodeIds = const [],
    this.nodeNames = const [],
  });

  factory BookRecord.fromJson(Map<String, dynamic> json) => BookRecord(
    book: Book.fromJson(json),
    nodeIds: (json['node_ids'] as List? ?? const [])
        .map((id) => id.toString())
        .toList(growable: false),
    nodeNames: (json['node_names'] as List? ?? const [])
        .map((name) => name.toString())
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    ...book.toJson(),
    'node_ids': nodeIds,
    'node_names': nodeNames,
  };
}
