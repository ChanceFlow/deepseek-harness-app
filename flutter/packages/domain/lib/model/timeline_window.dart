/// Neutral paginated timeline window consumed by the chat screen.
///
/// The app never learns how pages are fetched; it only renders this window
/// and emits an action when the user asks for older history.
library;

import 'timeline_item.dart';

final class TimelineWindow {
  const TimelineWindow({
    this.items = const <TimelineItem>[],
    this.hasMoreOlder = false,
    this.isLoadingOlder = false,
    this.isLoading = false,
  });

  final List<TimelineItem> items;
  final bool hasMoreOlder;
  final bool isLoadingOlder;

  /// The session's first full load (or a reconnect resync) is in flight.
  /// Distinguishes "nothing loaded yet" from "nothing to show": the UI
  /// renders a loading indicator instead of an empty hero while true.
  final bool isLoading;
}
