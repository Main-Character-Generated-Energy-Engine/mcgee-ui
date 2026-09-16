import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/netlify_narration_endpoint.dart';

void main() {
  test('local Flutter pages use the local function server in every mode', () {
    for (final host in ['localhost', '127.0.0.1', '::1']) {
      for (final isDebug in [true, false]) {
        final endpoint = resolveNetlifyNarrationEndpoint(
          page: Uri(scheme: 'http', host: host, port: 54321),
          isDebug: isDebug,
        );
        expect(endpoint.host, host);
        expect(endpoint.port, 8888);
        expect(endpoint.path, '/api/narrate');
      }
    }
  });

  test('debug builds never default to a deployed backend', () {
    final endpoint = resolveNetlifyNarrationEndpoint(
      page: Uri.parse('https://mcgee-narrator.netlify.app/'),
      isDebug: true,
    );
    expect(endpoint.toString(), 'http://localhost:8888/api/narrate');
  });

  test('deployed release builds use their own origin including previews', () {
    final endpoint = resolveNetlifyNarrationEndpoint(
      page: Uri.parse('https://preview--mcgee-narrator.netlify.app/film'),
      isDebug: false,
    );
    expect(endpoint.toString(),
        'https://preview--mcgee-narrator.netlify.app/api/narrate');
  });

  test('a remote backend requires an explicit development override', () {
    final endpoint = resolveNetlifyNarrationEndpoint(
      page: Uri.parse('http://localhost:54321/'),
      isDebug: true,
      configured: 'https://mcgee-narrator.netlify.app/api/narrate',
    );
    expect(endpoint.toString(),
        'https://mcgee-narrator.netlify.app/api/narrate');
  });

  test('relative and unsupported overrides fail instead of choosing a backend', () {
    for (final configured in ['/api/narrate', 'localhost:8888', 'file:///api']) {
      expect(
        () => resolveNetlifyNarrationEndpoint(
          page: Uri.parse('http://localhost:54321/'),
          isDebug: true,
          configured: configured,
        ),
        throwsArgumentError,
      );
    }
  });
}
