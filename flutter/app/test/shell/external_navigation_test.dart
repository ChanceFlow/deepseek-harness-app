/// Same-origin stays in the page; everything else leaves for the system.
library;

import 'package:app/shell/external_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

final Uri _base = Uri.parse('http://10.0.0.5:3083');

void main() {
  test('the host origin and its paths stay in the page', () {
    expect(isExternalUrl('http://10.0.0.5:3083/', _base), isFalse);
    expect(
      isExternalUrl('http://10.0.0.5:3083/session/abc?x=1', _base),
      isFalse,
    );
  });

  test('another host, port or scheme is external', () {
    expect(isExternalUrl('http://10.0.0.6:3083/', _base), isTrue);
    expect(isExternalUrl('http://10.0.0.5:8080/', _base), isTrue);
    expect(isExternalUrl('https://10.0.0.5:3083/', _base), isTrue);
    expect(isExternalUrl('https://example.com/docs', _base), isTrue);
  });

  test('app-to-app schemes are external', () {
    expect(isExternalUrl('mailto:hi@example.com', _base), isTrue);
    expect(isExternalUrl('tel:+10000000', _base), isTrue);
    expect(
      isExternalUrl('intent://scan/#Intent;scheme=zxing;end', _base),
      isTrue,
    );
  });

  test('in-page-only schemes never leave', () {
    expect(isExternalUrl('about:blank', _base), isFalse);
    expect(isExternalUrl('data:text/html,hi', _base), isFalse);
    expect(isExternalUrl('blob:http://10.0.0.5:3083/abc', _base), isFalse);
  });

  test('a malformed URL is treated as external rather than navigated', () {
    expect(isExternalUrl('http://[::1', _base), isTrue);
  });
}
