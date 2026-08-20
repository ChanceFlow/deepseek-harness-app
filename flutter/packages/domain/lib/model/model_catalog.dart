/// Model catalog vocabulary for the models screen.
library;

final class ModelSelection {
  const ModelSelection({
    required this.provider,
    required this.model,
    this.reasoningEffort,
  });

  final String provider;
  final String model;
  final String? reasoningEffort;

  @override
  bool operator ==(Object other) =>
      other is ModelSelection &&
      other.provider == provider &&
      other.model == model &&
      other.reasoningEffort == reasoningEffort;

  @override
  int get hashCode => Object.hash(provider, model, reasoningEffort);
}

final class ModelReasoningEffort {
  const ModelReasoningEffort({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is ModelReasoningEffort &&
      other.id == id &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);
}

final class ModelReasoning {
  const ModelReasoning({
    this.efforts = const <ModelReasoningEffort>[],
    this.defaultEffort,
  });

  final List<ModelReasoningEffort> efforts;
  final String? defaultEffort;

  @override
  bool operator ==(Object other) =>
      other is ModelReasoning &&
      _listEquals(other.efforts, efforts) &&
      other.defaultEffort == defaultEffort;

  @override
  int get hashCode => Object.hash(Object.hashAll(efforts), defaultEffort);
}

final class ModelCatalogModel {
  const ModelCatalogModel({
    required this.id,
    required this.name,
    this.description,
    this.reasoning,
  });

  final String id;
  final String name;
  final String? description;
  final ModelReasoning? reasoning;

  @override
  bool operator ==(Object other) =>
      other is ModelCatalogModel &&
      other.id == id &&
      other.name == name &&
      other.description == description &&
      other.reasoning == reasoning;

  @override
  int get hashCode => Object.hash(id, name, description, reasoning);
}

final class ModelProviderGroup {
  const ModelProviderGroup({
    required this.id,
    required this.name,
    this.models = const <ModelCatalogModel>[],
  });

  final String id;
  final String name;
  final List<ModelCatalogModel> models;

  @override
  bool operator ==(Object other) =>
      other is ModelProviderGroup &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.models, models);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(models));
}

final class ModelCatalogFailure {
  const ModelCatalogFailure({
    required this.id,
    required this.name,
    required this.message,
  });

  final String id;
  final String name;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ModelCatalogFailure &&
      other.id == id &&
      other.name == name &&
      other.message == message;

  @override
  int get hashCode => Object.hash(id, name, message);
}

final class SessionModels {
  const SessionModels({
    required this.current,
    required this.routable,
    this.groups = const <ModelProviderGroup>[],
    this.failures = const <ModelCatalogFailure>[],
  });

  final ModelSelection current;
  final bool routable;
  final List<ModelProviderGroup> groups;
  final List<ModelCatalogFailure> failures;

  @override
  bool operator ==(Object other) =>
      other is SessionModels &&
      other.current == current &&
      other.routable == routable &&
      _listEquals(other.groups, groups) &&
      _listEquals(other.failures, failures);

  @override
  int get hashCode => Object.hash(
    current,
    routable,
    Object.hashAll(groups),
    Object.hashAll(failures),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
