import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/asr/asr_models_controller.dart';
import 'package:app/ui/settings/asr/asr_models_screen.dart';
import 'package:asr/asr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsrModelsScreen Widget Tests', () {
    testWidgets('renders 3 model cards and header properly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<AsrModelCardState> cards = AsrModelManifest.all.map((AsrModelInfo info) {
        return AsrModelCardState(
          info: info,
          entry: ModelRegistryEntry(
            modelId: info.id,
            source: ModelSource.modelScope,
            localDir: '/tmp/${info.id}',
            status: AsrModelStatus.idle,
          ),
        );
      }).toList();

      final AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        defaultSource: ModelSource.modelScope,
        allowCellular: false,
        installedCount: 0,
        totalCount: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(
            uiState: state,
            onAction: (_) {},
          ),
        ),
      );

      expect(find.text('ASR Models'), findsOneWidget);
      expect(find.text('SenseVoice-Small'), findsOneWidget);
      expect(find.text('Zipformer Bilingual (Streaming)'), findsOneWidget);
      expect(find.text('Whisper large-v3-turbo'), findsOneWidget);
      expect(find.text('Download'), findsNWidgets(3));
    });

    testWidgets('dispatches start download action on tap', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<AsrModelsAction> actions = <AsrModelsAction>[];
      final List<AsrModelCardState> cards = AsrModelManifest.all.map((AsrModelInfo info) {
        return AsrModelCardState(
          info: info,
          entry: ModelRegistryEntry(
            modelId: info.id,
            source: ModelSource.modelScope,
            localDir: '/tmp/${info.id}',
            status: AsrModelStatus.idle,
          ),
        );
      }).toList();

      final AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        defaultSource: ModelSource.modelScope,
        installedCount: 0,
        totalCount: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(
            uiState: state,
            onAction: actions.add,
          ),
        ),
      );

      await tester.tap(find.text('Download').first);
      await tester.pump();

      expect(actions.length, equals(1));
      expect(actions.first, isA<StartDownloadAction>());
      expect((actions.first as StartDownloadAction).modelId, equals('sensevoice-small'));
    });

    testWidgets('shows delete confirmation dialog on delete button tap', (WidgetTester tester) async {
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
            source: ModelSource.modelScope,
            localDir: '/tmp/sensevoice-small',
            status: AsrModelStatus.downloaded,
          ),
          diskUsageBytes: 154140672,
        ),
      ];

      const AsrModelsUiState state = AsrModelsUiState(
        models: cards,
        installedCount: 1,
        totalCount: 3,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: AsrModelsScreen(
            uiState: state,
            onAction: actions.add,
          ),
        ),
      );

      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete model'), findsOneWidget);
      expect(find.text('Are you sure you want to delete SenseVoice-Small? You can download it again anytime.'), findsOneWidget);

      // Tap confirm Delete inside Dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(actions.length, equals(1));
      expect(actions.first, isA<DeleteModelAction>());
      expect((actions.first as DeleteModelAction).modelId, equals('sensevoice-small'));
    });
  });
}
