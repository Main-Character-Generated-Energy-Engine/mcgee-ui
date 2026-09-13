import 'dart:io';

import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter_io.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.write(_usage);
    return;
  }

  OpenRouterHttpClient? client;
  Directory? stagingDirectory;
  try {
    final options = _Options.parse(arguments);
    final captures = await loadTimestampedJpegs(
      Directory(options.capturesPath),
    );
    if (captures.isEmpty) {
      throw StateError(
        'No timestamp-named JPEGs found in ${options.capturesPath}',
      );
    }

    final apiKey = await loadOpenRouterApiKey(File(options.apiKeyPath));
    client = OpenRouterHttpClient(apiKey: apiKey);
    final coreCaptures = [
      for (final capture in captures)
        CapturedImage(
          id: capture.id,
          source: options.source,
          capturedAt: capture.capturedAt,
          path: capture.file.path,
          protagonistHint: options.protagonistHint,
        ),
    ];
    final outputDirectory = Directory(options.outputPath);
    final runDirectory = Directory(
      '${outputDirectory.path}.part-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    stagingDirectory = runDirectory;
    final engine = NarrationEngine(
      sceneInterpreter: const DirectCaptureInterpreter(),
      narrator: OpenRouterNarrationModel(
        client: client,
        model: options.narrationModel,
        requireSpokenLine: true,
        includeCaptures: true,
      ),
      speechSynthesizer: OpenRouterSpeechSynthesizer(
        client: client,
        model: options.speechModel,
        voice: options.voiceId,
      ),
      audioOutput: Mp3FileAudioOutput(
        destination: File('${runDirectory.path}/narration.mp3'),
      ),
      policy: const NarrationPolicy(
        minimumGap: Duration.zero,
        maximumObservationAge: null,
        minimumSalience: 0,
        sceneLookback: 0,
      ),
      maxCapturesPerObservation: coreCaptures.length,
    );
    final outcome = await engine.submit(coreCaptures);
    await engine.close();
    if (outcome.kind != NarrationOutcomeKind.spoken) {
      throw StateError(
        'Narration engine did not produce audio: '
        '${outcome.error ?? outcome.reason ?? outcome.kind.name}',
      );
    }
    final manifest = await writeWebcamManifest(
      outputDirectory: runDirectory,
      captures: coreCaptures,
      outcome: outcome,
      narrationModel: options.narrationModel,
      speechModel: options.speechModel,
      voice: options.voiceName,
      voiceId: options.voiceId,
      provider: 'openrouter',
    );
    await publishWebcamArtifacts(
      stagingDirectory: runDirectory,
      outputDirectory: outputDirectory,
    );

    stdout.writeln('Generated ${outputDirectory.path}/narration.mp3');
    stdout.writeln(
      'Manifest ${outputDirectory.path}/${manifest.uri.pathSegments.last}',
    );
  } catch (error) {
    stderr.writeln('Unable to generate webcam narration: $error');
    exitCode = 1;
  } finally {
    client?.close();
    final staging = stagingDirectory;
    if (staging != null && await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }
}

final class _Options {
  const _Options({
    required this.capturesPath,
    required this.outputPath,
    required this.apiKeyPath,
    required this.source,
    required this.protagonistHint,
    required this.narrationModel,
    required this.speechModel,
    required this.voiceName,
    required this.voiceId,
  });

  final String capturesPath;
  final String outputPath;
  final String apiKeyPath;
  final String source;
  final String protagonistHint;
  final String narrationModel;
  final String speechModel;
  final String voiceName;
  final String voiceId;

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument\n$_usage');
      }
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('Missing value for $argument\n$_usage');
      }
      values[argument] = arguments[++index];
    }

    const known = {
      '--captures',
      '--output',
      '--api-key-file',
      '--source',
      '--protagonist-hint',
      '--narration-model',
      '--speech-model',
      '--voice',
    };
    final unknown = values.keys.where((key) => !known.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown option: ${unknown.first}\n$_usage');
    }
    final voiceArgument = values['--voice'] ?? 'morgan-freeman';
    final voiceOption = OpenRouterVoiceOption.named(voiceArgument);
    final voiceName = voiceOption?.name ?? voiceArgument;
    final voiceId = voiceOption?.voiceId ?? voiceArgument;
    final speechModel =
        values['--speech-model'] ??
        voiceOption?.model ??
        OpenRouterVoiceOption.morganFreeman.model;

    return _Options(
      capturesPath: values['--captures'] ?? 'captures/webcam',
      outputPath: values['--output'] ?? 'output/webcam',
      apiKeyPath: values['--api-key-file'] ?? '.secrets/openrouter-key',
      source: values['--source'] ?? 'webcam',
      protagonistHint:
          values['--protagonist-hint'] ??
          'the recurring foreground camera holder',
      narrationModel: values['--narration-model'] ?? 'openai/gpt-5.6-sol',
      speechModel: speechModel,
      voiceName: voiceName,
      voiceId: voiceId,
    );
  }
}

const _usage = '''
Generate one documentary narration MP3 for timestamped webcam captures.

Usage: dart run bin/generate_webcam_track.dart [options]

  --captures PATH       Input directory (default: captures/webcam)
  --output PATH         Artifact directory (default: output/webcam)
  --api-key-file PATH   API key file (default: .secrets/openrouter-key)
  --source NAME         Capture source stored in the manifest (default: webcam)
  --protagonist-hint H  Visual hint (default: recurring foreground camera holder)
  --narration-model ID  Comedy model (default: openai/gpt-5.6-sol)
  --speech-model ID     Speech model (default: fish-audio/s2.1-pro)
  --voice NAME          morgan-freeman, david-attenborough, jade, or a provider voice ID
''';
