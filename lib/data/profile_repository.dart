import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile_data.dart';

class ProfileRepository {
  final SharedPreferences _prefs;

  ProfileRepository(this._prefs);

  static const _keyName = 'profile_name';
  static const _keyStream = 'profile_stream';

  Future<void> saveProfile(String name, String stream) async {
    await _prefs.setString(_keyName, name);
    await _prefs.setString(_keyStream, stream);
  }

  Future<ProfileData?> loadProfile() {
    try {
      final name = _prefs.getString(_keyName);
      final stream = _prefs.getString(_keyStream);
      if (name == null || stream == null) return Future.value(null);
      return Future.value(ProfileData(name: name, stream: stream));
    } catch (_) {
      return Future.value(null);
    }
  }

  Future<bool> hasProfile() {
    try {
      return Future.value(
        _prefs.containsKey(_keyName) && _prefs.containsKey(_keyStream),
      );
    } catch (_) {
      return Future.value(false);
    }
  }
}
