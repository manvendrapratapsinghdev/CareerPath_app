/// One of the 13 institution groups (G1..G9, G10a, G10b, G11, X) from
/// `institution_groups`. Groups say what kind of institution something is,
/// independent of the career domain.
class InstitutionGroup {
  /// `G1`..`G9`, `G10a`, `G10b`, `G11` or `X`.
  final String code;
  final String name;
  final String? description;
  final int sortOrder;

  const InstitutionGroup({
    required this.code,
    required this.name,
    this.description,
    required this.sortOrder,
  });

  factory InstitutionGroup.fromJson(Map<String, dynamic> json) =>
      InstitutionGroup(
        code: json['code'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'description': description,
    'sort_order': sortOrder,
  };

  /// `X` rows (labs, employers, post-selection academies) admit no students.
  bool get admitsStudents => code != 'X';

  @override
  String toString() => 'InstitutionGroup($code, $name)';
}
