import 'package:flutter/foundation.dart';

import '../data/bookmark_repository.dart';

class BookmarkService extends ChangeNotifier {
  final BookmarkRepository _repository;

  BookmarkService(this._repository);

  List<String> get bookmarkedIds => _repository.getAll();

  bool isBookmarked(String nodeId) => _repository.isBookmarked(nodeId);

  Future<void> toggle(String nodeId) async {
    if (isBookmarked(nodeId)) {
      await _repository.remove(nodeId);
    } else {
      await _repository.add(nodeId);
    }
    notifyListeners();
  }
}
