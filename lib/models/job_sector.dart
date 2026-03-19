/// Represents a job sector for a career path.
class JobSector {
  final int id;
  final String name;
  final String? description;

  const JobSector({
    required this.id,
    required this.name,
    this.description,
  });

  factory JobSector.fromJson(Map<String, dynamic> json) {
    return JobSector(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }

  @override
  String toString() => 'JobSector($id, $name)';
}
