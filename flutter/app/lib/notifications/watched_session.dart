/// The "user is watching" fact behind the selected-session silence rules.
///
/// The web's carve-out — a selected session's own turn completing is
/// silent — assumes the conversation pane is always on screen next to the
/// sidebar. The phone's destinations are not: Chat, Workspaces, and
/// Settings are exclusive full-screen surfaces, so the selected session
/// completes unwatched whenever the user is reading another destination.
/// Both silence rules (the foreground toast channel and the
/// working-notification suppression) read this fact instead of the raw
/// selection, so a turn finishing in the selected session while the user
/// browses Workspaces or Settings still surfaces.
library;

/// The session the user is actually watching: the chat controller's
/// selection only while the Chat destination covers the screen; null when
/// another destination does (the conversation still exists but is not
/// visible, so nothing about it is "already being watched").
String? watchedSessionId({
  required bool chatDestinationActive,
  required String? selectedSessionId,
}) => chatDestinationActive ? selectedSessionId : null;
