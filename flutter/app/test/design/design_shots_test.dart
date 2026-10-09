/// Design review renderer: pumps the real screens at phone size and writes
/// one PNG per state under `test/design/shots/`.
///
/// These are outputs, not baselines. `scripts/render_design.py` always
/// passes `--update-goldens`, so nothing here can fail on a pixel; the
/// review happens on the published page, by eye.
///
/// Only that script runs them: the shots need host fonts and their PNGs
/// are gitignored, so anywhere else — a plain `flutter test`, CI — they
/// skip. The switch is an environment variable rather than a tag in
/// `dart_test.yaml`, because that file is read only when the runner starts
/// inside `flutter/app/`, and the suite runs from `flutter/`.
///
/// Procedure, and the traps that cost a render:
/// [.agents/skills/dsh-design-review](../../../../.agents/skills/dsh-design-review/SKILL.md).
@Tags(<String>['design'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/notifications/session_notice.dart';
import 'package:app/ui/chat/card_detail.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/file_preview_sheet.dart';
import 'package:app/ui/chat/stats_line.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/tool_detail_surface.dart';
import 'package:app/ui/chat/tool_row_model.dart';
import 'package:app/ui/chat/transcript_view_mode.dart';
import 'package:app/ui/settings/gesture_shortcuts_section.dart';
import 'package:app/ui/settings/session_log_settings.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/shell_settings_page.dart';
import 'package:app/ui/settings/theme_preference.dart';
import 'package:app/ui/settings/web_search_settings_page.dart';
import 'package:app/ui/shared/archived_filter.dart';
import 'package:app/ui/shared/session_archive_confirm_dialog.dart';
import 'package:app/ui/subagents/subagent_screen.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:asr/asr.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/session_archive.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/workspace.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_fixtures.dart';

/// Pixel size of the rendered device: a 360×844dp phone at 2x.
const Size _kPhone = Size(720, 1688);
const double _kDevicePixelRatio = 2.0;

/// Set by `scripts/render_design.py`; unset everywhere else.
///
/// A compile-time define, not an environment variable: the test runner hands
/// the isolate a curated environment, so an exported variable never arrives.
const String? _skip = bool.fromEnvironment('DSH_DESIGN_SHOTS')
    ? null
    : 'design shots: python3 scripts/render_design.py';

/// The Han face `scripts/render_design.py` resolved on the host, as an
/// absolute path; empty when the script ran without one.
const String _cjkFontPath = String.fromEnvironment('DSH_DESIGN_CJK_FONT');

/// The platform text scale a shot renders at (`DSH_DESIGN_TEXT_SCALE`), 1.0
/// when unset. A row that clips its text clips on a phone set to a large step,
/// and a picture of it is how that is reviewed: `flutter test -t design
/// --update-goldens app/test/design --dart-define=DSH_DESIGN_SHOTS=true
/// --dart-define=DSH_DESIGN_TEXT_SCALE=2.0`.
/// The raw define, read once.
const String _textScaleDefine = String.fromEnvironment('DSH_DESIGN_TEXT_SCALE');

/// The platform text scale a shot renders at, 1.0 when the define is empty.
final double _textScale = _textScaleDefine.isEmpty
    ? 1.0
    : double.parse(_textScaleDefine);

/// What a shot does after the screen settles, when the state alone cannot
/// express it — opening the drawer, holding a bubble.
typedef ShotAction = Future<void> Function(WidgetTester tester);

final class DesignShot {
  const DesignShot({
    required this.name,
    this.state,
    this.host,
    this.act,
    this.dark = true,
    this.locale,
    this.scale,
    this.loadAttachment,
    this.readFile,
    this.readFileBytes,
  });

  final String name;

  /// The platform text step this shot renders at; the harness define when
  /// unset. A step of its own lets a large-text twin sit beside its default
  /// twin as a separate picture.
  final double? scale;

  /// Chat fixture; renders [ChatScreen] when set.
  final ChatUiState? state;

  /// Full-tree builder for a non-chat surface (the settings tab): it
  /// receives the harness theme (the light/dark twin) and builds its
  /// own root ProviderScope + MaterialApp + screen — the same shape
  /// the surface's widget tests pump, a root scope rather than a
  /// nested one. Called inside the test, so temp files and teardowns
  /// are safe to create here.
  final Widget Function(ThemeData theme, Locale? locale)? host;

  final ShotAction? act;

  /// Whether the dark twin renders too. A state whose defect is layout
  /// rather than tone renders once and stays cheap to review.
  final bool dark;

  /// Locale the shot renders chrome in; null leaves the platform default
  /// (English). A localized chrome string (e.g. the question card's
  /// recommended badge, "Recommended" vs "推荐") earns a zh twin.
  final Locale? locale;

  /// Durable-attachment answer for a state that carries result images; null
  /// leaves the surface's bare-pump answer (a placeholder frame).
  final AttachmentLoader? loadAttachment;

  /// Workspace-file answer for a state whose shot opens the preview sheet;
  /// null leaves the surface's bare-pump answer, which refuses the read.
  final WorkspaceFileReader? readFile;

  /// Byte answer for the same sheet: an image path reads bytes directly, and
  /// a text path falls back to them after a `not-text` refusal. Null leaves
  /// the bare-pump refusal.
  final WorkspaceFileBytesReader? readFileBytes;
}

/// The bare harness' answer for a durable attachment: nothing was fetched,
/// so an image card renders its placeholder frame.
Future<Uint8List?> _noAttachment(String sessionId, AttachmentRef ref) =>
    Future<Uint8List?>.value();

/// The bare harness' answer for a workspace-file read: the seam is unwired, so
/// the preview sheet renders its failure state rather than a fetched file.
Future<WorkspaceFileContent> _noWorkspaceFileRead(
  String sessionId,
  String path,
) async {
  throw UnsupportedError('workspaceFiles/read is not wired');
}

/// The bare harness' answer for a workspace byte read, refused for the same
/// reason: the seam has no repository behind it.
Future<WorkspaceFileBytes> _noWorkspaceFileBytes(
  String sessionId,
  String path,
) async {
  throw UnsupportedError('workspaceFiles/readBytes is not wired');
}

/// The text the extensionless-licence preview shot shows: a plain file that
/// takes the sheet's text window rather than an image or a refusal.
const String kDesignLicenceText = '''
ISC License

Copyright (c) 2026 the deepseek-harness-app authors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS.
''';

final List<DesignShot> shots = <DesignShot>[
  DesignShot(name: 'timeline-folding', state: timelineFoldingStateEn()),
  DesignShot(
    name: 'timeline-folding-expanded',
    state: timelineFoldingStateEn(),
    act: (tester) async {
      await tester.tap(find.byType(ActivityGroupRow).last);
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'timeline-folding-zh',
    state: timelineFoldingStateZh(),
    locale: const Locale('zh'),
  ),
  DesignShot(
    name: 'timeline-folding-expanded-zh',
    state: timelineFoldingStateZh(),
    locale: const Locale('zh'),
    act: (tester) async {
      await tester.tap(find.byType(ActivityGroupRow).last);
      await settle(tester);
    },
  ),
  // The Turn control over the phase card: a settled Turn reads as one line plus
  // the answer it produced, and its work — the phase, the reasoning, the tool
  // rows — is what the line reveals. The pair is the whole two-level fold: the
  // reply must survive the collapse, and the phase card must not survive it.
  DesignShot(name: 'turn-process-folded', state: turnProcessFoldedState()),
  DesignShot(
    name: 'turn-process-open',
    state: turnProcessFoldedState(),
    act: (tester) async {
      // The second Turn is the one with work; the first folds to a bare line.
      // The section's own control row is its first InkWell — the answer row it
      // wraps carries taps of its own (copy, fork), so the row's centre is not
      // the control.
      final section = find.byType(TurnProcessRow).last;
      await tester.tap(
        find.descendant(of: section, matching: find.byType(InkWell)).first,
      );
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'turn-process-folded-zh',
    state: turnProcessFoldedState(zh: true),
    locale: const Locale('zh'),
  ),
  // A Turn in flight: the control counts seconds and never folds, and the phase
  // header carries the live label plus the running call's first readable
  // argument — the one line the reference adds over a bare tool name.
  DesignShot(name: 'turn-process-live', state: turnProcessLiveState()),
  // The same running line in Chinese: the localized label carries its own
  // spacing around the duration and the same trailing marks — a static fact a
  // shot can show, unlike reduced motion or an hours-scale duration, which the
  // widget tests own.
  DesignShot(
    name: 'turn-process-live-zh',
    state: turnProcessLiveState(),
    locale: const Locale('zh'),
  ),
  DesignShot(name: 'transcript', state: busyState()),
  // The transcript's one-line marker rows in one column: the context
  // injection, the compaction marker, the slash command and a tool row.
  DesignShot(name: 'marker-rows', state: markerRowsState()),
  // The same column with the phase opened, so the inline injection row sits
  // beside the thought and the tool call it shares its chrome with.
  DesignShot(
    name: 'marker-rows-expanded',
    state: markerRowsState(),
    act: (tester) async {
      await tester.tap(find.byType(ActivityGroupRow));
      await settle(tester);
    },
  ),
  // A turn that wrote and delivered files: both turn-tail rows, with the
  // delivered-file cards collapsing behind their toggle.
  DesignShot(name: 'presented-files', state: presentedFilesState()),
  // The same turn with its activity group open, so the `present` call's own
  // row — the delivery title and the declared paths — is readable.
  DesignShot(
    name: 'presented-files-call',
    state: presentedFilesState(),
    act: (tester) async {
      await tester.tap(find.byType(ActivityGroupRow));
      await settle(tester);
    },
  ),
  // The preview sheet on a delivered file, one shot per answer the sheet can
  // give: it used to collapse every failure into a single "load failed" line
  // with a Retry that could never succeed. The first delivered card is a
  // rendered PNG, so its open takes the image path — the byte read — while a
  // PDF card takes the no-renderer path without spending a call at all.
  DesignShot(
    name: 'preview-too-large',
    state: presentedFilesState(),
    readFile: (sessionId, path) async => throw DshBusinessException(
      code: 'workspace-file/too-large',
      message: 'lines 1-5000 of "$path" exceed the 2097152 byte cap',
    ),
    readFileBytes: (sessionId, path) async => throw DshBusinessException(
      code: 'workspace-file/too-large',
      message: 'lines 1-5000 of "$path" exceed the 2097152 byte cap',
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').first);
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'preview-not-found',
    state: presentedFilesState(),
    readFile: (sessionId, path) async => throw DshBusinessException(
      code: 'workspace-file/not-found',
      message: path,
    ),
    readFileBytes: (sessionId, path) async => throw DshBusinessException(
      code: 'workspace-file/not-found',
      message: path,
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').first);
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'preview-failed',
    state: presentedFilesState(),
    readFile: (sessionId, path) async => throw DshBusinessException(
      code: 'gateway/unavailable',
      message: 'gateway down',
    ),
    readFileBytes: (sessionId, path) async => throw DshBusinessException(
      code: 'gateway/unavailable',
      message: 'gateway down',
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').first);
      await settle(tester);
    },
  ),
  // A declared PDF: no renderer exists, so the sheet names the path and offers
  // the copy action instead of spending a read that cannot change the answer.
  DesignShot(
    name: 'preview-unsupported',
    state: presentedFilesState(),
    act: (tester) async {
      await tester.tap(find.text('Open').at(2));
      await settle(tester);
    },
  ),
  // The two answers a readable file gets: a licence file with no extension is
  // read as text and takes the fenced window, and the rendered PNG is read as
  // bytes and drawn — the sheet spends the byte call only on the image path.
  DesignShot(
    name: 'preview-text',
    state: presentedFilesState(),
    readFile: (sessionId, path) async => WorkspaceFileContent(
      absolutePath: '/srv/art-pipeline/$path',
      version: 'v1',
      text: kDesignLicenceText,
      offset: 1,
      lines: kDesignLicenceText.split('\n').length,
      eof: true,
      bytes: kDesignLicenceText.length,
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').at(3));
      await settle(tester);
    },
  ),
  // The paged window's notice, and the pin's in-preview panel chrome with it:
  // `bg-layer-2`, the `--dsw-radius-lg` corner and
  // `--dsw-elevation-prominent` (`ui-sidebar-documentpreview/.../office/
  // FontNotice.module.css` `.panel`, :14-31) — a regression to the flat
  // `surfaceContainerHigh` chip is visible here and nowhere else, because the
  // text baseline's window ends (`eof: true`).
  DesignShot(
    name: 'preview-truncated',
    state: presentedFilesState(),
    readFile: (sessionId, path) async => WorkspaceFileContent(
      absolutePath: '/srv/art-pipeline/$path',
      version: 'v1',
      text: kDesignLicenceText,
      offset: 1,
      lines: 40,
      eof: false,
      bytes: kDesignLicenceText.length,
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').at(3));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'preview-image',
    state: presentedFilesState(),
    readFileBytes: (sessionId, path) async => WorkspaceFileBytes(
      absolutePath: '/srv/art-pipeline/$path',
      version: 'v1',
      offset: 0,
      data: base64Decode(kDesignImagePngBase64),
      eof: true,
      bytes: base64Decode(kDesignImagePngBase64).length,
    ),
    act: (tester) async {
      await tester.tap(find.text('Open').first);
      await settle(tester);
      // A memory image decode needs the real event loop; without this the
      // frame is still pending when the golden is captured.
      await tester.runAsync(() async {
        await precacheImage(
          MemoryImage(base64Decode(kDesignImagePngBase64)),
          tester.element(find.byType(MaterialApp)),
        );
      });
      await settle(tester);
    },
  ),
  // The dock with every seat the host mounts and a draft waiting on a
  // running turn: the state where a phone-width action row runs out of room.
  DesignShot(
    name: 'composer-crowded',
    state: composerCrowdedState(),
    act: (tester) async {
      await tester.enterText(
        find.byType(TextField).first,
        'Hold this until the turn settles, then queue it.',
      );
      await settle(tester);
    },
  ),
  DesignShot(name: 'prose', state: proseState()),
  // A tool result that carried a durable image: the row folds its picture
  // card open, the way the reference `read_image` toolview does.
  DesignShot(
    name: 'tool-image',
    state: toolImageState(),
    loadAttachment: (sessionId, ref) async =>
        base64Decode(kDesignImagePngBase64),
    act: (tester) async {
      await tester.tap(find.text('Read'));
      await settle(tester);
      // A memory image decode needs the real event loop; without this the
      // frame is still pending when the golden is captured.
      await tester.runAsync(() async {
        await precacheImage(
          MemoryImage(base64Decode(kDesignImagePngBase64)),
          tester.element(find.byType(MaterialApp)),
        );
      });
      await settle(tester);
    },
  ),
  DesignShot(name: 'prose-lists', state: proseListsState(), dark: false),
  // Inline code in both scripts and across a wrap: the chip, its Han fallback
  // and the body step's line height, in the transcript the reader sees.
  DesignShot(name: 'prose-code', state: proseCodeState()),
  // One mixed Latin+Han paragraph at each shipped weight — 400 body, 500
  // title, 600 strong, 700 heading — in the app's own styles: the pair the
  // weight measurements are read against, and where a step that does not sit
  // with the other script shows.
  const DesignShot(name: 'font-weights', host: _fontWeightHost),
  DesignShot(name: 'empty', state: emptyState(), dark: false),
  DesignShot(
    name: 'workspace-sheet',
    state: emptyStateWithWorkspaces(),
    act: (tester) async {
      await tester.tap(find.text('Choose workspace'));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'drawer',
    state: busyState(),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
    },
  ),
  // The same drawer at the platform's 2.0x text step. The brand row is the
  // row that used to stripe from 1.3x and the group header is the one that
  // striped from 2.0x; the pair of pictures is how the yield reads.
  DesignShot(
    name: 'sidebar-scale-20',
    state: busyState(),
    scale: 2.0,
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
    },
  ),
  // The pin block: pinned rows lead their group in the user's own order and
  // wear the glyph; the unpinned rows keep the activity priority.
  DesignShot(
    name: 'sidebar-pinned',
    state: pinnedSidebarState(),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'sidebar-scroll-bleed',
    host: (theme, locale) => _sidebarMultiBackendHost(theme, locale),
    act: (tester) async {
      await _loadRegistry(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
      final listFinder = find.descendant(
        of: find.byType(SessionPanel),
        matching: find.byType(ListView),
      );
      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      scrollableState.position.jumpTo(28.0);
      await settle(tester);
    },
  ),
  // The collapsed rail: a ≥720dp-only form the phone viewport can never
  // show. The act moves this one shot's viewport to a tablet width (the
  // catalog device stays the phone; _kPhone belongs to every other shot)
  // and folds the sidebar, so the rail's seats render as readers see them.
  DesignShot(
    name: 'sidebar-rail',
    state: busyState(),
    act: (tester) async {
      tester.view.physicalSize = const Size(1440, 1688);
      await settle(tester);
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await settle(tester);
    },
  ),
  // The archive prompt family: the Host's running-work refusal as the
  // confirmation that names the work, and the browsing sidebar under the
  // archived filter with one archived row.
  DesignShot(
    name: 'archive-stop-confirm',
    host: _archiveConfirmHost,
    act: (tester) async {
      await tester.tap(find.text('open'));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'archived-sidebar-filter',
    host: _archivedSidebarHost,
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.filter_list));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'message-menu',
    state: busyState(),
    dark: false,
    act: (tester) async {
      await tester.longPress(find.text(kBubbleUnderTest));
      await settle(tester);
    },
  ),
  // The ask card under the card → detail pattern: the dock keeps one line (the
  // question, its detail's first line, the Answer chip) and the whole question
  // — detail and options — opens on a large sheet whose Submit/Skip are pinned
  // at the bottom. The pair is the whole pattern: what the transcript shows,
  // and the one surface deeper it opens.
  DesignShot(name: 'question', state: questionState()),
  DesignShot(
    name: 'question-open',
    state: questionState(),
    act: (tester) async {
      await tester.tap(find.text('Answer'));
      await settle(tester);
    },
  ),
  // The plan card: same shape, content-shaped detail — the one-line row in the
  // dock, then the pushed document with the review's actions pinned in the
  // bottom bar. Opening the document answers nothing.
  DesignShot(name: 'plan-review', state: planReviewState()),
  DesignShot(
    name: 'plan-review-open',
    state: planReviewState(),
    act: (tester) async {
      await tester.tap(find.text('Plan ready for review'));
      await settle(tester);
    },
  ),
  // A short phone panel (a 616dp-class device, or one whose keyboard is open):
  // the row and its primary action must stay above the panel's bottom edge —
  // where the root tab bar sits and takes no taps — instead of sliding under.
  DesignShot(
    name: 'plan-review-short-panel',
    state: planReviewState(),
    act: (tester) async {
      tester.view.physicalSize = const Size(720, 960);
      await settle(tester);
    },
  ),
  // The zh twin renders the same card with the localized chrome — the
  // recommended badge must read 推荐, not Recommended.
  DesignShot(
    name: 'question-zh',
    state: questionState(),
    locale: const Locale('zh'),
  ),
  DesignShot(
    name: 'plan-review-zh',
    state: planReviewState(),
    locale: const Locale('zh'),
  ),
  // The approval card's pair: the wait as one line with Allow once, then the
  // request's own sheet carrying the command and both answers.
  DesignShot(name: 'approval', state: approvalState()),
  DesignShot(
    name: 'approval-open',
    state: approvalState(),
    act: (tester) async {
      await tester.tap(find.text('Waiting for approval'));
      await settle(tester);
    },
  ),
  // The diff / tool-output card's own surface: the row's peek is bounded at
  // 280px, and the whole payload opens here — every diff line and both IO
  // sections — with the edited file's preview and the copy seat pinned at the
  // bottom. The row half of this pair is the tool-row shot above.
  const DesignShot(name: 'tool-detail', host: _toolDetailHost),
  // Settings shots: the index over a two-host registry fixture, then each
  // surface a row opens. The index and the host sheet pair with the
  // same-named before shots; the pages and the choice sheets are new
  // surfaces this pass introduced.
  const DesignShot(
    name: 'settings-general',
    host: _settingsHost,
    act: _loadRegistry,
  ),
  // The two general items this pass adds. The gesture reference is the phone's
  // answer to the pin's shortcut surface — read-only, because a phone has no
  // keyboard to bind — and the session-log switch is the Host entry's accepted
  // value, which is why it needs a settings plane that serves the namespace.
  const DesignShot(name: 'settings-gestures', host: _gesturesHost),
  const DesignShot(
    name: 'settings-session-log',
    host: _sessionLogHost,
    act: _loadRegistry,
  ),
  // The zh twin: the index reads 主机 / 应用设置 and the language row states
  // 跟随系统.
  const DesignShot(
    name: 'settings-general-zh',
    host: _settingsHost,
    locale: Locale('zh'),
    act: _loadRegistry,
    dark: false,
  ),
  const DesignShot(
    name: 'settings-hosts',
    host: _settingsHost,
    act: _openHostsPage,
    dark: false,
  ),
  // The one surface that selects the default agent preset: the root row
  // states it, this page offers it once.
  const DesignShot(
    name: 'settings-agent-presets',
    host: _settingsHost,
    act: _openAgentPresetsPage,
  ),
  // The deployment default a new session starts from: the catalog's
  // defaultOptions, with the namespace's own value as the selection. The
  // current session's picker stays the composer's access chip.
  const DesignShot(
    name: 'settings-permission-defaults',
    host: _settingsPermissionHost,
    act: _openPermissionDefaultsPage,
    dark: false,
  ),
  // One preset's declared composition: the YAML the host renders, viewed
  // from the roster card's read-only affordance.
  const DesignShot(
    name: 'settings-agent-preset-declaration',
    host: _settingsAgentPresetHost,
    act: _openAgentPresetDeclaration,
    dark: false,
  ),
  const DesignShot(
    name: 'settings-credentials',
    host: _settingsHost,
    act: _openCredentialsPage,
    dark: false,
  ),
  const DesignShot(
    name: 'settings-plugins',
    host: _settingsHost,
    act: _openPluginsPage,
    dark: false,
  ),
  // The two plugin config pages the pin serves from its Plugins page: the
  // shell executor's two numeric limits, and the web-search provider's key,
  // endpoint and search budget.
  const DesignShot(
    name: 'settings-shell',
    host: _settingsShellHost,
    dark: false,
  ),
  const DesignShot(name: 'settings-web-search', host: _settingsWebSearchHost),
  // A single-choice picker is a sheet, not a page: three options cost the
  // index one row instead of three capsules.
  const DesignShot(
    name: 'settings-language',
    host: _settingsHost,
    act: _openLanguageSheet,
    dark: false,
  ),
  const DesignShot(
    name: 'settings-appearance',
    host: _settingsAppearanceHost,
    act: _openAppearanceSheet,
  ),
  // The transcript view selector: the Chat section's first row, and the sheet
  // its four modes live in. The row states the persisted `ui-chat` value, and
  // the sheet is the only control that governs the transcript's fold.
  const DesignShot(
    name: 'settings-transcript-view',
    host: _settingsTranscriptViewHost,
    act: _openTranscriptViewSheet,
  ),
  DesignShot(
    name: 'voice-recording',
    state: busyState(),
    host: (theme, locale) => _voiceRecordingHost(theme, locale, false),
    act: _settleVoiceShot,
  ),
  DesignShot(
    name: 'voice-recording-zh',
    state: busyState(),
    locale: const Locale('zh'),
    host: (theme, locale) => _voiceRecordingHost(theme, locale, true),
    act: _settleVoiceShot,
    dark: false,
  ),
  DesignShot(
    name: 'voice-cancel-armed',
    state: busyState(),
    host: (theme, locale) => _voiceRecordingHost(theme, locale, false),
    act: _settleVoiceArmedShot,
  ),
  DesignShot(
    name: 'voice-transcribing',
    state: busyState(),
    host: (theme, locale) => _voiceRecordingHost(
      theme,
      locale,
      false,
      endPhase: VoiceInputPhase.finalizing,
    ),
    act: _settleVoiceShot,
    dark: false,
  ),
  DesignShot(
    name: 'voice-nomodel-dialog',
    host: (theme, locale) => _voiceNoModelDialogHost(theme, locale, false),
  ),
  DesignShot(
    name: 'voice-nomodel-dialog-zh',
    locale: const Locale('zh'),
    host: (theme, locale) => _voiceNoModelDialogHost(theme, locale, true),
    dark: false,
  ),
  DesignShot(
    name: 'settings-asr-models',
    host: (theme, locale) => _settingsAsrHost(theme, locale, false),
  ),
  DesignShot(
    name: 'settings-asr-models-zh',
    locale: const Locale('zh'),
    host: (theme, locale) => _settingsAsrHost(theme, locale, true),
    dark: false,
  ),
  DesignShot(
    name: 'settings-error-logs',
    host: (theme, locale) => _settingsErrorLogsHost(theme, locale, false),
  ),
  DesignShot(
    name: 'settings-error-logs-zh',
    locale: const Locale('zh'),
    host: (theme, locale) => _settingsErrorLogsHost(theme, locale, true),
  ),
  // The online voice-input mode: the new card with the Volcengine
  // credential form (dark) and the Tencent one (light), each scrolled to
  // bring the card's fields into frame.
  DesignShot(
    name: 'settings-asr-online',
    host: (theme, locale) => _settingsAsrOnlineHost(
      theme,
      locale,
      const OnlineAsrSettings(
        mode: VoiceInputMode.online,
        provider: OnlineAsrProvider.volcengineDoubao,
        volcengine: VolcengineDoubaoAsrConfig(apiKey: 'vk-demo-4f8a-9c2e-77b1'),
      ),
    ),
    act: _scrollToVoiceInputModeCard,
  ),
  DesignShot(
    name: 'settings-asr-online-tencent',
    host: (theme, locale) => _settingsAsrOnlineHost(
      theme,
      locale,
      const OnlineAsrSettings(
        mode: VoiceInputMode.online,
        provider: OnlineAsrProvider.tencentHunyuan,
        tencent: TencentHunyuanAsrConfig(
          appId: '1900000000',
          secretId: 'AKIDzrJyc0mZdB6demoExample',
          secretKey: 'c2VjcmV0S2V5RGVtbw==',
        ),
      ),
    ),
    act: _scrollToVoiceInputModeCard,
    dark: false,
  ),
  // The Subagents screen: the catalog tree (running child, settled
  // one-shot, diagnostic row) with a branch expanded, the host-error
  // banner over the crowded tree, and the one-shot read-only record.
  DesignShot(
    name: 'subagents',
    host: (theme, locale) => _subagentsHost(theme, locale, subagentsState()),
    act: (tester) async {
      // The web toggleBranch seat: expanding a node renders the branch
      // loading row in the same frame.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'subagents-error',
    host: (theme, locale) =>
        _subagentsHost(theme, locale, subagentsErrorState()),
  ),
  DesignShot(
    name: 'subagents-child',
    host: (theme, locale) =>
        _subagentsHost(theme, locale, subagentsChildState()),
  ),
  // The house menu material over the transcript. The pin draws a menu as a
  // translucent fill on a `blur(40px) saturate(150%)` backdrop
  // (`MenuSurface.module.css:25-31`), and the fill's 58% / 45% alpha is what
  // makes the blur load-bearing: the transcript behind the panel has to read
  // through it. The shot exists for that read-through — without the backdrop
  // the fill is a flat see-through panel.
  // The stats sheet is the tall one — it reaches up over the transcript's own
  // lines, which is the only way a blur can be judged: the shot has to show
  // text reading through the panel, not a card floating over empty page.
  DesignShot(
    name: 'menu-material',
    state: busyState(),
    act: (tester) async {
      // The composer's stats line opens the house sheet (`stats_line.dart`);
      // the model seat (`model_select.dart`) opens the same material at its
      // content height.
      await tester.tap(find.byType(StatsLine));
      await settle(tester);
    },
  ),
];

/// A running session animates forever, so `pumpAndSettle` never returns.
/// Every wait in this harness is a bounded pump instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// The `$events` registration answer the gateway sends over
/// `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake, so
/// the shots' connection handshakes reach CONNECTED (green dots).
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/user'},
  },
);

class _SilentSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    // A broadcast controller drops events with no listener; the handshake
    // frame therefore lands after this call's listener attaches.
    scheduleMicrotask(() => _frames.add(_readyFrame()));
    return _frames.stream;
  }
}

/// Whether a Han face was found this run. Without one the Chinese half of
/// the UI renders as empty rectangles, which reads as a layout bug that
/// isn't there — so the harness says so rather than letting the reviewer
/// discover it in the PNG.
bool _cjkLoaded = false;

/// The families [_load] registered, so a test can assert the harness paints
/// with the app's own names rather than one no device resolves.
final Set<String> _registeredFamilies = <String>{};

/// Test fonts default to a blank box face: without these loads every glyph
/// renders as a rectangle and every icon as an empty square.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is unset — run through scripts/render_design.py');
  }
  final assets = '$root/bin/cache/artifacts/material_fonts';
  await _load(kUiFontFamily, <String>[
    '$assets/Roboto-Regular.ttf',
    '$assets/Roboto-Medium.ttf',
    '$assets/Roboto-Bold.ttf',
  ]);
  await _load('MaterialIcons', <String>['$assets/MaterialIcons-Regular.otf']);
  // The app's code face is the reference's stack (`kCodeFontFamily` and its
  // fallbacks); no face in it ships with the app, so the harness registers the
  // first installed mono face under each name in the stack — the same "first
  // hit wins" rule the app asks the platform for, resolved here rather than
  // left to whichever family the engine settles on.
  const List<String> monoPaths = <String>[
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
  ];
  for (final String family in <String>[
    kCodeFontFamily,
    ...kCodeFontFamilyFallback,
  ]) {
    await _load(family, monoPaths, first: true);
  }
  final home = Platform.environment['HOME'] ?? '';
  // The Han half of the app's own family chain (`kUiFontFamilyFallback`): the
  // harness registers the host's Han face under every family the app declares,
  // in the app's order and by the same "first hit wins" rule the code face
  // uses, so a shot resolves what the phone asks for. It used to register a
  // family named `NotoSansCJK`, which no device knows and no theme names — the
  // shots rendered a face the app never requested, and which one it was
  // depended on the host.
  final List<String> hanPaths = <String>[
    // The path the script resolved on the host travels as a define: the
    // renderer runs in a container that mounts the tree, not the home dir.
    if (_cjkFontPath.isNotEmpty) _cjkFontPath,
    '$home/.cache/dsh-design/fonts/NotoSansSC.ttf',
    '$home/.local/share/fonts/NotoSansSC.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
  ];
  _cjkLoaded = false;
  for (final String family in kUiFontFamilyFallback) {
    // `sans-serif` is Android's generic alias, not a face a device ships; the
    // app's chain ends on it the way the pin's stack does.
    if (family == 'sans-serif') continue;
    _cjkLoaded = await _load(family, hanPaths, first: true) || _cjkLoaded;
  }
  if (!_cjkLoaded) {
    stderr.writeln(
      'design shots: no CJK font — Chinese renders as boxes. '
      'Fix: python3 scripts/render_design.py --fetch-fonts',
    );
  }
}

/// Loads every path that exists, or only the first when [first] is set
/// (a family that wants one face, not a weight set). Returns whether any
/// face was found.
Future<bool> _load(
  String family,
  List<String> paths, {
  bool first = false,
}) async {
  final found = paths.where((path) => File(path).existsSync());
  if (found.isEmpty) return false;
  final loader = FontLoader(family);
  for (final path in first ? found.take(1) : found) {
    loader.addFont(
      File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  await loader.load();
  _registeredFamilies.add(family);
  return true;
}

/// The settings shots' tree: a root ProviderScope over the settings
/// screen, with a temp-backed registry seeded from the two-host
/// document (scope bar + Hosts rows), a temp-backed shared store
/// (preference rows), and quiet transport seams for every host URL
/// the document names.
Widget _settingsHost(ThemeData theme, Locale? locale) =>
    _settingsTree(theme, locale);

/// The gesture reference on its own: the page the Settings entry opens.
Widget _gesturesHost(ThemeData theme, Locale? locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  theme: theme,
  home: const SettingsGesturesPage(),
);

/// The settings index over a plane that serves the `session-log-deepseek`
/// entry, so the row the Host publishes is the one on screen. A plane that
/// does not serve it renders no row at all, which is the row's own test.
Widget _sessionLogHost(ThemeData theme, Locale? locale) =>
    _settingsTree(theme, locale, repository: _SessionLogShotRepository());

/// The settings plane for that shot: one namespace, its `enabled` field, and
/// nothing else reachable from the settings surface.
class _SessionLogShotRepository extends ChatRepository {
  @override
  Future<SettingsSnapshot> describeSettings() async => const SettingsSnapshot(
    writable: true,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      SettingsNamespace(
        ns: kSessionLogSettingsNs,
        applies: SettingsApplies.live,
        revision: 3,
        hasUserLayer: false,
        secretCount: 0,
        schema: SettingsSchema.empty,
        value: <String, Object?>{kSessionLogEnabledField: true},
      ),
    ],
    credentialRefs: <String>[],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The tool payload's surface, on a real edit: the diff the row peeks at, the
/// call's arguments, and its settled result.
/// The mixed sentence at each shipped weight, in the app's own styles.
Widget _fontWeightHost(ThemeData theme, Locale? locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  theme: theme,
  home: Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          for (final (String label, FontWeight weight)
              in const <(String, FontWeight)>[
                ('body 400', FontWeight.w400),
                ('title 500', FontWeight.w500),
                ('strong 600', FontWeight.w600),
                ('heading 700', FontWeight.w700),
              ])
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.labelSmall),
                  Text.rich(
                    const TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: 'The dock is capped — '),
                        TextSpan(text: '输入区封顶，待办折起来。'),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontWeight: weight,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ),
);

Widget _toolDetailHost(ThemeData theme, Locale? locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  theme: theme,
  home: ToolDetailSurface(
    args: const ToolDetailArgs(
      title: 'Edit chat_screen.dart',
      path: 'flutter/app/lib/ui/chat/chat_screen.dart',
      input:
          '{"path":"flutter/app/lib/ui/chat/chat_screen.dart",'
          '"old_string":"maxLines: 2","new_string":"maxLines: 4"}',
      output: 'Updated 1 file: chat_screen.dart (+2 -2)',
      diff: EditDiffModel(
        filePath: 'flutter/app/lib/ui/chat/chat_screen.dart',
        oldString: 'maxLines: 2',
        newString: 'maxLines: 4',
        lines: <ToolDiffLine>[
          ToolDiffLine(kind: DiffLineKind.equal, text: '        child: Text('),
          ToolDiffLine(
            kind: DiffLineKind.equal,
            text: '          widget.draft,',
          ),
          ToolDiffLine(
            kind: DiffLineKind.delete,
            text: '          maxLines: 2,',
          ),
          ToolDiffLine(
            kind: DiffLineKind.insert,
            text: '          maxLines: 4,',
          ),
          ToolDiffLine(
            kind: DiffLineKind.equal,
            text: '          overflow: TextOverflow.ellipsis,',
          ),
        ],
      ),
    ),
    onPreviewFile: (path, {diff}) {},
  ),
);

/// The stop-and-archive confirmation over its dim backdrop: the work list the
/// Host named and the destructive commit are what this shot reviews. The
/// dialog opens from a real press so it rides a route the way the app root
/// mounts it.
Widget _archiveConfirmHost(ThemeData theme, Locale? locale) => MaterialApp(
  debugShowCheckedModeBanner: false,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  theme: theme,
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => SessionArchiveConfirmDialog(
              request: const SessionArchiveRequest(
                backendId: 'default',
                sessionId: 's-archived-run',
                displayTitle: 'Refactor the timeline fold',
                activity: <SessionActivityEntry>[
                  SessionActivityEntry(
                    kind: SessionActivityKind.turn,
                    rawKind: 'turn',
                  ),
                  SessionActivityEntry(
                    kind: SessionActivityKind.job,
                    rawKind: 'job',
                    items: <SessionActivityItem>[
                      SessionActivityItem(id: 'job-1', label: 'cargo test'),
                      SessionActivityItem(id: 'job-2', label: 'flutter build'),
                    ],
                  ),
                  SessionActivityEntry(
                    kind: SessionActivityKind.schedule,
                    rawKind: 'schedule',
                    items: <SessionActivityItem>[
                      SessionActivityItem(id: 'sch-1', label: 'nightly build'),
                    ],
                  ),
                ],
              ),
              onConfirm: () async {},
              onArchived: () {},
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

/// The browsing sidebar under "show archived", with one archived row: the
/// grayed row, its badge, its unarchive verb, and the filter menu are the
/// surface.
Widget _archivedSidebarHost(ThemeData theme, Locale? locale) {
  final dir = Directory.systemTemp.createTempSync('dsh-design-archive');
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = LocalStateStore(File('${dir.path}/local_state.json'));
  // The controller reads the stored choice on construction; seeding the cache
  // is what makes the shot render the "show archived" view.
  store.write(kArchivedFilterKey, ArchivedFilter.show.storedName);
  return ProviderScope(
    overrides: [localStateStoreProvider.overrideWith((ref) async => store)],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: SessionPanel(
            sessions: _archivedSessions,
            workspaces: _archivedWorkspaces,
            searchResults: const <SessionSearchResult>[],
            selectedSessionId: 's-live',
            onSelectSession: (_) {},
            onCreateSession: (_) {},
            onSearchSessions: (_) {},
            backendId: 'default',
            onRenameSession: (_, _) {},
            onForkSession: (_, _) {},
            onArchiveSession: (_, _) {},
            onUnarchiveSession: (_, _) {},
          ),
        ),
      ),
    ),
  );
}

/// The sidebar fixture: one live row and one archived row in one workspace.
const List<SessionSummary> _archivedSessions = <SessionSummary>[
  SessionSummary(
    id: 's-live',
    title: 'Timeline folding',
    blank: false,
    updatedAtEpochMs: 1700000000000,
  ),
  SessionSummary(
    id: 's-archived',
    title: 'Old parser sweep',
    blank: false,
    archived: true,
    updatedAtEpochMs: 1699000000000,
  ),
];

const List<WorkspaceSummary> _archivedWorkspaces = <WorkspaceSummary>[
  WorkspaceSummary(
    workspaceId: 'w1',
    path: '/tmp/deepseek-harness-android',
    title: 'deepseek-harness-android',
    sessionIds: <String>['s-live', 's-archived'],
  ),
];

/// The same tree with the scoped host answering `settings.describe` for the
/// `ui-theme` namespace. Without it the appearance row can only ever state
/// that the host did not answer, which is not the surface this shot
/// reviews.
Widget _settingsAppearanceHost(ThemeData theme, Locale? locale) =>
    _settingsTree(theme, locale, repository: _FakeThemeNamespaceRepository());

/// The same tree with the scoped host answering `settings.describe` for the
/// `ui-chat` namespace, so the transcript view row renders a persisted mode
/// rather than the unavailable state.
Widget _settingsTranscriptViewHost(ThemeData theme, Locale? locale) =>
    _settingsTree(theme, locale, repository: _FakeTranscriptViewRepository());

Widget _settingsAgentPresetHost(ThemeData theme, Locale? locale) =>
    _settingsTree(
      theme,
      locale,
      repository: _FakeAgentPresetDocumentRepository(),
    );

/// One scoped repository method: the declaration the preset page reads.
class _FakeAgentPresetDocumentRepository implements ChatRepository {
  @override
  Future<AgentPresetDocument> readAgentPreset(String agentPreset) async =>
      AgentPresetDocument(
        agentPreset: agentPreset,
        name: 'Standard',
        description: 'The default toolchain.',
        content:
            '- id: tool-bash\n'
            '  name: \'@deepseek-ai/dsh-tool-bash\'\n'
            '- id: tool-read\n'
            '  name: \'@deepseek-ai/dsh-tool-read\'\n'
            '- id: session-title\n'
            '  name: \'@deepseek-ai/dsh-session-title\'\n'
            '  config:\n'
            '    enabled: !!js ctx.get(\'profileContext\') !== undefined\n',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Widget _settingsPermissionHost(ThemeData theme, Locale? locale) =>
    _settingsTree(
      theme,
      locale,
      repository: _FakePermissionCatalogRepository(),
    );

/// One scoped repository method: the permission catalog the page offers. The
/// effective default it marks comes from the settings channel, which this
/// fixture's screen state carries.
class _FakePermissionCatalogRepository implements ChatRepository {
  @override
  Future<PermissionPresetCatalog> loadPermissionPresetCatalog() async =>
      const PermissionPresetCatalog(
        options: <PermissionPresetOption>[
          PermissionPresetOption(
            value: 'workspace-write',
            name: 'Workspace write',
            description:
                'Write inside the workspace and permitted temporary '
                'directories; wider retries require approval.',
          ),
          PermissionPresetOption(
            value: 'danger-full-access',
            name: 'danger-full-access',
            description: 'Full file access without approval prompts.',
          ),
        ],
        defaultOptions: <PermissionPresetOption>[
          PermissionPresetOption(
            value: 'workspace-write',
            name: 'Workspace write',
            description:
                'Write inside the workspace and permitted temporary '
                'directories; wider retries require approval.',
          ),
          PermissionPresetOption(
            value: 'danger-full-access',
            name: 'danger-full-access',
            description: 'Full file access without approval prompts.',
          ),
        ],
        defaultPreset: 'workspace-write',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

/// One scoped repository method: the `ui-theme` namespace the appearance row
/// reads. Nothing else in these fixtures calls the settings plane.
/// One scoped repository method pair: the `ui-chat` namespace the transcript
/// view row reads, and the write its sheet issues.
class _FakeTranscriptViewRepository implements ChatRepository {
  @override
  Future<SettingsSnapshot> describeSettings() async => const SettingsSnapshot(
    writable: true,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      SettingsNamespace(
        ns: kChatSettingsNamespace,
        applies: SettingsApplies.live,
        revision: 7,
        hasUserLayer: true,
        secretCount: 0,
        schema: SettingsSchema.empty,
        value: <String, Object?>{kTranscriptViewField: 'standard'},
      ),
    ],
    credentialRefs: <String>[],
  );

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async => (await describeSettings()).namespaces.first;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _FakeThemeNamespaceRepository implements ChatRepository {
  @override
  Future<SettingsSnapshot> describeSettings() async => const SettingsSnapshot(
    writable: true,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      SettingsNamespace(
        ns: kThemeSettingsNamespace,
        applies: SettingsApplies.live,
        revision: 4,
        hasUserLayer: true,
        secretCount: 0,
        schema: SettingsSchema.empty,
        value: <String, Object?>{kThemePreferenceField: 'dark'},
      ),
    ],
    credentialRefs: <String>[],
  );

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async => (await describeSettings()).namespaces.first;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

/// The shell page over a Host that serves the POSIX executor namespace.
Widget _settingsShellHost(ThemeData theme, Locale? locale) => _settingsTree(
  theme,
  locale,
  repository: _FakePluginConfigRepository(),
  page: const SettingsShellPage(backendId: 'default'),
);

/// The web-search page over a Host that serves the provider namespace and
/// already holds a key.
Widget _settingsWebSearchHost(ThemeData theme, Locale? locale) => _settingsTree(
  theme,
  locale,
  repository: _FakePluginConfigRepository(apiKeyConfigured: true),
  page: const SettingsWebSearchPage(backendId: 'default'),
);

/// The two plugin namespaces as the Host would describe them, with the
/// provider's credential reported as configured.
class _FakePluginConfigRepository implements ChatRepository {
  _FakePluginConfigRepository({this.apiKeyConfigured = false});

  final bool apiKeyConfigured;

  @override
  Future<SettingsSnapshot> describeSettings() async => const SettingsSnapshot(
    writable: true,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      SettingsNamespace(
        ns: 'bash-sandbox',
        applies: SettingsApplies.live,
        revision: 7,
        hasUserLayer: true,
        secretCount: 0,
        schema: SettingsSchema.empty,
        value: <String, Object?>{'timeoutMs': 30000, 'maxOutputBytes': 1048576},
        user: <String, Object?>{'timeoutMs': 30000},
      ),
      SettingsNamespace(
        ns: 'web-search-deepseek',
        applies: SettingsApplies.live,
        revision: 3,
        hasUserLayer: false,
        secretCount: 1,
        schema: SettingsSchema.empty,
        value: <String, Object?>{'maxUses': 5},
      ),
    ],
    credentialRefs: <String>['DEEPSEEK_API_KEY'],
  );

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async =>
      <CredentialStatus>[
        CredentialStatus(
          ref: refs.first,
          configured: apiKeyConfigured,
          writable: true,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

Widget _settingsTree(
  ThemeData theme,
  Locale? locale, {
  ChatRepository? repository,
  Widget? page,
}) {
  final registryDir = Directory.systemTemp.createTempSync(
    'dsh-design-registry',
  );
  addTearDown(() => registryDir.deleteSync(recursive: true));
  final registryFile = File('${registryDir.path}/backends.json');
  registryFile.writeAsStringSync(kSettingsRegistryDoc);
  final stateDir = Directory.systemTemp.createTempSync('dsh-design-state');
  addTearDown(() => stateDir.deleteSync(recursive: true));
  return ProviderScope(
    overrides: [
      backendStoreProvider.overrideWith(
        (ref) async => BackendStore(registryFile, seedBaseUrl: kDshBaseUrl),
      ),
      localStateStoreProvider.overrideWith(
        (ref) async =>
            LocalStateStore(File('${stateDir.path}/local_state.json')),
      ),
      if (repository != null)
        chatRepositoryProvider('default').overrideWithValue(repository),
      for (final uri in [
        Uri.parse('http://10.0.2.2:3080'),
        Uri.parse('http://10.0.2.2:3081'),
      ]) ...[
        dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(uri).overrideWithValue(_SilentSocket()),
      ],
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme,
      home:
          page ?? SettingsScreen(uiState: settingsUiState(), onAction: (_) {}),
    ),
  );
}

/// A spoken phrase as the capture stream reports it: one group of per-window
/// peaks per 100ms chunk. The input meter draws every band, so a still of a
/// live session reviews a sliding trail rather than one flat bar.
const List<List<double>> _kVoicePhraseBands = <List<double>>[
  [0.16, 0.62, 0.94, 0.71],
  [0.35, 0.78, 0.52, 0.24],
  [0.90, 0.66, 0.31, 0.12],
  [0.22, 0.45, 0.83, 0.58],
  [0.51, 0.29, 0.14, 0.37],
  [0.86, 0.94, 0.63, 0.40],
  [0.27, 0.15, 0.44, 0.69],
  [0.58, 0.72, 0.36, 0.19],
  [0.93, 0.47, 0.22, 0.55],
  [0.31, 0.64, 0.80, 0.42],
];

/// Voice controller that hands the composer one capture chunk per 100ms of
/// pumped time, so a shot renders a session with history instead of a mounted
/// frame.
///
/// The phrase opens on an idle frame: the dock reaches voice mode through its
/// mode seat, and that seat declines a press while a capture owns the session.
class _ScriptedVoiceInputController extends VoiceInputController {
  _ScriptedVoiceInputController({
    required super.manager,
    required List<VoiceInputUiState> frames,
  }) : _frames = frames,
       _current = frames.first,
       super(
         audioRecorder: MockAudioInputSource(simulatedDuration: Duration.zero),
       );

  final List<VoiceInputUiState> _frames;
  final StreamController<VoiceInputUiState> _out =
      StreamController<VoiceInputUiState>.broadcast();

  VoiceInputUiState _current;
  int _played = 0;

  /// How many capture chunks the phrase holds.
  int get frameCount => _frames.length;

  @override
  VoiceInputUiState get state => _current;

  @override
  Stream<VoiceInputUiState> get uiState => _out.stream;

  /// Hands over the next capture frame. Once the phrase is spent the session
  /// keeps whatever it last showed, as a live but silent capture does.
  void playNextFrame() {
    if (_played >= _frames.length) return;
    _current = _frames[_played++];
    if (!_out.isClosed) _out.add(_current);
  }

  void stop() => unawaited(_out.close());

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async => '';

  @override
  Future<void> cancelRecording() async {}
}

/// The scripted voice session the voice shots render. A shot's `act` callback
/// receives only the tester, so the fixture registers itself here for the
/// pumping loop to speak through.
_ScriptedVoiceInputController? _voiceSession;

/// The finger the voice shots leave on the bar: the capture surface, its meter
/// and its hint only exist while a hold does, so a released shot would review
/// an idle composer.
TestGesture? _voiceHold;

/// Settles the chrome, switches the dock into voice mode the way the reader
/// does, then plays the phrase one capture chunk per pumped frame with a finger
/// down: the meter's trail is made of the chunks it actually saw, so the still
/// reviews a spoken sentence rather than a couple of coalesced frames.
Future<void> _settleVoiceShot(WidgetTester tester) async {
  await settle(tester);
  // The band becomes the hold bar only through the mode seat.
  await tester.tap(find.byIcon(Icons.mic_none));
  await tester.pump();
  final hold = await tester.startGesture(
    tester.getCenter(find.byType(VoiceHoldBar)),
  );
  _voiceHold = hold;
  await tester.pump();
  final session = _voiceSession;
  if (session != null) {
    for (var i = 0; i < session.frameCount; i++) {
      session.playNextFrame();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await tester.pump();
}

/// The same hold, slid up past the discard threshold: the bar and the bubble
/// both turn to the armed face, which is the state a reader has to recognise
/// before they lift their finger.
Future<void> _settleVoiceArmedShot(WidgetTester tester) async {
  await _settleVoiceShot(tester);
  final hold = _voiceHold;
  if (hold == null) return;
  await hold.moveBy(const Offset(0, -kVoiceCancelSlide - 12));
  await tester.pump();
}

/// Full-tree builder for a live voice session: a scripted capture stream so
/// the dock, its input meter and the microphone seat all render mid-session.
///
/// With [endPhase] the phrase stops short and its tail belongs to that phase,
/// carrying the same envelope — no new audio, which is what a session waiting
/// on the engine looks like: the trail runs out to the floor and the seat
/// changes its mind.
Widget _voiceRecordingHost(
  ThemeData theme,
  Locale? locale,
  bool zh, {
  VoiceInputPhase? endPhase,
}) {
  final tempDir = Directory.systemTemp.createTempSync('dsh-design-voice');
  addTearDown(() => tempDir.deleteSync(recursive: true));
  final registryFile = File('${tempDir.path}/models_registry.json');
  final registry = ModelsRegistry(registryFile: registryFile);
  unawaited(
    registry.updateEntry(
      ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '${tempDir.path}/sensevoice-small',
        status: AsrModelStatus.downloaded,
      ),
    ),
  );
  final manager = AsrModelManager(baseModelsDir: tempDir, registry: registry);

  final transcription = zh
      ? '端侧语音识别实时转写测试'
      : 'On-device speech recognition live transcription test';
  final spokenChunks = endPhase == null ? _kVoicePhraseBands.length : 7;
  final spoken = <VoiceInputUiState>[
    for (var i = 0; i < spokenChunks; i++)
      VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(milliseconds: 100 * (i + 1)),
        amplitude: _kVoicePhraseBands[i].reduce(max),
        envelope: _kVoicePhraseBands[i],
        liveTranscription: transcription,
        activeModel: AsrModelManifest.senseVoiceSmall,
        hasInstalledModels: true,
      ),
  ];
  final last = spoken.last;
  final frames = <VoiceInputUiState>[
    // The dock reaches voice mode through its mode seat, and that seat
    // declines a press while a capture owns the session: the phrase waits for
    // the shot's act on an idle frame.
    const VoiceInputUiState(hasInstalledModels: true),
    ...spoken,
    // The tail carries the same envelope object, so the meter learns no new
    // audio arrived and lets its trail run out.
    if (endPhase != null)
      for (var i = 0; i < 3; i++) last.copyWith(phase: endPhase),
  ];

  final controller = _ScriptedVoiceInputController(
    manager: manager,
    frames: frames,
  );
  _voiceSession = controller;
  addTearDown(controller.stop);

  return ProviderScope(
    overrides: [
      asrModelManagerProvider.overrideWith((ref) async => manager),
      voiceInputControllerProvider.overrideWith((ref) => controller),
      dshRpcClientProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_FakeRpc()),
      dshEventSocketProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_SilentSocket()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme,
      home: ChatScreen(uiState: busyState(), onAction: (_) {}),
    ),
  );
}

/// Full-tree builder for the "No Speech Model Installed" dialog shot.
Widget _voiceNoModelDialogHost(ThemeData theme, Locale? locale, bool zh) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: Scaffold(
      body: Center(
        child: AlertDialog(
          title: Text(zh ? '需要语音识别模型' : 'Speech Model Required'),
          content: Text(
            zh ? '请在设置中下载离线语音识别模型，即可开启端侧语音输入。' : 'Download an on-device speech recognition model in Settings to enable offline voice input.',
          ),
          actions: <Widget>[
            TextButton(onPressed: () {}, child: Text(zh ? '取消' : 'Cancel')),
            FilledButton(
              onPressed: () {},
              child: Text(zh ? '前往设置' : 'Go to Settings'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Full-tree builder for the ASR Models management screen shot showing downloaded
/// SenseVoice model, Active Speech Model selector, and catalog cards.
/// The ASR settings screen with the voice-input mode card switched to the
/// [settings] provider, so the credential form under review is on screen.
Widget _settingsAsrOnlineHost(
  ThemeData theme,
  Locale? locale,
  OnlineAsrSettings settings,
) {
  const cards = <AsrModelCardState>[
    AsrModelCardState(
      info: AsrModelManifest.senseVoiceSmall,
      entry: ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '/data/models/sensevoice-small',
        status: AsrModelStatus.downloaded,
      ),
      diskUsageBytes: 237431441,
    ),
  ];

  final state = AsrModelsUiState(
    models: cards,
    defaultSource: ModelSource.hfMirror,
    installedCount: 1,
    totalCount: 5,
    activeModelId: 'sensevoice-small',
    cloud: settings,
  );

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: AsrModelsScreen(uiState: state, onAction: (_) {}),
  );
}

/// Brings the voice-input mode card into frame: the card sits below the
/// download-source preferences, off the top of the viewport.
Future<void> _scrollToVoiceInputModeCard(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Voice input mode'),
    find.byType(ListView),
    const Offset(0, -240),
  );
  await settle(tester);
}

Widget _settingsAsrHost(ThemeData theme, Locale? locale, bool zh) {
  const cards = <AsrModelCardState>[
    AsrModelCardState(
      info: AsrModelManifest.senseVoiceSmall,
      entry: ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '/data/models/sensevoice-small',
        status: AsrModelStatus.downloaded,
        downloadedBytes: 237431441,
        totalBytes: 237431441,
      ),
      diskUsageBytes: 237431441,
    ),
    AsrModelCardState(
      info: AsrModelManifest.streamingZipformerZh,
      entry: ModelRegistryEntry(
        modelId: 'streaming-zipformer-zh',
        source: ModelSource.hfMirror,
        localDir: '/data/models/streaming-zipformer-zh',
        status: AsrModelStatus.idle,
      ),
    ),
    AsrModelCardState(
      info: AsrModelManifest.whisperLargeV3Turbo,
      entry: ModelRegistryEntry(
        modelId: 'whisper-large-v3-turbo',
        source: ModelSource.huggingFace,
        localDir: '/data/models/whisper-large-v3-turbo',
        status: AsrModelStatus.downloaded,
      ),
      diskUsageBytes: 1036613791,
    ),
  ];

  const state = AsrModelsUiState(
    models: cards,
    defaultSource: ModelSource.hfMirror,
    installedCount: 2,
    totalCount: 5,
    activeModelId: 'sensevoice-small',
  );

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: AsrModelsScreen(uiState: state, onAction: (_) {}),
  );
}

Widget _settingsErrorLogsHost(ThemeData theme, Locale? locale, bool zh) {
  final List<ErrorLogEntry> entries = <ErrorLogEntry>[
    ErrorLogEntry(
      id: 'err_1',
      timestamp: DateTime(2026, 8, 20, 14, 32, 5, 120),
      level: ErrorLogLevel.fatal,
      type: 'FlutterError:RenderFlex',
      message: zh
          ? 'RenderFlex 在右侧溢出了 24 个像素。'
          : 'A RenderFlex overflowed by 24 pixels on the right.',
      stackTrace:
          '#0 RenderFlex.performLayout (package:flutter/src/rendering/flex.dart:1000)\n'
          '#1 RenderObject.layout (package:flutter/src/rendering/object.dart:2000)\n'
          '#2 MultiChildLayoutView.performLayout (package:flutter/src/rendering/custom_layout.dart:120)',
      context: const <String, Object?>{
        'screen': 'ChatScreen',
        'backend': 'http://127.0.0.1:3080',
      },
      breadcrumbs: const <String>[
        '14:31:55.010 [INFO] App launch: ready',
        '14:32:00.540 [INFO] Switching active session: sess_001',
        '14:32:04.990 [WARN] Render tree layout pass requested',
      ],
    ),
    ErrorLogEntry(
      id: 'err_2',
      timestamp: DateTime(2026, 8, 20, 13, 15, 20, 450),
      level: ErrorLogLevel.error,
      type: 'SocketException',
      message: zh
          ? '系统错误：连接被拒绝 (errno = 111, address = 127.0.0.1, port = 3080)'
          : 'OS Error: Connection refused, errno = 111, address = 127.0.0.1, port = 3080',
      stackTrace:
          '#0 _NativeSocket.startConnect (dart:io-patch/socket_patch.dart:735)\n'
          '#1 _RawSocket.startConnect (dart:io-patch/socket_patch.dart:200)',
      context: const <String, Object?>{
        'endpoint': 'http://127.0.0.1:3080/v1/sessions',
      },
      breadcrumbs: const <String>[
        '13:15:19.100 [INFO] Connecting to backend: http://127.0.0.1:3080',
      ],
    ),
    ErrorLogEntry(
      id: 'err_3',
      timestamp: DateTime(2026, 8, 20, 12, 00, 10, 80),
      level: ErrorLogLevel.warning,
      type: 'ModelWarning',
      message: zh
          ? '离线语音识别模型加载耗时超过 1250ms。'
          : 'Active speech recognition model took 1250ms to warm up.',
    ),
  ];

  final ErrorLogsUiState state = ErrorLogsUiState(
    entries: entries,
    expandedIds: const <String>{'err_1'},
    activeBackendUrl: 'http://127.0.0.1:3080',
  );

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: ErrorLogsScreen(uiState: state, onAction: (_) {}),
  );
}

/// Full-tree builder for the Subagents screen shots. The surface takes a
/// `SubagentUiState` and an action sink like `ChatScreen` does, so the
/// shot pumps the screen directly — no route push, no controller fake.
Widget _subagentsHost(ThemeData theme, Locale? locale, SubagentUiState state) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: SubagentScreen(uiState: state, onAction: (_) {}),
  );
}

/// Full-tree builder for the multi-backend sidebar scroll shot: mounts
/// ChatScreen with multi-backend slices and the fake rpc/socket providers.
Widget _sidebarMultiBackendHost(ThemeData theme, Locale? locale) {
  final registryDir = Directory.systemTemp.createTempSync(
    'dsh-design-registry',
  );
  addTearDown(() => registryDir.deleteSync(recursive: true));
  final registryFile = File('${registryDir.path}/backends.json');
  registryFile.writeAsStringSync(kSettingsRegistryDoc);
  final stateDir = Directory.systemTemp.createTempSync('dsh-design-state');
  addTearDown(() => stateDir.deleteSync(recursive: true));
  final stateFile = File('${stateDir.path}/local_state.json');
  stateFile.writeAsStringSync('''
{
  "sidebar.groupOverrides": {
    "w1": true,
    "w2": true,
    "b1\\u0000wb1": true,
    "b2\\u0000wg1": true,
    "b2\\u0000wg2": true
  },
  "sidebar.overflowExpanded": ["w1", "w2", "b1\\u0000wb1"]
}
''');
  return ProviderScope(
    overrides: [
      backendStoreProvider.overrideWith(
        (ref) async => BackendStore(registryFile, seedBaseUrl: kDshBaseUrl),
      ),
      localStateStoreProvider.overrideWith(
        (ref) async => LocalStateStore(stateFile),
      ),
      dshRpcClientProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_FakeRpc()),
      dshEventSocketProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_SilentSocket()),
      for (final uri in [
        Uri.parse('http://10.0.2.2:3080'),
        Uri.parse('http://10.0.2.2:3081'),
        Uri.parse('http://10.0.2.2:3082'),
      ]) ...[
        dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(uri).overrideWithValue(_SilentSocket()),
      ],
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme,
      home: ChatScreen(
        uiState: multiBackendDrawerState(),
        backendSlices: kCrowdedBackendSlices,
        onAction: (_) {},
      ),
    ),
  );
}

/// The registry loads through real dart:io, which only completes in a
/// real-async zone: each runAsync round turns the event loop once and
/// each pump flushes what it scheduled.
Future<void> _loadRegistry(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await settle(tester);
}

Future<void> _openHostsPage(WidgetTester tester) async {
  await _loadRegistry(tester);
  // The host bar's sheet is the host surface now (no Hosts section).
  await tester.tap(find.text('Laptop').hitTestable());
  await settle(tester);
}

/// One root row, opened. Every settings surface this pass added hangs off
/// a row of the index, so the act is always "load the registry, bring the
/// row into frame, tap it".
Future<void> _tapSettingsRow(WidgetTester tester, String title) async {
  await _loadRegistry(tester);
  // The index is a lazy ListView: a row below the viewport has not been
  // built yet, so the scroll has to hunt for it rather than measure a
  // finder that cannot resolve. Every settings row this pass added hangs
  // off the index, and one row added above another pushes it out of the
  // first screenful.
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
  await tester.tap(find.text(title).hitTestable());
  await settle(tester);
}

Future<void> _openAgentPresetsPage(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Agent preset');

Future<void> _openAgentPresetDeclaration(WidgetTester tester) async {
  await _tapSettingsRow(tester, 'Agent preset');
  await tester.tap(find.text('View').first);
  await settle(tester);
}

Future<void> _openPermissionDefaultsPage(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Default permission preset');

Future<void> _openCredentialsPage(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Credentials');

Future<void> _openPluginsPage(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Host namespace values');

Future<void> _openLanguageSheet(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Language');

Future<void> _openAppearanceSheet(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Appearance');

Future<void> _openTranscriptViewSheet(WidgetTester tester) =>
    _tapSettingsRow(tester, 'Work details');

Future<void> _render(
  WidgetTester tester,
  DesignShot shot,
  ThemeData theme,
) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final double scale = shot.scale ?? _textScale;
  if (scale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    shot.host != null
        ? shot.host!(theme, shot.locale)
        : ProviderScope(
            overrides: [
              dshRpcClientProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_FakeRpc()),
              dshEventSocketProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_SilentSocket()),
            ],
            child: MaterialApp(
              // The banner is chrome the reviewer did not ask about.
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: shot.locale,
              theme: theme,
              home: ChatScreen(
                uiState: shot.state!,
                onAction: (_) {},
                loadAttachment: shot.loadAttachment ?? _noAttachment,
                readWorkspaceFile: shot.readFile ?? _noWorkspaceFileRead,
                readWorkspaceFileBytes:
                    shot.readFileBytes ?? _noWorkspaceFileBytes,
              ),
            ),
          ),
  );
  await settle(tester);
  await shot.act?.call(tester);
}

void main() {
  // Runs even where the shots skip: the guard is about which families the
  // harness registers, not about pixels.
  test('the harness registers the families the app declares', () async {
    if (Platform.environment['FLUTTER_ROOT'] == null) {
      markTestSkipped('FLUTTER_ROOT is unset — run through flutter test');
      return;
    }
    await _loadFonts();
    // The Latin half always resolves: the engine ships it.
    expect(_registeredFamilies, contains(kUiFontFamily));
    if (!_cjkLoaded) {
      markTestSkipped('no Han face on this host — see --fetch-fonts');
      return;
    }
    // Every Han family the app names is registered under that name; a harness
    // that invented one (it used to register `NotoSansCJK`) fails here.
    for (final String family in kUiFontFamilyFallback) {
      if (family == 'sans-serif') continue;
      expect(
        _registeredFamilies,
        contains(family),
        reason: 'the app declares $family for Han',
      );
    }
  });

  // The group carries the skip so the reason reaches the reader who ran
  // the suite and wondered where the shots went.
  group('design shots', () {
    setUpAll(_loadFonts);

    for (final shot in shots) {
      testWidgets('${shot.name} light', (tester) async {
        await _render(tester, shot, DshTheme.light());
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shots/${shot.name}_light.png'),
        );
      });

      if (!shot.dark) continue;
      testWidgets('${shot.name} dark', (tester) async {
        await _render(tester, shot, DshTheme.dark());
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shots/${shot.name}_dark.png'),
        );
      });
    }
  }, skip: _skip);
}
