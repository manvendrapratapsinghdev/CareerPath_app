import 'package:flutter/foundation.dart';

import '../data/recently_viewed_repository.dart';

class RecentlyViewedService extends ChangeNotifier {
  final RecentlyViewedRepository _repository;

  RecentlyViewedService(this._repository);

  List<String> get recentIds => _repository.getAll();

  Future<void> addVisit(String nodeId) async {
    await _repository.addVisit(nodeId);
    notifyListeners();
  }

  Future<void> clear() async {
    await _repository.clear();
    notifyListeners();
  }
}
