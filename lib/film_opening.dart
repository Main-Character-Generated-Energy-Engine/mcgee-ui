import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openai.dart';

/// Fictional credits and scene-independent voiceover generated before capture.
final class FilmOpening {
  const FilmOpening({
    required this.title,
    required this.director,
    required this.narration,
  });

  factory FilmOpening.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Opening must be a JSON object.');
    }
    String field(String name, int limit) {
      final text = value[name];
      if (text is! String || text.trim().isEmpty || text.length > limit) {
        throw FormatException('Invalid opening $name.');
      }
      return text.trim();
    }

    return FilmOpening(
      title: field('title', 90),
      director: field('director', 70),
      narration: field('narration', 900),
    );
  }

  final String title;
  final String director;
  final String narration;
}

final class PreparedFilmOpening {
  const PreparedFilmOpening({required this.opening, required this.track});

  final FilmOpening opening;
  final AudioTrack track;
}

Future<FilmOpening> generateFilmOpening(
  OpenAiApi client,
  NarrationLanguage language,
) async {
  final config =
      jsonDecode(
            await rootBundle.loadString('lib/assets/film-opening-prompt.json'),
          )
          as Map<String, dynamic>;
  final response = await client
      .createResponse({
        'model': config['model'],
        'reasoning': {'effort': 'high'},
        // High reasoning effort consumes this same budget before the JSON.
        'max_output_tokens': 2400,
        'store': false,
        'instructions': config['instructions'],
        'input': 'Create a new opening in ${language.englishName}.',
      })
      .timeout(const Duration(seconds: 30));
  if (response['status'] == 'incomplete' || response['error'] != null) {
    throw const FormatException('Opening generation did not complete.');
  }
  final direct = response['output_text'];
  final output = response['output'];
  if (direct is String) return FilmOpening.fromJson(jsonDecode(direct));
  final text = StringBuffer();
  if (output is List) {
    for (final item in output.whereType<Map>()) {
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content.whereType<Map>()) {
        if (part['type'] == 'output_text' && part['text'] is String) {
          text.write(part['text']);
        }
      }
    }
  }
  return FilmOpening.fromJson(jsonDecode(text.toString()));
}
