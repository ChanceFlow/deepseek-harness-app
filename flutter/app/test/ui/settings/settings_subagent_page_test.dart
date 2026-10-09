/// Subagent settings tests — the two-namespace controller, its CAS fence, and
/// the pin's reject-don't-clamp guard.
library;

import 'package:app/ui/settings/settings_subagent_page.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsRepository extends ChatRepository {
  _FakeSettingsRepository(this.namespaces);

  List<SettingsNamespace> namespaces;

  /// The document's write flag; every case here writes.
  bool writable = true;
  bool refuseWrite = false;
  final List<(String, String, String, int?)> writes =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: writable,
    hasDocument: true,
    namespaces: namespaces,
    credentialRefs: const <String>[],
  );

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    writes.add((ns, key, jsonValue, expectedRevision));
    if (refuseWrite) throw StateError('refused');
    return (await describeSettings()).namespaces.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SettingsNamespace _ns(String name, Map<String, Object?> value, int revision) =>
    SettingsNamespace(
      ns: name,
      applies: SettingsApplies.live,
      revision: revision,
      hasUserLayer: false,
      secretCount: 0,
      value: value,
      schema: SettingsSchema.empty,
    );

Future<SubagentSettingsController> _controller(
  _FakeSettingsRepository repository, {
  List<SubagentModelRoute> catalog = const <SubagentModelRoute>[],
}) async {
  final controller = SubagentSettingsController(repository, catalog: catalog);
  addTearDown(controller.dispose);
  await pumpEventQueue();
  return controller;
}

void main() {
  test('a limits write carries the subagent namespace revision', () async {
    final repository = _FakeSettingsRepository(<SettingsNamespace>[
      _ns(kSubagentLimitsNamespace, <String, Object?>{
        kSubagentMaxDepthField: 2,
        kSubagentMaxActiveSubagentsField: 3,
      }, 5),
    ]);
    final controller = await _controller(repository);

    expect(controller.state.limitsExposed, isTrue);
    expect(controller.setMaxDepth('4'), isTrue);
    await controller.save();

    expect(repository.writes, <(String, String, String, int?)>[
      (kSubagentLimitsNamespace, kSubagentMaxDepthField, '4', 5),
    ]);
  });

  test('a model-selection write carries its own namespace revision', () async {
    final repository = _FakeSettingsRepository(<SettingsNamespace>[
      _ns(kSubagentModelSelectionNamespace, <String, Object?>{
        kSubagentEnabledField: false,
      }, 9),
    ]);
    final controller = await _controller(repository);

    controller.setEnabled(true);
    await controller.save();

    expect(repository.writes, <(String, String, String, int?)>[
      (kSubagentModelSelectionNamespace, kSubagentEnabledField, 'true', 9),
    ]);
  });

  test(
    'a rejected limit is refused, not clamped, and writes nothing',
    () async {
      final repository = _FakeSettingsRepository(<SettingsNamespace>[
        _ns(kSubagentLimitsNamespace, <String, Object?>{
          kSubagentMaxDepthField: 2,
          kSubagentMaxActiveSubagentsField: 3,
        }, 5),
      ]);
      final controller = await _controller(repository);

      // Below the minimum (`maxDepth` allows 0, `maxActiveSubagents` 1), a
      // negative zero, and a non-integer: every one is refused
      // (`subagent-limits-card-controller.ts:29-37`).
      expect(controller.setMaxDepth('-1'), isFalse);
      expect(controller.state.maxDepth, 2);
      expect(controller.state.rejectedField, kSubagentMaxDepthField);
      expect(controller.setMaxActiveSubagents('0'), isFalse);
      expect(controller.setMaxActiveSubagents('-0'), isFalse);
      expect(controller.state.maxActiveSubagents, 3);
      expect(controller.setMaxActiveSubagents('1e3'), isFalse);
      expect(controller.setMaxDepth('9007199254740992'), isFalse);
      expect(controller.state.maxDepth, 2);

      await controller.save();
      expect(repository.writes, isEmpty);
    },
  );

  test('an unpublished namespace stays absent and writes nothing', () async {
    final repository = _FakeSettingsRepository(<SettingsNamespace>[]);
    final controller = await _controller(repository);

    expect(controller.state.limitsExposed, isFalse);
    expect(controller.state.modelsExposed, isFalse);
    expect(controller.state.maxDepth, isNull);
    await controller.save();
    expect(repository.writes, isEmpty);
  });

  test(
    'a stored route the catalog dropped still renders, unavailable',
    () async {
      final repository = _FakeSettingsRepository(<SettingsNamespace>[
        _ns(kSubagentModelSelectionNamespace, <String, Object?>{
          kSubagentEnabledField: true,
          kSubagentAllowedModelsField: <Map<String, String>>[
            <String, String>{'provider': 'deepseek', 'model': 'gone'},
          ],
        }, 4),
      ]);
      final controller = await _controller(
        repository,
        catalog: const <SubagentModelRoute>[
          SubagentModelRoute(
            provider: 'deepseek',
            model: 'live',
            providerName: 'DeepSeek',
            modelName: 'Live Model',
          ),
        ],
      );

      expect(controller.state.allowedModels, hasLength(1));
      expect(controller.state.allowedModels.first.key, 'deepseek/gone');
      expect(controller.state.allowedModels.first.available, isFalse);
    },
  );

  test('the join keeps a dropped route, marked unavailable', () {
    const SubagentModelRoute stored = SubagentModelRoute(
      provider: 'deepseek',
      model: 'gone',
    );
    final List<SubagentModelRoute> rows = joinSubagentRoutes(
      const <SubagentModelRoute>[stored],
      const <SubagentModelRoute>[
        SubagentModelRoute(
          provider: 'deepseek',
          model: 'live',
          providerName: 'DeepSeek',
          modelName: 'Live Model',
        ),
      ],
    );

    expect(rows, hasLength(1));
    expect(rows.first.key, 'deepseek/gone');
    expect(rows.first.available, isFalse);
  });

  test('the join takes the catalog label for an advertised route', () {
    final List<SubagentModelRoute> rows = joinSubagentRoutes(
      const <SubagentModelRoute>[
        SubagentModelRoute(provider: 'deepseek', model: 'live'),
      ],
      const <SubagentModelRoute>[
        SubagentModelRoute(
          provider: 'deepseek',
          model: 'live',
          providerName: 'DeepSeek',
          modelName: 'Live Model',
        ),
      ],
    );

    expect(rows.first.available, isTrue);
    expect(rows.first.modelName, 'Live Model');
    expect(rows.first.providerName, 'DeepSeek');
  });

  test('an empty catalog strikes nothing out', () {
    final List<SubagentModelRoute> rows = joinSubagentRoutes(
      const <SubagentModelRoute>[
        SubagentModelRoute(provider: 'deepseek', model: 'gone'),
      ],
      const <SubagentModelRoute>[],
    );

    expect(rows.single.available, isTrue);
  });

  test(
    'an unavailable route is still written unchanged, never dropped',
    () async {
      final repository = _FakeSettingsRepository(<SettingsNamespace>[
        _ns(kSubagentModelSelectionNamespace, <String, Object?>{
          kSubagentEnabledField: false,
          kSubagentAllowedModelsField: <Map<String, String>>[
            <String, String>{'provider': 'deepseek', 'model': 'gone'},
          ],
        }, 6),
      ]);
      final controller = await _controller(
        repository,
        catalog: const <SubagentModelRoute>[
          SubagentModelRoute(provider: 'deepseek', model: 'live'),
        ],
      );

      expect(controller.state.allowedModels.single.available, isFalse);
      // Marking is presentation: the entry is a stored authorization, so the
      // save that follows must not touch `allowedModels` at all.
      controller.setEnabled(true);
      await controller.save();

      expect(
        repository.writes.where((w) => w.$2 == kSubagentAllowedModelsField),
        isEmpty,
      );
      expect(repository.writes, <(String, String, String, int?)>[
        (kSubagentModelSelectionNamespace, kSubagentEnabledField, 'true', 6),
      ]);
    },
  );
}
