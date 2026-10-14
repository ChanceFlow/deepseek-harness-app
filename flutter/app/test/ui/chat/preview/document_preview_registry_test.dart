/// Document-preview registry tests: which renderers claim a path, in which
/// order, and which paths have none at all.
///
/// The rule being pinned is the reference's
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/registry.ts:36-49`,
/// `.../document/suffix.ts:31-36`): longest declared suffix first, the
/// plain-text viewer only where the bytes are readable text, and a known
/// binary container with no renderer left with no candidate.
library;

import 'package:app/ui/chat/preview/document_preview_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an HTML path offers the document renderer and its source', () {
    expect(previewCandidates('docs/report.html'), <PreviewCandidate>[
      const PreviewCandidate(
        PreviewRenderer.html,
        PreviewLoadMode.bytesComplete,
      ),
      const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
    ]);
  });

  test(
    'suffix matching is the lowercased basename, with \\ as a separator',
    () {
      expect(
        previewCandidates(r'C:\work\REPORT.HTML').first.renderer,
        PreviewRenderer.html,
      );
      expect(documentFileName('/a/b/C.TXT'), 'c.txt');
    },
  );

  test('a declared binary suffix keeps its renderer and loses the source', () {
    expect(previewCandidates('assets/logo.png'), <PreviewCandidate>[
      const PreviewCandidate(
        PreviewRenderer.image,
        PreviewLoadMode.bytesComplete,
      ),
    ]);
  });

  test('an SVG keeps the source view because the reference does not call it '
      'binary', () {
    expect(previewCandidates('assets/logo.svg'), <PreviewCandidate>[
      const PreviewCandidate(
        PreviewRenderer.image,
        PreviewLoadMode.bytesComplete,
      ),
      const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
    ]);
  });

  test('markdown and code stay in the text lane', () {
    for (final path in <String>['notes.md', 'lib/main.dart', 'data.json']) {
      expect(previewCandidates(path), <PreviewCandidate>[
        const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
      ], reason: path);
    }
  });

  test('a binary container no renderer claims has no candidate at all', () {
    for (final path in <String>[
      'bundle.zip',
      'clip.mp4',
      'fonts/brand.woff2',
    ]) {
      expect(previewCandidates(path), isEmpty, reason: path);
      expect(unviewableBinaryPath(path), isTrue, reason: path);
    }
  });

  test('a spreadsheet claims its suffixes, and a delimited one keeps its '
      'source', () {
    const grid = PreviewCandidate(
      PreviewRenderer.spreadsheet,
      PreviewLoadMode.bytesComplete,
    );
    expect(previewCandidates('book.xlsx'), <PreviewCandidate>[grid]);
    expect(binaryDocumentPath('book.xlsx'), isTrue);
    expect(previewCandidates('data.csv'), <PreviewCandidate>[
      grid,
      const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
    ]);
    expect(previewCandidates('data.tsv').first, grid);
  });

  test('a PDF is claimed whole and loses the source view', () {
    const document = PreviewCandidate(
      PreviewRenderer.pdf,
      PreviewLoadMode.bytesComplete,
    );
    expect(previewCandidates('docs/report.PDF'), <PreviewCandidate>[document]);
    expect(binaryDocumentPath('docs/report.pdf'), isTrue);
    // The suffix stays in the reference's binary container list; a
    // registration for it takes precedence, because that list is consulted
    // only when nothing matched.
    expect(unviewableBinaryPath('docs/report.pdf'), isTrue);
  });

  test('office documents are converted, so they have no source view', () {
    const office = PreviewCandidate(
      PreviewRenderer.office,
      PreviewLoadMode.renderer,
    );
    for (final path in <String>[
      'docs/brief.doc',
      'docs/brief.docx',
      'docs/deck.pptx',
    ]) {
      expect(previewCandidates(path), <PreviewCandidate>[office], reason: path);
      expect(binaryDocumentPath(path), isTrue, reason: path);
    }
  });

  test('xls has no parser yet, so its suffix stays unclaimed', () {
    expect(previewCandidates('legacy.xls'), isEmpty);
    expect(unviewableBinaryPath('legacy.xls'), isTrue);
  });

  test(
    'binaryDocumentPath reads the declarations, not the unviewable list',
    () {
      expect(binaryDocumentPath('assets/logo.png'), isTrue);
      expect(binaryDocumentPath('assets/logo.svg'), isFalse);
      expect(binaryDocumentPath('legacy.xls'), isFalse);
    },
  );

  test('a compound suffix matches as a unit', () {
    expect(matchedSuffixLength('bundle.tar.gz', <String>['tar', 'gz']), 2);
    expect(matchedSuffixLength('bundle.tar.gz', <String>['tar.gz', 'gz']), 6);
    expect(normalizeSuffix('.HTML'), 'html');
  });

  test('a path with no suffix reads as text', () {
    expect(previewCandidates('LICENSE'), <PreviewCandidate>[
      const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
    ]);
  });
}
