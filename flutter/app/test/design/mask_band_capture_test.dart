/// Mask-band capture: does the transcript's own surface cut a horizontal band
/// through its text when a message is appended, or when it scrolls?
///
/// The user reports a hard-edged band through a line of text with ghosted text
/// above and below it, on a settled Turn with its process open, and says it
/// appears **on send** rather than only while scrolling. This capture pumps the
/// real screen on that fixture, opens the fold, appends a message the way a send
/// does, then scrolls — writing one PNG per step plus the mask geometry that
/// produced it, so the band can be answered as geometry rather than by eye:
///
/// `geometry.txt` carries, per step, every mounted `RenderShaderMask`'s box and
/// global origin, the mask layer's own `maskRect` (the rect the engine actually
/// masks against), and the transcript viewport's `pixels` / `maxScrollExtent` /
/// `viewportDimension`. A band that travels with the content is a mask-geometry
/// bug; one fixed on screen while the content moves is compositing.
///
/// Runs only with both `--dart-define=DSH_DESIGN_SHOTS=true` and
/// `--dart-define=DSH_MOTION_CAPTURE=true`, like `motion_capture_test.dart`, so
/// a page publish and CI both skip it.
///
/// Reproduce (from `flutter/`):
///   flutter test -t design --dart-define=DSH_DESIGN_SHOTS=true \
///     --dart-define=DSH_MOTION_CAPTURE=true \
///     --dart-define=DSH_DESIGN_CJK_FONT=/abs/path/NotoSansSC.ttf \
///     --plain-name 'mask band' app/test/design/mask_band_capture_test.dart
@Tags(<String>['design'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_fixtures.dart';

/// The rendered device the shots use: a 360×844dp phone at 2x.
const Size _kPhone = Size(720, 1688);
const double _kDevicePixelRatio = 2.0;

const String? _skip =
    bool.fromEnvironment('DSH_DESIGN_SHOTS') &&
        bool.fromEnvironment('DSH_MOTION_CAPTURE')
    ? null
    : 'mask band capture: flutter test -t design '
          '--dart-define=DSH_DESIGN_SHOTS=true '
          '--dart-define=DSH_MOTION_CAPTURE=true';

const String _cjkFontPath = String.fromEnvironment('DSH_DESIGN_CJK_FONT');

final GlobalKey _boundaryKey = GlobalKey();

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async => RpcResult(ok: true, value: <String, Object?>{});

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

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
    scheduleMicrotask(() => _frames.add(_readyFrame()));
    return _frames.stream;
  }
}

bool _cjkLoaded = false;

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) fail('FLUTTER_ROOT is unset — run through the toolchain');
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

ThemeData _withRealFonts(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: _cjkLoaded ? <String>['NotoSansCJK'] : null,
  ),
);

/// The real chat screen on [state], wrapped so a frame can be read back.
Widget _app(ChatUiState state) => RepaintBoundary(
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
      locale: const Locale('zh'),
      theme: _withRealFonts(ThemeData.light()),
      home: ChatScreen(uiState: state, onAction: (_) {}),
    ),
  ),
);

Directory _framesDir() {
  for (final path in <String>['test/design/shots', 'app/test/design/shots']) {
    final shots = Directory(path);
    if (shots.existsSync()) {
      return Directory('${shots.path}/mask-band')..createSync(recursive: true);
    }
  }
  fail('shots tree not found from ${Directory.current.path}');
}

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
    if (data == null) fail('frame ${file.path}: no PNG data');
    png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  file.writeAsBytesSync(png, flush: true);
}

/// One step's mask geometry, in the scene's own coordinates.
String _geometry(WidgetTester tester, String step) {
  final lines = <String>['== $step'];
  var index = 0;
  for (final object in tester.allRenderObjects) {
    if (object is! RenderShaderMask) continue;
    final origin = object.localToGlobal(Offset.zero);
    final layer = object.layer;
    lines.add(
      'mask#$index size=${object.size.width.toStringAsFixed(1)}x'
      '${object.size.height.toStringAsFixed(1)} '
      'origin=(${origin.dx.toStringAsFixed(1)},${origin.dy.toStringAsFixed(1)}) '
      'maskRect=${layer?.maskRect}',
    );
    index++;
  }
  // Who hosts each mask: the ancestor widget chain names the site without a
  // debugger.
  index = 0;
  for (final element in find.byType(ShaderMask).evaluate()) {
    final chain = <String>[];
    element.visitAncestorElements((ancestor) {
      chain.add(ancestor.widget.runtimeType.toString());
      return chain.length < 6;
    });
    lines.add('shaderMask#$index hosts ${chain.join(' < ')}');
    index++;
  }
  final listView = find.byType(ListView);
  if (listView.evaluate().isNotEmpty) {
    final rect = tester.getRect(listView.first);
    lines.add(
      'transcript rect=${rect.left.toStringAsFixed(1)},'
      '${rect.top.toStringAsFixed(1)},${rect.right.toStringAsFixed(1)},'
      '${rect.bottom.toStringAsFixed(1)}',
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: listView, matching: find.byType(Scrollable)).first,
    );
    final position = scrollable.position;
    lines.add(
      'transcript pixels=${position.pixels.toStringAsFixed(1)} '
      'max=${position.maxScrollExtent.toStringAsFixed(1)} '
      'viewport=${position.viewportDimension.toStringAsFixed(1)} '
      'extent=${(position.pixels + position.viewportDimension).toStringAsFixed(1)}',
    );
  }
  final bodies = find.byType(ProcessGroupBody);
  lines.add('group bodies=${bodies.evaluate().length}');
  for (final element in bodies.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    lines.add(
      '  body size=${box.size.width.toStringAsFixed(1)}x'
      '${box.size.height.toStringAsFixed(1)} '
      'origin=(${origin.dx.toStringAsFixed(1)},${origin.dy.toStringAsFixed(1)})',
    );
  }
  return lines.join('\n');
}

/// A transcript long enough to scroll: the fixture's own Turns stay at the
/// tail — the completed Turn the user photographed — with padding above them.
ChatUiState _longState(ChatUiState base) => ChatUiState(
  sessions: base.sessions,
  selectedSessionId: 's1',
  timeline: <TimelineItem>[
    for (var index = 0; index < 10; index++) ...<TimelineItem>[
      TimelineMessage(
        ChatMessage(
          id: 'pad-u$index',
          sessionId: 's1',
          role: MessageRole.user,
          text: '第 $index 轮：把这一行补上，长度足够把内容顶出视口。',
          createdAtEpochMs: kNow - 100000 + index * 2000,
          seq: -200 + index * 2,
        ),
      ),
      TimelineMessage(
        ChatMessage(
          id: 'pad-a$index',
          sessionId: 's1',
          role: MessageRole.assistant,
          text: '第 $index 轮回答：这一行也足够长，用来把内容顶出视口，看看遮罩有没有切到字。',
          createdAtEpochMs: kNow - 99000 + index * 2000,
          seq: -199 + index * 2,
        ),
      ),
    ],
    ...base.timeline,
  ],
);

void main() {
  group('mask band', () {
    setUpAll(_loadFonts);

    testWidgets('open, append, scroll', (tester) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = _kDevicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dir = _framesDir();
      final geometry = <String>[];
      final base = turnProcessFoldedState(zh: true);
      final long = _longState(base);

      await tester.pumpWidget(_app(long));
      await tester.pump(const Duration(milliseconds: 400));

      // A reader sitting at the tail, where a send happens.
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      geometry.add(_geometry(tester, '00 at tail'));
      await _writeFrame(tester, File('${dir.path}/00-at-tail.png'));

      // Open the last Turn's process fold, the state the user photographed.
      final section = find.byType(TurnProcessRow).last;
      await tester.tap(
        find.descendant(of: section, matching: find.byType(InkWell)).first,
      );
      await tester.pump(const Duration(milliseconds: 400));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      geometry.add(_geometry(tester, '01 fold open'));
      await _writeFrame(tester, File('${dir.path}/01-fold-open.png'));

      // A send: one more user message at the tail, exactly what the composer
      // appends, captured frame by frame through the follow scroll that a send
      // starts.
      final appended = ChatUiState(
        sessions: long.sessions,
        selectedSessionId: 's1',
        timeline: <TimelineItem>[
          ...long.timeline,
          const TimelineMessage(
            ChatMessage(
              id: 'append-u1',
              sessionId: 's1',
              role: MessageRole.user,
              text: '再补一句：把这条也记下来，长度够切开一行文字看看有没有横带。',
              createdAtEpochMs: kNow + 1000,
              seq: 90,
            ),
          ),
        ],
      );
      await tester.pumpWidget(_app(appended));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
        geometry.add(_geometry(tester, '02 send frame $frame'));
        await _writeFrame(tester, File('${dir.path}/02-send-$frame.png'));
      }
      await tester.pumpAndSettle();
      geometry.add(_geometry(tester, '03 send settled'));
      await _writeFrame(tester, File('${dir.path}/03-send-settled.png'));

      // A manual fling for the scroll-only case.
      await tester.fling(find.byType(ListView), const Offset(0, 320), 2000);
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
        geometry.add(_geometry(tester, '04 fling frame $frame'));
        await _writeFrame(tester, File('${dir.path}/04-fling-$frame.png'));
      }
      await tester.pumpAndSettle();
      geometry.add(_geometry(tester, '05 fling settled'));
      await _writeFrame(tester, File('${dir.path}/05-fling-settled.png'));

      File('${dir.path}/geometry.txt')
          .writeAsStringSync('${geometry.join('\n')}\n', flush: true);
    });

    // The third mask site: `ProcessGroupBody`'s mask, which is the only one
    // whose box *moves* — it lives inside the scrolling transcript, so every
    // scroll frame changes its paint offset while its `maskRect` is set from
    // that offset at paint time. This scenario mounts one for real (an
    // expanded activity group) in a transcript tall enough to scroll.
    testWidgets('group body mask inside a scrolling transcript', (
      tester,
    ) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = _kDevicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dir = _framesDir();
      final geometry = <String>[];
      final base = timelineFoldingStateEn();
      final long = ChatUiState(
        sessions: base.sessions,
        selectedSessionId: 's1',
        timeline: <TimelineItem>[
          for (var index = 0; index < 8; index++) ...<TimelineItem>[
            TimelineMessage(
              ChatMessage(
                id: 'bod-u$index',
                sessionId: 's1',
                role: MessageRole.user,
                text: 'Round $index: padding so the transcript can scroll.',
                createdAtEpochMs: kNow - 100000 + index * 2000,
                seq: -200 + index * 2,
              ),
            ),
            TimelineMessage(
              ChatMessage(
                id: 'bod-a$index',
                sessionId: 's1',
                role: MessageRole.assistant,
                text:
                    'Round $index answer: long enough to push the transcript '
                    'past its viewport so the mask has something to fade.',
                createdAtEpochMs: kNow - 99000 + index * 2000,
                seq: -199 + index * 2,
              ),
            ),
          ],
          ...base.timeline,
        ],
      );

      await tester.pumpWidget(_app(long));
      await tester.pump(const Duration(milliseconds: 400));

      // Open the last activity group, which mounts its own masked body.
      await tester.tap(find.byType(ActivityGroupRow).last);
      await tester.pump(const Duration(milliseconds: 400));

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      geometry.add(_geometry(tester, 'B00 group open, at tail'));
      await _writeFrame(tester, File('${dir.path}/B00-group-open.png'));

      // Scroll the transcript back up through the masked body, frame by frame:
      // the body's own box slides while its mask is reapplied.
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 240);
      await tester.pump();
      for (var frame = 0; frame < 6; frame++) {
        scrollable.position.jumpTo(
          (scrollable.position.maxScrollExtent - 240 + frame * 40).clamp(
            0.0,
            scrollable.position.maxScrollExtent,
          ),
        );
        await tester.pump(const Duration(milliseconds: 32));
        geometry.add(_geometry(tester, 'B01 scroll frame $frame'));
        await _writeFrame(tester, File('${dir.path}/B01-scroll-$frame.png'));
      }

      await tester.fling(find.byType(ListView), const Offset(0, 300), 2000);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
        geometry.add(_geometry(tester, 'B02 fling frame $frame'));
        await _writeFrame(tester, File('${dir.path}/B02-fling-$frame.png'));
      }
      // Not `pumpAndSettle`: the fixture carries a live row whose sweep
      // animates forever. Fixed pumps land the friction scroll instead.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      geometry.add(_geometry(tester, 'B03 settled'));
      await _writeFrame(tester, File('${dir.path}/B03-settled.png'));

      File('${dir.path}/geometry-bodies.txt')
          .writeAsStringSync('${geometry.join('\n')}\n', flush: true);
    });

    // The band itself, as frames: `ProcessGroupBody`'s edge before and after the
    // child resizes itself. The same spot in every frame — the body's own
    // bottom 24px — so a reader can see the erase and its absence side by side.
    testWidgets('group body edge frames', (tester) async {
      tester.view.physicalSize = _kPhone;
      tester.view.devicePixelRatio = _kDevicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dir = _framesDir();
      final rowKey = GlobalKey<_SelfSizingRowState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  const SizedBox(height: 200),
                  ProcessGroupBody(child: _SelfSizingRow(key: rowKey)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await _writeFrame(tester, File('${dir.path}/edge-0-fits.png'));

      // Grow past the cap without any scroll: the fade must appear.
      rowKey.currentState!.toggle();
      await tester.pump();
      await tester.pump();
      await _writeFrame(tester, File('${dir.path}/edge-1-overflows.png'));

      // A reader scroll inside the body: the gate is read true here, which is
      // the state the stale band needs.
      await tester.drag(
        find.descendant(
          of: find.byType(ProcessGroupBody),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -60),
      );
      await tester.pump();
      await _writeFrame(tester, File('${dir.path}/edge-2-scrolled.png'));

      // Shrink back under the cap: the fade must go, and the last line stay.
      rowKey.currentState!.toggle();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _writeFrame(tester, File('${dir.path}/edge-3-shrunk.png'));
    });
  }, skip: _skip);
}

/// A row that resizes itself, the way a pin tool row discloses in place: its
/// own `setState` changes the body's content height with no scroll event and no
/// rebuild of the body.
class _SelfSizingRow extends StatefulWidget {
  const _SelfSizingRow({super.key});

  @override
  State<_SelfSizingRow> createState() => _SelfSizingRowState();
}

class _SelfSizingRowState extends State<_SelfSizingRow> {
  bool _open = false;

  /// Flip the row's own height, the way a tool row discloses in place.
  void toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const SizedBox(height: 40, child: ColoredBox(color: Color(0xFF3366CC))),
      SizedBox(
        width: double.infinity,
        height: _open ? 660 : 20,
        child: const ColoredBox(color: Color(0xFF000000)),
      ),
    ],
  );
}
