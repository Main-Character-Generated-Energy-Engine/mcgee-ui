import 'dart:convert';

import 'package:flutter/services.dart';

/// Host-loaded writing directions shared with the server's narrator modes.
final class NarratorProfile {
  const NarratorProfile({
    required this.openingInstructions,
    required this.liveInstructions,
  });

  final String openingInstructions;
  final String liveInstructions;
}

Future<Map<String, NarratorProfile>> loadNarratorProfiles() async {
  final data = jsonDecode(
    await rootBundle.loadString('lib/assets/narrator-profiles.json'),
  ) as Map<String, dynamic>;
  return Map<String, NarratorProfile>.unmodifiable({
    for (final entry in data.entries)
      entry.key: NarratorProfile(
        openingInstructions: entry.value['openingInstructions'] as String,
        liveInstructions: entry.value['liveInstructions'] as String,
      ),
  });
}
