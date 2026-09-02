/// The HTTP/3 engine factory never throws outside Android and always
/// yields null there, so every host-side test surface (and CI) rides the
/// default `IOClient` path unchanged. The Android branch itself is not
/// unit-testable on this host: it is covered by the Gradle build smoke
/// (cronet-embedded packaging) and real-device grayscale, per the
/// [HTTP/3 engine decision note](../../../../.agents/notes/implemented/feature/2026-09-02-http3-cronet-engine-default.md).
library;

import 'package:app/di/http_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('non-Android host returns null (default engine fallback)', () {
    expect(dshHttp3Engine(), isNull);
  });
}
