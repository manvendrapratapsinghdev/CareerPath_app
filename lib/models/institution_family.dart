import 'sqlite_values.dart';

/// A named family of institutions such as the IITs or NLUs (`families`).
///
/// Every Indian family is listed, even ones with no institute in the DB yet,
/// so the app can say "31 NITs in India · 6 listed".
class InstitutionFamily {
  /// `iit`, `nit`, `aiims`, `nlu`, `iti`, …
  final String slug;
  final String name;
  final String groupCode;

  /// Raw regulator text, e.g. `MoE` or `NMC; INC`.
  final String? regulators;
  final String? officialListUrl;

  /// How many exist nationally per the official list; `null` until confirmed.
  final int? nationalCount;
  final String? nationalCountAsOf;

  const InstitutionFamily({
    required this.slug,
    required this.name,
    required this.groupCode,
    this.regulators,
    this.officialListUrl,
    this.nationalCount,
    this.nationalCountAsOf,
  });

  factory InstitutionFamily.fromJson(Map<String, dynamic> json) =>
      InstitutionFamily(
        slug: json['slug'] as String,
        name: json['name'] as String,
        groupCode: json['group_code'] as String,
        regulators: json['regulators'] as String?,
        officialListUrl: json['official_list_url'] as String?,
        nationalCount: (json['national_count'] as num?)?.toInt(),
        nationalCountAsOf: json['national_count_as_of'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'name': name,
    'group_code': groupCode,
    'regulators': regulators,
    'official_list_url': officialListUrl,
    'national_count': nationalCount,
    'national_count_as_of': nationalCountAsOf,
  };

  List<String> get regulatorList => splitSqliteList(regulators);

  @override
  String toString() => 'InstitutionFamily($slug, $name)';
}
