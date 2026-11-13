/// The shell's only state for a blocked microphone.
///
/// A host page owns its own prompt copy: the shell never injects a notice into
/// the page. When Android will no longer show the runtime-permission dialog,
/// the page cannot recover on its own, so the shell surfaces one recovery
/// affordance above it. One affordance at a time: a newer blocked host replaces
/// the newest label, and dismissing or recovering clears it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A host whose page asked for the microphone and found the permission
/// permanently denied.
@immutable
final class MicPermissionBlocked {
  const MicPermissionBlocked({required this.hostLabel});

  /// The host whose page asked, as the shell's own label for it.
  final String hostLabel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MicPermissionBlocked && other.hostLabel == hostLabel;

  @override
  int get hashCode => hostLabel.hashCode;
}

/// Holds the host block currently being recovered from, or null when no page
/// is waiting on the microphone permission.
class MicPermissionRecovery extends Notifier<MicPermissionBlocked?> {
  @override
  MicPermissionBlocked? build() => null;

  /// Reports that [hostLabel]'s page asked and its permissions are blocked.
  void reportBlocked(String hostLabel) {
    state = MicPermissionBlocked(hostLabel: hostLabel);
  }

  /// Drops the affordance: the user dismissed it, or a later ask was granted.
  void clear() {
    state = null;
  }
}

final micPermissionRecoveryProvider =
    NotifierProvider<MicPermissionRecovery, MicPermissionBlocked?>(
      MicPermissionRecovery.new,
    );
