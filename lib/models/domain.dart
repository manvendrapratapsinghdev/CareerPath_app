import 'sqlite_values.dart';

/// A career domain such as Engineering, Law or CA/CMA/CS (`domains`).
class Domain {
  /// `engineering`, `medical`, `law`, `ca_cma_cs`, …
  final String slug;
  final String name;

  /// `degree`, `professional_body`, `exam` or `mixed`.
  final String routeType;
  final String? regulators;
  final String? entranceExams;
  final int sortOrder;

  const Domain({
    required this.slug,
    required this.name,
    required this.routeType,
    this.regulators,
    this.entranceExams,
    required this.sortOrder,
  });

  factory Domain.fromJson(Map<String, dynamic> json) => Domain(
    slug: json['slug'] as String,
    name: json['name'] as String,
    routeType: json['route_type'] as String? ?? 'degree',
    regulators: json['regulators'] as String?,
    entranceExams: json['entrance_exams'] as String?,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
    'route_type': routeType,
    'regulators': regulators,
    'entrance_exams': entranceExams,
    'sort_order': sortOrder,
  };

  /// Degree and mixed routes have a college ladder; the others are steps or
  /// exams.
  bool get hasCollegeLadder => routeType == 'degree' || routeType == 'mixed';

  List<String> get regulatorList => splitSqliteList(regulators);
  List<String> get entranceExamList => splitSqliteList(entranceExams);

  @override
  String toString() => 'Domain($slug, $name)';
}

/// NIRF categories that match a domain, best first (plan §8.6). Domains
/// without a NIRF category of their own fall back to [nirfFallbackCategories].
const Map<String, List<String>> nirfCategoriesByDomain = {
  'engineering': ['Engineering'],
  'computing': ['Engineering'],
  'science': ['Research'],
  'medical': ['Medical'],
  'dental': ['Dental'],
  'pharmacy': ['Pharmacy'],
  'agriculture': ['Agriculture and Allied Sectors'],
  'veterinary': ['Agriculture and Allied Sectors'],
  'architecture': ['Architecture and Planning'],
  'management': ['Management'],
  'law': ['Law'],
};

/// Institution-wide NIRF categories used when there is no domain rank.
const List<String> nirfFallbackCategories = [
  'Overall',
  'University',
  'College',
  'Colleges',
  'State Public University',
  'Open University',
];

/// The NIRF categories to try for [domainSlug], domain-matched first.
List<String> nirfCategoriesFor(String? domainSlug) => [
  ...?nirfCategoriesByDomain[domainSlug],
  ...nirfFallbackCategories,
];
