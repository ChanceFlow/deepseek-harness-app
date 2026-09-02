import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/asr/asr_models_controller.dart';
import 'package:app/ui/settings/asr/asr_models_screen.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsrModelsScreen Widget Tests', () {
    testWidgets('renders 4 downloadable model cards and header properly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The controller only surfaces downloadable models for a fresh user
      // (uninstalled discontinued entries are hidden), so build from the
      // same view of the manifest.
      final List<AsrModelCardState> cards = AsrModelManifest.downloadable.map((
        AsrModelInfo info,
      ) {
        return AsrModelCardState(
          info: info,
          entry: ModelRegistryEntry(
            modelId: info.id,
            source: ModelSource.hfMirror,
            localDir: '/tmp/${info.id}',
            status: AsrModelStatus.idle,
          ),
        );
      }).toList();

      final AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        defaultSource: ModelSource.hfMirror,
        allowCellular: false,
        installedCount: 0,
        totalCount: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(uiState: state, onAction: (_) {}),
        ),
      );

      expect(find.text('ASR Models'), findsOneWidget);
      expect(find.text('SenseVoice-Small'), findsOneWidget);
      expect(find.text('Fun-ASR-Nano 2512 (CTC)'), findsOneWidget);
      expect(find.text('Zipformer 中文流式 (2025)'), findsOneWidget);
      expect(find.text('Zipformer 多语种流式'), findsOneWidget);
      expect(find.text('Paraformer Bilingual (Streaming)'), findsNothing);
      expect(find.text('Whisper large-v3-turbo'), findsNothing);
      expect(find.text('Download'), findsNWidgets(4));
    });

    testWidgets('dispatches start download action on tap', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<AsrModelsAction> actions = <AsrModelsAction>[];
      final List<AsrModelCardState> cards = AsrModelManifest.downloadable.map((
        AsrModelInfo info,
      ) {
        return AsrModelCardState(
          info: info,
          entry: ModelRegistryEntry(
            modelId: info.id,
            source: ModelSource.hfMirror,
            localDir: '/tmp/${info.id}',
            status: AsrModelStatus.idle,
          ),
        );
      }).toList();

      final AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        defaultSource: ModelSource.hfMirror,
        installedCount: 0,
        totalCount: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(uiState: state, onAction: actions.add),
        ),
      );

      await tester.tap(find.text('Download').first);
      await tester.pump();

      expect(actions.length, equals(1));
      expect(actions.first, isA<StartDownloadAction>());
      expect(
        (actions.first as StartDownloadAction).modelId,
        equals('sensevoice-small'),
      );
    });

    testWidgets('shows delete confirmation dialog on delete button tap', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<AsrModelsAction> actions = <AsrModelsAction>[];
      const List<AsrModelCardState> cards = <AsrModelCardState>[
        AsrModelCardState(
          info: AsrModelManifest.senseVoiceSmall,
          entry: ModelRegistryEntry(
            modelId: 'sensevoice-small',
            source: ModelSource.hfMirror,
            localDir: '/tmp/sensevoice-small',
            status: AsrModelStatus.downloaded,
          ),
          diskUsageBytes: 154140672,
        ),
      ];

      const AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        installedCount: 1,
        totalCount: 4,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(uiState: state, onAction: actions.add),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete model'), findsOneWidget);
      expect(
        find.text(
          'Are you sure you want to delete SenseVoice-Small? You can download it again anytime.',
        ),
        findsOneWidget,
      );

      // Tap confirm Delete inside Dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(actions.length, equals(1));
      expect(actions.first, isA<DeleteModelAction>());
      expect(
        (actions.first as DeleteModelAction).modelId,
        equals('sensevoice-small'),
      );
    });

    testWidgets(
      'renders active speech model section when models are downloaded',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const List<AsrModelCardState> cards = <AsrModelCardState>[
          AsrModelCardState(
            info: AsrModelManifest.senseVoiceSmall,
            entry: ModelRegistryEntry(
              modelId: 'sensevoice-small',
              source: ModelSource.hfMirror,
              localDir: '/tmp/sensevoice-small',
              status: AsrModelStatus.downloaded,
            ),
            diskUsageBytes: 237431441,
          ),
        ];

        const AsrModelsUiState state = AsrModelsUiState(
          models: cards,
          installedCount: 1,
          totalCount: 4,
          activeModelId: 'sensevoice-small',
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: AsrModelsScreen(uiState: state, onAction: (_) {}),
          ),
        );

        expect(find.text('Active speech model'), findsOneWidget);
      },
    );

    testWidgets(
      'discontinued installed model shows local-only chip without download',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // An installed copy of a discontinued model (e.g. Whisper carried
        // over from an older release) stays visible, deletable, and — per
        // the active-model selector — usable, but must not offer Download.
        const List<AsrModelCardState> cards = <AsrModelCardState>[
          AsrModelCardState(
            info: AsrModelManifest.whisperLargeV3Turbo,
            entry: ModelRegistryEntry(
              modelId: 'whisper-large-v3-turbo',
              source: ModelSource.hfMirror,
              localDir: '/tmp/whisper-large-v3-turbo',
              status: AsrModelStatus.downloaded,
            ),
            diskUsageBytes: 1036613791,
          ),
        ];

        const AsrModelsUiState state = AsrModelsUiState(
          models: cards,
          installedCount: 1,
          totalCount: 4,
          activeModelId: 'whisper-large-v3-turbo',
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: AsrModelsScreen(uiState: state, onAction: (_) {}),
          ),
        );

        expect(
          find.text('Whisper large-v3-turbo'),
          findsNWidgets(2),
          reason: 'card title + active-model selector row',
        );
        expect(find.text('Discontinued · local copy only'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Download'), findsNothing);
      },
    );
  });

  group('AsrOnlineSettingsCard', () {
    Future<void> pumpCard(
      WidgetTester tester,
      AsrModelsUiState state,
      void Function(AsrModelsAction) onAction,
    ) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(uiState: state, onAction: onAction),
        ),
      );
    }

    testWidgets('shows the mode card with offline selected by default', (
      WidgetTester tester,
    ) async {
      await pumpCard(
        tester,
        const AsrModelsUiState(cloud: OnlineAsrSettings()),
        (_) {},
      );

      expect(find.text('Voice input mode'), findsOneWidget);
      expect(find.text('On-device'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      // Provider radios only surface once online is selected.
      expect(find.text('Volcengine · Doubao'), findsNothing);
    });

    testWidgets('online mode reveals provider radios and credential forms', (
      WidgetTester tester,
    ) async {
      await pumpCard(
        tester,
        const AsrModelsUiState(
          cloud: OnlineAsrSettings(
            mode: VoiceInputMode.online,
            provider: OnlineAsrProvider.volcengineDoubao,
            volcengine: VolcengineDoubaoAsrConfig(apiKey: 'k-test'),
          ),
        ),
        (_) {},
      );

      expect(find.text('Volcengine · Doubao'), findsOneWidget);
      expect(find.text('Tencent Cloud · Hunyuan'), findsOneWidget);
      expect(find.text('API Key'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('switching to online dispatches the mode action', (
      WidgetTester tester,
    ) async {
      final List<AsrModelsAction> actions = <AsrModelsAction>[];
      await pumpCard(
        tester,
        const AsrModelsUiState(cloud: OnlineAsrSettings()),
        actions.add,
      );

      await tester.tap(find.text('Online'));
      await tester.pump();

      expect(actions, contains(isA<SetVoiceInputModeAction>()));
    });

    testWidgets('tencent form exposes its three credential fields', (
      WidgetTester tester,
    ) async {
      await pumpCard(
        tester,
        const AsrModelsUiState(
          cloud: OnlineAsrSettings(
            mode: VoiceInputMode.online,
            provider: OnlineAsrProvider.tencentHunyuan,
          ),
        ),
        (_) {},
      );

      expect(find.text('AppID'), findsOneWidget);
      expect(find.text('SecretId'), findsOneWidget);
      expect(find.text('SecretKey'), findsOneWidget);
      expect(
        find.textContaining('Hy-ASR-3.0-preview'),
        findsWidgets,
        reason: 'the engine id and preview limits are named in the form',
      );
    });
  });
}
