import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/film_opening.dart';
import 'package:mcgee/narrator_profile.dart';
import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openai.dart';

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
      expect(client.body['reasoning'], {'effort': 'medium'});
      expect(client.body['max_output_tokens'], 1200);
      expect(client.body['store'], isFalse);
      expect(jsonEncode(client.body), isNot(contains('input_image')));
    },
  );

  test('every narrator sends its own opener and accepts mode point of view', () async {
    final profiles = await loadNarratorProfiles();
    final examples = <String, String>{
      'morgan-freeman': 'I remembered Ari searching for the words; his pride had made an apology difficult.',
      'david-attenborough': 'Nature conserves energy. Ari is one human animal whose next demand tests those reserves.',
      'jade': "Ari faces a decision crisis. We're turning now to the live feed.",
    };
    for (final entry in examples.entries) {
      final api = _OpeningApi(narration: entry.value);
      final opening = await generateFilmOpening(
        api,
        NarrationLanguage.english,
        characterName: 'Ari',
        profile: profiles[entry.key],
      );
      expect(opening.narration, entry.value);
      expect(api.responseCalls, 1);
      expect(api.body['instructions'], contains(profiles[entry.key]!.openingInstructions));
      expect(api.body['instructions'], isNot(contains('No personal pronouns')));
    }
  });

  test(
    'rejects malformed generated credits instead of displaying broken fields',
    () {
      for (final value in <Object?>[
        null,
        <String, Object?>{},
        {'title': '', 'director': 'Someone', 'narration': 'A beginning.'},
        {'title': 'A film', 'director': 4, 'narration': 'A beginning.'},
      ]) {
        expect(() => FilmOpening.fromJson(value), throwsFormatException);
      }
    },
  );

  test('does not reject an opening for exceeding a prose length target', () {
    final narration = 'A' * 901;
    final opening = FilmOpening.fromJson({
      'title': 'A film',
      'director': 'Someone',
      'narration': narration,
    });
    expect(opening.narration, narration);
  });
}

final class _OpeningApi implements OpenAiApi {
  _OpeningApi({this.narration = 'La vie ordinaire d’Ari mérite une attention extraordinaire.'});

  final String narration;
  int responseCalls = 0;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    this.body = body;
    responseCalls++;
    return {
      'output': [
        {
          'content': [
            {
              'type': 'output_text',
              'text': jsonEncode({
                'title': 'Le poids des petites choses',
                'director': 'Bastien Valcour de Sève',
                'narration': narration,
              }),
            },
          ],
        },
      ],
    };
  }
}
