/// Debug-build tooling package (dev).
///
/// Only ever wired in on debug builds: the app's `main()` guards the
/// bootstrap call with `kDebugMode`, and the bootstrap itself refuses to
/// install hooks in release mode.
library;

export 'src/bootstrap.dart';
export 'src/build_info.dart';
export 'src/crash_marker.dart';
export 'src/crash_record.dart';
export 'src/frame_stats.dart';
export 'src/frame_tracker.dart';
export 'src/log_buffer.dart';
export 'src/telemetry.dart';