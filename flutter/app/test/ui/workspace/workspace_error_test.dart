/// Workspace route failure surface: a host-configuration error renders as
/// a localized sentence with a retry, never as `error.toString()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/workspace/workspace_screen.dart';

import '../../l10n_app.dart';

void main() {
  testWidgets('a classified store failure reads as localized copy with retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The registry future fails the way a store read does; the
          // surface must not print the exception.
          backendRegistryStateProvider.overrideWithValue(
            const AsyncError(
              BackendStoreException(BackendErrorCode.readFailed),
              StackTrace.empty,
            ),
          ),
        ],
        child: l10nApp(home: const WorkspaceRoute()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Failed to read host configuration file.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('an unclassified failure falls back to the generic sentence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendRegistryStateProvider.overrideWithValue(
            AsyncError(StateError('storage plugin missing'), StackTrace.empty),
          ),
        ],
        child: l10nApp(home: const WorkspaceRoute()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load host configuration."), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
  });
}
