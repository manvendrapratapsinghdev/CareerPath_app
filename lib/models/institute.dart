/// Represents an educational institute for a career path.
class Institute {
  final int id;
  final String? sourceId;
  final String name;
  final String? city;
  final String? district;
  final String? state;
  final String? website;
  final String? description;

  const Institute({
    required this.id,
    this.sourceId,
    required this.name,
    this.city,
    this.district,
    this.state,
    this.website,
    this.description,
  });

  factory Institute.fromJson(Map<String, dynamic> json) {
    return Institute(
      id: json['id'] as int,
      sourceId: json['source_id'] as String?,
      name: json['name'] as String,
      city: json['city'] as String?,
      district: json['district'] as String?,
      state: json['state'] as String?,
      website: json['website'] as String?,
      description: json['description'] as String?,
    );
  }

  String? get location {
    final parts = <String>[];
    for (final value in [district ?? city, state]) {
      if (value != null && value.isNotEmpty && !parts.contains(value)) {
        parts.add(value);
      }
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  String toString() => 'Institute($id, $name)';
}
