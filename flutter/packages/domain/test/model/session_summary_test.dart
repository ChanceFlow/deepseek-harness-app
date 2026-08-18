import 'package:test/test.dart';

import 'package:domain/model/session.dart';

void main() {
  test('display title uses durable title first', () {
    const session = SessionSummary(
      id: 'session-1',
      title: 'Triage issue',
      cwd: '/home/user/work',
    );

    expect(session.displayTitle, 'Triage issue');
  });

  test('display title falls back to workspace basename then id', () {
    const byPath = SessionSummary(
      id: 'session-1',
      cwd: '/home/user/checkout',
    );
    const withTrailingSeparator = SessionSummary(
      id: 'session-2',
      cwd: 'C:\\work\\checkout\\',
    );
    const withoutAncestors = SessionSummary(
      id: 'session-3',
    );

    expect(byPath.displayTitle, 'checkout');
    expect(withTrailingSeparator.displayTitle, 'checkout');
    expect(withoutAncestors.displayTitle, 'session-3');
  });
}
