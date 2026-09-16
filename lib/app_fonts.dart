import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fonts are ready before the first frame; widgets never initiate downloads.
abstract final class AppFonts {
  static const bodyFamily = 'Cormorant Garamond';
  static const openingStyle = TextStyle(fontFamily: bodyFamily);

  static Future<void> load() async {
    final body = FontLoader(bodyFamily);
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
