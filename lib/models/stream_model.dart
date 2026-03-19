class StreamModel {
  final String id;
  final String name;
  final List<String> categoryIds;
  final String? intro;

  /// Count of root nodes from the /api/streams response.
  /// Available immediately — before categories are lazily loaded.
  final int rootNodeCount;

  StreamModel({
    required this.id,
    required this.name,
    required this.categoryIds,
    this.intro,
    int? rootNodeCount,
  }) : rootNodeCount = rootNodeCount ?? categoryIds.length;

  factory StreamModel.fromJson(Map<String, dynamic> json) {
    return StreamModel(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryIds: List<String>.from(json['categoryIds'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'categoryIds': categoryIds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          _listEquals(categoryIds, other.categoryIds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(categoryIds));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
