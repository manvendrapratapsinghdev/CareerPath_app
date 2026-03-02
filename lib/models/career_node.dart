class CareerNode {
  final String id;
  final String name;
  final String? parentId;
  final List<String> childIds;

  CareerNode({
    required this.id,
    required this.name,
    this.parentId,
    this.childIds = const [],
  });

  bool get isLeaf => childIds.isEmpty;

  factory CareerNode.fromJson(Map<String, dynamic> json) {
    return CareerNode(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      childIds: json['childIds'] != null
          ? List<String>.from(json['childIds'] as List)
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'childIds': childIds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CareerNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          parentId == other.parentId &&
          _listEquals(childIds, other.childIds);

  @override
  int get hashCode => Object.hash(id, name, parentId, Object.hashAll(childIds));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
