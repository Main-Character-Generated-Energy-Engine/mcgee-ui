/// Languages supported by the live documentary narrator.
enum NarrationLanguage {
  english(
    apiValue: 'en',
    englishName: 'English',
    nativeName: 'English',
    startupLine: 'The hour has come. Destiny now turns on a single move.',
    writerInstruction: 'Write the narration only in English.',
  ),
  french(
    apiValue: 'fr',
    englishName: 'French',
    nativeName: 'Français',
    startupLine:
        "L'heure est venue. Le destin tient désormais à un seul geste.",
    writerInstruction: 'Rédigez la narration uniquement en français.',
  ),
  spanish(
    apiValue: 'es',
    englishName: 'Spanish',
    nativeName: 'Español',
    startupLine:
        'Ha llegado la hora. El destino depende ahora de un solo movimiento.',
    writerInstruction: 'Escribe la narración únicamente en español.',
  ),
  italian(
    apiValue: 'it',
    englishName: 'Italian',
    nativeName: 'Italiano',
    startupLine: "L'ora è giunta. Il destino dipende ormai da una sola mossa.",
    writerInstruction: 'Scrivi la narrazione esclusivamente in italiano.',
  ),
  catalan(
    apiValue: 'ca',
    englishName: 'Catalan',
    nativeName: 'Català',
    startupLine: "Ha arribat l'hora. El destí depèn ara d'un sol moviment.",
    writerInstruction: 'Escriu la narració exclusivament en català.',
  );

  const NarrationLanguage({
    required this.apiValue,
    required this.englishName,
    required this.nativeName,
    required this.startupLine,
    required this.writerInstruction,
  });

  /// Stable value for API requests and persistence.
  final String apiValue;

  /// Name suitable for an English-language accessibility label.
  final String englishName;

  /// Name shown in the language picker.
  final String nativeName;

  /// Localized version of the short line spoken when narration starts.
  final String startupLine;

  /// High-priority instruction for the provider-side final writing pass.
  final String writerInstruction;

  static NarrationLanguage fromApiValue(String value) {
    return NarrationLanguage.values.firstWhere(
      (language) => language.apiValue == value,
      orElse: () =>
          throw FormatException('Unsupported narration language: $value'),
    );
  }
}
