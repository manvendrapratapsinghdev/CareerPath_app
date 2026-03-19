/// Represents a recommended book for a career path.
class Book {
  final int id;
  final String title;
  final String? author;
  final String? url;
  final String? description;

  const Book({
    required this.id,
    required this.title,
    this.author,
    this.url,
    this.description,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as int,
      title: json['title'] as String,
      author: json['author'] as String?,
      url: json['url'] as String?,
      description: json['description'] as String?,
    );
  }

  @override
  String toString() => 'Book($id, $title)';
}
