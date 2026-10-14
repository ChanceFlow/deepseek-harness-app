/// Pure-Dart domain representation for a host-rendered Office document.
library;

import 'dart:typed_data';

/// A complete PDF the host rendered from one Office document
/// (`officeToPdf/render`).
///
/// Mirrors the reference `RenderedDocumentBytes`
/// (`reference/deepseek-harness/packages/document/office-to-pdf/src/types.ts:48-51`),
/// a `WorkspaceFileBytes` — the source document's identity plus the whole PDF —
/// with the conversion's font report. This model carries the two facts the
/// phone path consumes: the PDF in [data] and the families the conversion
/// could not find in [missingFonts]. The host renders complete documents
/// (`offset` 0, `eof` true), and the identity fields exist on the reference for
/// its browser-side cache; this path holds no PDF cache, so it surfaces
/// neither them nor `officeToPdf/generation` (the reasoning lives in
/// `.agents/notes/implemented/feature/2026-10-12-office-to-pdf-preview-wire.md`).
final class OfficePdfDocument {
  const OfficePdfDocument({required this.data, required this.missingFonts});

  /// The caller-owned complete PDF document.
  final Uint8List data;

  /// The OOXML font families the conversion could not find, in the host's
  /// order; empty for a binary Office format, which carries its fonts.
  final List<String> missingFonts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfficePdfDocument &&
          _sameBytes(other.data, data) &&
          _sameStrings(other.missingFonts, missingFonts));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(data), Object.hashAll(missingFonts));
}

/// Compares two byte views by content, not identity.
bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares two string lists by content and order.
bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
