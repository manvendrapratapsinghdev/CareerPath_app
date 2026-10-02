/// An official list an institute appears on (`institute_verifications`),
/// e.g. the MoE list of IITs or the NMC list of medical colleges.
class InstituteVerification {
  final int instituteId;
  final String authority;
  final String listName;
  final String listUrl;
  final String? listAsOf;
  final String? referenceId;
  final String verifiedAt;

  const InstituteVerification({
    required this.instituteId,
    required this.authority,
    required this.listName,
    required this.listUrl,
    this.listAsOf,
    this.referenceId,
    required this.verifiedAt,
  });

  factory InstituteVerification.fromJson(Map<String, dynamic> json) =>
      InstituteVerification(
        instituteId: (json['institute_id'] as num).toInt(),
        authority: json['authority'] as String,
        listName: json['list_name'] as String,
        listUrl: json['list_url'] as String? ?? '',
        listAsOf: json['list_as_of'] as String?,
        referenceId: json['reference_id'] as String?,
        verifiedAt: json['verified_at'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'institute_id': instituteId,
    'authority': authority,
    'list_name': listName,
    'list_url': listUrl,
    'list_as_of': listAsOf,
    'reference_id': referenceId,
    'verified_at': verifiedAt,
  };

  @override
  String toString() => 'InstituteVerification($instituteId, $authority)';
}
