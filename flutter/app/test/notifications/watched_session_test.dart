/// The watched-session fact: selection only while the Chat destination
/// covers the screen (see watched_session.dart for why the web's
/// "selected stays silent" carve-out needs the destination qualifier on
/// the phone).
library;

import 'package:app/notifications/watched_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the selected session is watched while Chat is active', () {
    expect(
      watchedSessionId(
        chatDestinationActive: true,
        selectedSessionId: 'session-a',
      ),
      'session-a',
    );
  });

  test('another active destination watches nothing', () {
    expect(
      watchedSessionId(
        chatDestinationActive: false,
        selectedSessionId: 'session-a',
      ),
      isNull,
    );
  });

  test('no selection watches nothing on any destination', () {
    expect(
      watchedSessionId(chatDestinationActive: true, selectedSessionId: null),
      isNull,
    );
    expect(
      watchedSessionId(chatDestinationActive: false, selectedSessionId: null),
      isNull,
    );
  });
}
