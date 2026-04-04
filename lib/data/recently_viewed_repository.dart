import 'package:shared_preferences/shared_preferences.dart';

class RecentlyViewedRepository {
  final SharedPreferences _prefs;

  RecentlyViewedRepository(this._prefs);

  static const _key = 'recently_viewed_nodes';
  static const maxItems = 15;

  List<String> getAll() {
    try {
      return _prefs.getStringList(_key) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> addVisit(String nodeId) async {
    try {
      final list = getAll();
      list.remove(nodeId);
      list.insert(0, nodeId);
      if (list.length > maxItems) {
        list.removeRange(maxItems, list.length);
      }
      return await _prefs.setStringList(_key, list);
    } catch (_) {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      return await _prefs.remove(_key);
    } catch (_) {
      return false;
    }
  }
}
