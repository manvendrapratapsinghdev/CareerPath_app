/// An Indian state or union territory (`states`, LGD-coded).
class StateRegion {
  /// ISO 3166-2 code, e.g. `IN-RJ`.
  final String code;
  final int lgdCode;
  final String countryCode;
  final String name;

  /// `state` or `ut`.
  final String kind;

  /// `north`, `south`, `east`, `west`, `central` or `north_east`.
  final String zone;

  const StateRegion({
    required this.code,
    required this.lgdCode,
    this.countryCode = 'IN',
    required this.name,
    required this.kind,
    required this.zone,
  });

  factory StateRegion.fromJson(Map<String, dynamic> json) => StateRegion(
    code: json['code'] as String,
    lgdCode: (json['lgd_code'] as num).toInt(),
    countryCode: json['country_code'] as String? ?? 'IN',
    name: json['name'] as String,
    kind: json['kind'] as String? ?? 'state',
    zone: json['zone'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'lgd_code': lgdCode,
    'country_code': countryCode,
    'name': name,
    'kind': kind,
    'zone': zone,
  };

  bool get isUnionTerritory => kind == 'ut';

  @override
  String toString() => 'StateRegion($code, $name)';
}
