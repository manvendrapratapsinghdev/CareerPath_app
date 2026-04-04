import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/bookmark_repository.dart';
import 'package:career_path/services/bookmark_service.dart';

void main() {
  late BookmarkService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = BookmarkService(BookmarkRepository(prefs));
  });

  test('initially has no bookmarks', () {
    expect(service.bookmarkedIds, isEmpty);
    expect(service.isBookmarked('node-1'), isFalse);
  });

  test('toggle adds a bookmark', () async {
    await service.toggle('node-1');
    expect(service.isBookmarked('node-1'), isTrue);
    expect(service.bookmarkedIds, ['node-1']);
  });

  test('toggle removes an existing bookmark', () async {
    await service.toggle('node-1');
    await service.toggle('node-1');
    expect(service.isBookmarked('node-1'), isFalse);
    expect(service.bookmarkedIds, isEmpty);
  });

  test('notifies listeners on toggle', () async {
    int callCount = 0;
    service.addListener(() => callCount++);

    await service.toggle('node-1');
    expect(callCount, 1);

    await service.toggle('node-1');
    expect(callCount, 2);
  });

  test('multiple bookmarks work independently', () async {
    await service.toggle('node-1');
    await service.toggle('node-2');
    expect(service.bookmarkedIds, ['node-1', 'node-2']);

    await service.toggle('node-1');
    expect(service.isBookmarked('node-1'), isFalse);
    expect(service.isBookmarked('node-2'), isTrue);
  });
}
