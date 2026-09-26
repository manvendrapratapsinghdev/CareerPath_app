import 'institute.dart';

/// A course offered by an institute (from `institute_courses`).
class InstituteCourse {
  final int id;
  final String name;
  final String level;
  final String? credential;
  final String? specialization;
  final String? duration;
  final String? mode;
  final String? eligibility;
  final String? officialUrl;

  /// Career path slugs this course leads to (from `course_career_nodes`).
  final List<String> careerSlugs;

  const InstituteCourse({
    required this.id,
    required this.name,
    required this.level,
    this.credential,
    this.specialization,
    this.duration,
    this.mode,
    this.eligibility,
    this.officialUrl,
    this.careerSlugs = const [],
  });

  factory InstituteCourse.fromJson(Map<String, dynamic> json) =>
      InstituteCourse(
        id: json['id'] as int,
        name: json['name'] as String,
        level: json['level'] as String? ?? '',
        credential: json['credential'] as String?,
        specialization: json['specialization'] as String?,
        duration: json['duration'] as String?,
        mode: json['mode'] as String?,
        eligibility: json['eligibility'] as String?,
        officialUrl: json['official_course_url'] as String?,
        careerSlugs: (json['career_slugs'] as List? ?? const [])
            .map((slug) => slug.toString())
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'level': level,
    'credential': credential,
    'specialization': specialization,
    'duration': duration,
    'mode': mode,
    'eligibility': eligibility,
    'official_course_url': officialUrl,
    'career_slugs': careerSlugs,
  };
}

/// A ranking such as NIRF 2025 Engineering (from `institute_rankings`).
class InstituteRanking {
  final String system;
  final int year;
  final String category;
  final int? rank;
  final String? rankBand;
  final double? score;
  final String? sourceUrl;

  const InstituteRanking({
    required this.system,
    required this.year,
    required this.category,
    this.rank,
    this.rankBand,
    this.score,
    this.sourceUrl,
  });

  factory InstituteRanking.fromJson(Map<String, dynamic> json) =>
      InstituteRanking(
        system: json['system'] as String,
        year: json['year'] as int,
        category: json['category'] as String,
        rank: json['rank'] as int?,
        rankBand: json['rank_band'] as String?,
        score: (json['score'] as num?)?.toDouble(),
        sourceUrl: json['source_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'system': system,
    'year': year,
    'category': category,
    'rank': rank,
    'rank_band': rankBand,
    'score': score,
    'source_url': sourceUrl,
  };

  /// Rank for display: exact rank, else the band (e.g. "151-200").
  String get rankLabel => rank?.toString() ?? rankBand ?? '-';

  /// Sort key: exact ranks first, bands by their lower bound.
  int get sortKey =>
      rank ??
      int.tryParse(RegExp(r'\d+').firstMatch(rankBand ?? '')?.group(0) ?? '') ??
      9999;

  String get label => '$system $year $category';
}

/// An institute with its courses, rankings and categories.
class InstituteRecord {
  final Institute institute;
  final List<InstituteCourse> courses;
  final List<InstituteRanking> rankings;
  final List<String> categories;

  const InstituteRecord({
    required this.institute,
    this.courses = const [],
    this.rankings = const [],
    this.categories = const [],
  });

  factory InstituteRecord.fromJson(Map<String, dynamic> json) =>
      InstituteRecord(
        institute: Institute.fromJson(json),
        courses: (json['courses'] as List? ?? const [])
            .map((c) => InstituteCourse.fromJson(Map<String, dynamic>.from(c)))
            .toList(growable: false),
        rankings: (json['rankings'] as List? ?? const [])
            .map((r) => InstituteRanking.fromJson(Map<String, dynamic>.from(r)))
            .toList(growable: false),
        categories: (json['categories'] as List? ?? const [])
            .map((c) => c.toString())
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'id': institute.id,
    'source_id': institute.sourceId,
    'name': institute.name,
    'city': institute.city,
    'district': institute.district,
    'state': institute.state,
    'website': institute.website,
    'description': institute.description,
    'courses': courses.map((c) => c.toJson()).toList(),
    'rankings': rankings.map((r) => r.toJson()).toList(),
    'categories': categories,
  };
}
