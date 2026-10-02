import 'sqlite_values.dart';

/// Where an institute sits in the taxonomy (`institute_classification`,
/// at most one row per institute).
class InstituteClassification {
  final int instituteId;
  final String groupCode;
  final String? familySlug;

  /// `central_govt`, `state_govt`, `govt_aided`, `private`, `trust` or `ppp`.
  final String? ownership;
  final String? statutoryBasis;
  final bool admitsStudents;

  /// Set on campus / department / centre rows: the institute they belong to.
  final int? parentInstituteId;

  /// A national summary row such as "IITs", not a real campus.
  final bool isFamilyRecord;

  /// `false` only for Phase-2 coaching rows, bodies that admit no students
  /// and family records. Unlisted rows are kept out of the app.
  final bool listed;

  /// UGC Yes/No check, private institutions only: `true` = verified,
  /// `false` = not verified, `null` = government (not applicable).
  final bool? ugcVerified;
  final String? ugcListName;
  final String? ugcReferenceId;
  final String? ugcSourceUrl;
  final String? ugcCheckedAt;

  /// Recognitions held, e.g. `NMC` or `PCI,AICTE`.
  final String? regulators;

  /// `high` (official list), `medium` (official site) or `low` (heuristic).
  final String confidence;
  final String? sourceUrl;
  final String? verifiedAt;
  final String? notes;

  const InstituteClassification({
    required this.instituteId,
    required this.groupCode,
    this.familySlug,
    this.ownership,
    this.statutoryBasis,
    this.admitsStudents = true,
    this.parentInstituteId,
    this.isFamilyRecord = false,
    this.listed = true,
    this.ugcVerified,
    this.ugcListName,
    this.ugcReferenceId,
    this.ugcSourceUrl,
    this.ugcCheckedAt,
    this.regulators,
    this.confidence = 'low',
    this.sourceUrl,
    this.verifiedAt,
    this.notes,
  });

  factory InstituteClassification.fromJson(Map<String, dynamic> json) =>
      InstituteClassification(
        instituteId: (json['institute_id'] as num).toInt(),
        groupCode: json['group_code'] as String,
        familySlug: json['family_slug'] as String?,
        ownership: json['ownership'] as String?,
        statutoryBasis: json['statutory_basis'] as String?,
        admitsStudents: sqliteBool(json['admits_students'], fallback: true),
        parentInstituteId: (json['parent_institute_id'] as num?)?.toInt(),
        isFamilyRecord: sqliteBool(json['is_family_record'], fallback: false),
        listed: sqliteBool(json['listed'], fallback: true),
        ugcVerified: sqliteBoolOrNull(json['ugc_verified']),
        ugcListName: json['ugc_list_name'] as String?,
        ugcReferenceId: json['ugc_reference_id'] as String?,
        ugcSourceUrl: json['ugc_source_url'] as String?,
        ugcCheckedAt: json['ugc_checked_at'] as String?,
        regulators: json['regulators'] as String?,
        confidence: json['confidence'] as String? ?? 'low',
        sourceUrl: json['source_url'] as String?,
        verifiedAt: json['verified_at'] as String?,
        notes: json['notes'] as String?,
      );

  /// Same keys and value shapes as the DB row (flags as `1`/`0`).
  Map<String, dynamic> toJson() => {
    'institute_id': instituteId,
    'group_code': groupCode,
    'family_slug': familySlug,
    'ownership': ownership,
    'statutory_basis': statutoryBasis,
    'admits_students': sqliteFlag(admitsStudents),
    'parent_institute_id': parentInstituteId,
    'is_family_record': sqliteFlag(isFamilyRecord),
    'listed': sqliteFlag(listed),
    'ugc_verified': sqliteFlag(ugcVerified),
    'ugc_list_name': ugcListName,
    'ugc_reference_id': ugcReferenceId,
    'ugc_source_url': ugcSourceUrl,
    'ugc_checked_at': ugcCheckedAt,
    'regulators': regulators,
    'confidence': confidence,
    'source_url': sourceUrl,
    'verified_at': verifiedAt,
    'notes': notes,
  };

  /// Private or trust-run: the only rows that carry a UGC Yes/No result.
  bool get isPrivate => ownership == 'private' || ownership == 'trust';

  /// A campus, department or centre of another institute.
  bool get isChild => parentInstituteId != null;

  /// A real, listed, top-level institute students can apply to.
  bool get isTopLevelListing =>
      listed && !isFamilyRecord && !isChild && admitsStudents;

  List<String> get regulatorList => splitSqliteList(regulators);

  @override
  String toString() =>
      'InstituteClassification($instituteId, $groupCode, $familySlug)';
}
