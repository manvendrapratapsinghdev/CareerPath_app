/// A district in the Indian Local Government Directory (`districts`).
class DistrictRegion {
  final int lgdCode;
  final String stateCode;
  final String name;

  const DistrictRegion({
    required this.lgdCode,
    required this.stateCode,
    required this.name,
  });

  factory DistrictRegion.fromJson(Map<String, dynamic> json) => DistrictRegion(
    lgdCode: (json['lgd_code'] as num).toInt(),
    stateCode: json['state_code'] as String,
    name: json['name'] as String,
  );

  Map<String, dynamic> toJson() => {
    'lgd_code': lgdCode,
    'state_code': stateCode,
    'name': name,
  };

  @override
  String toString() => 'DistrictRegion($lgdCode, $name)';
}
