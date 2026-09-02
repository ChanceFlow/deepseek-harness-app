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
import 'dart:math' show max;

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/subagents/subagent_screen.dart';
import 'package:app/ui/subagents/subagent_ui_state.dart';
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
    name: 'workspace-sheet',
    state: emptyStateWithWorkspaces(),
    act: (tester) async {
      await tester.tap(find.text('Choose workspace'));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'drawer',
    state: busyState(),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'sidebar-scroll-bleed',
    host: (theme, locale) => _sidebarMultiBackendHost(theme, locale),
    act: (tester) async {
      await _loadRegistry(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
      final listFinder = find.descendant(
        of: find.byType(SessionPanel),
        matching: find.byType(ListView),
      );
      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      scrollableState.position.jumpTo(28.0);
      await settle(tester);
    },
  ),
  // The collapsed rail: a ≥720dp-only form the phone viewport can never
  // show. The act moves this one shot's viewport to a tablet width (the
  // catalog device stays the phone; _kPhone belongs to every other shot)
  // and folds the sidebar, so the rail's seats render as readers see them.
  DesignShot(
    name: 'sidebar-rail',
    state: busyState(),
    act: (tester) async {
      tester.view.physicalSize = const Size(1440, 1688);
      await settle(tester);
      await tester.tap(find.byTooltip('Collapse sidebar'));
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
  // The trajectory outline: the ledger-style turn-group headers over a
  // two-turn fold (a failed tool in the first turn, a running tool in
  // the second). The collapse twin folds the first group so its
  // subtitle carries the tool-count summary and the error-ink failure
  // count instead of the prompt echo.
  DesignShot(
    name: 'outline',
    state: outlineState(),
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'outline-collapsed',
    state: outlineState(),
    dark: false,
    act: (tester) async {
      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await settle(tester);
      // Matches the turn-1 header under both the old ▾-glyph button and
      // the new borderless tile, so this pass renders a real before.
      await tester.tap(find.textContaining('Turn 1 · 2'));
      await settle(tester);
    },
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
    name: 'voice-transcribing',
    state: busyState(),
    host: (theme, locale) => _voiceRecordingHost(
      theme,
      locale,
      false,
      endPhase: VoiceInputPhase.finalizing,
    ),
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
  // The online voice-input mode: the new card with the Volcengine
  // credential form (dark) and the Tencent one (light), each scrolled to
  // bring the card's fields into frame.
  DesignShot(
    name: 'settings-asr-online',
    host: (theme, locale) => _settingsAsrOnlineHost(
      theme,
      locale,
      const OnlineAsrSettings(
        mode: VoiceInputMode.online,
        provider: OnlineAsrProvider.volcengineDoubao,
        volcengine: VolcengineDoubaoAsrConfig(apiKey: 'vk-demo-4f8a-9c2e-77b1'),
      ),
    ),
    act: _scrollToVoiceInputModeCard,
  ),
  DesignShot(
    name: 'settings-asr-online-tencent',
    host: (theme, locale) => _settingsAsrOnlineHost(
      theme,
      locale,
      const OnlineAsrSettings(
        mode: VoiceInputMode.online,
        provider: OnlineAsrProvider.tencentHunyuan,
        tencent: TencentHunyuanAsrConfig(
          appId: '1900000000',
          secretId: 'AKIDzrJyc0mZdB6demoExample',
          secretKey: 'c2VjcmV0S2V5RGVtbw==',
        ),
      ),
    ),
    act: _scrollToVoiceInputModeCard,
    dark: false,
  ),
  // The Subagents screen: the catalog tree (running child, settled
  // one-shot, diagnostic row) with a branch expanded, the host-error
  // banner over the crowded tree, and the one-shot read-only record.
  DesignShot(
    name: 'subagents',
    host: (theme, locale) => _subagentsHost(theme, locale, subagentsState()),
    act: (tester) async {
      // The web toggleBranch seat: expanding a node renders the branch
      // loading row in the same frame.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await settle(tester);
    },
  ),
  DesignShot(
    name: 'subagents-error',
    host: (theme, locale) =>
        _subagentsHost(theme, locale, subagentsErrorState()),
  ),
  DesignShot(
    name: 'subagents-child',
    host: (theme, locale) =>
        _subagentsHost(theme, locale, subagentsChildState()),
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
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload,
  ) async {
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

/// A spoken phrase as the capture stream reports it: one group of per-window
/// peaks per 100ms chunk. The input meter draws every band, so a still of a
/// live session reviews a sliding trail rather than one flat bar.
const List<List<double>> _kVoicePhraseBands = <List<double>>[
  [0.16, 0.62, 0.94, 0.71],
  [0.35, 0.78, 0.52, 0.24],
  [0.90, 0.66, 0.31, 0.12],
  [0.22, 0.45, 0.83, 0.58],
  [0.51, 0.29, 0.14, 0.37],
  [0.86, 0.94, 0.63, 0.40],
  [0.27, 0.15, 0.44, 0.69],
  [0.58, 0.72, 0.36, 0.19],
  [0.93, 0.47, 0.22, 0.55],
  [0.31, 0.64, 0.80, 0.42],
];

/// Voice controller that hands the dock one capture chunk per 100ms of pumped
/// time, so a shot renders a session with history instead of a mounted frame.
class _ScriptedVoiceInputController extends VoiceInputController {
  _ScriptedVoiceInputController({
    required super.manager,
    required List<VoiceInputUiState> frames,
  }) : _frames = frames,
       _current = frames.first,
       super(
         audioRecorder: MockAudioInputSource(simulatedDuration: Duration.zero),
       );

  final List<VoiceInputUiState> _frames;
  final StreamController<VoiceInputUiState> _out =
      StreamController<VoiceInputUiState>.broadcast();

  VoiceInputUiState _current;
  int _played = 0;

  /// How many capture chunks the phrase holds.
  int get frameCount => _frames.length;

  @override
  VoiceInputUiState get state => _current;

  @override
  Stream<VoiceInputUiState> get uiState => _out.stream;

  /// Hands over the next capture frame. Once the phrase is spent the session
  /// keeps whatever it last showed, as a live but silent capture does.
  void playNextFrame() {
    if (_played >= _frames.length) return;
    _current = _frames[_played++];
    if (!_out.isClosed) _out.add(_current);
  }

  void stop() => unawaited(_out.close());

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async => '';

  @override
  Future<void> cancelRecording() async {}
}

/// The scripted voice session the voice shots render. A shot's `act` callback
/// receives only the tester, so the fixture registers itself here for the
/// pumping loop to speak through.
_ScriptedVoiceInputController? _voiceSession;

/// Settles the chrome, then plays the phrase one capture chunk per pumped
/// frame: the meter's trail is made of the chunks it actually saw, so the
/// still reviews a spoken sentence rather than a couple of coalesced frames.
Future<void> _settleVoiceShot(WidgetTester tester) async {
  await settle(tester);
  final session = _voiceSession;
  if (session != null) {
    for (var i = 0; i < session.frameCount; i++) {
      session.playNextFrame();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await tester.pump();
}

/// Full-tree builder for a live voice session: a scripted capture stream so
/// the dock, its input meter and the microphone seat all render mid-session.
///
/// With [endPhase] the phrase stops short and its tail belongs to that phase,
/// carrying the same envelope — no new audio, which is what a session waiting
/// on the engine looks like: the trail runs out to the floor and the seat
/// changes its mind.
Widget _voiceRecordingHost(
  ThemeData theme,
  Locale? locale,
  bool zh, {
  VoiceInputPhase? endPhase,
}) {
  final tempDir = Directory.systemTemp.createTempSync('dsh-design-voice');
  addTearDown(() => tempDir.deleteSync(recursive: true));
  final registryFile = File('${tempDir.path}/models_registry.json');
  final registry = ModelsRegistry(registryFile: registryFile);
  unawaited(
    registry.updateEntry(
      ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '${tempDir.path}/sensevoice-small',
        status: AsrModelStatus.downloaded,
      ),
    ),
  );
  final manager = AsrModelManager(baseModelsDir: tempDir, registry: registry);

  final transcription = zh
      ? '端侧语音识别实时转写测试'
      : 'On-device speech recognition live transcription test';
  final spokenChunks = endPhase == null ? _kVoicePhraseBands.length : 7;
  final spoken = <VoiceInputUiState>[
    for (var i = 0; i < spokenChunks; i++)
      VoiceInputUiState(
        phase: VoiceInputPhase.recording,
        duration: Duration(milliseconds: 100 * (i + 1)),
        amplitude: _kVoicePhraseBands[i].reduce(max),
        envelope: _kVoicePhraseBands[i],
        liveTranscription: transcription,
        activeModel: AsrModelManifest.senseVoiceSmall,
        hasInstalledModels: true,
      ),
  ];
  final last = spoken.last;
  final frames = <VoiceInputUiState>[
    ...spoken,
    // The tail carries the same envelope object, so the meter learns no new
    // audio arrived and lets its trail run out.
    if (endPhase != null)
      for (var i = 0; i < 3; i++) last.copyWith(phase: endPhase),
  ];

  final controller = _ScriptedVoiceInputController(
    manager: manager,
    frames: frames,
  );
  _voiceSession = controller;
  addTearDown(controller.stop);

  return ProviderScope(
    overrides: [
      asrModelManagerProvider.overrideWith((ref) async => manager),
      voiceInputControllerProvider.overrideWith((ref) => controller),
      dshRpcClientProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_FakeRpc()),
      dshEventSocketProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_SilentSocket()),
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
            zh ? '请在设置中下载离线语音识别模型，即可开启端侧语音输入。' : 'Download an on-device speech recognition model in Settings to enable offline voice input.',
          ),
          actions: <Widget>[
            TextButton(onPressed: () {}, child: Text(zh ? '取消' : 'Cancel')),
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
/// The ASR settings screen with the voice-input mode card switched to the
/// [settings] provider, so the credential form under review is on screen.
Widget _settingsAsrOnlineHost(
  ThemeData theme,
  Locale? locale,
  OnlineAsrSettings settings,
) {
  const cards = <AsrModelCardState>[
    AsrModelCardState(
      info: AsrModelManifest.senseVoiceSmall,
      entry: ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '/data/models/sensevoice-small',
        status: AsrModelStatus.downloaded,
      ),
      diskUsageBytes: 237431441,
    ),
  ];

  final state = AsrModelsUiState(
    models: cards,
    defaultSource: ModelSource.hfMirror,
    installedCount: 1,
    totalCount: 5,
    activeModelId: 'sensevoice-small',
    cloud: settings,
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

/// Brings the voice-input mode card into frame: the card sits below the
/// download-source preferences, off the top of the viewport.
Future<void> _scrollToVoiceInputModeCard(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.text('Voice input mode'),
    find.byType(ListView),
    const Offset(0, -240),
  );
  await settle(tester);
}

Widget _settingsAsrHost(ThemeData theme, Locale? locale, bool zh) {
  const cards = <AsrModelCardState>[
    AsrModelCardState(
      info: AsrModelManifest.senseVoiceSmall,
      entry: ModelRegistryEntry(
        modelId: 'sensevoice-small',
        source: ModelSource.hfMirror,
        localDir: '/data/models/sensevoice-small',
        status: AsrModelStatus.downloaded,
        downloadedBytes: 237431441,
        totalBytes: 237431441,
      ),
      diskUsageBytes: 237431441,
    ),
    AsrModelCardState(
      info: AsrModelManifest.streamingZipformerZh,
      entry: ModelRegistryEntry(
        modelId: 'streaming-zipformer-zh',
        source: ModelSource.hfMirror,
        localDir: '/data/models/streaming-zipformer-zh',
        status: AsrModelStatus.idle,
      ),
    ),
    AsrModelCardState(
      info: AsrModelManifest.whisperLargeV3Turbo,
      entry: ModelRegistryEntry(
        modelId: 'whisper-large-v3-turbo',
        source: ModelSource.huggingFace,
        localDir: '/data/models/whisper-large-v3-turbo',
        status: AsrModelStatus.downloaded,
      ),
      diskUsageBytes: 1036613791,
    ),
  ];

  const state = AsrModelsUiState(
    models: cards,
    defaultSource: ModelSource.hfMirror,
    installedCount: 2,
    totalCount: 5,
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

/// Full-tree builder for the Subagents screen shots. The surface takes a
/// `SubagentUiState` and an action sink like `ChatScreen` does, so the
/// shot pumps the screen directly — no route push, no controller fake.
Widget _subagentsHost(ThemeData theme, Locale? locale, SubagentUiState state) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: _withRealFonts(theme),
    home: SubagentScreen(uiState: state, onAction: (_) {}),
  );
}

/// Full-tree builder for the multi-backend sidebar scroll shot: mounts
/// ChatScreen with multi-backend slices and the fake rpc/socket providers.
Widget _sidebarMultiBackendHost(ThemeData theme, Locale? locale) {
  final registryDir = Directory.systemTemp.createTempSync(
    'dsh-design-registry',
  );
  addTearDown(() => registryDir.deleteSync(recursive: true));
  final registryFile = File('${registryDir.path}/backends.json');
  registryFile.writeAsStringSync(kSettingsRegistryDoc);
  final stateDir = Directory.systemTemp.createTempSync('dsh-design-state');
  addTearDown(() => stateDir.deleteSync(recursive: true));
  final stateFile = File('${stateDir.path}/local_state.json');
  stateFile.writeAsStringSync('''
{
  "sidebar.groupOverrides": {
    "w1": true,
    "w2": true,
    "b1\\u0000wb1": true,
    "b2\\u0000wg1": true,
    "b2\\u0000wg2": true
  },
  "sidebar.overflowExpanded": ["w1", "w2", "b1\\u0000wb1"]
}
''');
  return ProviderScope(
    overrides: [
      backendStoreProvider.overrideWith(
        (ref) async => BackendStore(registryFile, seedBaseUrl: kDshBaseUrl),
      ),
      localStateStoreProvider.overrideWith(
        (ref) async => LocalStateStore(stateFile),
      ),
      dshRpcClientProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_FakeRpc()),
      dshEventSocketProvider(Uri.parse(kDshBaseUrl))
          .overrideWithValue(_SilentSocket()),
      for (final uri in [
        Uri.parse('http://10.0.2.2:3080'),
        Uri.parse('http://10.0.2.2:3081'),
        Uri.parse('http://10.0.2.2:3082'),
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
      home: ChatScreen(
        uiState: multiBackendDrawerState(),
        backendSlices: kCrowdedBackendSlices,
        onAction: (_) {},
      ),
    ),
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

Future<void> _render(
  WidgetTester tester,
  DesignShot shot,
  ThemeData theme,
) async {
  tester.view.physicalSize = _kPhone;
  tester.view.devicePixelRatio = _kDevicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    shot.host != null
        ? shot.host!(theme, shot.locale)
        : ProviderScope(
            overrides: [
              dshRpcClientProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_FakeRpc()),
              dshEventSocketProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_SilentSocket()),
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
