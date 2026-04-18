import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/leaf_details.dart';

class LeafDetailsCache {
  final SharedPreferences _prefs;

  LeafDetailsCache(this._prefs);

  static const _prefix = 'cached_leaf_';

  Future<bool> save(String nodeId, LeafDetails details) async {
    try {
      final json = jsonEncode(details.toJson());
      return await _prefs.setString('$_prefix$nodeId', json);
    } catch (_) {
      return false;
    }
  }

  LeafDetails? get(String nodeId) {
    try {
      final raw = _prefs.getString('$_prefix$nodeId');
      if (raw == null) return null;
      return LeafDetails.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> remove(String nodeId) async {
    try {
      return await _prefs.remove('$_prefix$nodeId');
    } catch (_) {
      return false;
    }
  }

  bool has(String nodeId) {
    return _prefs.containsKey('$_prefix$nodeId');
  }
}
