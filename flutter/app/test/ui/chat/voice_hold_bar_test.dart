/// The composer's hold-to-talk control: one press holds a capture, the release
/// sends it, and sliding up over the bar discards it.
///
/// The control and the bubble it anchors are the surface under test, so the
/// tree mounts the real bar inside a route (the bubble needs an `Overlay`) and
/// the sessions advance through the same `uiState` the controller publishes.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/platform/audio_recorder.dart';
import 'package:app/ui/chat/voice_input/voice_hold_bar.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:app/ui/chat/voice_input/voice_record_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _audioChannel = MethodChannel(kAudioRecordChannel);

void _noop() {}

/// The earcons the bar asked the platform for, read back through the real
/// channel rather than a seam invented for the test.
Future<List<String?>> _captureSounds(WidgetTester tester) async {
  final effects = <String?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _audioChannel,
    (call) async {
      if (call.method == 'playSoundEffect') {
        effects.add(
          (call.arguments! as Map<Object?, Object?>)['effect'] as String?,
        );
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _audioChannel,
      null,
    ),
  );
  return effects;
}

/// The bar on its own, the way the composer's voice band mounts it.
Widget _bar(
  VoiceInputUiState uiState, {
  bool enabled = true,
  bool busy = false,
  VoidCallback onStart = _noop,
  VoidCallback onFinish = _noop,
  VoidCallback onCancel = _noop,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: VoiceHoldBar(
            enabled: enabled,
            busy: busy,
            uiState: uiState,
            onStart: onStart,
            onFinish: onFinish,
            onCancel: onCancel,
            onOpenSettings: _noop,
          ),
        ),
      ),
    ),
  );
}

/// The bar with a session behind it: the host advances `phase` the way
/// [VoiceInputController] does, so a hold is observed against a session that is
/// actually live rather than against a state frozen at idle.
class _SessionHost extends StatefulWidget {
  const _SessionHost({
    required this.idle,
    this.onStarted,
    this.onFinished,
    this.onCanceled,
  });

  final VoiceInputUiState idle;
  final VoidCallback? onStarted;
  final VoidCallback? onFinished;
  final VoidCallback? onCanceled;

  @override
  State<_SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<_SessionHost> {
  late VoiceInputUiState _state = widget.idle;

  void _start() => setState(
    () => _state = VoiceInputUiState(
      phase: VoiceInputPhase.recording,
      duration: const Duration(seconds: 1),
      amplitude: 0.4,
      hasInstalledModels: widget.idle.hasInstalledModels,
    ),
  );

  void _end() => setState(() => _state = widget.idle);

  @override
  Widget build(BuildContext context) {
    return _bar(
      _state,
      onStart: () {
        _start();
        widget.onStarted?.call();
      },
      onFinish: () {
        _end();
        widget.onFinished?.call();
      },
      onCancel: () {
        _end();
        widget.onCanceled?.call();
      },
    );
  }
}

const _ready = VoiceInputUiState(hasInstalledModels: true);

const _recording = VoiceInputUiState(
  phase: VoiceInputPhase.recording,
  duration: Duration(seconds: 7),
  amplitude: 0.6,
  hasInstalledModels: true,
);

/// A live capture the engine is already transcribing.
const _transcribing = VoiceInputUiState(
  phase: VoiceInputPhase.recording,
  duration: Duration(seconds: 3),
  amplitude: 0.5,
  liveTranscription: 'open the settings screen',
  hasInstalledModels: true,
);

/// Presses the bar: the pointer is down and no release has happened yet.
Future<TestGesture> _press(WidgetTester tester) async {
  final hold = await tester.startGesture(
    tester.getCenter(find.byType(VoiceHoldBar)),
  );
  await tester.pump();
  return hold;
}

void main() {
  group('VoiceHoldBar and the bubble it anchors', () {
    testWidgets('an idle bar invites the hold and shows no session', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_bar(_ready));
      await tester.pump();

      expect(find.text('Hold to talk'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('a live session anchors its bubble above the bar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_bar(_recording));
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('0:07'), findsOneWidget);
      // The gesture the reader is in the middle of, named where they look.
      expect(find.text('Release to send · slide up to cancel'), findsOneWidget);

      final bar = tester.getRect(find.byType(VoiceHoldBar));
      final clock = tester.getRect(find.text('0:07'));
      expect(
        clock.top,
        lessThan(bar.top),
        reason: 'the bubble sits above the bar',
      );
    });

    testWidgets('the bubble carries the engine transcription as it lands', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_bar(_transcribing));
      await tester.pump(const Duration(milliseconds: 40));

      // The words the engine heard ride the bubble itself: the draft field they
      // are also written into sits behind it, so the reader would otherwise be
      // speaking blind.
      expect(find.text('open the settings screen'), findsOneWidget);
    });

    testWidgets('a capture offers no buttons: both endings are the gesture', (
      WidgetTester tester,
    ) async {
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _bar(
          _transcribing,
          onFinish: () => finished++,
          onCancel: () => canceled++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      // The session is fully live and no finger is down — the state that used
      // to grow a Cancel/Send row. Both are gone: release sends, slide up
      // discards, and the surface stays a report.
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Send'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(finished, 0);
      expect(canceled, 0);
    });

    testWidgets('the bubble takes no pointer', (WidgetTester tester) async {
      await tester.pumpWidget(_bar(_recording));
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        find.ancestor(
          of: find.byType(VoiceRecordBubble),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
        reason: 'the report must never intercept the thumb driving the bar',
      );
    });

    testWidgets('a press records, and the release sends it', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var started = 0;
      var finished = 0;
      await tester.pumpWidget(
        _SessionHost(
          idle: _ready,
          onStarted: () => started++,
          onFinished: () => finished++,
        ),
      );
      await tester.pump();

      final hold = await _press(tester);
      expect(started, 1, reason: 'the press down opens the capture');
      expect(finished, 0, reason: 'and does not end it');
      // The bar names the release on its own face, where the finger is.
      expect(find.text('Release to send'), findsOneWidget);
      expect(find.text('Release to send · slide up to cancel'), findsOneWidget);

      await hold.up();
      await tester.pump();

      expect(finished, 1, reason: 'the release sends');
      expect(sounds, <String?>['start', 'send']);
      // The session is over, so the bar is back to its invitation.
      expect(find.text('Hold to talk'), findsOneWidget);
    });

    testWidgets('sliding up arms the discard and cancels on release', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _bar(
          _recording,
          onFinish: () => finished++,
          onCancel: () => canceled++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      final hold = await _press(tester);

      // Short of the threshold the hold still means "send".
      await hold.moveBy(const Offset(0, -kVoiceCancelSlide / 2));
      await tester.pump();
      expect(find.text('Release to cancel'), findsNothing);
      expect(find.text('Release to send'), findsOneWidget);

      await hold.moveBy(const Offset(0, -kVoiceCancelSlide));
      await tester.pump();
      expect(find.text('Release to cancel'), findsWidgets);

      await hold.up();
      await tester.pump();

      expect(canceled, 1);
      expect(finished, 0, reason: 'an armed hold never sends');
      expect(sounds, <String?>['cancel']);
    });

    testWidgets('a press opened from idle can slide straight to discard', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _SessionHost(
          idle: _ready,
          onFinished: () => finished++,
          onCanceled: () => canceled++,
        ),
      );
      await tester.pump();

      final hold = await _press(tester);
      expect(find.text('Release to send'), findsOneWidget);

      await hold.moveBy(const Offset(0, -kVoiceCancelSlide - 10));
      await tester.pump();
      expect(find.text('Release to cancel'), findsWidgets);

      await hold.up();
      // The exit starts on the frame after the session ends, then waits out the
      // switcher's own removal grace, so it takes one pump to begin and one to
      // finish rather than a single long one.
      await tester.pump();
      await tester.pump(Durations.medium1 + const Duration(milliseconds: 100));

      expect(canceled, 1);
      expect(finished, 0);
      expect(sounds, <String?>['start', 'cancel']);
      // The session is over, so the surface that reported it is gone too.
      expect(find.text('Release to cancel'), findsNothing);
    });

    testWidgets('a pointer the platform takes discards and frees the hold', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _bar(
          _recording,
          onFinish: () => finished++,
          onCancel: () => canceled++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      final hold = await _press(tester);
      expect(find.text('Release to send'), findsOneWidget);

      // A system gesture or the app leaving the foreground. Nobody said
      // "send", so the capture is discarded — and, the point of the test, the
      // hold is released rather than left stuck with the bar answering
      // nothing ever again.
      await hold.cancel();
      await tester.pump();

      expect(canceled, 1);
      expect(finished, 0);
      expect(sounds, <String?>['cancel']);

      // A fresh press still opens a capture.
      canceled = 0;
      final again = await _press(tester);
      expect(find.text('Release to send'), findsOneWidget);
      await again.up();
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('a session the engine holds declines the press by name', (
      WidgetTester tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _bar(
          const VoiceInputUiState(
            phase: VoiceInputPhase.finalizing,
            hasInstalledModels: true,
          ),
          busy: true,
          onStart: () => started++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      // The bar and the bubble it anchors both name the wait: the reader's
      // thumb and their eye are in different places.
      expect(find.text('Transcribing…'), findsWidgets);
      final hold = await _press(tester);
      await hold.up();
      await tester.pump();

      expect(started, 0);
      expect(find.text('Release to send'), findsNothing);
    });

    testWidgets('an engine-owned phase names itself in the bubble', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _bar(
          const VoiceInputUiState(
            phase: VoiceInputPhase.finalizing,
            duration: Duration(seconds: 3),
            hasInstalledModels: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('Transcribing…'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a bar with nothing installed points at Settings instead', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var started = 0;
      await tester.pumpWidget(
        _bar(const VoiceInputUiState(), onStart: () => started++),
      );
      await tester.pump();

      final hold = await _press(tester);
      await hold.up();
      await tester.pumpAndSettle();

      expect(started, 0);
      expect(find.text('Speech Model Required'), findsOneWidget);
      expect(sounds, isEmpty, reason: 'a blocked press is not a boundary');
    });

    testWidgets('a model without the downloaded engine asks for the engine', (
      WidgetTester tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _bar(
          const VoiceInputUiState(
            hasInstalledModels: true,
            runtimeInstalled: false,
          ),
          onStart: () => started++,
        ),
      );
      await tester.pump();

      final hold = await _press(tester);
      await hold.up();
      await tester.pumpAndSettle();

      // The engine is a separate install from the model, so the gate names it
      // rather than the model the reader already has.
      expect(started, 0);
      expect(find.text('Speech Engine Required'), findsOneWidget);
      expect(find.text('Speech Model Required'), findsNothing);
    });

    testWidgets('reduce-motion still shows the bubble and settles', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true, size: Size(400, 800)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: VoiceHoldBar(
                    enabled: true,
                    busy: false,
                    uiState: _recording,
                    onStart: _noop,
                    onFinish: _noop,
                    onCancel: _noop,
                    onOpenSettings: _noop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The clock, the pulse and the meter all stand still under reduce-motion,
      // so the frame settles instead of ticking forever.
      await tester.pumpAndSettle();
      expect(find.text('0:07'), findsOneWidget);
    });

    testWidgets('a live capture keeps the meter moving', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_bar(_recording));
      await tester.pump(const Duration(milliseconds: 40));

      // The trail slides on the audio clock, so there is no frame at which the
      // bubble is finished drawing: it never settles while it records.
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

    testWidgets('the bubble carries the native debug strip when it has stats', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _bar(
          const VoiceInputUiState(
            phase: VoiceInputPhase.recording,
            hasInstalledModels: true,
            debugStats: AudioDebugStats(
              reads: 42,
              eventsSent: 40,
              maxAbs: 0.5,
              sourceUsed: 'mic',
              isRecording: true,
              eventsReceived: 39,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.textContaining('reads=42'), findsOneWidget);
      expect(find.textContaining('src=mic'), findsOneWidget);
    });
  });
}
