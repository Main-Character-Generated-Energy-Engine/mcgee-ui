import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/film_opening.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openai.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native opening request needs no capture and preserves localized credits',
    () async {
      final client = _OpeningApi();
      final opening = await generateFilmOpening(
        client,
        NarrationLanguage.french,
        characterName: 'Ari',
      );

      expect(opening.title, 'Le poids des petites choses');
      expect(opening.director, 'Bastien Valcour de Sève');
      expect(client.body['input'], contains('Create a new opening in French.'));
      expect(client.body['input'], contains('"Ari"'));
      expect(client.body['model'], 'openai/gpt-5.6-terra');
      expect(client.body['reasoning'], {'effort': 'high'});
      expect(client.body['max_output_tokens'], 2400);
      expect(client.body['store'], isFalse);
      expect(jsonEncode(client.body), isNot(contains('input_image')));
      expect(client.speechCalls, 0);
    },
  );

  test(
    'rejects malformed generated credits instead of displaying broken fields',
    () {
      for (final value in <Object?>[
        null,
        <String, Object?>{},
        {'title': '', 'director': 'Someone', 'narration': 'A beginning.'},
        {'title': 'A film', 'director': 4, 'narration': 'A beginning.'},
        {'title': 'A film', 'director': 'Someone', 'narration': 'x' * 901},
      ]) {
        expect(() => FilmOpening.fromJson(value), throwsFormatException);
      }
    },
  );
}

final class _OpeningApi implements OpenAiApi {
  late Map<String, Object?> body;
  int speechCalls = 0;

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    this.body = body;
    return {
      'output': [
        {
          'content': [
            {
              'type': 'output_text',
              'text': jsonEncode({
                'title': 'Le poids des petites choses',
                'director': 'Bastien Valcour de Sève',
                'narration':
                    'La vie ordinaire d’Ari mérite une attention extraordinaire.',
              }),
            },
          ],
        },
      ],
    };
  }

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) async {
    speechCalls++;
    return Uint8List.fromList([1]);
  }
}
