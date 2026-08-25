/// Design review renderer: pumps the real screens at phone size and writes
/// one PNG per state under `test/design/shots/`.
///
/// These are outputs, not baselines. `scripts/render_design.py` always
/// passes `--update-goldens`, so nothing here can fail on a pixel; the
/// review happens on the published page, by eye.
///
/// Only that script runs them: the shots need host fonts and their PNGs
/// are gitignored, so anywhere else — a plain `flutter test`, CI — they
/// skip. The switch is an environment variable rather than a tag in
/// `dart_test.yaml`, because that file is read only when the runner starts
/// inside `flutter/app/`, and the suite runs from `flutter/`.
///
/// Procedure, and the traps that cost a render:
/// [.agents/skills/dsh-design-review](../../../../.agents/skills/dsh-design-review/SKILL.md).
@Tags(<String>['design'])
library;

import 'dart:async';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design_fixtures.dart';

/// Pixel size of the rendered device: a 360×844dp phone at 2x.
const Size _kPhone = Size(720, 1688);
const double _kDevicePixelRatio = 2.0;

/// Set by `scripts/render_design.py`; unset everywhere else.
final String? _skip = Platform.environment['DSH_DESIGN_SHOTS'] == '1'
    ? null
    : 'design shots: python3 scripts/render_design.py';

/// What a shot does after the screen settles, when the state alone cannot
/// express it — opening the drawer, holding a bubble.
typedef ShotAction = Future<void> Function(WidgetTester tester);

final class DesignShot {
  const DesignShot({
    required this.name,
    this.state,
    this.host,
    this.act,
    this.dark = true,
    this.locale,
  });

  final String name;

  /// Chat fixture; renders [ChatScreen] when set.
  final ChatUiState? state;

  /// Full-tree builder for a non-chat surface (the settings tab): it
  /// receives the harness theme (the light/dark twin) and builds its
  /// own root ProviderScope + MaterialApp + screen — the same shape
  /// the surface's widget tests pump, a root scope rather than a
  /// nested one. Called inside the test, so temp files and teardowns
  /// are safe to create here.
  final Widget Function(ThemeData theme, Locale? locale)? host;

  final ShotAction? act;

  /// Whether the dark twin renders too. A state whose defect is layout
  /// rather than tone renders once and stays cheap to review.
  final bool dark;

  /// Locale the shot renders chrome in; null leaves the platform default
  /// (English). A localized chrome string (e.g. the question card's
  /// recommended badge, "Recommended" vs "推荐") earns a zh twin.
  final Locale? locale;
}

final List<DesignShot> shots = <DesignShot>[
  DesignShot(name: 'transcript', state: busyState()),
  DesignShot(name: 'prose', state: proseState()),
  DesignShot(name: 'prose-lists', state: proseListsState(), dark: false),
  DesignShot(name: 'empty', state: emptyState(), dark: false),
  DesignShot(
    name: 'drawer',
    state: busyState(),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'message-menu',
    state: busyState(),
    dark: false,
    act: (tester) async {
      await tester.longPress(find.text(kBubbleUnderTest));
      await settle(tester);
    },
  ),
  DesignShot(name: 'question', state: questionState()),
  // The zh twin renders the same card with the localized chrome — the
  // recommended badge must read 推荐, not Recommended.
  DesignShot(
    name: 'question-zh',
    state: questionState(),
    locale: const Locale('zh'),
  ),
  // Settings shots: the two-category surface (App / Host) on a
  // two-host registry fixture. The default view (Host settings,
  // General) and the registry page pair with the same-named before
  // shots; the App category and its zh twin are new surfaces.
  const DesignShot(
    name: 'settings-general',
    host: _settingsHost,
    act: _loadRegistry,
  ),
  const DesignShot(
    name: 'settings-hosts',
    host: _settingsHost,
    act: _openHostsPage,
    dark: false,
  ),
  const DesignShot(
    name: 'settings-app',
    host: _settingsHost,
    act: _openAppCategory,
    dark: false,
  ),
  // The zh twin: the App category reads 应用设置 and the language
  // row's capsules carry their own-language display names.
  const DesignShot(
    name: 'settings-app-zh',
    host: _settingsHost,
    locale: Locale('zh'),
    act: _openAppCategoryZh,
    dark: false,
  ),
  DesignShot(
    name: 'voice-recording',
    state: busyState(),
    host: (theme, locale) => _voiceRecordingHost(theme, locale, false),
    act: _settleVoiceShot,
  ),
  DesignShot(
    name: 'voice-recording-zh',
    state: busyState(),
    locale: const Locale('zh'),
    host: (theme, locale) => _voiceRecordingHost(theme, locale, true),
    act: _settleVoiceShot,
    dark: false,
  ),
  DesignShot(
    name: 'voice-nomodel-dialog',
    host: (theme, locale) => _voiceNoModelDialogHost(theme, locale, false),
  ),
  DesignShot(
    name: 'voice-nomodel-dialog-zh',
    locale: const Locale('zh'),
    host: (theme, locale) => _voiceNoModelDialogHost(theme, locale, true),
    dark: false,
  ),
  DesignShot(
    name: 'settings-asr-models',
    host: (theme, locale) => _settingsAsrHost(theme, locale, false),
  ),
  DesignShot(
    name: 'settings-asr-models-zh',
    locale: const Locale('zh'),
    host: (theme, locale) => _settingsAsrHost(theme, locale, true),
    dark: false,
  ),
];

/// A running session animates forever, so `pumpAndSettle` never returns.
/// Every wait in this harness is a bounded pump instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(String endpoint, String method, JsonMap payload) async {
    if (endpoint == 'host.describe') {
      // A valid description so the settings shots' connection
      // handshakes reach CONNECTED (green dots, versioned rows).
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'version': '0.1.1',
          'cwd': '/home/user/Projects/deepseek-harness-app',
          'provider': 'deepseek',
          'model': 'glm-x',
          'attachedSessions': 1,
          'canOpenPath': true,
        },
      );
    }
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _SilentSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

/// Whether a Han face was found this run. Without one the Chinese half of
/// the UI renders as empty rectangles, which reads as a layout bug that
/// isn't there — so the harness says so rather than letting the reviewer
/// discover it in the PNG.
bool _cjkLoaded = false;

/// Test fonts default to a blank box face: without these loads every glyph
/// renders as a rectangle and every icon as an empty square.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    fail('FLUTTER_ROOT is unset — run through scripts/render_design.py');
  }
  final assets = '$root/bin/cache/artifacts/material_fonts';
  await _load('Roboto', <String>[
    '$assets/Roboto-Regular.ttf',
    '$assets/Roboto-Medium.ttf',
    '$assets/Roboto-Bold.ttf',
  ]);
  await _load('MaterialIcons', <String>['$assets/MaterialIcons-Regular.otf']);
  // Payload type asks for a monospace family by name; any installed face
  // renders the same shape decision, so the first hit wins.
  await _load('monospace', <String>[
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
  ], first: true);
  final home = Platform.environment['HOME'] ?? '';
  _cjkLoaded = await _load('NotoSansCJK', <String>[
    '$home/.cache/dsh-design/fonts/NotoSansSC.ttf',
    '$home/.local/share/fonts/NotoSansSC.ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
  ], first: true);
  if (!_cjkLoaded) {
    stderr.writeln(
      'design shots: no CJK font — Chinese renders as boxes. '
      'Fix: python3 scripts/render_design.py --fetch-fonts',
    );
  }
}

/// Loads every path that exists, or only the first when [first] is set
/// (a family that wants one face, not a weight set). Returns whether any
/// face was found.
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
/// resolves to the test's box face — is pointed at Roboto, with Han
/// behind it the way a device's fallback chain would sit.
ThemeData _withRealFonts(ThemeData base) {
  final fallback = _cjkLoaded ? <String>['NotoSansCJK'] : null;
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: fallback,
    ),
  );
}

/// The settings shots' tree: a root ProviderScope over the settings
/// screen, with a temp-backed registry seeded from the two-host
/// document (scope bar + Hosts rows), a temp-backed shared store
/// (preference rows), and quiet transport seams for every host URL
/// the document names.
Widget _settingsHost(ThemeData theme, Locale? locale) {
  final registryDir = Directory.systemTemp.createTempSync(
    'dsh-design-registry',
  );
  addTearDown(() => registryDir.deleteSync(recursive: true));
  final registryFile = File('${registryDir.path}/backends.json');
  registryFile.writeAsStringSync(kSettingsRegistryDoc);
  final stateDir = Directory.systemTemp.createTempSync('dsh-design-state');
  addTearDown(() => stateDir.deleteSync(recursive: true));
  return ProviderScope(
    overrides: [
      backendStoreProvider.overrideWith(
        (ref) async => BackendStore(registryFile, seedBaseUrl: kDshBaseUrl),
      ),
      localStateStoreProvider.overrideWith(
        (ref) async =>
            LocalStateStore(File('${stateDir.path}/local_state.json')),
      ),
      for (final uri in [
        Uri.parse('http://10.0.2.2:3080'),
        Uri.parse('http://10.0.2.2:3081'),
      ]) ...[
        dshRpcClientProvider(uri).overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(uri).overrideWithValue(_SilentSocket()),
      ],
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: _withRealFonts(theme),
      home: SettingsScreen(uiState: settingsUiState(), onAction: (_) {}),
    ),
  );
}

class _StaticVoiceInputController extends VoiceInputController {
  _StaticVoiceInputController({
    required super.manager,
    required this.initialState,
  }) : super(audioRecorder: MockAudioInputSource(simulatedDuration: Duration.zero));

  final VoiceInputUiState initialState;

  @override
  VoiceInputUiState get state => initialState;

  @override
  Stream<VoiceInputUiState> get uiState =>
      Stream<VoiceInputUiState>.value(initialState);

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async => '';

  @override
  Future<void> cancelRecording() async {}
}

Future<void> _settleVoiceShot(WidgetTester tester) async {
  await settle(tester);
}

/// Full-tree builder for the voice recording state: initializes a static ASR state
/// so the VoiceRecordingDock and active soundwave render deterministically.
Widget _voiceRecordingHost(ThemeData theme, Locale? locale, bool zh) {
  final tempDir = Directory.systemTemp.createTempSync('dsh-design-voice');
  addTearDown(() => tempDir.deleteSync(recursive: true));
  final registryFile = File('${tempDir.path}/models_registry.json');
  final registry = ModelsRegistry(registryFile: registryFile);
  registry.updateEntry(
    ModelRegistryEntry(
      modelId: 'sensevoice-small',
      source: ModelSource.hfMirror,
      localDir: '${tempDir.path}/sensevoice-small',
      status: AsrModelStatus.downloaded,
    ),
  );
  final manager = AsrModelManager(
    baseModelsDir: tempDir,
    registry: registry,
  );
  final controller = _StaticVoiceInputController(
    manager: manager,
    initialState: VoiceInputUiState(
      phase: VoiceInputPhase.recording,
      duration: const Duration(seconds: 5),
      amplitude: 0.65,
      activeModel: AsrModelManifest.senseVoiceSmall,
      hasInstalledModels: true,
      liveTranscription: zh ? '端侧语音识别实时转写测试' : 'On-device speech recognition live transcription test',
    ),
  );

  return ProviderScope(
    overrides: [
      asrModelManagerProvider.overrideWith((ref) async => manager),
      voiceInputControllerProvider.overrideWith((ref) => controller),
      dshRpcClientProvider(Uri.parse(kDshBaseUrl)).overrideWithValue(_FakeRpc()),
      dshEventSocketProvider(Uri.parse(kDshBaseUrl)).overrideWithValue(_SilentSocket()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: _withRealFonts(theme),
      home: ChatScreen(uiState: busyState(), onAction: (_) {}),
    ),
  );
}

/// Full-tree builder for the "No Speech Model Installed" dialog shot.
Widget _voiceNoModelDialogHost(ThemeData theme, Locale? locale, bool zh) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: _withRealFonts(theme),
    home: Scaffold(
      body: Center(
        child: AlertDialog(
          title: Text(zh ? '需要语音识别模型' : 'Speech Model Required'),
          content: Text(
            zh
                ? '请在设置中下载离线语音识别模型，即可开启端侧语音输入。'
                : 'Download an on-device speech recognition model in Settings to enable offline voice input.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {},
              child: Text(zh ? '取消' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {},
              child: Text(zh ? '前往设置' : 'Go to Settings'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Full-tree builder for the ASR Models management screen shot showing downloaded
/// SenseVoice model, Active Speech Model selector, and catalog cards.
Widget _settingsAsrHost(ThemeData theme, Locale? locale, bool zh) {
  const cards = <AsrModelCardState>[
    AsrModelCardState(
      info: AsrModelManifest.senseVoiceSmall,
      entry: ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '/data/models/sensevoice-small',
        status: AsrModelStatus.downloaded,
        downloadedBytes: 239549735,
        totalBytes: 239549735,
      ),
      diskUsageBytes: 239549735,
    ),
    AsrModelCardState(
      info: AsrModelManifest.zipformerBilingual,
      entry: ModelRegistryEntry(
        modelId: 'zipformer-bilingual',
        source: ModelSource.hfMirror,
        localDir: '/data/models/zipformer-bilingual',
        status: AsrModelStatus.idle,
      ),
    ),
    AsrModelCardState(
      info: AsrModelManifest.whisperLargeV3Turbo,
      entry: ModelRegistryEntry(
        modelId: 'whisper-large-v3-turbo',
        source: ModelSource.huggingFace,
        localDir: '/data/models/whisper-large-v3-turbo',
        status: AsrModelStatus.idle,
      ),
    ),
  ];

  final state = AsrModelsUiState(
    models: cards,
    defaultSource: ModelSource.hfMirror,
    installedCount: 1,
    totalCount: 3,
    activeModelId: 'sensevoice-small',
  );

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: _withRealFonts(theme),
    home: AsrModelsScreen(uiState: state, onAction: (_) {}),
  );
}

/// The registry loads through real dart:io, which only completes in a
/// real-async zone: each runAsync round turns the event loop once and
/// each pump flushes what it scheduled.
Future<void> _loadRegistry(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await settle(tester);
}

Future<void> _openHostsPage(WidgetTester tester) async {
  await _loadRegistry(tester);
  // The host bar's sheet is the host surface now (no Hosts section).
  await tester.tap(find.text('Laptop').hitTestable());
  await settle(tester);
}

Future<void> _openAppCategory(WidgetTester tester) async {
  await _loadRegistry(tester);
  await settle(tester);
}

Future<void> _openAppCategoryZh(WidgetTester tester) async {
  await _loadRegistry(tester);
  await settle(tester);
}

Future<void> _render(WidgetTester tester, DesignShot shot, ThemeData theme) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    shot.host != null
        ? shot.host!(theme, shot.locale)
        : ProviderScope(
            overrides: [
              dshRpcClientProvider(
                Uri.parse(kDshBaseUrl),
              ).overrideWithValue(_FakeRpc()),
              dshEventSocketProvider(
                Uri.parse(kDshBaseUrl),
              ).overrideWithValue(_SilentSocket()),
            ],
            child: MaterialApp(
              // The banner is chrome the reviewer did not ask about.
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: shot.locale,
              theme: _withRealFonts(theme),
              home: ChatScreen(uiState: shot.state!, onAction: (_) {}),
            ),
          ),
  );
  await settle(tester);
  await shot.act?.call(tester);
}

void main() {
  // The group carries the skip so the reason reaches the reader who ran
  // the suite and wondered where the shots went.
  group('design shots', () {
    setUpAll(_loadFonts);

    for (final shot in shots) {
      testWidgets('${shot.name} light', (tester) async {
        await _render(tester, shot, DshTheme.light());
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shots/${shot.name}_light.png'),
        );
      });

      if (!shot.dark) continue;
      testWidgets('${shot.name} dark', (tester) async {
        await _render(tester, shot, DshTheme.dark());
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('shots/${shot.name}_dark.png'),
        );
      });
    }
  }, skip: _skip);
}
