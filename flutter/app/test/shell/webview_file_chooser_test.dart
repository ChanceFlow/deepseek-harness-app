/// The page's file input maps to the picker's vocabulary.
library;

import 'package:app/shell/webview_file_chooser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

FileSelectorParams _params({
  bool capture = false,
  List<String> acceptTypes = const <String>[],
  FileSelectorMode mode = FileSelectorMode.open,
}) {
  return FileSelectorParams(
    isCaptureEnabled: capture,
    acceptTypes: acceptTypes,
    mode: mode,
  );
}

void main() {
  test('a single file input asks the picker for one file', () async {
    final requests = <FileChooserRequest>[];
    final paths = await WebViewFileChooser.choose(
      _params(),
      picker: (request) async {
        requests.add(request);
        return const <String>['/tmp/notes.txt'];
      },
    );

    expect(requests.single.allowMultiple, isFalse);
    expect(requests.single.type, FileType.any);
    expect(requests.single.allowedExtensions, isNull);
    expect(paths, <String>['/tmp/notes.txt']);
  });

  test('a multiple file input asks for every selected path', () async {
    final requests = <FileChooserRequest>[];
    final paths = await WebViewFileChooser.choose(
      _params(mode: FileSelectorMode.openMultiple),
      picker: (request) async {
        requests.add(request);
        return const <String>['/tmp/a.pdf', '/tmp/b.pdf'];
      },
    );

    expect(requests.single.allowMultiple, isTrue);
    expect(paths, <String>['/tmp/a.pdf', '/tmp/b.pdf']);
  });

  test('an image accept asks the picker for images', () async {
    final requests = <FileChooserRequest>[];
    await WebViewFileChooser.choose(
      _params(acceptTypes: const <String>['image/*']),
      picker: (request) async {
        requests.add(request);
        return const <String>[];
      },
    );

    expect(requests.single.type, FileType.image);
    expect(requests.single.allowedExtensions, isNull);
  });

  test('a wildcard accept asks the picker for any file', () async {
    final requests = <FileChooserRequest>[];
    await WebViewFileChooser.choose(
      _params(acceptTypes: const <String>['*/*']),
      picker: (request) async {
        requests.add(request);
        return const <String>[];
      },
    );

    expect(requests.single.type, FileType.any);
  });

  test('a .pdf accept becomes a custom extension filter', () async {
    final requests = <FileChooserRequest>[];
    await WebViewFileChooser.choose(
      _params(acceptTypes: const <String>['.pdf']),
      picker: (request) async {
        requests.add(request);
        return const <String>[];
      },
    );

    expect(requests.single.type, FileType.custom);
    expect(requests.single.allowedExtensions, <String>['pdf']);
  });

  test('an exact MIME accept becomes the extensions it describes', () async {
    final requests = <FileChooserRequest>[];
    await WebViewFileChooser.choose(
      _params(acceptTypes: const <String>['application/pdf']),
      picker: (request) async {
        requests.add(request);
        return const <String>[];
      },
    );

    expect(requests.single.type, FileType.custom);
    expect(requests.single.allowedExtensions, <String>['pdf']);
  });

  test('an accept with several exact asks merges their extensions', () async {
    final requests = <FileChooserRequest>[];
    await WebViewFileChooser.choose(
      _params(acceptTypes: const <String>['.pdf', 'image/png', 'image/jpeg']),
      picker: (request) async {
        requests.add(request);
        return const <String>[];
      },
    );

    expect(requests.single.type, FileType.custom);
    expect(requests.single.allowedExtensions, <String>[
      'jpeg',
      'jpg',
      'pdf',
      'png',
    ]);
  });

  test(
    'an unexpressible MIME falls back to any file, never a subset',
    () async {
      final requests = <FileChooserRequest>[];
      await WebViewFileChooser.choose(
        _params(acceptTypes: const <String>['application/x-unknown']),
        picker: (request) async {
          requests.add(request);
          return const <String>[];
        },
      );

      expect(requests.single.type, FileType.any);
      expect(requests.single.allowedExtensions, isNull);
    },
  );

  test(
    'capture reaches the picker and is answered as a normal file ask',
    () async {
      final requests = <FileChooserRequest>[];
      final paths = await WebViewFileChooser.choose(
        _params(capture: true),
        picker: (request) async {
          requests.add(request);
          return const <String>['/tmp/photo.jpg'];
        },
      );

      expect(requests.single.capture, isTrue);
      expect(requests.single.allowMultiple, isFalse);
      expect(paths, <String>['/tmp/photo.jpg']);
    },
  );

  test(
    'a capture picker answers first when the page asked for capture',
    () async {
      final fileRequests = <FileChooserRequest>[];
      final captureRequests = <FileChooserRequest>[];
      final paths = await WebViewFileChooser.choose(
        _params(capture: true),
        picker: (request) async {
          fileRequests.add(request);
          return const <String>['/tmp/upload.txt'];
        },
        capturePicker: (request) async {
          captureRequests.add(request);
          return const <String>['/tmp/photo.jpg'];
        },
      );

      expect(fileRequests, isEmpty);
      expect(captureRequests.single.capture, isTrue);
      expect(paths, <String>['/tmp/photo.jpg']);
    },
  );

  test('a capture picker is not consulted when the page did not ask', () async {
    final captureRequests = <FileChooserRequest>[];
    final paths = await WebViewFileChooser.choose(
      _params(),
      picker: (request) async => const <String>['/tmp/upload.txt'],
      capturePicker: (request) async {
        captureRequests.add(request);
        return const <String>['/tmp/photo.jpg'];
      },
    );

    expect(captureRequests, isEmpty);
    expect(paths, <String>['/tmp/upload.txt']);
  });

  test('a canceled picker answers with an empty list', () async {
    final paths = await WebViewFileChooser.choose(
      _params(),
      picker: (request) async => const <String>[],
    );

    expect(paths, isEmpty);
  });
}
