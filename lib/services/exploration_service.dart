import 'package:flutter/foundation.dart';

import '../data/exploration_repository.dart';

class ExplorationService extends ChangeNotifier {
  final ExplorationRepository _repository;

  ExplorationService(this._repository);

  Set<String> get visitedIds => _repository.getAll();

  bool isVisited(String nodeId) => _repository.isVisited(nodeId);

  Future<void> markVisited(String nodeId) async {
    final wasNew = !_repository.isVisited(nodeId);
    await _repository.markVisited(nodeId);
    if (wasNew) notifyListeners();
  }

  int visitedCountFor(List<String> nodeIds) {
    final visited = visitedIds;
    return nodeIds.where((id) => visited.contains(id)).length;
  }
}
