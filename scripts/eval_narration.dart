// Run from the repository root: dart run scripts/eval_narration.dart
// Uses the real writer and local images, with no speech or camera access.
import 'dart:convert';
import 'dart:io';

import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/src/core/writer_instructions.dart';
import 'package:mcgee/src/openai/openai_response_parsing.dart';
import 'package:mcgee/src/openrouter/openrouter_http_client.dart';
import 'package:mcgee/src/openrouter/openrouter_narration_model.dart';

Future<void> main(List<String> args) async {
  final modes = args.where((arg) => !arg.startsWith('--')).toList();
  final scenario =
      args
          .where((arg) => arg.startsWith('--scenario='))
          .map((arg) => arg.substring('--scenario='.length))
          .firstOrNull ??
      'stationary';
  final passages = int.parse(
    args
            .where((arg) => arg.startsWith('--passages='))
            .map((arg) => arg.substring('--passages='.length))
            .firstOrNull ??
        '13',
  );
  if (![
        'stationary',
        'stale-object',
        'object-exits',
        'stale-drive',
        'stale-strategy',
      ].contains(scenario) ||
      passages < 1 ||
      passages > 24) {
    throw ArgumentError('Use a supported scenario and 1 to 24 passages.');
  }
  final keyFile = File('.secrets/openrouter-key');
  final key =
      (Platform.environment['OPENROUTER_API_KEY'] ??
              (keyFile.existsSync() ? keyFile.readAsStringSync() : ''))
          .trim();
  if (key.isEmpty) {
    throw StateError('Set OPENROUTER_API_KEY or its local file.');
  }
  final profiles =
      jsonDecode(File('lib/assets/narrator-profiles.json').readAsStringSync())
          as Map<String, dynamic>;
  final opening =
      jsonDecode(File('lib/assets/film-opening-prompt.json').readAsStringSync())
          as Map<String, dynamic>;
  final client = OpenRouterHttpClient(apiKey: key);
  final output = File('.dart_tool/narration-eval.json');
  output.parent.createSync(recursive: true);
  final results = <Map<String, Object?>>[];
  try {
    for (final mode in ['morgan-freeman', 'david-attenborough', 'jade']) {
      if (modes.isNotEmpty && !modes.contains(mode)) continue;
      final profile = profiles[mode] as Map<String, dynamic>;
      final response = await client
          .createResponse({
            'model': opening['model'],
            'reasoning': {'effort': 'medium'},
            'max_output_tokens': 1200,
            'store': false,
            'instructions':
                '${opening['instructions']}\n${profile['openingInstructions']}',
            'input':
                'Create a new opening in English. The protagonist name is "Ari".',
          })
          .timeout(const Duration(seconds: 60));
      final credits = jsonDecode(extractOpenAiOutputText(response)) as Map;
      final memory = NarrativeMemory();
      if (scenario == 'stale-object') {
        memory.recordNarration(
          text: 'The subject picked up a bottle and prepared to drink.',
          observedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          canonUpdates: const {
            'current_activity': 'The subject holds a bottle.',
            'story_goal': 'Take a drink from the bottle.',
            'story_tactic': 'Raise the bottle.',
            'open_thread': 'Finish the drink.',
          },
        );
      }
      if (scenario == 'stale-drive') {
        memory.recordNarration(
          text:
              'The specimen waits for nourishment and a food-seeking opportunity.',
          observedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          canonUpdates: const {
            'biological_drive': 'nourishment',
            'story_goal': 'Choose a food-seeking tactic.',
            'story_tactic': 'Wait for nourishment.',
            'open_thread': 'Find nourishment.',
          },
        );
      }
      if (scenario == 'stale-strategy') {
        for (var oldBeat = 0; oldBeat < 3; oldBeat++) {
          memory.recordNarration(
            text:
                'The specimen has settled on a brief hello and the timing of that greeting.',
            observedAt: DateTime.now().subtract(Duration(minutes: 3 - oldBeat)),
            canonUpdates: const {
              'biological_drive': 'reproduction',
              'story_goal': 'Prepare a brief greeting.',
              'story_tactic': 'Offer a soft hello.',
              'story_outcome': 'A brief hello is ready.',
              'open_thread': 'The greeting question is resolved.',
            },
          );
        }
      }
      memory.recordNarration(
        startsEpisode: true,
        text: credits['narration'] as String,
        observedAt: DateTime.now(),
      );
      final result = <String, Object?>{
        'mode': mode,
        'scenario': scenario,
        'opening': credits,
        'beats': <Map<String, Object?>>[],
      };
      results.add(result);
      stdout.writeln('$mode opening: ${credits['narration']}');
      final model = OpenRouterNarrationModel(
        client: client,
        requireSpokenLine: true,
        continuous: true,
        maximumWords: 20,
        includeCaptures: true,
        characterName: 'Ari',
        narratorInstructions: () => profile['liveInstructions'] as String,
      );
      // These images are test inputs only. They define no production defaults.
      // The default scenario contains no handheld object throughout.
      for (var beat = 0; beat < passages; beat++) {
        final fixture = scenario == 'object-exits' && beat == 0 ? '3' : '2';
        final capture = CapturedImage(
          id: 'eval-$beat',
          source: 'camera',
          capturedAt: DateTime.now(),
          bytes: await File(
            'test/fixtures/mock-camera-feed/$fixture.jpg',
          ).readAsBytes(),
        );
        final observation = await const DirectCaptureInterpreter().interpret([
          capture,
        ]);
        final snapshot = memory.snapshot;
        final expectedStage = RegExp(
          r'\n([A-Z]+):',
        ).firstMatch(storyArcInstruction(snapshot))!.group(1)!.toLowerCase();
        final draft = await model
            .narrate(
              NarrationRequest(
                observation: observation,
                memory: snapshot,
                captures: [capture],
                prompt: const ContinuousDocumentaryPromptBuilder().build(
                  observation: observation,
                  memory: snapshot,
                ),
              ),
            )
            .timeout(const Duration(seconds: 90));
        memory.recordNarration(
          text: draft.text!,
          observedAt: capture.capturedAt,
          motifs: draft.motifs,
          canonUpdates: draft.canonUpdates,
        );
        (result['beats'] as List).add({
          'fixture': '$fixture.jpg',
          'expectedStage': expectedStage,
          'unexpectedObjectReference':
              fixture == '2' &&
              RegExp(
                r'\b(bottle|flask|container|vessel|water|sip|drink(?:ing)?)\b',
                caseSensitive: false,
              ).hasMatch(draft.text!),
          'text': draft.text,
          'canon': memory.snapshot.canon,
        });
        output.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(results)}\n',
        );
        stdout.writeln('${beat + 1} [$expectedStage]: ${draft.text}');
        if ((result['beats'] as List).last['unexpectedObjectReference'] ==
            true) {
          stdout.writeln(
            'Review: possible unsupported object or action reference.',
          );
        }
        if (draft.canonUpdates['arc_stage'] != expectedStage) {
          stdout.writeln(
            'Review: returned arc stage differs from the requested beat.',
          );
        }
      }
    }
    stdout.writeln('Saved evaluation to ${output.path}');
  } finally {
    client.close();
  }
}
