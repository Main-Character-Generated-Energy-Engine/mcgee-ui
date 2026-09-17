String extractOpenAiOutputText(Map<String, Object?> response) {
  final direct = response['output_text'];
  if (direct is String && direct.isNotEmpty) return direct;

  final output = response['output'];
  if (output is List) {
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map &&
            part['type'] == 'output_text' &&
            part['text'] is String) {
          return part['text'] as String;
        }
      }
    }
  }
  throw const FormatException('OpenAI response did not contain output text');
}
