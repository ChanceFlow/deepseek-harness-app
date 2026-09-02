import 'package:app/l10n/app_localizations.dart';
import 'package:app/platform/audio_recorder.dart';
import 'package:app/ui/chat/voice_input/voice_input_ui_state.dart';
import 'package:app/ui/chat/voice_input/voice_record_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _audioChannel = MethodChannel(kAudioRecordChannel);

/// Long enough for the framework's long-press recognizer to claim the gesture.
const Duration _hold = Duration(milliseconds: 600);

void _noop() {}

/// The earcons the seat asked the platform for, read back through the real
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

/// The seat on its own, the way the composer's tool row mounts it. The bubble
/// it anchors is the surface under test, so the tree needs the overlay a real
/// route provides.
Widget _seat(
  VoiceInputUiState uiState, {
  bool enabled = true,
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
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: VoiceMicButton(
            enabled: enabled,
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

/// The seat with a session behind it: the host advances `phase` the way
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: VoiceMicButton(
              enabled: true,
              uiState: _state,
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
              onOpenSettings: _noop,
            ),
          ),
        ),
      ),
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

/// Presses and holds the seat long enough to be a hold rather than a tap.
Future<TestGesture> _pressAndHold(WidgetTester tester) async {
  final hold = await tester.startGesture(
    tester.getCenter(find.byType(IconButton)),
  );
  await tester.pump(_hold);
  return hold;
}

void main() {
  group('VoiceMicButton and its anchored bubble', () {
    testWidgets('no session puts no bubble on screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_seat(_ready));
      await tester.pump();

      expect(find.text('0:00'), findsNothing);
      expect(find.text('Tap the mic to finish'), findsNothing);
    });

    testWidgets('a live session anchors a bubble above the seat', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_seat(_recording));
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('0:07'), findsOneWidget);
      // The gesture the reader is in the middle of, named where they look.
      expect(find.text('Tap the mic to finish'), findsOneWidget);

      final seat = tester.getRect(find.byType(IconButton));
      final clock = tester.getRect(find.text('0:07'));
      expect(
        clock.top,
        lessThan(seat.top),
        reason: 'the bubble sits above the seat',
      );
    });

    testWidgets('a tap on an idle seat opens a capture and sounds it', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var started = 0;
      await tester.pumpWidget(_seat(_ready, onStart: () => started++));
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(started, 1);
      expect(sounds, <String?>['start']);
    });

    testWidgets('a tap on a live seat plays the send earcon', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var finished = 0;
      await tester.pumpWidget(_seat(_recording, onFinish: () => finished++));
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(finished, 1);
      expect(sounds, <String?>['send']);
    });

    testWidgets('holding records and releasing sends', (
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

      final hold = await _pressAndHold(tester);
      expect(started, 1, reason: 'the press that holds opens the capture');
      expect(finished, 0, reason: 'and does not end it');
      // While the finger is down the bubble names the release.
      expect(find.text('Release to send · slide up to cancel'), findsOneWidget);

      await hold.up();
      await tester.pump();

      expect(finished, 1, reason: 'the release sends');
      expect(sounds, <String?>['start', 'send']);
    });

    testWidgets('sliding up arms the discard and cancels on release', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var finished = 0;
      var canceled = 0;
      await tester.pumpWidget(
        _seat(
          _recording,
          onFinish: () => finished++,
          onCancel: () => canceled++,
        ),
      );
      await tester.pump();

      final hold = await _pressAndHold(tester);

      // Short of the threshold the hold still means "send".
      await hold.moveBy(const Offset(0, -kVoiceCancelSlide / 2));
      await tester.pump();
      expect(find.text('Release to cancel'), findsNothing);

      await hold.moveBy(const Offset(0, -kVoiceCancelSlide));
      await tester.pump();
      expect(find.text('Release to cancel'), findsOneWidget);

      await hold.up();
      await tester.pump();

      expect(canceled, 1);
      expect(finished, 0, reason: 'an armed hold never sends');
      expect(sounds, <String?>['cancel']);
    });

    testWidgets('a hold opened from idle can slide straight to discard', (
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

      final hold = await _pressAndHold(tester);
      expect(find.text('Release to send · slide up to cancel'), findsOneWidget);

      await hold.moveBy(const Offset(0, -kVoiceCancelSlide - 10));
      await tester.pump();
      expect(find.text('Release to cancel'), findsOneWidget);

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

    testWidgets('a session the engine holds declines the press', (
      WidgetTester tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _seat(
          const VoiceInputUiState(
            phase: VoiceInputPhase.finalizing,
            hasInstalledModels: true,
          ),
          enabled: false,
          onStart: () => started++,
        ),
      );
      await tester.pump();

      final hold = await _pressAndHold(tester);
      await hold.up();
      await tester.pump();

      expect(started, 0);
    });

    testWidgets('an engine-owned phase names itself in the bubble', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _seat(
          const VoiceInputUiState(
            phase: VoiceInputPhase.finalizing,
            duration: Duration(seconds: 3),
            hasInstalledModels: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('Transcribing…'), findsOneWidget);
      expect(find.text('Tap the mic to finish'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a seat with nothing installed points at Settings instead', (
      WidgetTester tester,
    ) async {
      final sounds = await _captureSounds(tester);
      var started = 0;
      await tester.pumpWidget(
        _seat(const VoiceInputUiState(), onStart: () => started++),
      );
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(started, 0);
      expect(find.text('Speech Model Required'), findsOneWidget);
      expect(sounds, isEmpty, reason: 'a blocked press is not a boundary');
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
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: VoiceMicButton(
                    enabled: true,
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
      await tester.pumpWidget(_seat(_recording));
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
        _seat(
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
