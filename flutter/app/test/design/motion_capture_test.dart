/// Motion capture: renders the running row as a numbered PNG sequence so the
/// one animation the design page can only show as stills — the tail's sway
/// under the label's stepped sweep — can be reviewed as motion.
///
/// Same gate as the design shots: tagged `design` and skipped unless the
/// runner passes `--dart-define=DSH_DESIGN_SHOTS=true`, because the frames
/// need host fonts and are gitignored artifacts, never a baseline. They land
/// under `test/design/shots/motion/<mode>/`, a subdirectory of the ignored
/// `shots/` tree, so the published page's non-recursive glob never picks them
/// up.
///
/// One seamless loop is the least common multiple of the row's two clocks —
/// the tail's 1.0s sway and [kSweepCycle]'s 1.5s sweep — so 3.0s, cut as 100
/// frames at 30ms. A whole number of GIF centiseconds is deliberate: the
/// assembled file's own period is then the captured one, so the loop point
/// carries the same phase as its first frame. Each frame also logs the phase it
/// read from the mounted tree into `phases.txt`, and `geometry.txt` carries the
/// row's rect in the frames' own physical pixels for the crop.
///
/// Reproduce (from `flutter/`):
///   flutter test -t design --dart-define=DSH_DESIGN_SHOTS=true \
///     --plain-name 'motion capture' app/test/design/motion_capture_test.dart
///   ffmpeg -framerate 100/3 -i .../motion/motion/frame_%03d.png -loop 0 out.gif
///
/// The plumbing below (fonts, the two transport seams) is deliberately local:
/// `design_shots_test.dart` is another task's write scope, so this capability
/// stays additive rather than refactoring the shared harness.
@Tags(<String>['design'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/running_status_row.dart';
import 'package:app/ui/chat/running_whale_tail.dart';
import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_fixtures.dart';

/// The rendered device the shots use: a 360×844dp phone at 2x.
const Size _kPhone = Size(720, 1688);
const double _kDevicePixelRatio = 2.0;

/// The shortest window that repeats both clocks: the tail beats every 1.0s,
/// the sweep runs every [kSweepCycle] (1.5s), and 3.0s is their least common
/// multiple. 30ms is also a whole number of GIF centiseconds.
const int _kFrames = 100;
const Duration _kStep = Duration(milliseconds: 30);

/// Set by the runner; unset in a plain `flutter test` and in CI.
const String? _skip = bool.fromEnvironment('DSH_DESIGN_SHOTS')
    ? null
    : 'motion capture: flutter test -t design --dart-define=DSH_DESIGN_SHOTS=true';

/// The Han face the runner resolved on the host, as an absolute path.
const String _cjkFontPath = String.fromEnvironment('DSH_DESIGN_CJK_FONT');

/// The boundary every frame is read from.
final GlobalKey _boundaryKey = GlobalKey();

/// The bare transport's answer: an empty successful result.
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
/// `/api/remote.mux`: the connection generation handshake, so the screen
/// renders connected chrome instead of an unreachable-host banner.
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

bool _cjkLoaded = false;

/// Test fonts default to a blank box face: without these loads every glyph
/// renders as a rectangle. The running row's sentence is English, so the Han
/// face is optional.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is unset — run through the design toolchain');
  }
  final assets = '$root/bin/cache/artifacts/material_fonts';
  await _load('Roboto', <String>[
    '$assets/Roboto-Regular.ttf',
    '$assets/Roboto-Medium.ttf',
    '$assets/Roboto-Bold.ttf',
  ]);
  await _load('MaterialIcons', <String>['$assets/MaterialIcons-Regular.otf']);
  final home = Platform.environment['HOME'] ?? '';
  _cjkLoaded = await _load('NotoSansCJK', <String>[
    if (_cjkFontPath.isNotEmpty) _cjkFontPath,
    '$home/.cache/dsh-design/fonts/NotoSansSC.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ], first: true);
}

/// Loads every path that exists, or the first when [first] is set. Returns
/// whether any face was found.
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
  return true;
}

/// The loaded faces carry real names, so the theme's null family — which
/// resolves to the test's box face — is pointed at Roboto, with Han behind it.
ThemeData _withRealFonts(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: _cjkLoaded ? <String>['NotoSansCJK'] : null,
  ),
);

/// The real chat screen over the running fixture, wrapped so a frame can be
/// read back. With [reduced] the row's own accessibility setting is forced,
/// the same `MediaQuery.disableAnimationsOf` the widget reads.
Widget _app(ThemeData theme, {required bool reduced}) {
  final Widget chat = ChatScreen(
    uiState: turnProcessLiveState(),
    onAction: (_) {},
  );
  return RepaintBoundary(
    key: _boundaryKey,
    child: ProviderScope(
      overrides: [
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_SilentSocket()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _withRealFonts(theme),
        home: reduced
            ? Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: true),
                  child: chat,
                ),
              )
            : chat,
      ),
    ),
  );
}

/// Where the frames go: the ignored shots tree, whichever of the two working
/// directories the runner started from.
Directory _framesDir(String mode) {
  for (final path in <String>['test/design/shots', 'app/test/design/shots']) {
    final shots = Directory(path);
    if (shots.existsSync()) {
      return Directory('${shots.path}/motion/$mode')
        ..createSync(recursive: true);
    }
  }
  fail('shots tree not found from ${Directory.current.path}');
}

/// The running row's sweep clock, as the mounted row reports it.
AnimationController? _sweepController(WidgetTester tester) => tester
    .widget<SweepHighlight>(
      find.descendant(
        of: find.byType(RunningStatusRow),
        matching: find.byType(SweepHighlight),
      ),
    )
    .controller;

/// The tail's sway on this frame, read from the mounted tree: the (0,1) entry
/// of the sway transform, which [Transform.rotate] fills with `-sin(angle)`.
/// Null where reduced motion mounts no transform at all, which is itself the
/// evidence.
double? _swaySin(WidgetTester tester) {
  final tail = find.descendant(
    of: find.byType(RunningWhaleTail),
    matching: find.byType(Transform),
  );
  if (tail.evaluate().isEmpty) return null;
  return tester.widget<Transform>(tail).transform.entry(0, 1);
}

/// What the two clocks read on this frame: `frame,t_ms,sway_m01,sway_deg,
/// sweep_ms,sweep_travel,sweep_animating`. `sway_m01` is the sway transform's
/// (0,1) entry — `Transform.rotate` fills it with `-sin(angle)`, so `sway_deg`
/// is the rotation itself.
String _phaseLine(WidgetTester tester, int frame) {
  final double? sway = _swaySin(tester);
  final AnimationController? sweep = _sweepController(tester);
  final Duration? elapsed = sweep?.lastElapsedDuration;
  return <String>[
    '$frame',
    '${frame * _kStep.inMilliseconds}',
    sway?.toStringAsFixed(4) ?? '',
    sway == null
        ? ''
        : (-math.asin(sway.clamp(-1.0, 1.0)) * 180 / math.pi).toStringAsFixed(
            3,
          ),
    elapsed?.inMilliseconds.toString() ?? '',
    elapsed == null ? '' : sweepTravel(elapsed).toStringAsFixed(4),
    sweep?.isAnimating.toString() ?? 'false',
  ].join(',');
}

/// Writes one frame of the boundary at the device pixel ratio.
Future<void> _writeFrame(WidgetTester tester, File file) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Uint8List png;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(
      pixelRatio: _kDevicePixelRatio,
    );
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    if (data == null) fail('frame ${file.path}: the PNG encoder returned none');
    png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  file.writeAsBytesSync(png, flush: true);
}

/// A logical rect in the frames' own physical pixels.
Rect _physical(Rect logical) => Rect.fromLTWH(
  logical.left * _kDevicePixelRatio,
  logical.top * _kDevicePixelRatio,
  logical.width * _kDevicePixelRatio,
  logical.height * _kDevicePixelRatio,
);

String _pad(int frame) => frame.toString().padLeft(3, '0');

/// Captures one mode's frame sequence, its phase log and its crop geometry.
Future<void> _capture(WidgetTester tester, String mode) async {
  final bool reduced = mode == 'still';
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_app(DshTheme.dark(), reduced: reduced));
  // The row's two controllers start in didChangeDependencies; one more frame
  // seeds the tickers' start time, so frame 0 is phase zero.
  await tester.pump();

  final Rect rowAtStart = tester.getRect(find.byType(RunningStatusRow));
  final Rect tailAtStart = tester.getRect(find.byType(RunningWhaleTail));

  final Directory dir = _framesDir(mode);
  final List<String> phases = <String>[
    'frame,t_ms,sway_m01,sway_deg,sweep_ms,sweep_travel,sweep_animating',
  ];
  final List<double?> sway = <double?>[];
  for (var frame = 0; frame < _kFrames; frame++) {
    phases.add(_phaseLine(tester, frame));
    sway.add(_swaySin(tester));
    await _writeFrame(tester, File('${dir.path}/frame_${_pad(frame)}.png'));
    await tester.pump(_kStep);
  }
  File('${dir.path}/phases.txt').writeAsStringSync('${phases.join('\n')}\n');

  // The crop box in the frames' own physical pixels, sampled at both ends so a
  // drifting row cannot silently invalidate the crop.
  final Rect rowAtEnd = tester.getRect(find.byType(RunningStatusRow));
  final Rect tailAtEnd = tester.getRect(find.byType(RunningWhaleTail));
  File('${dir.path}/geometry.txt').writeAsStringSync(
    <String>[
      'mode=$mode',
      'device=${_kPhone.width.toInt()}x${_kPhone.height.toInt()}',
      'frames=$_kFrames',
      'step_ms=${_kStep.inMilliseconds}',
      'row_frame0_logical=$rowAtStart',
      'row_frame0_physical=${_physical(rowAtStart)}',
      'row_frameLast_physical=${_physical(rowAtEnd)}',
      'tail_frame0_logical=$tailAtStart',
      'tail_frame0_physical=${_physical(tailAtStart)}',
      'tail_frameLast_physical=${_physical(tailAtEnd)}',
    ].join('\n'),
  );

  stdout.writeln('motion capture ($mode): $_kFrames frames -> ${dir.path}');
  stdout.writeln('  row  physical (frame 0): ${_physical(rowAtStart)}');
  stdout.writeln('  row  physical (last):    ${_physical(rowAtEnd)}');
  stdout.writeln('  tail physical (frame 0): ${_physical(tailAtStart)}');
  stdout.writeln('  tail physical (last):    ${_physical(tailAtEnd)}');
  stdout.writeln('  phase probe: ${phases[1]} .. ${phases.last}');

  // The row must not move under the crop while the clocks run.
  expect(_physical(rowAtEnd), _physical(rowAtStart));

  if (reduced) {
    // Reduced motion: no tail transform is mounted at all, and the row's sweep
    // clock was never started.
    expect(sway.every((value) => value == null), isTrue);
    expect(_sweepController(tester)?.isAnimating ?? false, isFalse);
  } else {
    // The capture really swept: a still run would log one value for all frames.
    expect(sway.whereType<double>().toSet().length, greaterThan(1));
  }
}

void main() {
  group('motion capture', () {
    setUpAll(_loadFonts);

    testWidgets('running row motion frames', (tester) async {
      await _capture(tester, 'motion');
    });

    testWidgets('running row still frames', (tester) async {
      await _capture(tester, 'still');
    });
  }, skip: _skip);
}
