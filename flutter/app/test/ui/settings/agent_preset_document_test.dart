/// Agent-preset declaration page: the read's YAML lands as a selectable
/// document, and a refused read states itself instead of an empty card.
library;

import 'package:app/di/providers.dart';
import 'package:app/ui/settings/agent_preset_document.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const String _backendId = 'default';

class _FixedScope extends SettingsBackendScope {
  @override
  String build() => _backendId;
}

class _FakeRepository extends Fake implements ChatRepository {
  _FakeRepository(this.read);

  final Future<AgentPresetDocument> Function() read;

  @override
  Future<AgentPresetDocument> readAgentPreset(String agentPreset) => read();
}

const AgentPresetDocument _document = AgentPresetDocument(
  agentPreset: 'standard',
  name: 'Standard',
  description: 'The default toolchain.',
  content: '- id: tool-bash\n  name: "@deepseek-ai/dsh-tool-bash"\n',
);

Future<void> _pump(
  WidgetTester tester, {
  required ChatRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider(_backendId).overrideWithValue(repository),
        settingsBackendScopeProvider.overrideWith(_FixedScope.new),
      ],
      child: l10nApp(
        home: const SettingsAgentPresetDocumentPage(
          agentPreset: 'standard',
          label: 'standard',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the published name, sentence and declaration', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository(() async => _document));

    // The published name takes the bar once the read lands.
    expect(find.text('Standard'), findsWidgets);
    expect(find.text('The default toolchain.'), findsOneWidget);
    expect(find.textContaining('dsh-tool-bash'), findsOneWidget);
    // The heading renders its intro only: the bar carries the title.
    expect(
      find.textContaining('child plugin list this preset declares'),
      findsOneWidget,
    );
  });

  testWidgets('a refused read states it and keeps the roster label', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        () => throw const RepositoryFailure(
          'agent-preset/not-found',
          'Unknown agent preset: standard',
        ),
      ),
    );

    expect(
      find.text('The declaration could not be read from this host.'),
      findsOneWidget,
    );
    expect(find.text('standard'), findsWidgets);
  });
}
