import 'dart:convert';
import 'dart:io';

import '../core/contracts.dart';
import '../core/models.dart';

/// An offline audio sink used by the milestone CLI instead of device playback.
final class Mp3FileAudioOutput implements AudioOutput {
  Mp3FileAudioOutput({required this.destination, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final File destination;
  final DateTime Function() _clock;

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    final bytes = track.bytes;
    if (bytes == null) {
      throw ArgumentError('MP3 file output requires an in-memory audio track');
    }
    await destination.parent.create(recursive: true);
    await writeBytesAtomically(destination, bytes);
    return AudioPlayback(startedAt: _clock(), completed: Future<void>.value());
  }

  @override
  Future<void> stop() async {}
}

Future<File> writeWebcamManifest({
  required Directory outputDirectory,
  required List<CapturedImage> captures,
  required NarrationOutcome outcome,
  required String narrationModel,
  required String speechModel,
  required String voice,
  String? voiceId,
  String provider = 'openai',
  DateTime Function()? clock,
}) async {
  if (outcome.kind != NarrationOutcomeKind.spoken || outcome.text == null) {
    throw ArgumentError('A spoken narration outcome is required');
  }
  final manifestFile = File('${outputDirectory.path}/manifest.json');
  final now = clock ?? DateTime.now;
  final manifest = {
    'schema_version': 1,
    'created_at': now().toUtc().toIso8601String(),
    'audio': {'path': 'narration.mp3', 'media_type': 'audio/mpeg'},
    'narration': {
      'text': outcome.text,
      'observed_at': outcome.observedAt.toUtc().toIso8601String(),
      'audio_output_started_at': outcome.playbackStartedAt
          ?.toUtc()
          .toIso8601String(),
    },
    'source_captures': [
      for (final capture in captures)
        {
          'id': capture.id,
          'source': capture.source,
          'captured_at': capture.capturedAt.toUtc().toIso8601String(),
        },
    ],
    'generation': {
      'provider': provider,
      'vision_model': narrationModel,
      'narration_model': narrationModel,
      'speech_model': speechModel,
      'voice': voice,
      'voice_id': ?voiceId,
    },
  };
  const encoder = JsonEncoder.withIndent('  ');
  await outputDirectory.create(recursive: true);
  await writeTextAtomically(manifestFile, '${encoder.convert(manifest)}\n');
  return manifestFile;
}

/// Publishes a fully rendered MP3/manifest pair and cleans up partial commits.
Future<void> publishWebcamArtifacts({
  required Directory stagingDirectory,
  required Directory outputDirectory,
}) async {
  const names = <String>['narration.mp3', 'manifest.json'];
  for (final name in names) {
    final staged = File('${stagingDirectory.path}/$name');
    if (!await staged.exists() || await staged.length() == 0) {
      throw StateError('Staged webcam artifact is missing or empty: $name');
    }
  }

  await outputDirectory.parent.create(recursive: true);
  final backupDirectory = Directory(
    '${outputDirectory.path}.backup-$pid-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );
  final hadPreviousOutput = await outputDirectory.exists();
  if (hadPreviousOutput) {
    await outputDirectory.rename(backupDirectory.path);
  }
  try {
    await stagingDirectory.rename(outputDirectory.path);
  } catch (_) {
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    if (hadPreviousOutput && await backupDirectory.exists()) {
      await backupDirectory.rename(outputDirectory.path);
    }
    rethrow;
  }
  if (await backupDirectory.exists()) {
    await backupDirectory.delete(recursive: true);
  }
}

Future<void> writeBytesAtomically(File destination, List<int> bytes) async {
  final temporary = File('${destination.path}.part-$pid');
  try {
    final sink = temporary.openWrite();
    sink.add(bytes);
    await sink.flush();
    await sink.close();
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<void> writeTextAtomically(File destination, String value) async {
  final temporary = File('${destination.path}.part-$pid');
  try {
    final sink = temporary.openWrite(encoding: utf8);
    sink.write(value);
    await sink.flush();
    await sink.close();
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
