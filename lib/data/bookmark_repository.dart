import 'package:shared_preferences/shared_preferences.dart';

class BookmarkRepository {
  final SharedPreferences _prefs;

  BookmarkRepository(this._prefs);

  static const _key = 'bookmarked_nodes';

  List<String> getAll() {
    try {
      return _prefs.getStringList(_key) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> add(String nodeId) async {
    try {
      final list = getAll();
      if (list.contains(nodeId)) return true;
      list.add(nodeId);
      return await _prefs.setStringList(_key, list);
    } catch (_) {
      return false;
    }
  }

  Future<bool> remove(String nodeId) async {
    try {
      final list = getAll();
      list.remove(nodeId);
      return await _prefs.setStringList(_key, list);
    } catch (_) {
      return false;
    }
  }

  bool isBookmarked(String nodeId) {
    return getAll().contains(nodeId);
  }
}
