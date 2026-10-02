import 'dart:convert';

/// A saved India → State → District → City filter. All-null means all India.
class InstituteLocationFilter {
  final String? stateCode;
  final String? stateName;
  final int? districtLgd;
  final String? districtName;
  final int? placeId;
  final String? placeName;
  final bool onlineOnly;

  const InstituteLocationFilter({
    this.stateCode,
    this.stateName,
    this.districtLgd,
    this.districtName,
    this.placeId,
    this.placeName,
    this.onlineOnly = false,
  });

  bool get isAllIndia =>
      !onlineOnly &&
      stateCode == null &&
      districtLgd == null &&
      placeId == null;

  factory InstituteLocationFilter.fromJson(Map<String, dynamic> json) =>
      InstituteLocationFilter(
        stateCode: json['state_code'] as String?,
        stateName: json['state_name'] as String?,
        districtLgd: (json['district_lgd'] as num?)?.toInt(),
        districtName: json['district_name'] as String?,
        placeId: (json['place_id'] as num?)?.toInt(),
        placeName: json['place_name'] as String?,
        onlineOnly: json['online_only'] == true,
      );

  factory InstituteLocationFilter.decode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const InstituteLocationFilter();
    }
    try {
      return InstituteLocationFilter.fromJson(
        jsonDecode(value) as Map<String, dynamic>,
      );
    } on Object {
      return const InstituteLocationFilter();
    }
  }

  String encode() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'state_code': stateCode,
    'state_name': stateName,
    'district_lgd': districtLgd,
    'district_name': districtName,
    'place_id': placeId,
    'place_name': placeName,
    'online_only': onlineOnly,
  };
}
