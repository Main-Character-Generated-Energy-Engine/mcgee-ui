const LANGUAGE_NAMES = Object.freeze({
  en: "English",
  fr: "French",
  es: "Spanish",
  it: "Italian",
  ca: "Catalan",
});

export function narrationLanguageName(code = "en") {
  if (typeof code !== "string" || !Object.hasOwn(LANGUAGE_NAMES, code)) {
    throw new Error("Unsupported narration language.");
  }
  return LANGUAGE_NAMES[code];
}

// Keep this shared English directive aligned with NarrationLanguage in Dart.
export function narrationLanguageInstruction(code = "en") {
  return `Write all spoken narration only in ${narrationLanguageName(code)}. ` +
    "Compose directly in that language using natural idiom and spoken rhythm; " +
    "do not translate an English draft. Preserve the understated humour and " +
    "cinematic seriousness.";
}
