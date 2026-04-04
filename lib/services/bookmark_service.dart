import 'package:flutter/foundation.dart';

import '../data/bookmark_repository.dart';
import '../data/leaf_details_cache.dart';
import '../models/leaf_details.dart';

class BookmarkService extends ChangeNotifier {
  final BookmarkRepository _repository;
  final LeafDetailsCache? _cache;

  BookmarkService(this._repository, [this._cache]);

  List<String> get bookmarkedIds => _repository.getAll();

  bool isBookmarked(String nodeId) => _repository.isBookmarked(nodeId);

  Future<void> toggle(String nodeId, {LeafDetails? details}) async {
    if (isBookmarked(nodeId)) {
      await _repository.remove(nodeId);
      _cache?.remove(nodeId);
    } else {
      await _repository.add(nodeId);
      if (details != null) {
        _cache?.save(nodeId, details);
      }
    }
    notifyListeners();
  }

  /// Cache leaf details for an already-bookmarked node.
  Future<void> cacheDetails(String nodeId, LeafDetails details) async {
    if (isBookmarked(nodeId)) {
      await _cache?.save(nodeId, details);
    }
  }

  /// Get cached leaf details for offline access.
  LeafDetails? getCachedDetails(String nodeId) {
    return _cache?.get(nodeId);
  }
}
