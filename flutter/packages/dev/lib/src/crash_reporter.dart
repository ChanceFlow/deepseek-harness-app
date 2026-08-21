// ignore_for_file: prefer_initializing_formals

/// Crash reporter — POSTs a captured bundle to the intake server.
///
/// Uses `package:http` with an injectable [http.Client] so tests can assert
/// the exact wire payload (method, path, headers, body JSON) against the
/// real [CrashBundleWire.toJson] shape without a live server.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'crash_bundle.dart';

class CrashReporter {
  CrashReporter({required Uri intakeUrl, http.Client? httpClient})
    : _intakeUrl = intakeUrl,
      _httpClient = httpClient ?? http.Client();

  final Uri _intakeUrl;
  final http.Client _httpClient;

  static const _path = 'api/crash';
  static const _timeout = Duration(seconds: 15);

  /// POST the bundle; returns true when the intake accepted it (2xx).
  /// Never throws for network/5xx — a failed report must not crash the app
  /// it is trying to save. The caller decides what to do on false.
  Future<bool> report(CrashBundleWire bundle) async {
    try {
      final response = await _httpClient
          .post(
            _intakeUrl.resolve(_path),
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(bundle.toJson()),
          )
          .timeout(_timeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}