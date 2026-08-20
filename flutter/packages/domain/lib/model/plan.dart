/// Plan collaboration state mirrored from the `plan` session projection.
library;

/// `active` is the last logged `plan/mode`; `pending` is true while a logged
/// `/plan` selection has not been recorded yet. The key's absence means the
/// plan capability is not composed on the host.
final class PlanState {
  const PlanState({required this.active, required this.pending});

  final bool active;
  final bool pending;

  @override
  bool operator ==(Object other) =>
      other is PlanState && other.active == active && other.pending == pending;

  @override
  int get hashCode => Object.hash(active, pending);
}
