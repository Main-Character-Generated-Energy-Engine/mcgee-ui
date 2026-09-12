import 'dart:convert';
import 'dart:typed_data';

import '../core/contracts.dart';
import '../core/models.dart';
import 'capture_path_reader.dart';
import 'openai_http_client.dart';
import 'openai_response_parsing.dart';

/// Produces a literal, provider-neutral account of an ordered capture window.
final class OpenAiSceneInterpreter implements SceneInterpreter {
  const OpenAiSceneInterpreter({
    required this.client,
    this.model = 'gpt-4.1-mini',
  });

  final OpenAiApi client;
  final String model;

  @override
  Future<SceneObservation> interpret(List<CapturedImage> captures) async {
    if (captures.isEmpty) {
      throw ArgumentError.value(captures, 'captures', 'Must not be empty');
    }

    final ordered = captures.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    final protagonistHints = ordered
        .map((capture) => capture.protagonistHint?.trim())
        .whereType<String>()
        .where((hint) => hint.isNotEmpty)
        .toSet();
    final protagonistGuidance = protagonistHints.isEmpty
        ? ''
        : ' Treat ${protagonistHints.join('; ')} as the focal protagonist.';
    final content = <Map<String, Object?>>[
      {
        'type': 'input_text',
        'text':
            'Observe this chronological camera sequence literally. Describe the '
            'visible action and meaningful change across frames. Use IDs exactly.'
            '$protagonistGuidance',
      },
    ];
    for (final capture in ordered) {
      final bytes = await _readCapture(capture);
      content
        ..add({
          'type': 'input_text',
          'text':
              'Capture ${capture.id}, observed at '
              '${capture.capturedAt.toUtc().toIso8601String()}:',
        })
        ..add({
          'type': 'input_image',
          'detail': 'low',
          'image_url':
              'data:${_mediaType(capture)};base64,${base64Encode(bytes)}',
        });
    }

    final response = await client.createResponse({
      'model': model,
      'max_output_tokens': 500,
      'store': false,
      'instructions': '''
You are the eyes of an editorial system. Report only what is visibly supported
across the supplied frames. Do not write jokes, narration, metaphors, dialogue,
or claims about identity, thoughts, relationships, or events outside the image.
Treat successive frames as samples of one scene, not independent photographs.
The description should be two concise sentences at most. The fingerprint should
be a stable lowercase label for the setting and primary visible action. Salience
is the degree of visible action or change, from 0 to 1. The focal capture ID is
the frame that best represents the action or change.
''',
      'input': [
        {'role': 'user', 'content': content},
      ],
      'text': {
        'format': {
          'type': 'json_schema',
          'name': 'scene_observation',
          'strict': true,
          'schema': {
            'type': 'object',
            'properties': {
              'description': {'type': 'string'},
              'fingerprint': {'type': 'string'},
              'salience': {'type': 'number', 'minimum': 0, 'maximum': 1},
              'setting': {'type': 'string'},
              'action': {'type': 'string'},
              'visible_subjects': {'type': 'string'},
              'temporal_change': {'type': 'string'},
              'focal_capture_id': {'type': 'string'},
            },
            'required': [
              'description',
              'fingerprint',
              'salience',
              'setting',
              'action',
              'visible_subjects',
              'temporal_change',
              'focal_capture_id',
            ],
            'additionalProperties': false,
          },
        },
      },
    });

    return parseSceneObservation(
      response,
      ordered.map((capture) => capture.id).toSet(),
    );
  }
}

SceneObservation parseSceneObservation(
  Map<String, Object?> response,
  Set<String> captureIds,
) {
  final decoded = jsonDecode(extractOpenAiOutputText(response));
  if (decoded is! Map) {
    throw const FormatException('Scene observation is not an object');
  }
  final json = decoded.map((key, value) => MapEntry(key.toString(), value));
  final description = _requiredString(json, 'description');
  final fingerprint = _requiredString(json, 'fingerprint');
  final salience = json['salience'];
  if (salience is! num || salience < 0 || salience > 1) {
    throw const FormatException('Scene salience must be between 0 and 1');
  }
  final focalCaptureId = _requiredString(json, 'focal_capture_id');
  if (!captureIds.contains(focalCaptureId)) {
    throw FormatException(
      'Scene used unknown focal capture ID $focalCaptureId',
    );
  }

  return SceneObservation(
    description: description,
    fingerprint: fingerprint,
    salience: salience.toDouble(),
    details: {
      'setting': _requiredString(json, 'setting'),
      'action': _requiredString(json, 'action'),
      'visible_subjects': _requiredString(json, 'visible_subjects'),
      'temporal_change': _requiredString(json, 'temporal_change'),
      'focal_capture_id': focalCaptureId,
    },
  );
}

Future<Uint8List> _readCapture(CapturedImage capture) async {
  final bytes = capture.bytes;
  if (bytes != null) return bytes;
  final path = capture.path;
  if (path == null) {
    throw StateError('Capture ${capture.id} has no image content');
  }
  return readCapturePath(path);
}

String _mediaType(CapturedImage capture) {
  final path = capture.path?.toLowerCase() ?? '';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Expected "$key" to be a string');
  return value;
}
