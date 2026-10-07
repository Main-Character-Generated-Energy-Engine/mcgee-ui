import 'package:flutter/foundation.dart';

import 'narration_diagnostics_stub.dart'
    if (dart.library.js_interop) 'narration_diagnostics_web.dart'
    as platform;

/// A snapshot of the failure, so a copied report describes the same incident
/// even if the selected voice or browser state changes afterwards.
final class NarrationDiagnostics {
  NarrationDiagnostics({
    required String stage,
    required Object error,
    required String narrator,
    required String language,
    StackTrace? stackTrace,
    String? credential,
  }) : report = redact(
         [
           'MCGEE narration report',
           'Time: ${DateTime.now().toUtc().toIso8601String()}',
           'Stage: $stage',
           'Narrator: $narrator',
           'Language: $language',
           'App: ${const String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: '0.1.0')}+${const String.fromEnvironment('FLUTTER_BUILD_NUMBER', defaultValue: '1')}',
           'Platform: ${kIsWeb ? 'web' : defaultTargetPlatform.name}',
           ...platform.browserDetails(),
           'Error: $error',
           if (stackTrace != null)
             'Stack:\n${stackTrace.toString().split('\n').take(8).join('\n')}',
         ].join('\n'),
         credential: credential,
       );

  final String report;

  static String redact(String text, {String? credential}) {
    var safe = text;
    for (final key in [
      const String.fromEnvironment('OPENROUTER_API_KEY'),
      credential ?? '',
    ]) {
      if (key.isNotEmpty) safe = safe.replaceAll(key, '[redacted]');
    }
    safe = safe
        .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]+'), '[redacted]')
        .replaceAll(
          RegExp(r'Bearer\s+[^\s"\x27,}]+', caseSensitive: false),
          'Bearer [redacted]',
        );
    return safe.length > 6000
        ? '${safe.substring(0, 6000)}\n[truncated]'
        : safe;
  }
}
