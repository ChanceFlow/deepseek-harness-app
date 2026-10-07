import 'package:test/test.dart';

import 'package:domain/model/open_in_app.dart';

void main() {
  group('WorkspacePathApplication', () {
    test('equality and hashCode cover every host-reported field', () {
      const files = WorkspacePathApplication(
        id: 'org.gnome.Nautilus.desktop',
        name: 'Files',
        isDefault: true,
        icon: 'data:image/png;base64,AAAA',
      );
      const same = WorkspacePathApplication(
        id: 'org.gnome.Nautilus.desktop',
        name: 'Files',
        isDefault: true,
        icon: 'data:image/png;base64,AAAA',
      );

      expect(files, equals(same));
      expect(files.hashCode, equals(same.hashCode));
      expect(
        files,
        isNot(
          equals(
            const WorkspacePathApplication(
              id: 'org.gnome.Nautilus.desktop',
              name: 'Files',
              isDefault: false,
              icon: 'data:image/png;base64,AAAA',
            ),
          ),
        ),
      );
      expect(
        files,
        isNot(
          equals(
            const WorkspacePathApplication(
              id: 'org.gnome.Nautilus.desktop',
              name: 'Files',
              isDefault: true,
              icon: null,
            ),
          ),
        ),
      );
    });

    test('a null icon is the desktop stating it supplied none', () {
      const code = WorkspacePathApplication(
        id: 'code.desktop',
        name: 'Code',
        isDefault: false,
        icon: null,
      );

      expect(code.icon, isNull);
      expect(code.isDefault, isFalse);
    });
  });
}
