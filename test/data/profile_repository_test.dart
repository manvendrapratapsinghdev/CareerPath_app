import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';

void main() {
  late ProfileRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repository = ProfileRepository(prefs);
  });

  group('saveProfile and loadProfile', () {
    test('round-trip: saves and loads profile data', () async {
      await repository.saveProfile('Alice', 'science');
      final profile = await repository.loadProfile();

      expect(profile, isNotNull);
      expect(profile!.name, 'Alice');
      expect(profile.stream, 'science');
    });

    test('overwrites previous profile on re-save', () async {
      await repository.saveProfile('Alice', 'science');
      await repository.saveProfile('Bob', 'commerce');

      final profile = await repository.loadProfile();
      expect(profile!.name, 'Bob');
      expect(profile.stream, 'commerce');
    });
  });

  group('loadProfile', () {
    test('returns null when no data saved', () async {
      final profile = await repository.loadProfile();
      expect(profile, isNull);
    });

    test('returns null when only name is saved', () async {
      SharedPreferences.setMockInitialValues({'profile_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs);

      final profile = await repo.loadProfile();
      expect(profile, isNull);
    });
  });

  group('hasProfile', () {
    test('returns false when no data saved', () async {
      final result = await repository.hasProfile();
      expect(result, isFalse);
    });

    test('returns true after profile is saved', () async {
      await repository.saveProfile('Carol', 'art');
      final result = await repository.hasProfile();
      expect(result, isTrue);
    });
  });
}
