/// A NAAC institution grade or NBA programme accreditation
/// (`institute_accreditations`). The ranking fallback when there is no NIRF
/// rank (plan §8.6).
class InstituteAccreditation {
  final int instituteId;

  /// `NAAC` or `NBA`.
  final String body;

  /// Empty for an institution-level grade; the programme name for NBA.
  final String programme;
  final String? grade;
  final String? status;
  final String? validUntil;
  final String sourceUrl;

  const InstituteAccreditation({
    required this.instituteId,
    required this.body,
    this.programme = '',
    this.grade,
    this.status,
    this.validUntil,
    required this.sourceUrl,
  });

  factory InstituteAccreditation.fromJson(Map<String, dynamic> json) =>
      InstituteAccreditation(
        instituteId: (json['institute_id'] as num).toInt(),
        body: json['body'] as String,
        programme: json['programme'] as String? ?? '',
        grade: json['grade'] as String?,
        status: json['status'] as String?,
        validUntil: json['valid_until'] as String?,
        sourceUrl: json['source_url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'institute_id': instituteId,
    'body': body,
    'programme': programme,
    'grade': grade,
    'status': status,
    'valid_until': validUntil,
    'source_url': sourceUrl,
  };

  bool get isInstitutionLevel => programme.isEmpty;

  @override
  String toString() => 'InstituteAccreditation($instituteId, $body $grade)';
}
