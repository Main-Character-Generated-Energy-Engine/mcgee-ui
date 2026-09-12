import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:narration_engine/src/core/models.dart';
import 'package:narration_engine/src/openai/webcam_audio_milestone.dart';
import 'package:test/test.dart';

void main() {
  test('file audio output writes MP3 bytes atomically', () async {
    final directory = await Directory.systemTemp.createTemp('mp3-output-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/nested/narration.mp3');
    final output = Mp3FileAudioOutput(
      destination: destination,
      clock: () => DateTime.utc(2026, 9, 12),
    );

    final playback = await output.play(
      AudioTrack(id: 'track', bytes: Uint8List.fromList([0x49, 0x44, 0x33])),
    );

    expect(await destination.readAsBytes(), [0x49, 0x44, 0x33]);
    expect(playback.startedAt, DateTime.utc(2026, 9, 12));
    await playback.completed;
  });

  test('writes a timestamped manifest for a spoken outcome', () async {
    final directory = await Directory.systemTemp.createTemp('manifest-');
    addTearDown(() => directory.delete(recursive: true));
    final observedAt = DateTime.fromMillisecondsSinceEpoch(
      1700000000000,
      isUtc: true,
    );
    final capture = CapturedImage(
      id: '1700000000.jpg',
      source: 'webcam',
      capturedAt: observedAt,
      path: '${directory.path}/1700000000.jpg',
    );

    final file = await writeWebcamManifest(
      outputDirectory: directory,
      captures: [capture],
      outcome: NarrationOutcome.spoken(
        observedAt: observedAt,
        playbackStartedAt: DateTime.utc(2026, 9, 12, 1),
        text: 'At last, the morning yields to administrative weather.',
      ),
      visionModel: 'vision-test',
      narrationModel: 'narration-test',
      speechModel: 'speech-test',
      voice: 'voice-test',
      voiceId: 'voice-id-test',
      provider: 'provider-test',
      clock: () => DateTime.utc(2026, 9, 12),
    );

    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(manifest['narration']['observed_at'], observedAt.toIso8601String());
    expect(
      manifest['narration']['audio_output_started_at'],
      '2026-09-12T01:00:00.000Z',
    );
    expect(manifest['source_captures'][0]['id'], capture.id);
    expect(manifest['generation']['narration_model'], 'narration-test');
    expect(manifest['generation']['provider'], 'provider-test');
    expect(manifest['generation']['voice_id'], 'voice-id-test');
    expect(manifest['created_at'], '2026-09-12T00:00:00.000Z');
  });

  test('publishes only a complete MP3 and manifest pair', () async {
    final directory = await Directory.systemTemp.createTemp('publish-pair-');
    addTearDown(() => directory.delete(recursive: true));
    final staging = Directory('${directory.path}/staging');
    final output = Directory('${directory.path}/output');
    await staging.create();
    await File('${staging.path}/narration.mp3')
        .writeAsBytes([0x49, 0x44, 0x33]);
    await File('${staging.path}/manifest.json').writeAsString('{}');

    await publishWebcamArtifacts(
      stagingDirectory: staging,
      outputDirectory: output,
    );

    expect(await File('${output.path}/narration.mp3').exists(), isTrue);
    expect(await File('${output.path}/manifest.json').exists(), isTrue);
  });

  test('publishing a rerun replaces the previous pair together', () async {
    final directory = await Directory.systemTemp.createTemp('publish-rerun-');
    addTearDown(() => directory.delete(recursive: true));
    final staging = Directory('${directory.path}/staging');
    final output = Directory('${directory.path}/output');
    await staging.create();
    await output.create();
    await File('${staging.path}/narration.mp3').writeAsBytes([2]);
    await File('${staging.path}/manifest.json').writeAsString('{"run":2}');
    await File('${output.path}/narration.mp3').writeAsBytes([1]);
    await File('${output.path}/manifest.json').writeAsString('{"run":1}');

    await publishWebcamArtifacts(
      stagingDirectory: staging,
      outputDirectory: output,
    );

    expect(await File('${output.path}/narration.mp3').readAsBytes(), [2]);
    expect(
      await File('${output.path}/manifest.json').readAsString(),
      '{"run":2}',
    );
  });
}
