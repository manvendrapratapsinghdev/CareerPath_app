import 'package:shared_preferences/shared_preferences.dart';

class RatePromptRepository {
  final SharedPreferences _prefs;

  RatePromptRepository(this._prefs);

  static const _sessionCountKey = 'rate_session_count';
  static const _firstSessionDateKey = 'rate_first_session_date';
  static const _dontAskAgainKey = 'rate_dont_ask_again';

  int getSessionCount() => _prefs.getInt(_sessionCountKey) ?? 0;

  Future<bool> incrementSessionCount() async {
    final count = getSessionCount() + 1;
    return _prefs.setInt(_sessionCountKey, count);
  }

  String? getFirstSessionDate() => _prefs.getString(_firstSessionDateKey);

  Future<bool> setFirstSessionDate(String date) async {
    return _prefs.setString(_firstSessionDateKey, date);
  }

  bool getDontAskAgain() => _prefs.getBool(_dontAskAgainKey) ?? false;

  Future<bool> setDontAskAgain(bool value) async {
    return _prefs.setBool(_dontAskAgainKey, value);
  }
}
