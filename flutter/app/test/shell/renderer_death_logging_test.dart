/// The shell logs one diagnostic entry per renderer death, not one per report.
///
/// Android reports a dead renderer once per WebView attached to it, so the
/// same death arrives as a burst. The recovery path already coalesces the
/// burst into one rebuild; this file drives that path through a fake
/// [RendererWatch] and reads the entry the shell left in the collector.
library;

import 'dart:async';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shell/shell_root.dart';
import 'package:app/shell/webview_renderer.dart';
import 'package:app/theme/theme.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart' as domain;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final BackendConfig _laptop = BackendConfig(
  id: 'laptop',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.0.5:3083'),
);
final BackendConfig _desktop = BackendConfig(
  id: 'desktop',
  label: 'Desktop',
  baseUri: Uri.parse('http://10.0.0.6:3083'),
);

/// A [RendererWatch] the test drives directly; no platform channel.
class _FakeRendererWatch implements RendererWatch {
  final StreamController<RendererGone> _reports =
      StreamController<RendererGone>.broadcast();

  @override
  Stream<RendererGone> get events => _reports.stream;

  /// Reports one renderer death, as one dead WebView would.
  void emit() => _reports.add(const RendererGone(didCrash: true, priority: 0));

  @override
  void dispose() {
    unawaited(_reports.close());
  }
}

Widget _shell(List<BackendConfig> hosts, _FakeRendererWatch watch) {
  return ProviderScope(
    overrides: [
      backendRegistryStateProvider.overrideWith(
        (ref) => Stream<BackendRegistryState>.value(
          BackendRegistryState(backends: hosts, activeId: 'laptop'),
        ),
      ),
      backendConnectionStateProvider.overrideWith(
        (ref, backendId) => Stream<domain.ConnectionState>.value(
          const domain.ConnectionState(phase: domain.ConnectionPhase.connected),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: DshTheme.light(),
      home: ShellRoot(
        rendererWatch: watch,
        hostViewBuilder: (context, backend) => Text('page:${backend.id}'),
      ),
    ),
  );
}

List<ErrorLogEntry> _goneEntries() => ErrorLogCollector.instance.entries
    .where((ErrorLogEntry entry) => entry.type == 'webview-renderer-gone')
    .toList();

void main() {
  setUp(ErrorLogCollector.instance.clear);
  tearDown(ErrorLogCollector.instance.clear);

  testWidgets('a three-report death burst leaves exactly one warning entry', (
    tester,
  ) async {
    final watch = _FakeRendererWatch();
    await tester.pumpWidget(_shell([_laptop, _desktop], watch));
    await tester.pumpAndSettle();

    // One renderer death, reported once per WebView it owned.
    watch.emit();
    watch.emit();
    watch.emit();
    await tester.pump();

    final List<ErrorLogEntry> entries = _goneEntries();
    expect(entries, hasLength(1));
    final ErrorLogEntry entry = entries.single;
    expect(entry.level, ErrorLogLevel.warning);
    expect(entry.message, contains('didCrash=true'));
    expect(entry.message, contains('priority=0'));
    expect(entry.context?['didCrash'], isTrue);
    expect(entry.context?['priority'], 0);
    expect(entry.context?['livePages'], 2);
    expect(entry.context?['consecutiveDeaths'], 1);
    expect(entry.context?['epoch'], 0);
    expect(
      ErrorLogCollector.instance.breadcrumbs.where(
        (String line) => line.contains('renderer gone'),
      ),
      hasLength(1),
      reason: 'the coalesced duplicates leave no second breadcrumb either',
    );

    await tester.pump(kRendererDeathBackoff);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
