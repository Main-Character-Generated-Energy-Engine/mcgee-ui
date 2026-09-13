Uri defaultNetlifyNarrationEndpoint() {
  const configured = String.fromEnvironment('NARRATION_API_URL');
  if (configured.isNotEmpty) return Uri.parse(configured);

  final page = Uri.base;
  if (page.host == 'localhost' || page.host == '127.0.0.1') {
    return Uri.parse('https://mcgee-narrator.netlify.app/api/narrate');
  }
  return page.resolve('/api/narrate');
}
