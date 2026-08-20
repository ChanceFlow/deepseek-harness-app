/// Goal screen — Flutter port of the legacy GoalScreen.kt.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/goal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'goal_ui_state.dart';

class GoalRoute extends ConsumerWidget {
  const GoalRoute({super.key, this.backendId});

  /// The backend this surface presents; null uses the active backend.
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved =
        backendId ?? ref.watch(activeBackendIdProvider).value ?? '';
    if (resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(goalControllerProvider(resolved));
    return StreamBuilder<GoalUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const GoalUiState();
        return GoalScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

/// Phase label rendered under the objective; wire phase names map to
/// localized copy.
String goalPhaseLabel(GoalPhase phase, AppLocalizations l10n) =>
    switch (phase) {
      GoalPhase.active => l10n.goalPhaseActive,
      GoalPhase.paused => l10n.goalPhasePaused,
      GoalPhase.blocked => l10n.goalPhaseBlocked,
      GoalPhase.complete => l10n.goalPhaseComplete,
    };

class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key, required this.uiState, required this.onAction});

  final GoalUiState uiState;
  final void Function(GoalAction) onAction;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final TextEditingController _objectiveController = TextEditingController();
  final TextEditingController _maxRoundsController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  String? _editingObjective;
  String? _editingGoalId;

  @override
  void didUpdateWidget(covariant GoalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compose remembered editingObjective keyed by goal id.
    final goalId = widget.uiState.goal?.goal.id;
    if (goalId != _editingGoalId) {
      _editingGoalId = goalId;
      _editingObjective = null;
    }
  }

  @override
  void dispose() {
    _objectiveController.dispose();
    _maxRoundsController.dispose();
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final goal = uiState.goal;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.goalTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (uiState.errorMessage case final error?)
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.sessionLabel,
                        style: theme.textTheme.labelLarge),
                  ),
                  OutlinedButton(
                    onPressed: uiState.selectedSessionId != null
                        ? () => widget.onAction(const RefreshGoalAction())
                        : null,
                    child: Text(l10n.refresh),
                  ),
                ],
              ),
              SizedBox(
                height: 150,
                child: ListView(
                  children: [
                    for (final session in uiState.sessions)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: session.id == uiState.selectedSessionId
                              ? null
                              : () => widget.onAction(
                                  SelectGoalSession(session.id),
                                ),
                          child: Text(session.displayTitle),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (goal == null) ...[
                Text(l10n.noCurrentGoal, style: theme.textTheme.titleSmall),
                TextField(
                  controller: _objectiveController,
                  decoration: InputDecoration(
                    hintText: l10n.goalObjectiveHint,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _maxRoundsController,
                        decoration: InputDecoration(
                          hintText: l10n.maxGoalRoundsHint,
                          isDense: true,
                        ),
                        onChanged: (text) {
                          final filtered = text.replaceAll(RegExp(r'\D'), '');
                          _maxRoundsController.text = filtered;
                          _maxRoundsController.selection =
                              TextSelection.collapsed(offset: filtered.length);
                          setState(() {});
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilledButton(
                        onPressed:
                            _objectiveController.text.trim().isNotEmpty &&
                                uiState.selectedSessionId != null
                            ? () => widget.onAction(
                                CreateGoalAction(
                                  _objectiveController.text,
                                  int.tryParse(_maxRoundsController.text),
                                ),
                              )
                            : null,
                        child: Text(l10n.create),
                      ),
                    ),
                  ],
                ),
              ] else
                ..._goalBody(context, goal),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _goalBody(BuildContext context, GoalProjection goal) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final snapshot = goal.goal;
    final editing = _editingObjective;
    if (editing == null) {
      return [
        Text(snapshot.objective, style: theme.textTheme.titleMedium),
        Text(
          l10n.goalStatusLine(
            snapshot.maxGoalRounds,
            goalPhaseLabel(snapshot.phase, l10n),
            snapshot.revision,
            goal.roundsStarted,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Wrap(
          children: [
            switch (snapshot.phase) {
              GoalPhase.active => FilledButton(
                onPressed: () => widget.onAction(const PauseGoalAction()),
                child: Text(l10n.pause),
              ),
              GoalPhase.paused || GoalPhase.blocked => FilledButton(
                onPressed: () => widget.onAction(const ResumeGoalAction()),
                child: Text(l10n.resume),
              ),
              GoalPhase.complete => FilledButton(
                onPressed: () => widget.onAction(const ClearGoalAction()),
                child: Text(l10n.clear),
              ),
            },
            if (snapshot.phase != GoalPhase.complete)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton(
                  onPressed: () => widget.onAction(const CompleteGoalAction()),
                  child: Text(l10n.complete),
                ),
              ),
            if (snapshot.phase != GoalPhase.complete)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _editController.text = snapshot.objective;
                    _editingObjective = snapshot.objective;
                  }),
                  child: Text(l10n.edit),
                ),
              ),
            // Deleting works from any phase (web GoalBar trash /
            // `/goal clear` semantics) — not only off a completed goal.
            if (snapshot.phase != GoalPhase.complete)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton(
                  onPressed: () => widget.onAction(const ClearGoalAction()),
                  child: Text(l10n.clear),
                ),
              ),
          ],
        ),
      ];
    }
    return [
      TextField(
        controller: _editController,
        decoration: InputDecoration(
          labelText: l10n.goalObjectiveHint,
          isDense: true,
        ),
        onChanged: (text) => setState(() => _editingObjective = text),
      ),
      Wrap(
        children: [
          FilledButton(
            onPressed: _editController.text.trim().isNotEmpty
                ? () {
                    widget.onAction(EditGoalAction(_editController.text));
                    setState(() => _editingObjective = null);
                  }
                : null,
            child: Text(l10n.save),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton(
              onPressed: () => setState(() => _editingObjective = null),
              child: Text(l10n.cancel),
            ),
          ),
        ],
      ),
    ];
  }
}
