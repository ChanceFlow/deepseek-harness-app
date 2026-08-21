/// Debug-build crash capture package (dev).
///
/// Only ever wired in on debug builds: the app's `main()` guards the
/// bootstrap call with `kDebugMode`, and the bootstrap itself refuses to
/// install hooks in release mode.
library;

export 'src/crash_bundle.dart';
export 'src/crash_marker.dart';
export 'src/crash_reporter.dart';
export 'src/dev_crash_bootstrap.dart';
export 'src/log_buffer.dart';