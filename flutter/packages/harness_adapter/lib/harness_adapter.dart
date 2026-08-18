/// Barrel export for the harness adapter.
///
/// The adapter is the only package that understands the dsh wire protocol;
/// UI code must import `domain` instead.
library;

export 'src/dsh_connection_manager.dart';
export 'src/harness_repository_impl.dart';
export 'src/rpc_map.dart';
export 'src/state_stream.dart';
export 'src/timeline_reducer.dart';
export 'src/wire_json.dart';
