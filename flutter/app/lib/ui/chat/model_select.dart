/// Composer model seat — mobile adaptation of the web ModelSelect seat
/// (figma 496:26454). The web's native-select pill becomes a compact
/// circle button consistent with the composer's ➕ control; the two-level
/// Model/Effort menu becomes a menu-surface bottom sheet (the web
/// MenuDropdown form).
library;

import 'package:app/l10n/app_localizations.dart';
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

  String _modelLabel(AppLocalizations l10n) {
    final current = _current;
    if (current == null) return l10n.modelLabel;
    final groups = models?.groups ?? const <ModelProviderGroup>[];
    for (final group in groups) {
      if (group.id != current.provider) continue;
      for (final model in group.models) {
        if (model.id == current.model) return model.name;
      }
    }
    return current.model;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    return IconButton(
      // Long-press discloses the active model; the sheet carries the rest.
      tooltip: '${l10n.modelLabel}: ${_modelLabel(l10n)}',
      onPressed: locked ? null : () => _open(context),
      // The settings-style glyph (the tune vocabulary the sheet header
      // uses) — not a sparkle.
      icon: const Icon(Icons.tune, size: 22),
      // Native tool control, same family as the composer ➕: a standard
      // 40px M3 icon button on the selector fill.
      style: IconButton.styleFrom(
        backgroundColor: ds.specificSelector,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        disabledBackgroundColor: ds.specificSelector,
        disabledForegroundColor: ds.labelTertiary,
        hoverColor: ds.interactiveBgHoverSolid,
        shape: const CircleBorder(),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    onRefresh();
    final root = Navigator.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Menu-surface sheet (MenuDropdown family): menu fill, 12px radius,
      // lv3 elevation, 4px inner padding.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: _ModelSelectSheet(
              models: models,
              onSelect: (selection) {
                onSelect(selection);
                root.pop();
              },
            ),
          ),
        ),
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
    ModelCatalogModel? currentModel;
    for (final group in models?.groups ?? const <ModelProviderGroup>[]) {
      for (final model in group.models) {
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [sheet],
    );
  }

  Widget _rootPane(BuildContext context, ModelCatalogModel? currentModel) {
    final current = widget.models?.current;
    final hasEffort = currentModel?.reasoning != null;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, l10n.modelLabel),
        _menuCell(
          context,
          label: l10n.modelLabel,
          value: _modelLabelOf(current, l10n),
          onTap: () => setState(() => _pane = _Pane.model),
        ),
        if (hasEffort)
          _menuCell(
            context,
            label: l10n.effortLabel,
            value: _effortLabelOf(current, currentModel, l10n),
            onTap: () => setState(() => _pane = _Pane.effort),
          ),
      ],
    );
  }

  Widget _modelPane(BuildContext context) {
    final models = widget.models;
    final l10n = AppLocalizations.of(context)!;
    if (models == null) {
      return _paneHeader(context, l10n.modelLabel);
    }
    // models.current is a required field on SessionModels.
    final current = models.current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, l10n.modelLabel),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final failure in models.failures)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Text(
                    '${failure.name}: ${failure.message}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              for (final group in models.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
    final l10n = AppLocalizations.of(context)!;
    final effective = current?.reasoningEffort ?? reasoning?.defaultEffort;
    final rows = <({String? id, String label, String? detail})>[
      if (reasoning == null || reasoning.defaultEffort == null)
        (id: null, label: l10n.providerDefault, detail: null),
      for (final effort in reasoning?.efforts ?? const <ModelReasoningEffort>[])
        (id: effort.id, label: effort.name, detail: effort.description),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneHeader(context, l10n.effortLabel),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canBack ? () => setState(() => _pane = _Pane.root) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                canBack ? Icons.arrow_back : Icons.tune,
                size: 16,
                color: dsOf(context).labelSecondary,
              ),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCell(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: dsOf(context).labelTertiary,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: dsOf(context).labelTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required bool selected,
    required String title,
    String? detail,
    required VoidCallback onTap,
  }) {
    final ds = dsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (detail case final text?)
                      Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontSize: 12, color: ds.labelTertiary),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _modelLabelOf(ModelSelection? current, AppLocalizations l10n) {
    if (current == null) return l10n.modelLabel;
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
    AppLocalizations l10n,
  ) {
    final reasoning = currentModel?.reasoning;
    if (reasoning == null) return '';
    final effective = current?.reasoningEffort ?? reasoning.defaultEffort;
    if (effective == null) return l10n.providerDefault;
    for (final effort in reasoning.efforts) {
      if (effort.id == effective) return effort.name;
    }
    return effective;
  }
}

enum _Pane { root, model, effort }
