import 'package:test/test.dart';

import 'package:domain/model/directory.dart';

void main() {
  group('Directory models', () {
    const entry1 = DirectoryEntry(
      name: 'src',
      path: '/home/user/src',
      hidden: false,
    );
    const entry2 = DirectoryEntry(
      name: '.git',
      path: '/home/user/.git',
      hidden: true,
    );

    test('DirectoryEntry equality and hashCode', () {
      const copy = DirectoryEntry(
        name: 'src',
        path: '/home/user/src',
        hidden: false,
      );
      expect(entry1, equals(copy));
      expect(entry1.hashCode, equals(copy.hashCode));
      expect(entry1, isNot(equals(entry2)));
    });

    test('DirectoryListing collection equality on crumbs and entries', () {
      const a = DirectoryListing(
        path: '/home/user',
        home: '/home/user',
        crumbs: [entry1],
        entries: [entry1, entry2],
        truncated: false,
      );
      const b = DirectoryListing(
        path: '/home/user',
        home: '/home/user',
        crumbs: [
          DirectoryEntry(name: 'src', path: '/home/user/src', hidden: false),
        ],
        entries: [
          DirectoryEntry(name: 'src', path: '/home/user/src', hidden: false),
          DirectoryEntry(name: '.git', path: '/home/user/.git', hidden: true),
        ],
        truncated: false,
      );
      const diffEntries = DirectoryListing(
        path: '/home/user',
        home: '/home/user',
        crumbs: [entry1],
        entries: [entry1],
        truncated: false,
      );
      const diffTruncated = DirectoryListing(
        path: '/home/user',
        home: '/home/user',
        crumbs: [entry1],
        entries: [entry1, entry2],
        truncated: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diffEntries)));
      expect(a, isNot(equals(diffTruncated)));
    });
  });
}
