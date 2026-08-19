/// Composer model seat — port of the web ModelSelect (figma 496:26454):
/// a 28px pill trigger ("Model · Effort" + chevron) opening a two-level
/// menu — the Model/Effort row pair, each drilling into its own list over
/// the shared session directory.
library;

import 'package:domain/model/model_catalog.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';

class ModelSelect extends StatelessWidget {
  const ModelSelect({
    super.key,
    required this.models,
    required this.locked,
    required this.onSelect,
    required this.onRefresh,
  });

  final SessionModels? models;
  final bool locked;
  final void Function(ModelSelection selection) onSelect;
  final VoidCallback onRefresh;

  ModelSelection? get _current => models?.current;

  /// The model row containing the current selection (for effort levels).
  ModelCatalogModel? get _currentModel {
    final current = _current;
    final groups = models?.groups ?? const <ModelProviderGroup>[];
    for (final group in groups) {
      for (final model in group.models) {
        if (group.id == current?.provider && model.id == current?.model) {
          return model;
        }
      }
    }
    return null;
  }

  String get _modelLabel {
    final current = _current;
    if (current == null) return 'Model';
    final groups = models?.groups ?? const <ModelProviderGroup>[];
    for (final group in groups) {
      if (group.id != current.provider) continue;
      for (final model in group.models) {
        if (model.id == current.model) return model.name;
      }
    }
    return current.model;
  }

  String? get _effortLabel {
    final reasoning = _currentModel?.reasoning;
    if (reasoning == null) return null;
    final effective = _current?.reasoningEffort ?? reasoning.defaultEffort;
    if (effective == null) return 'Provider default';
    for (final effort in reasoning.efforts) {
      if (effort.id == effective) return effort.name;
    }
    return effective;
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final effort = _effortLabel;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: locked ? null : () => _open(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        height: 28,
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _modelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: ds.labelSecondary,
                ),
              ),
            ),
            if (effort != null) ...[
              const SizedBox(width: 4),
              Text(
                effort,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: ds.labelCaption),
              ),
            ],
            Icon(Icons.keyboard_arrow_down, size: 14, color: ds.labelCaption),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    onRefresh();
    final root = Navigator.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ModelSelectSheet(
        models: models,
        onSelect: (selection) {
          onSelect(selection);
          root.pop();
        },
      ),
    );
  }
}

/// The two-level menu (mobile bottom-sheet form of the MenuDropdown).
class _ModelSelectSheet extends StatefulWidget {
  const _ModelSelectSheet({required this.models, required this.onSelect});

  final SessionModels? models;
  final void Function(ModelSelection selection) onSelect;

  @override
  State<_ModelSelectSheet> createState() => _ModelSelectSheetState();
}

class _ModelSelectSheetState extends State<_ModelSelectSheet> {
  _Pane _pane = _Pane.root;

  @override
  Widget build(BuildContext context) {
    final models = widget.models;
    final current = models?.current;
    final reasoning = <ModelCatalogModel>[];
    ModelCatalogModel? currentModel;
    for (final group in models?.groups ?? const <ModelProviderGroup>[]) {
      for (final model in group.models) {
        reasoning.add(model);
        if (group.id == current?.provider && model.id == current?.model) {
          currentModel = model;
        }
      }
    }

    final sheet = switch (_pane) {
      _Pane.root => _rootPane(context, currentModel),
      _Pane.model => _modelPane(context),
      _Pane.effort => _effortPane(context, currentModel),
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: sheet,
        ),
      ),
    );
  }

  Widget _rootPane(BuildContext context, ModelCatalogModel? currentModel) {
    final current = widget.models?.current;
    final hasEffort = currentModel?.reasoning != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, 'Model'),
        _menuCell(
          context,
          label: 'Model',
          value: _modelLabelOf(current),
          onTap: () => setState(() => _pane = _Pane.model),
        ),
        if (hasEffort)
          _menuCell(
            context,
            label: 'Effort',
            value: _effortLabelOf(current, currentModel),
            onTap: () => setState(() => _pane = _Pane.effort),
          ),
      ],
    );
  }

  Widget _modelPane(BuildContext context) {
    final models = widget.models;
    if (models == null) {
      return _paneHeader(context, 'Model');
    }
    // models.current is a required field on SessionModels.
    final current = models.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, 'Model'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final failure in models.failures)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${failure.name}: ${failure.message}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final group in models.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    group.name,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: dsOf(context).labelSecondary),
                  ),
                ),
                for (final model in group.models)
                  _option(
                    context,
                    selected:
                        group.id == current.provider &&
                        model.id == current.model,
                    title: model.name,
                    detail: model.description,
                    onTap: () => widget.onSelect(
                      ModelSelection(
                        provider: group.id,
                        model: model.id,
                        reasoningEffort: model.reasoning?.defaultEffort,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _effortPane(BuildContext context, ModelCatalogModel? currentModel) {
    final reasoning = currentModel?.reasoning;
    final current = widget.models?.current;
    final effective = current?.reasoningEffort ?? reasoning?.defaultEffort;
    final rows = <({String? id, String label, String? detail})>[
      if (reasoning == null || reasoning.defaultEffort == null)
        (id: null, label: 'Provider default', detail: null),
      for (final effort in reasoning?.efforts ?? const <ModelReasoningEffort>[])
        (id: effort.id, label: effort.name, detail: effort.description),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, 'Effort'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final row in rows)
                _option(
                  context,
                  selected: row.id == null
                      ? effective == null
                      : effective == row.id,
                  title: row.label,
                  detail: row.detail,
                  onTap: () {
                    final selection = current;
                    if (selection == null) return;
                    widget.onSelect(
                      ModelSelection(
                        provider: selection.provider,
                        model: selection.model,
                        reasoningEffort: row.id,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paneHeader(BuildContext context, String title) {
    final canBack = _pane != _Pane.root;
    return ListTile(
      dense: true,
      leading: canBack
          ? const Icon(Icons.keyboard_arrow_left)
          : const Icon(Icons.tune),
      title: Text(title),
      onTap: canBack ? () => setState(() => _pane = _Pane.root) : null,
    );
  }

  Widget _menuCell(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: dsOf(context).labelSecondary),
          ),
          const Icon(Icons.keyboard_arrow_right, size: 16),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _option(
    BuildContext context, {
    required bool selected,
    required String title,
    String? detail,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      selected: selected,
      title: Text(title),
      subtitle: detail == null
          ? null
          : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: selected ? const Icon(Icons.check) : const SizedBox.shrink(),
      onTap: onTap,
    );
  }

  String _modelLabelOf(ModelSelection? current) {
    if (current == null) return 'Model';
    final groups = widget.models?.groups ?? const <ModelProviderGroup>[];
    for (final group in groups) {
      if (group.id != current.provider) continue;
      for (final model in group.models) {
        if (model.id == current.model) return model.name;
      }
    }
    return current.model;
  }

  String _effortLabelOf(
    ModelSelection? current,
    ModelCatalogModel? currentModel,
  ) {
    final reasoning = currentModel?.reasoning;
    if (reasoning == null) return '';
    final effective = current?.reasoningEffort ?? reasoning.defaultEffort;
    if (effective == null) return 'Provider default';
    for (final effort in reasoning.efforts) {
      if (effort.id == effective) return effort.name;
    }
    return effective;
  }
}

enum _Pane { root, model, effort }
