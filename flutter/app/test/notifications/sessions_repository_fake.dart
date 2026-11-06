/// Session-list-only [ChatRepository] double shared by the notification
/// tests: the notification center reads `observeSessions` and nothing else,
/// so every other member falls through to `noSuchMethod` (a test that reaches
/// one fails loudly instead of silently getting a stub answer).
library;

import 'package:app/ui/state_stream.dart';
import 'package:domain/model/session.dart';
import 'package:domain/repository/chat_repository.dart';

class SessionsRepositoryFake implements ChatRepository {
  SessionsRepositoryFake(List<SessionSummary> initial)
    : sessions = AppStateStream<List<SessionSummary>>(initial);

  final AppStateStream<List<SessionSummary>> sessions;

  @override
  Stream<List<SessionSummary>> observeSessions() => sessions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
