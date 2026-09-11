/// Subagent route — the widget that binds a backend's subagent controller to
/// the catalog/child screen.
///
/// It lives beside the screen rather than in it so a surface that only needs
/// to push the route (the chat workflow card's member jump) does not import
/// the whole catalog tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'subagent_controller.dart';
import 'subagent_screen.dart';
import 'subagent_ui_state.dart';

class SubagentRoute extends ConsumerWidget {
  const SubagentRoute({super.key, this.backendId});

  /// The backend this surface presents; null uses the active backend.
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved =
        backendId ?? ref.watch(activeBackendIdProvider).value ?? '';
    if (resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(subagentControllerProvider(resolved));
    return StreamBuilder<SubagentUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const SubagentUiState();
        return SubagentScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

/// A pushed subagent surface pointed at a specific parent session, and
/// optionally at one child session to open once its catalog row lands.
///
/// The controller is built and disposed here rather than through the family
/// provider: the route is the only owner of this instance, and a
/// `ProviderScope` override that re-reads the provider it overrides would
/// rebuild its own subtree without bound.
class SubagentRecordRoute extends ConsumerStatefulWidget {
  const SubagentRecordRoute({
    required this.backendId,
    required this.initialSessionId,
    super.key,
    this.initialChildId,
  });

  /// The backend whose repository backs this record view.
  final String backendId;

  /// Parent session whose catalog the route opens.
  final String initialSessionId;

  /// Child session to open once the parent's catalog carries its row.
  final String? initialChildId;

  @override
  ConsumerState<SubagentRecordRoute> createState() =>
      _SubagentRecordRouteState();
}

class _SubagentRecordRouteState extends ConsumerState<SubagentRecordRoute> {
  SubagentController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = SubagentController(
      ref.read(chatRepositoryProvider(widget.backendId)),
      initialSessionId: widget.initialSessionId,
      initialChildId: widget.initialChildId,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<SubagentUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) => SubagentScreen(
        uiState: snapshot.data ?? const SubagentUiState(),
        onAction: controller.onAction,
      ),
    );
  }
}
