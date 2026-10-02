/// A campus location mapped to a canonical place (`campuses`).
class InstituteCampus {
  final int id;
  final int instituteId;
  final String? name;
  final int placeId;
  final String placeName;
  final String districtName;
  final int districtLgd;
  final String stateCode;
  final String stateName;
  final bool isMain;
  final String? sourceUrl;
  final String? verifiedAt;

  const InstituteCampus({
    required this.id,
    required this.instituteId,
    this.name,
    required this.placeId,
    required this.placeName,
    required this.districtName,
    required this.districtLgd,
    required this.stateCode,
    required this.stateName,
    this.isMain = false,
    this.sourceUrl,
    this.verifiedAt,
  });

  factory InstituteCampus.fromJson(Map<String, dynamic> json) =>
      InstituteCampus(
        id: (json['id'] as num).toInt(),
        instituteId: (json['institute_id'] as num).toInt(),
        name: json['name'] as String?,
        placeId: (json['place_id'] as num).toInt(),
        placeName: json['place_name'] as String? ?? '',
        districtName: json['district_name'] as String? ?? '',
        districtLgd: (json['district_lgd'] as num?)?.toInt() ?? 0,
        stateCode: json['state_code'] as String? ?? '',
        stateName: json['state_name'] as String? ?? '',
        isMain: (json['is_main'] as num?)?.toInt() == 1,
        sourceUrl: json['source_url'] as String?,
        verifiedAt: json['verified_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'institute_id': instituteId,
    'name': name,
    'place_id': placeId,
    'place_name': placeName,
    'district_name': districtName,
    'district_lgd': districtLgd,
    'state_code': stateCode,
    'state_name': stateName,
    'is_main': isMain ? 1 : 0,
    'source_url': sourceUrl,
    'verified_at': verifiedAt,
  };
}
