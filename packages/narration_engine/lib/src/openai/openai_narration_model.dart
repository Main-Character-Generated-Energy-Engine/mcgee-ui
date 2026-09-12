import 'dart:convert';

import '../core/contracts.dart';
import '../core/models.dart';
import 'openai_http_client.dart';
import 'openai_response_parsing.dart';

final class OpenAiNarrationModel implements NarrationModel {
  const OpenAiNarrationModel({
    required this.client,
    this.model = 'gpt-4.1-mini',
    this.requireSpokenLine = false,
  });

  final OpenAiApi client;
  final String model;
  final bool requireSpokenLine;

  @override
  Future<NarrationDraft> narrate(NarrationRequest request) async {
    final milestoneInstruction = requireSpokenLine
        ? 'This is a one-line offline demo: choose speak, not silence.'
        : 'Silence is a successful choice when the moment does not earn a line.';
    final response = await client.createResponse({
      'model': model,
      'max_output_tokens': 400,
      'store': false,
      'instructions':
          '''
You are the final writer for a restrained, premium nature documentary about an
ordinary person's day. $milestoneInstruction Write dry, precise observational
wit with affectionate dramatic distance. Stay grounded in the literal scene.
Avoid stock nature-documentary language, generic grandeur, forced metaphors,
and repetition. In particular, avoid "natural habitat", "majestic creature",
"the specimen", "ancient ritual", and "little does it know". Do not force every
action into a ritual, migration, hunt, or struggle. Understatement is welcome.
A spoken line must be one sentence of at most 24 words, with no stage directions.
Return an empty text when choosing silence. Motifs are terse labels for comic
devices used. Canon updates must be fictional continuity worth remembering
later, and should usually be empty.
''',
      'input': request.prompt,
      'text': {
        'format': {
          'type': 'json_schema',
          'name': 'narration_decision',
          'strict': true,
          'schema': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['speak', 'silence'],
              },
              'text': {'type': 'string'},
              'reason': {'type': 'string'},
              'motifs': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'canon_updates': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'key': {'type': 'string'},
                    'value': {'type': 'string'},
                  },
                  'required': ['key', 'value'],
                  'additionalProperties': false,
                },
              },
            },
            'required': ['action', 'text', 'reason', 'motifs', 'canon_updates'],
            'additionalProperties': false,
          },
        },
      },
    });

    final draft = parseNarrationDraft(response);
    if (requireSpokenLine && !draft.shouldSpeak) {
      throw const FormatException('Offline demo narrator chose silence');
    }
    return draft;
  }
}

NarrationDraft parseNarrationDraft(Map<String, Object?> response) {
  final decoded = jsonDecode(extractOpenAiOutputText(response));
  if (decoded is! Map) {
    throw const FormatException('Narration decision is not an object');
  }
  final json = decoded.map((key, value) => MapEntry(key.toString(), value));
  final action = _requiredString(json, 'action');
  final text = _requiredString(json, 'text').trim();
  final reason = _requiredString(json, 'reason');
  final motifsJson = json['motifs'];
  final canonJson = json['canon_updates'];
  if (motifsJson is! List || !motifsJson.every((value) => value is String)) {
    throw const FormatException('Narration motifs must be strings');
  }
  if (canonJson is! List) {
    throw const FormatException('Narration canon_updates must be an array');
  }
  final canon = <String, String>{};
  for (final value in canonJson) {
    if (value is! Map || value['key'] is! String || value['value'] is! String) {
      throw const FormatException('Invalid narration canon update');
    }
    canon[value['key'] as String] = value['value'] as String;
  }

  return switch (action) {
    'speak' when text.isNotEmpty => NarrationDraft.speak(
      text,
      motifs: motifsJson.cast<String>(),
      canonUpdates: canon,
    ),
    'silence' when text.isEmpty => NarrationDraft.silence(reason),
    'speak' => throw const FormatException('Spoken narration text is empty'),
    'silence' => throw const FormatException('Silent narration contains text'),
    _ => throw FormatException('Unknown narration action: $action'),
  };
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Expected "$key" to be a string');
  return value;
}
