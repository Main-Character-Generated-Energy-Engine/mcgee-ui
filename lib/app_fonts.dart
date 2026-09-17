import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fonts are ready before the first frame; widgets never initiate downloads.
abstract final class AppFonts {
  /// Flutter bundles Roboto as its Material UI font. Keep it explicit for
  /// interface copy such as subtitles and the onboarding card.
  static const dialogFamily = 'Roboto';

  /// Cormorant is reserved for the cinematic opening titles.
  static const titleFamily = 'Cormorant Garamond';
  static const openingStyle = TextStyle(fontFamily: titleFamily);
  static const subtitleStyle = TextStyle(fontFamily: dialogFamily);

  static Future<void> load() async {
    final body = FontLoader(titleFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      body.addFont(
        rootBundle.load('lib/assets/fonts/CormorantGaramond-$weight.ttf'),
      );
    }
    await body.load();
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        const ['Cormorant Garamond'],
        await rootBundle.loadString('lib/assets/fonts/OFL.txt'),
      );
    });
  }
}
