import 'package:flutter/foundation.dart';

Uri defaultNetlifyNarrationEndpoint() {
  const configured = String.fromEnvironment('NARRATION_API_URL');
  final endpoint = resolveNetlifyNarrationEndpoint(
    page: Uri.base,
    isDebug: kDebugMode,
    configured: configured,
  );
  if (kDebugMode) {
    debugPrint('[MCGEE] Narration backend: $endpoint'
        '${configured.isEmpty ? " (default)" : " (explicit override)"}');
  }
  return endpoint;
}

/// Local development must never silently use the deployed narration writer.
Uri resolveNetlifyNarrationEndpoint({
  required Uri page,
  required bool isDebug,
  String configured = '',
}) {
  if (configured.isNotEmpty) {
    final endpoint = Uri.parse(configured);
    if (!endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
      throw ArgumentError.value(
        configured,
        'NARRATION_API_URL',
        'Use an absolute http:// or https:// function URL.',
      );
    }
    return endpoint;
  }

  final loopback = page.host == 'localhost' ||
      page.host == '127.0.0.1' ||
      page.host == '::1';
  if (isDebug || loopback) {
    return Uri(
      scheme: 'http',
      host: loopback ? page.host : 'localhost',
      port: 8888,
      path: '/api/narrate',
    );
  }
  return page.resolve('/api/narrate');
}
