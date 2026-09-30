import 'package:career_path/services/course_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reduces the many stored spellings to one key each', () {
    for (final level in [
      'UG',
      'Undergraduate',
      'Under Graduate',
      'ug programme',
    ]) {
      expect(CourseLevels.ofCourse(level), {CourseLevels.ug}, reason: level);
    }
    for (final level in [
      'PG',
      'postgraduate',
      'Post Graduate',
      'post graduation',
      'Super-Speciality',
    ]) {
      expect(CourseLevels.ofCourse(level), {CourseLevels.pg}, reason: level);
    }
    for (final level in ['Doctoral', 'postdoctoral', 'Ph.D', 'fellowship']) {
      expect(CourseLevels.ofCourse(level), {
        CourseLevels.doctoral,
      }, reason: level);
    }
    expect(CourseLevels.ofCourse('certificate'), {CourseLevels.certificate});
    expect(CourseLevels.ofCourse('skill-development'), {
      CourseLevels.certificate,
    });
  });

  test('a mixed level names every level in it', () {
    expect(CourseLevels.ofCourse('postgraduate_diploma'), {
      CourseLevels.pg,
      CourseLevels.diploma,
    });
    expect(CourseLevels.ofCourse('ug/pg'), {CourseLevels.ug, CourseLevels.pg});
    expect(CourseLevels.ofCourse('integrated undergraduate-postgraduate'), {
      CourseLevels.integrated,
      CourseLevels.ug,
      CourseLevels.pg,
    });
    expect(CourseLevels.ofCourse('mixed'), isEmpty);
    expect(CourseLevels.ofCourse(''), isEmpty);
  });

  test('reads the level a student asks for', () {
    expect(CourseLevels.requested(['pg', 'courses', 'indore']), {
      CourseLevels.pg,
    });
    expect(CourseLevels.requested(['masters', 'phd']), {
      CourseLevels.pg,
      CourseLevels.doctoral,
    });
    expect(CourseLevels.requested(['bachelor', 'diploma']), {
      CourseLevels.ug,
      CourseLevels.diploma,
    });
    // "After graduation" means PG, "graduation course" UG: not a level word.
    expect(CourseLevels.requested(['after', 'graduation']), isEmpty);
    expect(CourseLevels.isLevelWord('pg'), isTrue);
    expect(CourseLevels.isLevelWord('pharmacy'), isFalse);
  });
}
