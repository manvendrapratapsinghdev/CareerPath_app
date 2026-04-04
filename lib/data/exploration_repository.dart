import 'package:shared_preferences/shared_preferences.dart';

class ExplorationRepository {
  final SharedPreferences _prefs;

  ExplorationRepository(this._prefs);

  static const _key = 'visited_nodes';

  Set<String> getAll() {
    try {
      return (_prefs.getStringList(_key) ?? []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<bool> markVisited(String nodeId) async {
    try {
      final set = getAll();
      if (set.contains(nodeId)) return true;
      set.add(nodeId);
      return await _prefs.setStringList(_key, set.toList());
    } catch (_) {
      return false;
    }
  }

  bool isVisited(String nodeId) => getAll().contains(nodeId);
}
