/// The localized sentence per probe class: one class, one sentence, in both
/// locales — never collapsed for display convenience. Also covers the
/// certificate remedy pointer and the status placeholder.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/dsh_reachability.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/l10n/app_localizations_en.dart';
import 'package:app/l10n/app_localizations_zh.dart';
import 'package:app/ui/settings/backend_reachability.dart';

void main() {
  final AppLocalizations en = AppLocalizationsEn();
  final AppLocalizations zh = AppLocalizationsZh();

  test('every outcome gets its own sentence in both locales', () {
    final Set<String> sentences = <String>{};
    for (final DshProbeOutcome outcome in DshProbeOutcome.values) {
      final DshProbeResult result = DshProbeResult(outcome: outcome);
      final String english = describeDshProbeResult(en, result);
      final String chinese = describeDshProbeResult(zh, result);
      expect(english, isNotEmpty, reason: '${outcome.name} (en)');
      expect(chinese, isNotEmpty, reason: '${outcome.name} (zh)');
      expect(
        chinese,
        isNot(english),
        reason: '${outcome.name} is not localized',
      );
      sentences.add(english);
    }
    // No class shares another's sentence: the classes are not collapsed.
    expect(sentences, hasLength(DshProbeOutcome.values.length));
  });

  test('a non-2xx status is named; a non-envelope body is not', () {
    expect(
      describeDshProbeResult(
        en,
        const DshProbeResult(
          outcome: DshProbeOutcome.unexpectedResponse,
          httpStatus: 502,
        ),
      ),
      'The host answered HTTP 502, which the dsh contract does not use.',
    );
    expect(
      describeDshProbeResult(
        en,
        const DshProbeResult(outcome: DshProbeOutcome.unexpectedResponse),
      ),
      en.backendProbeUnenvelopedResponse,
    );
    expect(
      describeDshProbeResult(
        zh,
        const DshProbeResult(
          outcome: DshProbeOutcome.unexpectedResponse,
          httpStatus: 502,
        ),
      ),
      contains('502'),
    );
  });

  test('the certificate class points at the per-host trust toggle', () {
    final String sentence = describeDshProbeResult(
      en,
      const DshProbeResult(outcome: DshProbeOutcome.certificateNotTrusted),
    );
    expect(sentence, contains('Trust this host'));
  });
}
