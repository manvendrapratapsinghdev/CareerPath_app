import '../data/profile_repository.dart';
import '../models/profile_data.dart';

class ProfileService {
  final ProfileRepository _repository;

  ProfileService(this._repository);

  /// Saves profile and returns true on success, false on failure.
  Future<bool> saveProfile(String name, String stream) async {
    try {
      await _repository.saveProfile(name, stream);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the current profile, or null if none exists.
  Future<ProfileData?> getProfile() {
    return _repository.loadProfile();
  }

  /// Returns true if a profile has been saved previously.
  Future<bool> isProfileComplete() {
    return _repository.hasProfile();
  }
}
