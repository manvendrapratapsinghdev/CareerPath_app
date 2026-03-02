import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  late ProfileService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = ProfileService(ProfileRepository(prefs));
  });

  group('saveProfile', () {
    test('returns true on successful save', () async {
      final result = await service.saveProfile('Alice', 'science');
      expect(result, isTrue);
    });

    test('persists data that can be retrieved via getProfile', () async {
      await service.saveProfile('Bob', 'commerce');
      final profile = await service.getProfile();
      expect(profile, isNotNull);
      expect(profile!.name, 'Bob');
      expect(profile.stream, 'commerce');
    });
  });

  group('getProfile', () {
    test('returns null when no profile saved', () async {
      final profile = await service.getProfile();
      expect(profile, isNull);
    });

    test('returns saved profile data', () async {
      await service.saveProfile('Carol', 'art');
      final profile = await service.getProfile();
      expect(profile, isNotNull);
      expect(profile!.name, 'Carol');
      expect(profile.stream, 'art');
    });
  });

  group('isProfileComplete', () {
    test('returns false when no profile saved', () async {
      final result = await service.isProfileComplete();
      expect(result, isFalse);
    });

    test('returns true after profile is saved', () async {
      await service.saveProfile('Dave', 'science');
      final result = await service.isProfileComplete();
      expect(result, isTrue);
    });
  });
}
