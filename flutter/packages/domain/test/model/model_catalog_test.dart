import 'package:test/test.dart';

import 'package:domain/model/model_catalog.dart';

void main() {
  group('Model catalog models', () {
    const selA = ModelSelection(
      provider: 'openai',
      model: 'gpt-4o',
      reasoningEffort: 'high',
    );
    const selB = ModelSelection(
      provider: 'openai',
      model: 'gpt-4o',
      reasoningEffort: 'high',
    );
    const selDiff = ModelSelection(provider: 'openai', model: 'gpt-4o-mini');

    test('ModelSelection equality', () {
      expect(selA, equals(selB));
      expect(selA.hashCode, equals(selB.hashCode));
      expect(selA, equals(selA));
      expect(selA, isNot(equals(selDiff)));
    });

    const effort1 = ModelReasoningEffort(
      id: 'low',
      name: 'Low Effort',
      description: 'Quick reasoning',
    );
    const effort2 = ModelReasoningEffort(
      id: 'high',
      name: 'High Effort',
      description: 'Deep reasoning',
    );

    test('ModelReasoningEffort equality', () {
      const eCopy = ModelReasoningEffort(
        id: 'low',
        name: 'Low Effort',
        description: 'Quick reasoning',
      );
      expect(effort1, equals(eCopy));
      expect(effort1.hashCode, equals(eCopy.hashCode));
      expect(effort1, isNot(equals(effort2)));
    });

    test('ModelReasoning with efforts collection', () {
      const a = ModelReasoning(
        efforts: [effort1, effort2],
        defaultEffort: 'low',
      );
      const b = ModelReasoning(
        efforts: [effort1, effort2],
        defaultEffort: 'low',
      );
      const diff = ModelReasoning(efforts: [effort1], defaultEffort: 'low');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    const modelCat = ModelCatalogModel(
      id: 'm1',
      name: 'Model 1',
      description: 'First model',
      reasoning: ModelReasoning(defaultEffort: 'medium'),
    );

    test('ModelCatalogModel equality', () {
      const copy = ModelCatalogModel(
        id: 'm1',
        name: 'Model 1',
        description: 'First model',
        reasoning: ModelReasoning(defaultEffort: 'medium'),
      );
      const diff = ModelCatalogModel(
        id: 'm1',
        name: 'Model 1',
        description: 'First model',
      );

      expect(modelCat, equals(copy));
      expect(modelCat.hashCode, equals(copy.hashCode));
      expect(modelCat, isNot(equals(diff)));
    });

    test('ModelProviderGroup with models collection', () {
      const a = ModelProviderGroup(
        id: 'p1',
        name: 'Provider 1',
        models: [modelCat],
      );
      const b = ModelProviderGroup(
        id: 'p1',
        name: 'Provider 1',
        models: [modelCat],
      );
      const diff = ModelProviderGroup(id: 'p1', name: 'Provider 1', models: []);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('ModelCatalogFailure equality', () {
      const a = ModelCatalogFailure(id: 'f1', name: 'OpenAI', message: 'Down');
      const b = ModelCatalogFailure(id: 'f1', name: 'OpenAI', message: 'Down');
      const diff = ModelCatalogFailure(
        id: 'f1',
        name: 'OpenAI',
        message: 'Timeout',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('SessionModels with groups and failures collection equality', () {
      const a = SessionModels(
        current: selA,
        routable: true,
        groups: [
          ModelProviderGroup(id: 'p1', name: 'P1', models: [modelCat]),
        ],
        failures: [
          ModelCatalogFailure(id: 'f1', name: 'P2', message: 'Failed'),
        ],
      );
      const b = SessionModels(
        current: selA,
        routable: true,
        groups: [
          ModelProviderGroup(id: 'p1', name: 'P1', models: [modelCat]),
        ],
        failures: [
          ModelCatalogFailure(id: 'f1', name: 'P2', message: 'Failed'),
        ],
      );
      const diff = SessionModels(current: selA, routable: false);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });
  });
}
