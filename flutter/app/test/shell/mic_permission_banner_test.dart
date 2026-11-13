/// The microphone-blocked banner and the shell state that drives it.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/shell/mic_permission_banner.dart';
import 'package:app/shell/mic_permission_recovery.dart';
import 'package:app/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

const MethodChannel _channel = MethodChannel('dsh/webview');

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: DshTheme.light(),
      home: const Scaffold(body: MicPermissionBanner()),
    ),
  );
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(MicPermissionBanner)),
      listen: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('a blocked host renders the banner with that host label', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(find.text(_en.micPermissionBlockedTitle), findsNothing);

    _containerOf(tester)
        .read(micPermissionRecoveryProvider.notifier)
        .reportBlocked('Laptop');
    await tester.pump();

    expect(find.text(_en.micPermissionBlockedTitle), findsOneWidget);
    expect(find.text(_en.micPermissionBlockedBody('Laptop')), findsOneWidget);
    expect(find.text(_en.micPermissionOpenSettings), findsOneWidget);
    expect(find.text(_en.micPermissionDismiss), findsOneWidget);
  });

  testWidgets('open settings asks the activity channel for app settings', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return true;
        });

    await tester.pumpWidget(_app());
    _containerOf(tester)
        .read(micPermissionRecoveryProvider.notifier)
        .reportBlocked('Laptop');
    await tester.pump();

    await tester.tap(find.text(_en.micPermissionOpenSettings));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), contains('openAppSettings'));
  });

  testWidgets('dismiss clears the shell state and unmounts the banner', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    _containerOf(tester)
        .read(micPermissionRecoveryProvider.notifier)
        .reportBlocked('Laptop');
    await tester.pump();
    expect(find.text(_en.micPermissionBlockedTitle), findsOneWidget);

    await tester.tap(find.text(_en.micPermissionDismiss));
    await tester.pumpAndSettle();

    expect(_containerOf(tester).read(micPermissionRecoveryProvider), isNull);
    expect(find.text(_en.micPermissionBlockedTitle), findsNothing);
  });

  test('report, replace and clear hold the newest host label', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(micPermissionRecoveryProvider.notifier);

    expect(container.read(micPermissionRecoveryProvider), isNull);

    notifier.reportBlocked('Laptop');
    expect(
      container.read(micPermissionRecoveryProvider),
      const MicPermissionBlocked(hostLabel: 'Laptop'),
    );

    notifier.reportBlocked('Desktop');
    expect(
      container.read(micPermissionRecoveryProvider),
      const MicPermissionBlocked(hostLabel: 'Desktop'),
    );

    notifier.clear();
    expect(container.read(micPermissionRecoveryProvider), isNull);
  });
}
