/// The file inputs a host page opens, answered by the system picker.
///
/// The WebView asks through `onShowFileChooser`; the page's `accept` and
/// `capture` attributes arrive as a [FileSelectorParams]. This seam normalises
/// that ask into a [FileChooserRequest] and hands it to an injectable picker,
/// so the mapping is testable without a platform view or a picker dialog.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Answers a file-selection ask with absolute paths; empty means cancel.
typedef FilePickerFn = Future<List<String>> Function(
  FileChooserRequest request,
);

/// One page file input, expressed in the picker's vocabulary.
///
/// [type] and [allowedExtensions] are `file_picker`'s filter arguments: the
/// picker has no parameter that takes a MIME type, so exact MIME asks become
/// the extensions they describe. A wildcard mixed with exact asks, or a MIME
/// type with no known extension, falls back to [FileType.any] rather than
/// excluding a file the page accepts.
@immutable
class FileChooserRequest {
  const FileChooserRequest({
    required this.allowMultiple,
    required this.capture,
    required this.type,
    this.allowedExtensions,
  });

  /// The request behind one WebView file-selection ask.
  factory FileChooserRequest.fromPlatform(FileSelectorParams params) {
    final filter = _filterFor(params.acceptTypes);
    return FileChooserRequest(
      allowMultiple: params.mode == FileSelectorMode.openMultiple,
      capture: params.isCaptureEnabled,
      type: filter.type,
      allowedExtensions: filter.allowedExtensions,
    );
  }

  /// Whether the page marked the input `multiple`.
  final bool allowMultiple;

  /// Whether the page marked the input `capture` (live camera or microphone).
  final bool capture;

  /// The picker's file-type filter.
  final FileType type;

  /// Dot-less extensions when [type] is [FileType.custom], else null.
  final List<String>? allowedExtensions;

  @override
  bool operator ==(Object other) =>
      other is FileChooserRequest &&
      other.allowMultiple == allowMultiple &&
      other.capture == capture &&
      other.type == type &&
      listEquals(other.allowedExtensions, allowedExtensions);

  @override
  int get hashCode => Object.hash(
    allowMultiple,
    capture,
    type,
    Object.hashAll(allowedExtensions ?? const <String>[]),
  );
}

/// Maps a WebView file-selection ask to the system picker.
abstract final class WebViewFileChooser {
  /// Answers [params] with absolute paths; empty means the user canceled.
  ///
  /// [capturePicker] answers a page that asked for live capture. The
  /// production call omits it because `file_picker` has no capture dialog:
  /// `capture` is still carried on the request, and [picker] answers it as a
  /// normal file ask.
  static Future<List<String>> choose(
    FileSelectorParams params, {
    FilePickerFn picker = pickFilesWithFilePicker,
    FilePickerFn? capturePicker,
  }) {
    final request = FileChooserRequest.fromPlatform(params);
    final capture = capturePicker;
    if (request.capture && capture != null) return capture(request);
    return picker(request);
  }
}

/// The production picker: the platform dialog behind `file_picker`.
///
/// Android copies every picked content URI into the app cache, so each result
/// carries an absolute local path. A platform failure is reported as an empty
/// selection, the same observable outcome as a cancel.
Future<List<String>> pickFilesWithFilePicker(FileChooserRequest request) async {
  try {
    final List<PlatformFile> files;
    if (request.allowMultiple) {
      files = await FilePicker.pickFiles(
        type: request.type,
        allowedExtensions: request.allowedExtensions,
      );
    } else {
      final file = await FilePicker.pickFile(
        type: request.type,
        allowedExtensions: request.allowedExtensions,
      );
      files = file == null ? const <PlatformFile>[] : <PlatformFile>[file];
    }
    final paths = <String>[];
    for (final file in files) {
      final path = file.path;
      if (path != null) paths.add(path);
    }
    return paths;
  } on PlatformException {
    return const <String>[];
  } on MissingPluginException {
    return const <String>[];
  }
}

/// Normalises the page's `accept` tokens to a picker filter.
///
/// Tokens are MIME types (`image/*`, `application/pdf`), extensions (`.pdf`),
/// or `*/*`; Android hands over exactly what the `accept` attribute contains.
({FileType type, List<String>? allowedExtensions}) _filterFor(
  List<String> acceptTypes,
) {
  final tokens = <String>[
    for (final accept in acceptTypes)
      for (final token in accept.split(','))
        if (token.trim().isNotEmpty) token.trim().toLowerCase(),
  ];
  if (tokens.isEmpty) {
    return (type: FileType.any, allowedExtensions: null);
  }

  final categories = <FileType>{};
  final extensions = <String>{};
  var unexpressible = false;
  for (final token in tokens) {
    if (token == '*/*' || token == '*') {
      return (type: FileType.any, allowedExtensions: null);
    }
    if (token == 'image/*') {
      categories.add(FileType.image);
    } else if (token == 'video/*') {
      categories.add(FileType.video);
    } else if (token == 'audio/*') {
      categories.add(FileType.audio);
    } else if (token.startsWith('.')) {
      if (token.length > 1) {
        extensions.add(token.substring(1));
      } else {
        unexpressible = true;
      }
    } else {
      final mapped = _mimeExtensions[token];
      if (mapped == null) {
        unexpressible = true;
      } else {
        extensions.addAll(mapped);
      }
    }
  }
  if (unexpressible) {
    return (type: FileType.any, allowedExtensions: null);
  }

  if (extensions.isEmpty) {
    if (categories.length == 1) {
      return (type: categories.single, allowedExtensions: null);
    }
    if (categories.length == 2 &&
        categories.contains(FileType.image) &&
        categories.contains(FileType.video)) {
      return (type: FileType.media, allowedExtensions: null);
    }
    // A wildcard mixed with another wildcard has no single picker type.
    return (type: FileType.any, allowedExtensions: null);
  }
  if (categories.isNotEmpty) {
    // A wildcard mixed with exact types cannot be expressed as one extension
    // list without excluding files the page accepts.
    return (type: FileType.any, allowedExtensions: null);
  }
  final allowed = extensions.toList()..sort();
  return (type: FileType.custom, allowedExtensions: allowed);
}

/// Exact MIME types whose picker filter is their extension list.
const Map<String, List<String>> _mimeExtensions = <String, List<String>>{
  'application/json': <String>['json'],
  'application/msword': <String>['doc'],
  'application/pdf': <String>['pdf'],
  'application/vnd.ms-excel': <String>['xls'],
  'application/vnd.ms-powerpoint': <String>['ppt'],
  'application/vnd.openxmlformats-officedocument.presentationml.presentation':
      <String>['pptx'],
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': <String>[
    'xlsx',
  ],
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      <String>['docx'],
  'application/zip': <String>['zip'],
  'audio/mpeg': <String>['mp3'],
  'image/gif': <String>['gif'],
  'image/jpeg': <String>['jpg', 'jpeg'],
  'image/png': <String>['png'],
  'image/webp': <String>['webp'],
  'text/csv': <String>['csv'],
  'text/plain': <String>['txt'],
  'video/mp4': <String>['mp4'],
  'video/webm': <String>['webm'],
};
