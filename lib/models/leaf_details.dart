import 'book.dart';
import 'institute.dart';
import 'job_sector.dart';

/// Rich details available only for leaf (final) career nodes.
class LeafDetails {
  final int nodeApiId;
  final String slug;
  final String name;
  final String? intro;
  final List<Book> books;
  final List<Institute> institutes;
  final List<JobSector> jobSectors;

  const LeafDetails({
    required this.nodeApiId,
    required this.slug,
    required this.name,
    this.intro,
    this.books = const [],
    this.institutes = const [],
    this.jobSectors = const [],
  });

  factory LeafDetails.fromJson(
    Map<String, dynamic> json, {
    Map<int, Book>? booksMap,
    Map<int, Institute>? institutesMap,
    Map<int, JobSector>? jobSectorsMap,
  }) {
    return LeafDetails(
      nodeApiId: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      intro: json['intro'] as String?,
      books: _parseBooks(json['books']),
      institutes: _parseInstitutes(json['institutes']),
      jobSectors: _parseJobSectors(json['job_sectors']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': nodeApiId,
      'slug': slug,
      'name': name,
      'intro': intro,
      'books': books
          .map((b) => {
                'id': b.id,
                'title': b.title,
                'author': b.author,
                'url': b.url,
                'description': b.description,
              })
          .toList(),
      'institutes': institutes
          .map((i) => {
                'id': i.id,
                'name': i.name,
                'city': i.city,
                'website': i.website,
                'description': i.description,
              })
          .toList(),
      'job_sectors': jobSectors
          .map((j) => {
                'id': j.id,
                'name': j.name,
                'description': j.description,
              })
          .toList(),
    };
  }

  static List<Book> _parseBooks(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((b) => Book.fromJson(b))
        .toList();
  }

  static List<Institute> _parseInstitutes(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((i) => Institute.fromJson(i))
        .toList();
  }

  static List<JobSector> _parseJobSectors(dynamic raw) {
    if (raw == null || raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((j) => JobSector.fromJson(j))
        .toList();
  }
}
