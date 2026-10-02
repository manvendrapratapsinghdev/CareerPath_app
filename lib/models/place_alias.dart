/// A former or alternate spelling mapped to one canonical location.
class PlaceAlias {
  final String alias;
  final int? placeId;
  final int? districtLgd;
  final String? stateCode;

  const PlaceAlias({
    required this.alias,
    this.placeId,
    this.districtLgd,
    this.stateCode,
  });

  factory PlaceAlias.fromJson(Map<String, dynamic> json) => PlaceAlias(
    alias: json['alias'] as String,
    placeId: (json['place_id'] as num?)?.toInt(),
    districtLgd: (json['district_lgd'] as num?)?.toInt(),
    stateCode: json['state_code'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'place_id': placeId,
    'district_lgd': districtLgd,
    'state_code': stateCode,
  };
}
