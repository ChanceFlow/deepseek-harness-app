/// Goal screen — Flutter port of the legacy GoalScreen.kt.
library;

import 'package:domain/model/goal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'goal_ui_state.dart';

class GoalRoute extends ConsumerWidget {
  const GoalRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(goalControllerProvider);
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

/// Kotlin enum toString renders the declaration name (uppercase).
String goalPhaseLabel(GoalPhase phase) => switch (phase) {
  GoalPhase.active => 'ACTIVE',
  GoalPhase.paused => 'PAUSED',
  GoalPhase.blocked => 'BLOCKED',
  GoalPhase.complete => 'COMPLETE',
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
    final goal = uiState.goal;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Goal', style: theme.textTheme.titleLarge),
              if (uiState.errorMessage case final error?)
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              Row(
                children: [
                  Expanded(
                    child: Text('Session', style: theme.textTheme.labelLarge),
                  ),
                  OutlinedButton(
                    onPressed: uiState.selectedSessionId != null
                        ? () => widget.onAction(const RefreshGoalAction())
                        : null,
                    child: const Text('Refresh'),
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
                Text('No current goal', style: theme.textTheme.titleSmall),
                TextField(
                  controller: _objectiveController,
                  decoration: const InputDecoration(
                    hintText: 'Goal objective',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _maxRoundsController,
                        decoration: const InputDecoration(
                          hintText: 'Max goal rounds (optional)',
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
                        child: const Text('Create'),
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
    final snapshot = goal.goal;
    final editing = _editingObjective;
    if (editing == null) {
      return [
        Text(snapshot.objective, style: theme.textTheme.titleMedium),
        Text(
          '${goalPhaseLabel(snapshot.phase)} · revision ${snapshot.revision} · '
          'rounds ${goal.roundsStarted}/${snapshot.maxGoalRounds}',
          style: theme.textTheme.bodySmall,
        ),
        Wrap(
          children: [
            switch (snapshot.phase) {
              GoalPhase.active => FilledButton(
                onPressed: () => widget.onAction(const PauseGoalAction()),
                child: const Text('Pause'),
              ),
              GoalPhase.paused || GoalPhase.blocked => FilledButton(
                onPressed: () => widget.onAction(const ResumeGoalAction()),
                child: const Text('Resume'),
              ),
              GoalPhase.complete => FilledButton(
                onPressed: () => widget.onAction(const ClearGoalAction()),
                child: const Text('Clear'),
              ),
            },
            if (snapshot.phase != GoalPhase.complete)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton(
                  onPressed: () => widget.onAction(const CompleteGoalAction()),
                  child: const Text('Complete'),
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
                  child: const Text('Edit'),
                ),
              ),
          ],
        ),
      ];
    }
    return [
      TextField(
        controller: _editController,
        decoration: const InputDecoration(
          labelText: 'Goal objective',
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
            child: const Text('Save'),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton(
              onPressed: () => setState(() => _editingObjective = null),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    ];
  }
}
