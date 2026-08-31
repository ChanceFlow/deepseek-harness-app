/// Tests for describeBackendError: verifying that every BackendErrorCode
/// maps to a natural, localized string in both English and Chinese, and that
/// raw error IDs or English debug text do not leak to the UI.
library;

import 'dart:ui';

import 'package:app/backends/backend_store.dart';
import 'package:app/backends/describe_backend_error.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10nEn = lookupAppLocalizations(const Locale('en'));
  final l10nZh = lookupAppLocalizations(const Locale('zh'));

  group('describeBackendError', () {
    test('maps every BackendErrorCode in both English and Chinese', () {
      for (final code in BackendErrorCode.values) {
        final en = describeBackendError(l10nEn, code);
        final zh = describeBackendError(l10nZh, code);

        expect(
          en,
          isNotEmpty,
          reason: 'English translation missing for ${code.name}',
        );
        expect(
          zh,
          isNotEmpty,
          reason: 'Chinese translation missing for ${code.name}',
        );

        // Must not return the raw enum name or ID
        expect(en, isNot(equals(code.name)));
        expect(zh, isNot(equals(code.name)));

        // English and Chinese should be different translations
        expect(
          en,
          isNot(equals(zh)),
          reason: 'Locales returned identical text for ${code.name}',
        );
      }
    });

    test('maps BackendStoreException with details in both locales', () {
      const exceptionWithDetail = BackendStoreException(
        BackendErrorCode.badBaseUrl,
        message: 'backends.json: bad baseUrl "ftp://invalid"',
        detail: 'ftp://invalid',
      );

      final en = describeBackendError(l10nEn, exceptionWithDetail);
      final zh = describeBackendError(l10nZh, exceptionWithDetail);

      expect(en, equals('Invalid host base URL: ftp://invalid'));
      expect(zh, equals('无效的主机地址：ftp://invalid'));
      expect(en, isNot(contains('backends.json:')));
      expect(zh, isNot(contains('backends.json:')));
    });

    test('maps encoded string "code:detail" in both locales', () {
      final en = describeBackendError(l10nEn, 'unknownBackend:b42');
      final zh = describeBackendError(l10nZh, 'unknownBackend:b42');

      expect(en, equals('Unknown host: b42'));
      expect(zh, equals('未知主机：b42'));
    });

    test('maps duplicateId with detail in both locales', () {
      final en = describeBackendError(l10nEn, 'duplicateId:default');
      final zh = describeBackendError(l10nZh, 'duplicateId:default');

      expect(en, equals('A host with ID “default” already exists.'));
      expect(zh, equals('已存在 ID 为“default”的主机。'));
    });

    test('maps bare code string in both locales', () {
      final en = describeBackendError(l10nEn, 'invalidJson');
      final zh = describeBackendError(l10nZh, 'invalidJson');

      expect(en, equals('Host configuration file contains invalid JSON.'));
      expect(zh, equals('主机配置文件包含无效的 JSON。'));
    });

    test('handles null and empty string safely', () {
      expect(describeBackendError(l10nEn, null), isEmpty);
      expect(describeBackendError(l10nEn, ''), isEmpty);
      expect(describeBackendError(l10nEn, '   '), isEmpty);
    });

    test('falls back gracefully for unknown error string', () {
      expect(
        describeBackendError(l10nEn, 'some custom error'),
        equals('some custom error'),
      );
    });
  });
}
