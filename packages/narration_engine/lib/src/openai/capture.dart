import 'dart:io';

/// A JPEG capture supplied by the host application.
final class TimestampedCapture {
  const TimestampedCapture({
    required this.id,
    required this.capturedAt,
    required this.file,
  });

  final String id;
  final DateTime capturedAt;
  final File file;
}

/// Reads `{unix-seconds}.jpg` captures in chronological order.
Future<List<TimestampedCapture>> loadTimestampedJpegs(
  Directory directory,
) async {
  if (!await directory.exists()) {
    throw FileSystemException(
      'Capture directory does not exist',
      directory.path,
    );
  }

  final captures = <TimestampedCapture>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final match = RegExp(
      r'^(\d+)\.jpe?g$',
      caseSensitive: false,
    ).firstMatch(name);
    if (match == null) continue;
    final unixSeconds = int.tryParse(match.group(1)!);
    if (unixSeconds == null) continue;
    captures.add(
      TimestampedCapture(
        id: name,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          unixSeconds * Duration.millisecondsPerSecond,
          isUtc: true,
        ),
        file: entity,
      ),
    );
  }

  captures.sort((a, b) {
    final byTime = a.capturedAt.compareTo(b.capturedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return captures;
}
