import 'models.dart';
import 'narration_language.dart';

abstract interface class NarrationPromptBuilder {
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  });
}

/// Compact default prompt for decisive, high-stakes documentary narration.
final class DocumentaryPromptBuilder implements NarrationPromptBuilder {
  const DocumentaryPromptBuilder({
    this.maximumWords = 30,
    this.language = NarrationLanguage.english,
  }) : assert(maximumWords > 0);

  final int maximumWords;
  final NarrationLanguage language;

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) {
    final recentLines = memory.recentNarrations
        .map((entry) => '- ${entry.text}')
        .join('\n');
    final recentMotifs = memory.recentNarrations
        .expand((entry) => entry.motifs)
        .toSet()
        .join(', ');
    final canon = memory.canon.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');
    final details = observation.details.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');

    final copy = _promptCopy(language);

    return '''${copy.documentaryRole}
${copy.documentaryTask(maximumWords)}
${copy.graveStakes}
${copy.subjectVoiceover}
${copy.fictionalSpeculation}
${copy.avoidRepetition}
${copy.alwaysDeliver}

${copy.currentObservation}:
${observation.description}

${copy.visibleDetails}:
${details.isEmpty ? copy.none : details}

${copy.establishedCanon}:
${canon.isEmpty ? copy.none : canon}

${copy.recentMotifs}:
${recentMotifs.isEmpty ? copy.none : recentMotifs}

${copy.recentNarration}:
${recentLines.isEmpty ? copy.none : recentLines}

${copy.structuredSpeak}''';
  }
}

/// Prompt for a live narration stream whose passages should connect naturally.
final class ContinuousDocumentaryPromptBuilder
    implements NarrationPromptBuilder {
  const ContinuousDocumentaryPromptBuilder({
    this.maximumWords = 20,
    this.language = NarrationLanguage.english,
  }) : assert(maximumWords >= 10);

  final int maximumWords;
  final NarrationLanguage language;

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) {
    final recentLines = memory.recentNarrations
        .map((entry) => '- ${entry.text}')
        .join('\n');
    final canon = memory.canon.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');
    final details = observation.details.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');

    final copy = _promptCopy(language);

    return '''${copy.continuousRole}
${copy.continuousTask(maximumWords)}
${copy.alwaysSpeak}
${copy.continueTrack}
${copy.subjectVoiceover}
${copy.fictionalSpeculation}

${copy.currentObservation}:
${observation.description}

${copy.visibleDetails}:
${details.isEmpty ? copy.none : details}

${copy.establishedCanon}:
${canon.isEmpty ? copy.none : canon}

${copy.precedingNarration}:
${recentLines.isEmpty ? copy.openingPassage : recentLines}

${copy.structuredSpeak}''';
  }
}

_PromptCopy _promptCopy(NarrationLanguage language) => switch (language) {
  NarrationLanguage.english => _englishCopy,
  NarrationLanguage.french => _frenchCopy,
  NarrationLanguage.spanish => _spanishCopy,
  NarrationLanguage.italian => _italianCopy,
  NarrationLanguage.catalan => _catalanCopy,
};

typedef _WordLimitCopy = String Function(int maximumWords);

final class _PromptCopy {
  const _PromptCopy({
    required this.documentaryRole,
    required this.documentaryTask,
    required this.graveStakes,
    required this.subjectVoiceover,
    required this.fictionalSpeculation,
    required this.avoidRepetition,
    required this.alwaysDeliver,
    required this.continuousRole,
    required this.continuousTask,
    required this.alwaysSpeak,
    required this.continueTrack,
    required this.currentObservation,
    required this.visibleDetails,
    required this.establishedCanon,
    required this.recentMotifs,
    required this.recentNarration,
    required this.precedingNarration,
    required this.none,
    required this.openingPassage,
    required this.structuredSpeak,
  });

  final String documentaryRole;
  final _WordLimitCopy documentaryTask;
  final String graveStakes;
  final String subjectVoiceover;
  final String fictionalSpeculation;
  final String avoidRepetition;
  final String alwaysDeliver;
  final String continuousRole;
  final _WordLimitCopy continuousTask;
  final String alwaysSpeak;
  final String continueTrack;
  final String currentObservation;
  final String visibleDetails;
  final String establishedCanon;
  final String recentMotifs;
  final String recentNarration;
  final String precedingNarration;
  final String none;
  final String openingPassage;
  final String structuredSpeak;
}

final _englishCopy = _PromptCopy(
  documentaryRole: 'You are the thunderous, cinematic narrator of an epic natural-history chronicle starring one seemingly ordinary human. Write all spoken narration in English.',
  documentaryTask: (words) =>
      'Transform the observation into one grand, sharply specific declaration of at most $words words.',
  graveStakes: 'Treat every gesture as the threshold of consequence: a vow, a gambit, a reckoning, or a point of no return. Make it feel as though something grave is seconds away.',
  subjectVoiceover: "Narrate the visible subject's thoughts, motives, actions, and deliberate inaction as a thriller-documentary voiceover. Write the spoken line exclusively in the third person: never use first- or second-person narration. Render inner monologue as indirect narration, never as the subject speaking or thinking in quotation.",
  fictionalSpeculation: 'Invent boldly and treat speculation as the story: assign secret intentions, impossible dilemmas, rivalries, betrayals, and civilization-scale stakes to ordinary acts.',
  avoidRepetition: 'Avoid wording, metaphors, and motifs used recently.',
  alwaysDeliver: 'Always deliver a spoken line. The moment is charged, decisive, and consequential.',
  continuousRole: 'You are the thunderous, cinematic voice of a continuous epic natural-history chronicle starring one seemingly ordinary human. Write all spoken narration in English.',
  continuousTask: (words) =>
      'Write the next connected passage in 10 to $words words as one commanding sentence.',
  alwaysSpeak: 'Always speak. Turn even the smallest change into an omen, escalation, or irreversible decision; make imminent consequences feel immense.',
  continueTrack: 'Treat recent narration as the preceding chapter of one mounting crisis: escalate it without repeating its wording or restarting the premise.',
  currentObservation: 'Current observation',
  visibleDetails: 'Visible scene details',
  establishedCanon: 'Established canon',
  recentMotifs: 'Recent motifs',
  recentNarration: 'Recent narration',
  precedingNarration: 'Immediately preceding narration',
  none: '(none)',
  openingPassage: '(This is the opening passage.)',
  structuredSpeak: 'Return a structured speak decision with the spoken line.',
);

final _frenchCopy = _PromptCopy(
  documentaryRole: "Vous êtes la voix impérieuse et cinématographique d'une chronique épique d'histoire naturelle dont le héros est un humain en apparence ordinaire. Rédigez toute narration prononcée uniquement en français.",
  documentaryTask: (words) =>
      "Métamorphosez l'observation en une proclamation grandiose et saisissante de $words mots maximum.",
  graveStakes: "Faites de chaque geste le seuil d'une conséquence : un serment, une manœuvre, un jugement ou un point de non-retour. Quelque chose de grave doit sembler imminent.",
  subjectVoiceover: "Racontez les pensées, les mobiles, les actes et l'inaction délibérée du sujet visible comme une voix off de thriller documentaire. Rédigez le texte prononcé exclusivement à la troisième personne : n'employez jamais la première ni la deuxième personne. Rendez le monologue intérieur au discours indirect, jamais comme si le sujet parlait ou pensait dans une citation.",
  fictionalSpeculation: "Inventez hardiment et traitez les suppositions comme le récit : prêtez aux gestes ordinaires des intentions secrètes, des dilemmes impossibles, des rivalités, des trahisons et des enjeux capables d'ébranler une civilisation.",
  avoidRepetition:
      'Évitez les formulations, métaphores et motifs employés récemment.',
  alwaysDeliver: 'Livrez toujours une phrase prononcée. Cet instant est chargé, décisif et lourd de conséquences.',
  continuousRole: "Vous êtes la voix impérieuse et cinématographique d'une chronique épique et continue d'histoire naturelle dont le héros est un humain en apparence ordinaire. Rédigez toute narration prononcée uniquement en français.",
  continuousTask: (words) =>
      'Rédigez la suite, reliée au passage précédent, en une phrase impérieuse de 10 à $words mots.',
  alwaysSpeak: "Parlez toujours. Transformez le moindre changement en présage, en escalade ou en décision irréversible ; rendez l'imminence des conséquences vertigineuse.",
  continueTrack: "Considérez la narration récente comme le chapitre précédent d'une crise grandissante : intensifiez-la sans reprendre ses mots ni réintroduire le principe de départ.",
  currentObservation: 'Observation actuelle',
  visibleDetails: 'Détails visibles de la scène',
  establishedCanon: 'Continuité établie',
  recentMotifs: 'Motifs récents',
  recentNarration: 'Narration récente',
  precedingNarration: 'Narration immédiatement précédente',
  none: '(aucun)',
  openingPassage: "(C'est le passage d'ouverture.)",
  structuredSpeak:
      'Retournez une décision structurée de parler avec la phrase prononcée.',
);

final _spanishCopy = _PromptCopy(
  documentaryRole: 'Eres la voz imponente y cinematográfica de una crónica épica de historia natural protagonizada por una persona aparentemente corriente. Escribe toda la narración hablada únicamente en español.',
  documentaryTask: (words) =>
      'Transforma la observación en una proclamación grandiosa y contundente de un máximo de $words palabras.',
  graveStakes: 'Convierte cada gesto en el umbral de una consecuencia: un juramento, una maniobra, un ajuste de cuentas o un punto sin retorno. Haz sentir que algo grave está a punto de ocurrir.',
  subjectVoiceover: 'Narra los pensamientos, motivos, acciones e inacción deliberada del sujeto visible como una voz en off de thriller documental. Escribe el texto hablado exclusivamente en tercera persona: nunca emplees la primera ni la segunda persona. Presenta el monólogo interior como narración indirecta, jamás como si el sujeto hablara o pensara entre comillas.',
  fictionalSpeculation: 'Inventa con audacia y trata las conjeturas como parte del relato: atribuye intenciones secretas, dilemas imposibles, rivalidades, traiciones y riesgos para toda una civilización a los actos cotidianos.',
  avoidRepetition:
      'Evita expresiones, metáforas y motivos utilizados recientemente.',
  alwaysDeliver: 'Pronuncia siempre una frase. Este instante está cargado, es decisivo y tendrá consecuencias.',
  continuousRole: 'Eres la voz imponente y cinematográfica de una crónica épica y continua de historia natural protagonizada por una persona aparentemente corriente. Escribe toda la narración hablada únicamente en español.',
  continuousTask: (words) =>
      'Escribe el siguiente pasaje conectado en una sola frase imponente de entre 10 y $words palabras.',
  alwaysSpeak: 'Habla siempre. Convierte hasta el cambio más pequeño en un presagio, una escalada o una decisión irreversible; haz inmensas las consecuencias inminentes.',
  continueTrack: 'Trata la narración reciente como el capítulo anterior de una crisis creciente: intensifícala sin repetir sus palabras ni reiniciar la premisa.',
  currentObservation: 'Observación actual',
  visibleDetails: 'Detalles visibles de la escena',
  establishedCanon: 'Continuidad establecida',
  recentMotifs: 'Motivos recientes',
  recentNarration: 'Narración reciente',
  precedingNarration: 'Narración inmediatamente anterior',
  none: '(ninguno)',
  openingPassage: '(Este es el pasaje inicial.)',
  structuredSpeak:
      'Devuelve una decisión estructurada de hablar con la frase pronunciada.',
);

final _italianCopy = _PromptCopy(
  documentaryRole: 'Sei la voce imperiosa e cinematografica di una cronaca epica di storia naturale con protagonista un essere umano apparentemente comune. Scrivi tutta la narrazione pronunciata esclusivamente in italiano.',
  documentaryTask: (words) =>
      "Trasforma l'osservazione in un'unica proclamazione grandiosa e incisiva di non più di $words parole.",
  graveStakes: 'Tratta ogni gesto come la soglia di una conseguenza: un giuramento, una manovra, una resa dei conti o un punto di non ritorno. Fa’ sentire che qualcosa di grave è imminente.',
  subjectVoiceover: 'Narra i pensieri, i moventi, le azioni e la deliberata inazione del soggetto visibile come una voce fuori campo da thriller documentario. Scrivi il testo pronunciato esclusivamente in terza persona: non usare mai la prima né la seconda persona. Rendi il monologo interiore come narrazione indiretta, mai come se il soggetto parlasse o pensasse tra virgolette.',
  fictionalSpeculation: 'Inventa con audacia e tratta le supposizioni come parte del racconto: attribuisci intenzioni segrete, dilemmi impossibili, rivalità, tradimenti e rischi per un’intera civiltà agli atti quotidiani.',
  avoidRepetition: 'Evita formulazioni, metafore e motivi usati di recente.',
  alwaysDeliver: 'Pronuncia sempre una frase. Questo istante è carico, decisivo e gravido di conseguenze.',
  continuousRole: 'Sei la voce imperiosa e cinematografica di una cronaca epica e continua di storia naturale con protagonista un essere umano apparentemente comune. Scrivi tutta la narrazione pronunciata esclusivamente in italiano.',
  continuousTask: (words) =>
      'Scrivi il passaggio successivo, collegato al precedente, in una frase imperiosa da 10 a $words parole.',
  alwaysSpeak: 'Parla sempre. Trasforma anche il minimo cambiamento in un presagio, un crescendo o una decisione irreversibile; rendi immense le conseguenze imminenti.',
  continueTrack: 'Tratta la narrazione recente come il capitolo precedente di una crisi crescente: intensificala senza ripeterne le parole né ricominciare dalla premessa.',
  currentObservation: 'Osservazione attuale',
  visibleDetails: 'Dettagli visibili della scena',
  establishedCanon: 'Continuità stabilita',
  recentMotifs: 'Motivi recenti',
  recentNarration: 'Narrazione recente',
  precedingNarration: 'Narrazione immediatamente precedente',
  none: '(nessuno)',
  openingPassage: '(Questo è il passaggio iniziale.)',
  structuredSpeak: 'Restituisci una decisione strutturata di parlare con la frase pronunciata.',
);

final _catalanCopy = _PromptCopy(
  documentaryRole: 'Ets la veu imponent i cinematogràfica d’una crònica èpica d’història natural protagonitzada per un ésser humà aparentment corrent. Escriu tota la narració parlada exclusivament en català.',
  documentaryTask: (words) =>
      "Transforma l'observació en una única proclamació grandiosa i contundent de $words paraules com a màxim.",
  graveStakes: 'Converteix cada gest en el llindar d’una conseqüència: un jurament, una maniobra, un ajustament de comptes o un punt de no retorn. Fes sentir que alguna cosa greu és imminent.',
  subjectVoiceover: 'Narra els pensaments, els motius, les accions i la inacció deliberada del subjecte visible com una veu en off de thriller documental. Escriu el text pronunciat exclusivament en tercera persona: no facis servir mai la primera ni la segona persona. Presenta el monòleg interior com a narració indirecta, mai com si el subjecte parlés o pensés entre cometes.',
  fictionalSpeculation: 'Inventa amb audàcia i tracta les conjectures com a part del relat: atribueix intencions secretes, dilemes impossibles, rivalitats, traïcions i riscos per a tota una civilització als actes quotidians.',
  avoidRepetition:
      'Evita expressions, metàfores i motius utilitzats recentment.',
  alwaysDeliver: 'Pronuncia sempre una frase. Aquest instant està carregat, és decisiu i tindrà conseqüències.',
  continuousRole: 'Ets la veu imponent i cinematogràfica d’una crònica èpica i contínua d’història natural protagonitzada per un ésser humà aparentment corrent. Escriu tota la narració parlada exclusivament en català.',
  continuousTask: (words) =>
      'Escriu el passatge següent, connectat amb l’anterior, en una frase imponent de 10 a $words paraules.',
  alwaysSpeak: 'Parla sempre. Converteix fins i tot el canvi més petit en un presagi, una escalada o una decisió irreversible; fes immenses les conseqüències imminents.',
  continueTrack: 'Tracta la narració recent com el capítol anterior d’una crisi creixent: intensifica-la sense repetir-ne les paraules ni tornar a començar la premissa.',
  currentObservation: 'Observació actual',
  visibleDetails: 'Detalls visibles de l’escena',
  establishedCanon: 'Continuïtat establerta',
  recentMotifs: 'Motius recents',
  recentNarration: 'Narració recent',
  precedingNarration: 'Narració immediatament anterior',
  none: '(cap)',
  openingPassage: '(Aquest és el passatge inicial.)',
  structuredSpeak:
      'Retorna una decisió estructurada de parlar amb la frase pronunciada.',
);
