import 'package:app/l10n/app_localizations.dart';
import 'package:app/platform/audio_recorder.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:app/ui/chat/voice_input/voice_recording_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump [uiState] into a bare dock, the way the composer does.
Widget _dock(
  VoiceInputUiState uiState, {
  VoidCallback onCancel = _noop,
  VoidCallback onDone = _noop,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Column(
        children: <Widget>[
          VoiceRecordingDock(
            uiState: uiState,
            onCancel: onCancel,
            onDone: onDone,
          ),
        ],
      ),
    ),
  );
}

void _noop() {}

void main() {
  group('VoiceRecordingDock & VoiceMicButton', () {
    testWidgets('VoiceMicButton shows prompt when tapped without models', (
      WidgetTester tester,
    ) async {
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

    testWidgets('VoiceMicButton triggers onTap when models are installed', (
      WidgetTester tester,
    ) async {
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

    testWidgets(
      'VoiceRecordingDock renders timer, soundwave, and dispatches cancel and done',
      (WidgetTester tester) async {
        bool canceled = false;
        bool done = false;

        const state = VoiceInputUiState(
          phase: VoiceInputPhase.recording,
          duration: Duration(seconds: 7),
          amplitude: 0.6,
        );

        await tester.pumpWidget(
          _dock(
            state,
            onCancel: () => canceled = true,
            onDone: () => done = true,
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
      },
    );

    testWidgets(
      'VoiceRecordingDock renders the native debug strip when stats are present',
      (WidgetTester tester) async {
        const state = VoiceInputUiState(
          phase: VoiceInputPhase.recording,
          duration: Duration.zero,
          debugStats: AudioDebugStats(
            reads: 42,
            eventsSent: 40,
            maxAbs: 0.5,
            sourceUsed: 'mic',
            isRecording: true,
            eventsReceived: 39,
          ),
        );

        await tester.pumpWidget(_dock(state));

        expect(find.textContaining('reads=42'), findsOneWidget);
        expect(find.textContaining('max=0.500'), findsOneWidget);
        expect(find.textContaining('src=mic'), findsOneWidget);
      },
    );

    testWidgets('VoiceRecordingDock hides the debug strip without stats', (
      WidgetTester tester,
    ) async {
      const state = VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration.zero,
      );

      await tester.pumpWidget(_dock(state));

      expect(find.textContaining('reads='), findsNothing);
    });

    testWidgets('an idle session collapses the dock and holds no controls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_dock(const VoiceInputUiState()));

      expect(find.text('Done'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('preparing the model says so and declines the seat', (
      WidgetTester tester,
    ) async {
      bool done = false;
      const state = VoiceInputUiState(phase: VoiceInputPhase.initializing);

      await tester.pumpWidget(_dock(state, onDone: () => done = true));

      expect(find.text('Getting ready…'), findsOneWidget);
      expect(find.text('Done'), findsNothing);

      await tester.tap(find.text('Getting ready…'));
      await tester.pump();
      expect(done, isFalse);

      // Cancel stays live: a session stuck loading a model is still the
      // reader's to abandon.
      bool canceled = false;
      await tester.pumpWidget(_dock(state, onCancel: () => canceled = true));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(canceled, isTrue);
    });

    testWidgets('transcribing owns the seat until the engine answers', (
      WidgetTester tester,
    ) async {
      bool done = false;
      const state = VoiceInputUiState(
        phase: VoiceInputPhase.finalizing,
        duration: Duration(seconds: 4),
      );

      await tester.pumpWidget(_dock(state, onDone: () => done = true));

      expect(find.text('Transcribing…'), findsOneWidget);
      expect(find.text('0:04'), findsOneWidget);

      await tester.tap(find.text('Transcribing…'));
      await tester.pump();
      expect(done, isFalse);
    });

    testWidgets('the session boundaries carry their own haptic weight', (
      WidgetTester tester,
    ) async {
      final haptics = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      bool started = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                VoiceMicButton(
                  enabled: true,
                  isRecording: false,
                  hasInstalledModels: true,
                  onTap: () => started = true,
                  onOpenSettings: () {},
                ),
                const VoiceRecordingDock(
                  uiState: VoiceInputUiState(phase: VoiceInputPhase.finalizing),
                  onCancel: _noop,
                  onDone: _noop,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(VoiceMicButton));
      await tester.pump();
      expect(started, isTrue);
      expect(
        haptics,
        contains('HapticFeedbackType.mediumImpact'),
        reason: 'going into a capture is a firm tap',
      );
    });

    testWidgets('reduce-motion leaves no endless animation on the dock', (
      WidgetTester tester,
    ) async {
      const state = VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(seconds: 2),
        amplitude: 0.5,
        envelope: <double>[0.2, 0.5, 0.4, 0.1],
      );

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                disableAnimations: true,
                size: Size(400, 800),
              ),
              child: VoiceRecordingDock(
                uiState: state,
                onCancel: _noop,
                onDone: _noop,
              ),
            ),
          ),
        ),
      );

      // The clock, the pulse and the meter all stand still under
      // reduce-motion, so the frame settles instead of ticking forever.
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a live capture keeps the meter moving', (
      WidgetTester tester,
    ) async {
      const first = VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(seconds: 2),
        amplitude: 0.5,
        envelope: <double>[0.2, 0.5, 0.4, 0.1],
      );
      const second = VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(seconds: 2),
        amplitude: 0.8,
        envelope: <double>[0.8, 0.6, 0.3, 0.5],
      );

      await tester.pumpWidget(_dock(first));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(_dock(second));
      await tester.pump(const Duration(milliseconds: 40));

      // The trail slides on the audio clock, so there is no frame at which
      // the dock is finished drawing: it never settles while it records.
      var settled = false;
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(milliseconds: 500),
        );
        settled = true;
      } on FlutterError {
        // The only way out of the loop is the timeout: the meter is still
        // moving, which is exactly what a live capture must do.
      }
      expect(settled, isFalse);
    });
  });
}
