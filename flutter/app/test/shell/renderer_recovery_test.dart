/// Renderer-death recovery: the shell rebuilds the pages whose renderer died,
/// coalesces the one-per-WebView report burst into one rebuild, and spaces
/// consecutive rebuilds with the backoff.
///
/// The pages are stand-ins (`hostViewBuilder`) and the reports come from a
/// fake [RendererWatch], so no platform view and no channel is involved.
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

Widget _shell(
  List<BackendConfig> hosts, {
  required _FakeRendererWatch watch,
  required void Function(BackendConfig host) onBuild,
  String? activeId,
}) {
  return ProviderScope(
    overrides: [
      backendRegistryStateProvider.overrideWith(
        (ref) => Stream<BackendRegistryState>.value(
          BackendRegistryState(backends: hosts, activeId: activeId),
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
        hostViewBuilder: (context, backend) {
          onBuild(backend);
          return Text('page:${backend.id}');
        },
      ),
    ),
  );
}

void main() {
  testWidgets('a renderer death rebuilds every live page after the backoff', (
    tester,
  ) async {
    final watch = _FakeRendererWatch();
    final builds = <String>[];
    await tester.pumpWidget(
      _shell(
        [_laptop, _desktop],
        activeId: 'laptop',
        watch: watch,
        onBuild: (host) => builds.add(host.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, ['laptop', 'desktop']);

    watch.emit();
    await tester.pump();
    expect(builds, [
      'laptop',
      'desktop',
    ], reason: 'the rebuild waits out the first backoff');

    await tester.pump(kRendererDeathBackoff);
    expect(builds, [
      'laptop',
      'desktop',
      'laptop',
      'desktop',
    ], reason: 'both live pages are rebuilt, not reused');
    expect(find.text('page:laptop'), findsOneWidget);
    expect(find.text('page:desktop'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a burst of one report per dead WebView rebuilds once', (
    tester,
  ) async {
    final watch = _FakeRendererWatch();
    final builds = <String>[];
    await tester.pumpWidget(
      _shell(
        [_laptop, _desktop],
        activeId: 'laptop',
        watch: watch,
        onBuild: (host) => builds.add(host.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, ['laptop', 'desktop']);

    // One renderer death, reported once per WebView it owned.
    watch.emit();
    watch.emit();
    watch.emit();
    await tester.pump();

    await tester.pump(kRendererDeathBackoff);
    expect(builds, [
      'laptop',
      'desktop',
      'laptop',
      'desktop',
    ], reason: 'the whole burst produced one rebuild');

    await tester.pump(kRendererDeathCoalesce);
    expect(builds, [
      'laptop',
      'desktop',
      'laptop',
      'desktop',
    ], reason: 'closing the coalescing window starts no further rebuild');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a second renderer death after the coalescing window rebuilds '
      'again', (tester) async {
    final watch = _FakeRendererWatch();
    final builds = <String>[];
    await tester.pumpWidget(
      _shell(
        [_laptop],
        activeId: 'laptop',
        watch: watch,
        onBuild: (host) => builds.add(host.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, ['laptop']);

    watch.emit();
    await tester.pump();
    await tester.pump(kRendererDeathBackoff);
    expect(builds, ['laptop', 'laptop']);

    // Let the coalescing window close, then a fresh death rebuilds again with
    // twice the delay (the second consecutive death).
    await tester.pump(kRendererDeathCoalesce);
    watch.emit();
    await tester.pump();
    await tester.pump(kRendererDeathBackoff * 2);
    expect(builds, [
      'laptop',
      'laptop',
      'laptop',
    ], reason: 'the next death replaces the page again');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
