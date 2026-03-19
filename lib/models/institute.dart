/// Represents an educational institute for a career path.
class Institute {
  final int id;
  final String name;
  final String? city;
  final String? website;
  final String? description;

  const Institute({
    required this.id,
    required this.name,
    this.city,
    this.website,
    this.description,
  });

  factory Institute.fromJson(Map<String, dynamic> json) {
    return Institute(
      id: json['id'] as int,
      name: json['name'] as String,
      city: json['city'] as String?,
      website: json['website'] as String?,
      description: json['description'] as String?,
    );
  }

  @override
  String toString() => 'Institute($id, $name)';
}
