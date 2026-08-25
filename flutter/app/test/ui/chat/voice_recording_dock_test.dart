import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:app/ui/chat/voice_input/voice_recording_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceRecordingDock & VoiceMicButton', () {
    testWidgets('VoiceMicButton shows prompt when tapped without models', (WidgetTester tester) async {
      bool openedSettings = false;
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: VoiceMicButton(
              enabled: true,
              isRecording: false,
              hasInstalledModels: false,
              onTap: () => tapped = true,
              onOpenSettings: () => openedSettings = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(VoiceMicButton));
      await tester.pumpAndSettle();

      expect(find.text('Speech Model Required'), findsOneWidget);
      expect(tapped, isFalse);

      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();

      expect(openedSettings, isTrue);
    });

    testWidgets('VoiceMicButton triggers onTap when models are installed', (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: VoiceMicButton(
              enabled: true,
              isRecording: false,
              hasInstalledModels: true,
              onTap: () => tapped = true,
              onOpenSettings: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(VoiceMicButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('VoiceRecordingDock renders timer, soundwave, and dispatches cancel and done', (WidgetTester tester) async {
      bool canceled = false;
      bool done = false;

      const state = VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(seconds: 7),
        amplitude: 0.6,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: VoiceRecordingDock(
              uiState: state,
              onCancel: () => canceled = true,
              onDone: () => done = true,
            ),
          ),
        ),
      );

      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(canceled, isTrue);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(done, isTrue);
    });
  });
}