import '../models/book_record.dart';
import 'search_aliases.dart';

/// Every recommended book with its career paths, loaded once from the
/// bundled database and searched in memory.
class BookCatalogService {
  /// Words that ask for books rather than colleges or careers.
  static const _bookWords = {
    'book',
    'books',
    'kitab',
    'kitabein',
    'kitaben',
    'kitabe',
    'pustak',
    'reading',
    'textbook',
    'textbooks',
    'author',
    'authors',
  };
  static const _stopWords = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'of',
    'in',
    'on',
    'for',
    'to',
    'is',
    'are',
    'what',
    'which',
    'who',
    'how',
    'me',
    'show',
    'tell',
    'list',
    'about',
    'best',
    'good',
    'top',
    'read',
    'should',
    'recommend',
    'suggest',
    'some',
    'any',
  };

  final Future<List<Map<String, dynamic>>> Function() _loader;
  List<BookRecord>? _records;
  Future<void>? _loading;

  BookCatalogService(this._loader);

  BookCatalogService.withRecords(List<BookRecord> records)
    : _loader = (() async => const []),
      _records = records;

  List<BookRecord> get records => _records ?? const [];

  Future<void> ensureLoaded() {
    if (_records != null) return Future.value();
    return _loading ??= _loader()
        .then((rows) {
          _records = rows.map(BookRecord.fromJson).toList(growable: false);
        })
        .whenComplete(() => _loading = null);
  }

  static bool asksForBooks(String query) =>
      _tokens(query).any(_bookWords.contains);

  /// Books whose title, author, career paths or description match [query],
  /// best first, and how many matched in all (before [limit]).
  ({List<BookRecord> hits, int total}) search(String query, {int limit = 6}) {
    final tokens = _tokens(query)
        .difference(_stopWords)
        .difference(_bookWords)
        .difference(searchFillerWords);
    if (tokens.isEmpty) return (hits: const [], total: 0);
    final scored = <(BookRecord, int)>[];
    for (final record in records) {
      final (:title, :author, :careers, :description) = _searchText(record);
      var score = 0;
      for (final token in tokens) {
        if (_hasWord(title, token)) {
          score += 10;
        } else if (_hasWord(author, token) || _hasWord(careers, token)) {
          score += 6;
        } else if (_hasWord(description, token)) {
          score += 2;
        }
      }
      if (score >= 6) scored.add((record, score));
    }
    scored.sort((a, b) {
      final order = b.$2.compareTo(a.$2);
      return order != 0 ? order : a.$1.book.title.compareTo(b.$1.book.title);
    });
    return (
      hits: scored.take(limit).map((entry) => entry.$1).toList(growable: false),
      total: scored.length,
    );
  }

  /// Grounding text for one book.
  static String describe(BookRecord record) {
    final book = record.book;
    return [
      'Title: ${book.title}',
      if (book.author?.trim().isNotEmpty == true)
        'Author: ${book.author!.trim()}',
      if (record.nodeNames.isNotEmpty)
        'Recommended for: ${record.nodeNames.take(5).join(', ')}',
      if (book.description?.trim().isNotEmpty == true)
        'Description: ${_clip(book.description!.trim(), 300)}',
    ].join('\n');
  }

  static final _texts =
      Expando<
        ({String title, String author, String careers, String description})
      >();

  static ({String title, String author, String careers, String description})
  _searchText(BookRecord record) => _texts[record] ??= (
    title: _haystack(record.book.title),
    author: _haystack(record.book.author ?? ''),
    careers: _haystack(record.nodeNames.join(' ')),
    description: _haystack(record.book.description ?? ''),
  );

  static Set<String> _tokens(String text) =>
      _haystack(text).split(' ').where((token) => token.length >= 2).toSet();

  static final _nonWord = RegExp('[^a-z0-9]+');

  /// Lowercase, dots dropped, other punctuation turned into single spaces,
  /// with a space at each end, so a word prefix match is `contains(' token')`.
  static String _haystack(String text) =>
      ' ${text.toLowerCase().replaceAll('.', '').replaceAll(_nonWord, ' ')} ';

  /// A word of [haystack] starts with [token]; a two-letter token ("ca")
  /// must be the whole word, or it would match "cabin" and "calculus".
  static bool _hasWord(String haystack, String token) =>
      haystack.contains(token.length < 3 ? ' $token ' : ' $token');

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';
}
