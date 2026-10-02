/// A city, town or village in a district (`places`).
class PlaceRecord {
  final int id;
  final int districtLgd;
  final String districtName;
  final String stateCode;
  final String name;
  final String kind;
  final bool isDistrictHeadquarters;

  const PlaceRecord({
    required this.id,
    required this.districtLgd,
    required this.districtName,
    required this.stateCode,
    required this.name,
    required this.kind,
    this.isDistrictHeadquarters = false,
  });

  factory PlaceRecord.fromJson(Map<String, dynamic> json) => PlaceRecord(
    id: (json['id'] as num).toInt(),
    districtLgd: (json['district_lgd'] as num).toInt(),
    districtName: json['district_name'] as String? ?? '',
    stateCode: json['state_code'] as String? ?? '',
    name: json['name'] as String,
    kind: json['kind'] as String? ?? 'city',
    isDistrictHeadquarters: (json['is_district_hq'] as num?)?.toInt() == 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'district_lgd': districtLgd,
    'district_name': districtName,
    'state_code': stateCode,
    'name': name,
    'kind': kind,
    'is_district_hq': isDistrictHeadquarters ? 1 : 0,
  };

  @override
  String toString() => 'PlaceRecord($id, $name)';
}
