const MAX_VIEW_DEPTH = 16;
const MAX_VIEW_NODES = 1024;
const MAX_CANVAS_COMMANDS = 2000;
const MAX_TEXT_LEN = 4096;
const VALID_TONES = new Set(['default', 'ok', 'warn', 'danger']);
const VALID_CANVAS_OPS = new Set(['clear', 'rect', 'rrect', 'circle', 'arc', 'line', 'path', 'polygon', 'bars', 'text']);
const VALID_HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

const LOCALE_PACKS = {
  en: {
    locale: 'en',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: 'What {host} offers',
    wishPlaceholder: 'I wish {host} would\u2026',
    send: 'Send',
    wishNote: 'The AI is scripted in this demo. Pick a wish.',
    installed: 'Installed',
    filterPlaceholder: 'Filter installed vibes\u2026',
    emptyInstalled: 'Nothing here yet. Make a wish.',
    sealedLegend: 'Values with a lock are sealed. {host} draws them. The vibe never sees them.',
    portableVibes: 'Portable vibes',
    portableSub: 'These need nothing from the app, so they run anywhere.',
    reads: 'Reads',
    shows: 'Shows',
    cannot: 'Cannot',
    onlyInsideBox: 'Only inside its own box',
    changeNothing: 'Change anything in {host}',
    nothingFromHost: 'Nothing from {host}',
    allowAndAdd: 'Allow and add',
    update: 'Update',
    cancel: 'Cancel',
    noNewPermissions: 'Version {version}. No new permissions.',
    inspect: 'Inspect',
    hideInspect: 'Hide inspect',
    share: 'Share',
    edit: 'Edit',
    rename: 'Rename',
    pause: 'Pause',
    resume: 'Resume',
    pinToTop: 'Pin to top',
    unpin: 'Unpin',
    moveUp: 'Move up',
    moveDown: 'Move down',
    revert: 'Revert',
    deleteLabel: 'Delete',
    undo: 'Undo',
    temporary: 'Temporary',
    pinned: 'Pinned',
    pinToVibeSpace: 'Pin to Vibe Space',
    pinnedToVibeSpace: 'Pinned to Vibe Space',
    madeByAgent: 'Made by the agent for this answer',
    retry: 'Retry',
    previewSample: 'Preview sample',
    returnToLive: 'Return to live',
    sourceOffline: 'Source offline',
    sourceRevoked: 'Source access turned off',
    sourceMissing: 'Source unavailable'
  },
  zh: {
    locale: 'zh',
    rtl: false,
    panelTitle: 'Vibe \u7a7a\u95f4',
    whatOffers: '{host} \u63d0\u4f9b\u7684\u80fd\u529b',
    wishPlaceholder: '\u6211\u5e0c\u671b {host} \u80fd\u591f\u2026',
    send: '\u53d1\u9001',
    wishNote: '\u6b64\u6f14\u793a\u4e2d AI \u4e3a\u9884\u8bbe\u811a\u672c\uff0c\u8bf7\u9009\u62e9\u4e00\u4e2a\u613f\u671b\u3002',
    installed: '\u5df2\u5b89\u88c5',
    filterPlaceholder: '\u7b5b\u9009\u5df2\u5b89\u88c5\u7684 vibe\u2026',
    emptyInstalled: '\u6682\u65e0\u5185\u5bb9\uff0c\u8bd5\u8bd5\u5199\u4e0b\u4e00\u4e2a\u613f\u671b\u3002',
    sealedLegend: '\u5e26\u9501\u7684\u503c\u5df2\u5c01\u88c5\uff0c\u7531 {host} \u7ed8\u5236\uff0cvibe \u65e0\u6cd5\u770b\u5230\u3002',
    portableVibes: '\u4fbf\u643a vibe',
    portableSub: '\u4e0d\u4f9d\u8d56\u5e94\u7528\u6570\u636e\uff0c\u53ef\u5728\u4efb\u610f\u5bbf\u4e3b\u4e2d\u8fd0\u884c\u3002',
    reads: '\u8bfb\u53d6',
    shows: '\u663e\u793a',
    cannot: '\u7981\u6b62',
    onlyInsideBox: '\u4ec5\u5728\u5176\u81ea\u8eab\u5bb9\u5668\u5185',
    changeNothing: '\u4fee\u6539 {host} \u4e2d\u7684\u4efb\u4f55\u5185\u5bb9',
    nothingFromHost: '\u4e0d\u8bfb\u53d6 {host} \u7684\u4efb\u4f55\u6570\u636e',
    allowAndAdd: '\u5141\u8bb8\u5e76\u6dfb\u52a0',
    update: '\u66f4\u65b0',
    cancel: '\u53d6\u6d88',
    noNewPermissions: '\u7248\u672c {version}\uff0c\u65e0\u65b0\u589e\u6743\u9650\u3002',
    inspect: '\u68c0\u67e5',
    hideInspect: '\u9690\u85cf\u68c0\u67e5',
    share: '\u5206\u4eab',
    edit: '\u7f16\u8f91',
    rename: '\u91cd\u547d\u540d',
    pause: '\u6682\u505c',
    resume: '\u6062\u590d',
    pinToTop: '\u7f6e\u9876',
    unpin: '\u53d6\u6d88\u7f6e\u9876',
    moveUp: '\u4e0a\u79fb',
    moveDown: '\u4e0b\u79fb',
    revert: '\u8fd8\u539f',
    deleteLabel: '\u5220\u9664',
    undo: '\u64a4\u9500',
    temporary: '\u4e34\u65f6',
    pinned: '\u5df2\u56fa\u5b9a',
    pinToVibeSpace: '\u56fa\u5b9a\u5230 Vibe \u7a7a\u95f4',
    pinnedToVibeSpace: '\u5df2\u56fa\u5b9a\u5230 Vibe \u7a7a\u95f4',
    madeByAgent: '\u7531\u667a\u80fd\u4f53\u4e3a\u6b64\u56de\u590d\u751f\u6210',
    retry: '\u91cd\u8bd5',
    previewSample: '\u9884\u89c8\u793a\u4f8b',
    returnToLive: '\u8fd4\u56de\u5b9e\u65f6\u6570\u636e',
    sourceOffline: '\u6570\u636e\u6e90\u79bb\u7ebf',
    sourceRevoked: '\u6570\u636e\u8bbf\u95ee\u5df2\u5173\u95ed',
    sourceMissing: '\u6570\u636e\u6e90\u4e0d\u53ef\u7528'
  },
  ja: {
    locale: 'ja',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: '{host} \u304c\u63d0\u4f9b\u3059\u308b\u6a5f\u80fd',
    wishPlaceholder: '{host} \u306b\u304a\u9858\u3044\u3059\u308b\u2026',
    send: '\u9001\u4fe1',
    wishNote: '\u3053\u306e\u30c7\u30e2\u306e AI \u306f\u30b9\u30af\u30ea\u30d7\u30c8\u5316\u3055\u308c\u3066\u3044\u307e\u3059\u3002',
    installed: '\u30a4\u30f3\u30b9\u30c8\u30fc\u30eb\u6e08\u307f',
    filterPlaceholder: 'vibe \u3092\u7d5e\u308a\u8fbc\u3080\u2026',
    emptyInstalled: '\u307e\u3060\u3042\u308a\u307e\u305b\u3093\u3002\u30ea\u30af\u30a8\u30b9\u30c8\u3057\u3066\u307f\u307e\u3057\u3087\u3046\u3002',
    sealedLegend: '\u9375\u4ed8\u304d\u306e\u5024\u306f\u5c01\u5370\u3055\u308c\u3001{host} \u304c\u63cf\u753b\u3057\u307e\u3059\u3002',
    portableVibes: '\u30dd\u30fc\u30bf\u30d6\u30eb vibe',
    portableSub: '\u30a2\u30d7\u30ea\u306e\u30c7\u30fc\u30bf\u4e0d\u8981\u3067\u3069\u3053\u3067\u3082\u52d5\u4f5c\u3057\u307e\u3059\u3002',
    reads: '\u8aad\u307f\u53d6\u308a',
    shows: '\u8868\u793a',
    cannot: '\u4e0d\u53ef',
    onlyInsideBox: '\u3053\u306e\u30dc\u30c3\u30af\u30b9\u5185\u306e\u307f',
    changeNothing: '{host} \u306e\u5909\u66f4',
    nothingFromHost: '{host} \u304b\u3089\u306f\u4f55\u3082\u8aad\u307f\u53d6\u308a\u307e\u305b\u3093',
    allowAndAdd: '\u8a31\u53ef\u3057\u3066\u8ffd\u52a0',
    update: '\u66f4\u65b0',
    cancel: '\u30ad\u30e3\u30f3\u30bb\u30eb',
    noNewPermissions: '\u30d0\u30fc\u30b8\u30e7\u30f3 {version}\u3002\u65b0\u3057\u3044\u6a29\u9650\u306f\u3042\u308a\u307e\u305b\u3093\u3002',
    inspect: '\u691c\u67fb',
    hideInspect: '\u691c\u67fb\u3092\u96a0\u3059',
    share: '\u5171\u6709',
    edit: '\u7de8\u96c6',
    rename: '\u540d\u524d\u3092\u5909\u66f4',
    pause: '\u4e00\u6642\u505c\u6b62',
    resume: '\u518d\u958b',
    pinToTop: '\u5148\u982d\u306b\u56fa\u5b9a',
    unpin: '\u56fa\u5b9a\u89e3\u9664',
    moveUp: '\u4e0a\u3078',
    moveDown: '\u4e0b\u3078',
    revert: '\u5143\u306b\u623b\u3059',
    deleteLabel: '\u524a\u9664',
    undo: '\u5143\u306b\u623b\u3059',
    temporary: '\u4e00\u6642\u7684',
    pinned: '\u56fa\u5b9a\u6e08\u307f',
    pinToVibeSpace: 'Vibe Space \u306b\u56fa\u5b9a',
    pinnedToVibeSpace: 'Vibe Space \u306b\u56fa\u5b9a\u3057\u307e\u3057\u305f',
    madeByAgent: '\u3053\u306e\u56de\u7b54\u7528\u306b\u30a8\u30fc\u30b8\u30a7\u30f3\u30c8\u304c\u4f5c\u6210',
    retry: '\u518d\u8a66\u884c',
    previewSample: '\u30b5\u30f3\u30d7\u30eb\u3092\u8868\u793a',
    returnToLive: '\u30e9\u30a4\u30d6\u306b\u623b\u3059',
    sourceOffline: '\u30bd\u30fc\u30b9\u304c\u30aa\u30d5\u30e9\u30a4\u30f3',
    sourceRevoked: '\u30a2\u30af\u30bb\u30b9\u304c\u7121\u52b9\u3067\u3059',
    sourceMissing: '\u30bd\u30fc\u30b9\u304c\u5229\u7528\u3067\u304d\u307e\u305b\u3093'
  },
  ko: {
    locale: 'ko',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: '{host} \uc81c\uacf5 \uae30\ub2a5',
    wishPlaceholder: '{host}\uc5d0\uac8c \uc6d0\ud558\ub294 \uae30\ub2a5\u2026',
    send: '\uc804\uc1a1',
    wishNote: '\uc774 \ub370\ubaa8\uc758 AI\ub294 \uc2a4\ud06c\ub9bd\ud2b8\ub85c \ub3d9\uc791\ud569\ub2c8\ub2e4.',
    installed: '\uc124\uce58\ub428',
    filterPlaceholder: '\uc124\uce58\ub41c vibe \uac80\uc0c9\u2026',
    emptyInstalled: '\uc544\uc9c1 \uc5c6\uc2b5\ub2c8\ub2e4. \uc6d0\ud558\ub294 \uae30\ub2a5\uc744 \uc785\ub825\ud574 \ubcf4\uc138\uc694.',
    sealedLegend: '\uc790\ubb3c\uc1e0 \uac12\uc740 \ubd09\uc778\ub418\uc5b4 {host}\uac00 \uadf8\ub9bd\ub2c8\ub2e4.',
    portableVibes: '\ud3ec\ud130\ube14 vibe',
    portableSub: '\uc571 \ub370\uc774\ud130 \uc5c6\uc774 \uc5b4\ub514\uc11c\ub098 \uc2e4\ud589\ub429\ub2c8\ub2e4.',
    reads: '\uc77d\uae30',
    shows: '\ud45c\uc2dc',
    cannot: '\ubd88\uac00',
    onlyInsideBox: '\uc790\uccb4 \uc0c1\uc790 \ub0b4\ubd80\ub9cc',
    changeNothing: '{host} \ub0b4\uc6a9 \ubcc0\uacbd',
    nothingFromHost: '{host}\uc5d0\uc11c \uc77d\uc9c0 \uc54a\uc74c',
    allowAndAdd: '\ud5c8\uc6a9 \ubc0f \ucd94\uac00',
    update: '\uc5c5\ub370\uc774\ud2b8',
    cancel: '\ucde8\uc18c',
    noNewPermissions: '\ubc84\uc804 {version}. \uc0c8 \uad8c\ud55c \uc5c6\uc74c.',
    inspect: '\uac80\uc0ac',
    hideInspect: '\uac80\uc0ac \uc228\uae30\uae30',
    share: '\uacf5\uc720',
    edit: '\ud3b8\uc9d1',
    rename: '\uc774\ub984 \ubcc0\uacbd',
    pause: '\uc77c\uc2dc\uc911\uc9c0',
    resume: '\uc7ac\uac1c',
    pinToTop: '\uc0c1\ub2e8 \uace0\uc815',
    unpin: '\uace0\uc815 \ud574\uc81c',
    moveUp: '\uc704\ub85c',
    moveDown: '\uc544\ub798\ub85c',
    revert: '\ub418\ub3cc\ub9ac\uae30',
    deleteLabel: '\uc0ad\uc81c',
    undo: '\uc2e4\ud589 \ucde8\uc18c',
    temporary: '\uc784\uc2dc',
    pinned: '\uace0\uc815\ub428',
    pinToVibeSpace: 'Vibe Space\uc5d0 \uace0\uc815',
    pinnedToVibeSpace: 'Vibe Space\uc5d0 \uace0\uc815\ub428',
    madeByAgent: '\uc774 \ub2f5\ubcc0\uc744 \uc704\ud574 \uc5d0\uc774\uc804\ud2b8\uac00 \uc0dd\uc131',
    retry: '\uc7ac\uc2dc\ub3c4',
    previewSample: '\uc0d8\ud50c \ubbf8\ub9ac\ubcf4\uae30',
    returnToLive: '\uc2e4\uc2dc\uac04\uc73c\ub85c \ub3cc\uc544\uac00\uae30',
    sourceOffline: '\uc18c\uc2a4 \uc624\ud504\ub77c\uc778',
    sourceRevoked: '\uc18c\uc2a4 \uc811\uadfc \uaebc\uc9d0',
    sourceMissing: '\uc18c\uc2a4 \uc0ac\uc6a9 \ubd88\uac00'
  },
  es: {
    locale: 'es',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: 'Lo que ofrece {host}',
    wishPlaceholder: 'Ojal\u00e1 {host} pudiera\u2026',
    send: 'Enviar',
    wishNote: 'La IA est\u00e1 guionizada en esta demo. Elige un deseo.',
    installed: 'Instalados',
    filterPlaceholder: 'Filtrar vibes instalados\u2026',
    emptyInstalled: 'Nada aqu\u00ed a\u00fan. Pide un deseo.',
    sealedLegend: 'Los valores con candado est\u00e1n sellados. {host} los dibuja; el vibe nunca los ve.',
    portableVibes: 'Vibes port\u00e1tiles',
    portableSub: 'No necesitan nada de la app, as\u00ed que funcionan en cualquier lugar.',
    reads: 'Lee',
    shows: 'Muestra',
    cannot: 'No puede',
    onlyInsideBox: 'Solo dentro de su propia caja',
    changeNothing: 'Cambiar algo en {host}',
    nothingFromHost: 'Nada de {host}',
    allowAndAdd: 'Permitir y a\u00f1adir',
    update: 'Actualizar',
    cancel: 'Cancelar',
    noNewPermissions: 'Versi\u00f3n {version}. Sin permisos nuevos.',
    inspect: 'Inspeccionar',
    hideInspect: 'Ocultar inspecci\u00f3n',
    share: 'Compartir',
    edit: 'Editar',
    rename: 'Renombrar',
    pause: 'Pausar',
    resume: 'Reanudar',
    pinToTop: 'Fijar arriba',
    unpin: 'Desfijar',
    moveUp: 'Subir',
    moveDown: 'Bajar',
    revert: 'Revertir',
    deleteLabel: 'Eliminar',
    undo: 'Deshacer',
    temporary: 'Temporal',
    pinned: 'Fijado',
    pinToVibeSpace: 'Fijar en Vibe Space',
    pinnedToVibeSpace: 'Fijado en Vibe Space',
    madeByAgent: 'Hecho por el agente para esta respuesta',
    retry: 'Reintentar',
    previewSample: 'Ver muestra',
    returnToLive: 'Volver a en vivo',
    sourceOffline: 'Fuente desconectada',
    sourceRevoked: 'Acceso desactivado',
    sourceMissing: 'Fuente no disponible'
  },
  fr: {
    locale: 'fr',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: 'Ce que propose {host}',
    wishPlaceholder: 'Je voudrais que {host}\u2026',
    send: 'Envoyer',
    wishNote: 'L\u2019IA est script\u00e9e dans cette d\u00e9mo. Choisissez un souhait.',
    installed: 'Install\u00e9s',
    filterPlaceholder: 'Filtrer les vibes install\u00e9s\u2026',
    emptyInstalled: 'Rien ici pour le moment. Faites un souhait.',
    sealedLegend: 'Les valeurs verrouill\u00e9es sont scell\u00e9es. {host} les affiche sans les r\u00e9v\u00e9ler.',
    portableVibes: 'Vibes portables',
    portableSub: 'Aucun acc\u00e8s requis, ils fonctionnent partout.',
    reads: 'Lit',
    shows: 'Affiche',
    cannot: 'Ne peut pas',
    onlyInsideBox: 'Uniquement dans sa propre bo\u00eete',
    changeNothing: 'Modifier quoi que ce soit dans {host}',
    nothingFromHost: 'Rien depuis {host}',
    allowAndAdd: 'Autoriser et ajouter',
    update: 'Mettre \u00e0 jour',
    cancel: 'Annuler',
    noNewPermissions: 'Version {version}. Aucune nouvelle permission.',
    inspect: 'Inspecter',
    hideInspect: 'Masquer l\u2019inspection',
    share: 'Partager',
    edit: 'Modifier',
    rename: 'Renommer',
    pause: 'Mettre en pause',
    resume: 'Reprendre',
    pinToTop: '\u00c9pingler en haut',
    unpin: 'D\u00e9s\u00e9pingler',
    moveUp: 'Monter',
    moveDown: 'Descendre',
    revert: 'R\u00e9tablir',
    deleteLabel: 'Supprimer',
    undo: 'Annuler',
    temporary: 'Temporaire',
    pinned: '\u00c9pingl\u00e9',
    pinToVibeSpace: '\u00c9pingler dans Vibe Space',
    pinnedToVibeSpace: '\u00c9pingl\u00e9 dans Vibe Space',
    madeByAgent: 'Cr\u00e9\u00e9 par l\u2019agent pour cette r\u00e9ponse',
    retry: 'R\u00e9essayer',
    previewSample: 'Aper\u00e7u exemple',
    returnToLive: 'Revenir au direct',
    sourceOffline: 'Source hors ligne',
    sourceRevoked: 'Acc\u00e8s d\u00e9sactiv\u00e9',
    sourceMissing: 'Source indisponible'
  },
  de: {
    locale: 'de',
    rtl: false,
    panelTitle: 'Vibe Space',
    whatOffers: 'Was {host} bietet',
    wishPlaceholder: 'Ich w\u00fcnschte, {host} w\u00fcrde\u2026',
    send: 'Senden',
    wishNote: 'Die KI ist in dieser Demo geskriptet. W\u00e4hle einen Wunsch.',
    installed: 'Installiert',
    filterPlaceholder: 'Installierte Vibes filtern\u2026',
    emptyInstalled: 'Noch nichts hier. \u00c4u\u00dfere einen Wunsch.',
    sealedLegend: 'Werte mit Schloss sind versiegelt. {host} zeichnet sie; der Vibe sieht sie nie.',
    portableVibes: 'Portable Vibes',
    portableSub: 'Ben\u00f6tigen nichts von der App und laufen \u00fcberall.',
    reads: 'Liest',
    shows: 'Zeigt',
    cannot: 'Kann nicht',
    onlyInsideBox: 'Nur in seiner eigenen Box',
    changeNothing: 'Etwas in {host} \u00e4ndern',
    nothingFromHost: 'Nichts von {host}',
    allowAndAdd: 'Erlauben & hinzuf\u00fcgen',
    update: 'Aktualisieren',
    cancel: 'Abbrechen',
    noNewPermissions: 'Version {version}. Keine neuen Berechtigungen.',
    inspect: 'Pr\u00fcfen',
    hideInspect: 'Pr\u00fcfung ausblenden',
    share: 'Teilen',
    edit: 'Bearbeiten',
    rename: 'Umbenennen',
    pause: 'Pausieren',
    resume: 'Fortsetzen',
    pinToTop: 'Oben anheften',
    unpin: 'L\u00f6sen',
    moveUp: 'Nach oben',
    moveDown: 'Nach unten',
    revert: 'Zur\u00fccksetzen',
    deleteLabel: 'L\u00f6schen',
    undo: 'R\u00fcckg\u00e4ngig',
    temporary: 'Tempor\u00e4r',
    pinned: 'Angeheftet',
    pinToVibeSpace: 'An Vibe Space anheften',
    pinnedToVibeSpace: 'An Vibe Space angeheftet',
    madeByAgent: 'Vom Agenten f\u00fcr diese Antwort erstellt',
    retry: 'Erneut versuchen',
    previewSample: 'Beispiel ansehen',
    returnToLive: 'Zur\u00fcck zu Live',
    sourceOffline: 'Quelle offline',
    sourceRevoked: 'Zugriff deaktiviert',
    sourceMissing: 'Quelle nicht verf\u00fcgbar'
  },
  ar: {
    locale: 'ar',
    rtl: true,
    panelTitle: '\u0645\u0633\u0627\u062d\u0629 Vibe',
    whatOffers: '\u0645\u0627 \u064a\u0642\u062f\u0645\u0647 {host}',
    wishPlaceholder: '\u0623\u062a\u0645\u0646\u0649 \u0644\u0648 \u064a\u0642\u0648\u0645 {host} \u0628\u0640\u2026',
    send: '\u0625\u0631\u0633\u0627\u0644',
    wishNote: '\u0627\u0644\u0630\u0643\u0627\u0621 \u0627\u0644\u0627\u0635\u0637\u0646\u0627\u0639\u064a \u0641\u064a \u0647\u0630\u0627 \u0627\u0644\u0639\u0631\u0636 \u0645\u0628\u0631\u0645\u062c \u0645\u0633\u0628\u0642\u064b\u0627.',
    installed: '\u0627\u0644\u0645\u062b\u0628\u062a\u0629',
    filterPlaceholder: '\u062a\u0635\u0641\u064a\u0629 \u0627\u0644\u0639\u0646\u0627\u0635\u0631 \u0627\u0644\u0645\u062b\u0628\u062a\u0629\u2026',
    emptyInstalled: '\u0644\u0627 \u064a\u0648\u062c\u062f \u0634\u064a\u0621 \u0628\u0639\u062f. \u0627\u0643\u062a\u0628 \u0637\u0644\u0628\u064b\u0627.',
    sealedLegend: '\u0627\u0644\u0642\u064a\u0645 \u0630\u0627\u062a \u0627\u0644\u0642\u0641\u0644 \u0645\u062e\u062a\u0648\u0645\u0629. \u064a\u0639\u0631\u0636\u0647\u0627 {host} \u062f\u0648\u0646 \u0623\u0646 \u064a\u0631\u0627\u0647\u0627 \u0627\u0644\u0628\u0631\u0646\u0627\u0645\u062c.',
    portableVibes: '\u0623\u062f\u0648\u0627\u062a \u0645\u062d\u0645\u0648\u0644\u0629',
    portableSub: '\u0644\u0627 \u062a\u062d\u062a\u0627\u062c \u0625\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0648\u062a\u0639\u0645\u0644 \u0641\u064a \u0623\u064a \u0645\u0643\u0627\u0646.',
    reads: '\u064a\u0642\u0631\u0623',
    shows: '\u064a\u0639\u0631\u0636',
    cannot: '\u0644\u0627 \u064a\u0645\u0643\u0646\u0647',
    onlyInsideBox: '\u062f\u0627\u062e\u0644 \u0635\u0646\u062f\u0648\u0642\u0647 \u0641\u0642\u0637',
    changeNothing: '\u062a\u063a\u064a\u064a\u0631 \u0623\u064a \u0634\u064a\u0621 \u0641\u064a {host}',
    nothingFromHost: '\u0644\u0627 \u0634\u064a\u0621 \u0645\u0646 {host}',
    allowAndAdd: '\u0633\u0645\u0627\u062d \u0648\u0625\u0636\u0627\u0641\u0629',
    update: '\u062a\u062d\u062f\u064a\u062b',
    cancel: '\u0625\u0644\u063a\u0627\u0621',
    noNewPermissions: '\u0627\u0644\u0625\u0635\u062f\u0627\u0631 {version}. \u0644\u0627 \u062a\u0648\u062c\u062f \u0623\u0630\u0648\u0646\u0627\u062a \u062c\u062f\u064a\u062f\u0629.',
    inspect: '\u0641\u062d\u0635',
    hideInspect: '\u0625\u062e\u0641\u0627\u0621 \u0627\u0644\u0641\u062d\u0635',
    share: '\u0645\u0634\u0627\u0631\u0643\u0629',
    edit: '\u062a\u0639\u062f\u064a\u0644',
    rename: '\u0625\u0639\u0627\u062f\u0629 \u062a\u0633\u0645\u064a\u0629',
    pause: '\u0625\u064a\u0642\u0627\u0641 \u0645\u0624\u0642\u062a',
    resume: '\u0627\u0633\u062a\u0626\u0646\u0627\u0641',
    pinToTop: '\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0627\u0644\u0623\u0639\u0644\u0649',
    unpin: '\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u062a\u062b\u0628\u064a\u062a',
    moveUp: '\u062a\u062d\u0631\u064a\u0643 \u0644\u0644\u0623\u0639\u0644\u0649',
    moveDown: '\u062a\u062d\u0631\u064a\u0643 \u0644\u0644\u0623\u0633\u0641\u0644',
    revert: '\u0627\u0633\u062a\u0639\u0627\u062f\u0629',
    deleteLabel: '\u062d\u0630\u0641',
    undo: '\u062a\u0631\u0627\u062c\u0639',
    temporary: '\u0645\u0624\u0642\u062a',
    pinned: '\u0645\u062b\u0628\u062a',
    pinToVibeSpace: '\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0645\u0633\u0627\u062d\u0629 Vibe',
    pinnedToVibeSpace: '\u062a\u0645 \u0627\u0644\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0645\u0633\u0627\u062d\u0629 Vibe',
    madeByAgent: '\u0623\u0646\u0634\u0623\u0647 \u0627\u0644\u0648\u0643\u064a\u0644 \u0644\u0647\u0630\u0647 \u0627\u0644\u0625\u062c\u0627\u0628\u0629',
    retry: '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629',
    previewSample: '\u0645\u0639\u0627\u064a\u0646\u0629 \u0639\u064a\u0646\u0629',
    returnToLive: '\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062d\u064a\u0629',
    sourceOffline: '\u0627\u0644\u0645\u0635\u062f\u0631 \u063a\u064a\u0631 \u0645\u062a\u0635\u0644',
    sourceRevoked: '\u062a\u0645 \u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u0648\u0635\u0648\u0644 \u0644\u0644\u0645\u0635\u062f\u0631',
    sourceMissing: '\u0627\u0644\u0645\u0635\u062f\u0631 \u063a\u064a\u0631 \u0645\u062a\u0627\u062d'
  }
};

function isPlainObject(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

export function isSealedHandle(val) {
  if (!isPlainObject(val)) return false;
  const keys = Object.keys(val);
  return keys.length === 1 && keys[0] === 'sealed' && typeof val.sealed === 'string' && val.sealed.length > 0;
}

function normalizeTone(tone) {
  return typeof tone === 'string' && VALID_TONES.has(tone) ? tone : 'default';
}

function sanitizeTextSlot(val) {
  if (isSealedHandle(val)) return { sealed: val.sealed };
  if (typeof val === 'number' && Number.isFinite(val)) return val;
  if (typeof val === 'string') return val.length > MAX_TEXT_LEN ? val.slice(0, MAX_TEXT_LEN) : val;
  if (typeof val === 'boolean') return String(val);
  if (isPlainObject(val)) {
    if (isSealedHandle(val.sealed ? { sealed: val.sealed } : null)) return { sealed: val.sealed };
    if (typeof val.literalString === 'string') return sanitizeTextSlot(val.literalString);
    if (typeof val.literalNumber === 'number') return sanitizeTextSlot(val.literalNumber);
    if (val.text !== undefined) return sanitizeTextSlot(val.text);
  }
  return '';
}

function sanitizeId(raw, fallback) {
  const s = typeof raw === 'string' && /^[a-zA-Z0-9_.-]{1,64}$/.test(raw) ? raw : fallback;
  return s;
}

function sanitizeCommand(raw, fallback = 'action') {
  if (typeof raw !== 'string' || !raw.trim()) return fallback;
  return raw.trim().slice(0, 128);
}

function sanitizeArgs(raw, depth = 0) {
  if (!isPlainObject(raw) || depth > 2) return undefined;
  const out = {};
  for (const [k, v] of Object.entries(raw)) {
    if (k === '__proto__' || k === 'constructor' || k === 'prototype') continue;
    if (v === null || typeof v === 'string' || typeof v === 'boolean' || (typeof v === 'number' && Number.isFinite(v))) {
      out[k] = v;
    } else if (isSealedHandle(v)) {
      out[k] = { sealed: v.sealed };
    } else if (isPlainObject(v) && depth < 2) {
      out[k] = sanitizeArgs(v, depth + 1);
    }
  }
  return out;
}

function attachSkylineMeta(out, node) {
  if (!out || !isPlainObject(node)) return out;
  if (isPlainObject(node.style)) out.style = sanitizeArgs(node.style, 1);
  if (typeof node.bindtap === 'string' && node.bindtap) out.bindtap = sanitizeCommand(node.bindtap);
  if (typeof node.bindinput === 'string' && node.bindinput) out.bindinput = sanitizeCommand(node.bindinput);
  if (isPlainObject(node.dataset)) out.dataset = sanitizeArgs(node.dataset, 1);
  return out;
}

function mapAdaptiveColor(color) {
  const c = typeof color === 'string' ? color.toLowerCase() : '';
  if (c === 'good') return 'ok';
  if (c === 'warning') return 'warn';
  if (c === 'attention') return 'danger';
  return 'default';
}

function parseMarkdownLines(md) {
  const text = String(md || '').slice(0, 65536);
  const lines = text.split(/\r?\n/);
  const children = [];
  let i = 0;

  while (i < lines.length && children.length < 200) {
    const line = lines[i].trim();
    if (!line) {
      i += 1;
      continue;
    }
    if (/^---+$/.test(line) || /^\*\*\*+$/.test(line)) {
      children.push({ type: 'divider' });
      i += 1;
      continue;
    }
    const headingMatch = line.match(/^#{1,6}\s+(.+)$/);
    if (headingMatch) {
      children.push({ type: 'heading', text: headingMatch[1].trim() });
      i += 1;
      continue;
    }
    if (line.startsWith('|') && i + 1 < lines.length && /^\|[\s:-]+\|/.test(lines[i + 1].trim())) {
      const parseCells = row => row.replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
      const headers = parseCells(line);
      i += 2;
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|') && rows.length < 100) {
        rows.push(parseCells(lines[i].trim()));
        i += 1;
      }
      children.push({ type: 'table', headers, rows });
      continue;
    }
    const listMatch = line.match(/^[-*+]\s+(.+)$/);
    if (listMatch) {
      children.push({ type: 'text', text: '\u2022 ' + listMatch[1].trim() });
      i += 1;
      continue;
    }
    children.push({ type: 'text', text: line });
    i += 1;
  }

  return { type: 'column', children };
}

function normalizeAdaptiveCardNode(node, budget) {
  if (!isPlainObject(node)) return null;
  if (budget.count >= MAX_VIEW_NODES) return null;
  budget.count += 1;

  const t = node.type;
  if (t === 'TextBlock') {
    const tone = mapAdaptiveColor(node.color);
    const isHeading = node.style === 'heading' || node.size === 'Large' || node.size === 'ExtraLarge' || node.size === 'Medium';
    if (isHeading) {
      return { type: 'heading', text: sanitizeTextSlot(node.text), tone };
    }
    return {
      type: 'text',
      text: sanitizeTextSlot(node.text),
      tone,
      strong: node.weight === 'Bolder' || undefined
    };
  }

  if (t === 'Container') {
    const items = Array.isArray(node.items) ? node.items : [];
    const children = items.map(item => normalizeAdaptiveCardNode(item, budget)).filter(Boolean);
    const containerType = node.style === 'emphasis' || node.style === 'good' || node.style === 'warning' || node.style === 'attention' ? 'card' : 'column';
    return { type: containerType, children, tone: mapAdaptiveColor(node.style) };
  }

  if (t === 'ColumnSet') {
    const cols = Array.isArray(node.columns) ? node.columns : [];
    const children = cols.map(col => normalizeAdaptiveCardNode(col, budget)).filter(Boolean);
    return { type: 'row', children };
  }

  if (t === 'Column') {
    const items = Array.isArray(node.items) ? node.items : [];
    const children = items.map(item => normalizeAdaptiveCardNode(item, budget)).filter(Boolean);
    return { type: 'column', children };
  }

  if (t === 'FactSet') {
    const facts = Array.isArray(node.facts) ? node.facts : [];
    return {
      type: 'table',
      headers: ['Key', 'Value'],
      rows: facts.slice(0, 100).map(f => [sanitizeTextSlot(f?.title), sanitizeTextSlot(f?.value)])
    };
  }

  if (t === 'Table') {
    const cols = Array.isArray(node.columns) ? node.columns : [];
    const rowsRaw = Array.isArray(node.rows) ? node.rows : [];
    const headers = cols.map((_, idx) => 'Col ' + (idx + 1));
    const rows = rowsRaw.slice(0, 100).map(r => {
      const cells = Array.isArray(r?.cells) ? r.cells : [];
      return cells.map(cell => {
        const items = Array.isArray(cell?.items) ? cell.items : [];
        return items[0] ? sanitizeTextSlot(items[0].text) : '';
      });
    });
    return { type: 'table', headers, rows };
  }

  if (t === 'Input.Text') {
    return {
      type: 'input',
      id: sanitizeId(node.id, 'input_' + budget.count),
      label: String(sanitizeTextSlot(node.label || node.placeholder || node.id || 'Input')),
      multiline: Boolean(node.isMultiline)
    };
  }

  if (t === 'Input.Toggle') {
    return {
      type: 'checkbox',
      id: sanitizeId(node.id, 'toggle_' + budget.count),
      label: String(sanitizeTextSlot(node.title || node.label || node.id || 'Toggle')),
      checked: node.value === 'true' || node.value === true
    };
  }

  if (t === 'Input.ChoiceSet') {
    const choices = Array.isArray(node.choices) ? node.choices : [];
    return {
      type: 'option_group',
      id: sanitizeId(node.id, 'choice_' + budget.count),
      label: String(sanitizeTextSlot(node.label || '')),
      multiSelect: Boolean(node.isMultiSelect),
      options: choices.slice(0, 50).map((c, idx) => ({
        id: sanitizeId(String(c?.value ?? idx), 'opt_' + idx),
        label: String(sanitizeTextSlot(c?.title ?? c?.value ?? ('Option ' + (idx + 1)))),
        value: typeof c?.value === 'string' ? c.value : undefined
      }))
    };
  }

  if (t === 'ActionSet') {
    const actions = Array.isArray(node.actions) ? node.actions : [];
    return {
      type: 'row',
      children: actions.map(a => normalizeAdaptiveCardNode(a, budget)).filter(Boolean)
    };
  }

  if (t === 'Action.Submit' || t === 'Action.Execute') {
    return {
      type: 'button',
      text: sanitizeTextSlot(node.title || 'Run'),
      command: sanitizeCommand(node.verb || (isPlainObject(node.data) && node.data.command) || node.title, 'submit'),
      args: sanitizeArgs(isPlainObject(node.data) ? node.data : undefined),
      tone: node.style === 'destructive' ? 'danger' : (node.style === 'positive' ? 'ok' : 'default')
    };
  }

  if (t === 'ProgressBar') {
    const v = typeof node.value === 'number' && Number.isFinite(node.value) ? Math.max(0, Math.min(1, node.value)) : 0;
    return { type: 'progress', value: v };
  }

  return null;
}

function adaptAdaptiveCard(card) {
  const budget = { count: 0 };
  const body = Array.isArray(card.body) ? card.body : [];
  const actions = Array.isArray(card.actions) ? card.actions : [];
  const children = body.map(item => normalizeAdaptiveCardNode(item, budget)).filter(Boolean);
  if (actions.length > 0) {
    const actionNodes = actions.map(a => normalizeAdaptiveCardNode(a, budget)).filter(Boolean);
    if (actionNodes.length > 0) {
      children.push({ type: 'row', children: actionNodes });
    }
  }
  return { type: 'column', children };
}

function unwrapA2uiValue(val) {
  if (isSealedHandle(val)) return { sealed: val.sealed };
  if (isPlainObject(val)) {
    if (typeof val.literalString === 'string') return val.literalString;
    if (typeof val.literalNumber === 'number') return val.literalNumber;
    if (typeof val.literalBoolean === 'boolean') return val.literalBoolean;
    if (isSealedHandle(val.sealed ? { sealed: val.sealed } : null)) return { sealed: val.sealed };
  }
  return val;
}

function adaptA2uiNode(nodeOrId, byId, visiting, depth, budget) {
  if (depth >= MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES) return null;
  let comp = nodeOrId;
  let idHint = null;
  if (typeof nodeOrId === 'string') {
    if (visiting.has(nodeOrId)) return null;
    comp = byId.get(nodeOrId);
    if (!comp) return null;
    idHint = nodeOrId;
    visiting.add(nodeOrId);
  }

  let result = null;
  try {
    if (!isPlainObject(comp)) return null;
    budget.count += 1;

    let typeName = comp.type;
    let props = comp;
    if (isPlainObject(comp.component)) {
      const entries = Object.entries(comp.component);
      if (entries.length > 0) {
        typeName = entries[0][0];
        props = isPlainObject(entries[0][1]) ? entries[0][1] : {};
      }
    }

    const resolveChildRefs = rawChildren => {
      let refs = [];
      if (Array.isArray(rawChildren)) refs = rawChildren;
      else if (isPlainObject(rawChildren) && Array.isArray(rawChildren.explicitList)) refs = rawChildren.explicitList;
      else if (typeof props.child === 'string') refs = [props.child];
      return refs.map(c => adaptA2uiNode(c, byId, visiting, depth + 1, budget)).filter(Boolean);
    };

    const tone = normalizeTone(props.tone);
    switch (typeName) {
      case 'Heading':
        result = { type: 'heading', text: sanitizeTextSlot(unwrapA2uiValue(props.text)), tone };
        break;
      case 'Text': {
        const hint = typeof props.usageHint === 'string' ? props.usageHint.toLowerCase() : '';
        if (hint === 'h1' || hint === 'h2' || hint === 'h3' || hint === 'heading') {
          result = { type: 'heading', text: sanitizeTextSlot(unwrapA2uiValue(props.text)), tone };
        } else {
          result = {
            type: 'text',
            text: sanitizeTextSlot(unwrapA2uiValue(props.text)),
            tone,
            strong: Boolean(props.strong || props.bold) || undefined,
            mono: Boolean(props.mono || props.code) || undefined
          };
        }
        break;
      }
      case 'Badge':
        result = { type: 'badge', text: sanitizeTextSlot(unwrapA2uiValue(props.text)), tone };
        break;
      case 'Metric':
      case 'Stat':
        result = {
          type: 'stat',
          label: sanitizeTextSlot(unwrapA2uiValue(props.label)),
          value: sanitizeTextSlot(unwrapA2uiValue(props.value)),
          tone
        };
        break;
      case 'Bar':
        result = {
          type: 'bar',
          label: sanitizeTextSlot(unwrapA2uiValue(props.label)),
          value: Number.isFinite(Number(props.value)) ? Number(props.value) : 0,
          max: Number.isFinite(Number(props.max)) && Number(props.max) > 0 ? Number(props.max) : 1,
          caption: props.caption !== undefined ? sanitizeTextSlot(unwrapA2uiValue(props.caption)) : undefined,
          swatch: typeof props.swatch === 'string' && VALID_HEX_COLOR.test(props.swatch) ? props.swatch : undefined,
          tone
        };
        break;
      case 'Sparkline':
        result = {
          type: 'sparkline',
          values: Array.isArray(props.values) ? props.values.filter(n => typeof n === 'number' && Number.isFinite(n)).slice(0, 240) : [],
          tone
        };
        break;
      case 'Button': {
        let label = props.text;
        if (label === undefined && typeof props.child === 'string') {
          const childNode = adaptA2uiNode(props.child, byId, visiting, depth + 1, budget);
          if (childNode && childNode.text !== undefined) label = childNode.text;
        }
        const actionName = isPlainObject(props.action) ? props.action.name : props.command;
        const actionCtx = isPlainObject(props.action) && isPlainObject(props.action.context)
          ? props.action.context
          : (props.args || props.arguments);
        result = {
          type: 'button',
          text: sanitizeTextSlot(unwrapA2uiValue(label ?? 'Action')),
          command: sanitizeCommand(actionName, 'action'),
          args: sanitizeArgs(actionCtx),
          tone
        };
        break;
      }
      case 'Card':
        result = { type: 'card', children: resolveChildRefs(props.children), tone };
        break;
      case 'Row':
        result = { type: 'row', children: resolveChildRefs(props.children), tone };
        break;
      case 'Column':
        result = { type: 'column', children: resolveChildRefs(props.children), tone };
        break;
      case 'TextField':
        result = {
          type: 'input',
          id: sanitizeId(props.id || idHint, 'field_' + budget.count),
          label: String(sanitizeTextSlot(unwrapA2uiValue(props.label || 'Input'))),
          secret: props.obscured === true || props.secret === true || undefined,
          multiline: props.multiline === true || undefined
        };
        break;
      case 'CheckBox':
        result = {
          type: 'checkbox',
          id: sanitizeId(props.id || idHint, 'cb_' + budget.count),
          label: String(sanitizeTextSlot(unwrapA2uiValue(props.label || 'Option'))),
          checked: Boolean(unwrapA2uiValue(props.value ?? props.checked)),
          command: typeof props.command === 'string' ? sanitizeCommand(props.command) : undefined
        };
        break;
      case 'MultipleChoice':
        result = {
          type: 'option_group',
          id: sanitizeId(props.id || idHint, 'choice_' + budget.count),
          label: props.label !== undefined ? String(sanitizeTextSlot(unwrapA2uiValue(props.label))) : undefined,
          multiSelect: Boolean(props.maxAllowedSelections !== 1 && props.multiSelect !== false ? props.multiSelect : false),
          options: (Array.isArray(props.options) ? props.options : []).slice(0, 50).map((o, idx) => ({
            id: sanitizeId(String(o?.id ?? o?.value ?? idx), 'opt_' + idx),
            label: String(sanitizeTextSlot(unwrapA2uiValue(o?.label ?? o?.value ?? ('Option ' + (idx + 1))))),
            value: typeof o?.value === 'string' ? o.value : undefined
          }))
        };
        break;
      case 'ProgressBar':
      case 'LinearProgress':
        result = {
          type: 'progress',
          value: typeof props.value === 'number' && Number.isFinite(props.value) ? Math.max(0, Math.min(1, props.value)) : 0,
          tone
        };
        break;
      case 'Table':
        result = {
          type: 'table',
          headers: (Array.isArray(props.headers) ? props.headers : []).slice(0, 32).map(h => sanitizeTextSlot(unwrapA2uiValue(h))),
          rows: (Array.isArray(props.rows) ? props.rows : []).slice(0, 200).map(r =>
            (Array.isArray(r) ? r : []).slice(0, 32).map(cell => sanitizeTextSlot(unwrapA2uiValue(cell)))
          )
        };
        break;
      case 'Divider':
        result = { type: 'divider' };
        break;
      default:
        result = null;
    }
  } finally {
    if (typeof nodeOrId === 'string') visiting.delete(nodeOrId);
  }
  return result;
}

function isA2uiPayload(raw) {
  if (!isPlainObject(raw)) return false;
  if (isPlainObject(raw.surfaceUpdate) && Array.isArray(raw.surfaceUpdate.components)) return true;
  if (Array.isArray(raw.components)) return true;
  if (isPlainObject(raw.component)) return true;
  const a2uiTypes = new Set([
    'Text', 'Heading', 'Badge', 'Button', 'Card', 'Row', 'Column',
    'TextField', 'CheckBox', 'MultipleChoice', 'ProgressBar', 'LinearProgress',
    'Metric', 'Stat', 'Table', 'Divider', 'Bar', 'Sparkline'
  ]);
  return typeof raw.type === 'string' && a2uiTypes.has(raw.type);
}

function normalizeCanonicalNode(node, depth, budget) {
  if (!isPlainObject(node) || depth >= MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES) return null;
  budget.count += 1;

  const t = node.type;
  const tone = normalizeTone(node.tone);

  if (t === 'column' || t === 'row' || t === 'card') {
    const kids = Array.isArray(node.children) ? node.children : [];
    const out = { type: t, children: kids.map(c => normalizeCanonicalNode(c, depth + 1, budget)).filter(Boolean) };
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'heading') {
    const out = { type: 'heading', text: sanitizeTextSlot(node.text) };
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'text') {
    const out = { type: 'text', text: sanitizeTextSlot(node.text) };
    if (tone !== 'default') out.tone = tone;
    if (node.strong || node.bold) out.strong = true;
    if (node.mono || node.code) out.mono = true;
    if (node.italic) out.italic = true;
    return attachSkylineMeta(out, node);
  }
  if (t === 'badge') {
    const out = { type: 'badge', text: sanitizeTextSlot(node.text) };
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'stat') {
    const out = { type: 'stat', label: sanitizeTextSlot(node.label), value: sanitizeTextSlot(node.value) };
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'bar') {
    const val = typeof node.value === 'number' && Number.isFinite(node.value) ? node.value : 0;
    const max = typeof node.max === 'number' && Number.isFinite(node.max) && node.max > 0 ? node.max : 1;
    const out = { type: 'bar', label: sanitizeTextSlot(node.label), value: val, max };
    if (node.caption !== undefined) out.caption = sanitizeTextSlot(node.caption);
    if (typeof node.swatch === 'string' && VALID_HEX_COLOR.test(node.swatch)) out.swatch = node.swatch;
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'sparkline') {
    const vals = Array.isArray(node.values) ? node.values.filter(n => typeof n === 'number' && Number.isFinite(n)).slice(0, 240) : [];
    const out = { type: 'sparkline', values: vals };
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'canvas') {
    if (!Array.isArray(node.commands)) {
      throw new Error('canvas node requires a commands array');
    }
    budget.canvasCommands = (budget.canvasCommands || 0) + node.commands.length;
    if (node.commands.length > MAX_CANVAS_COMMANDS || budget.canvasCommands > MAX_CANVAS_COMMANDS) {
      throw new Error(`canvas command budget (${MAX_CANVAS_COMMANDS}) exceeded`);
    }
    const width = typeof node.width === 'number' && Number.isFinite(node.width)
      ? Math.max(16, Math.min(2048, node.width))
      : 260;
    const height = typeof node.height === 'number' && Number.isFinite(node.height)
      ? Math.max(16, Math.min(2048, node.height))
      : 56;
    const commands = [];
    for (const rawCmd of node.commands) {
      if (!isPlainObject(rawCmd)) throw new Error('Invalid canvas command');
      const op = String(rawCmd.op || rawCmd.type || '');
      if (!VALID_CANVAS_OPS.has(op)) throw new Error(`Unsupported canvas op "${op}"`);
      const cmd = { ...rawCmd, op };
      if (cmd.text !== undefined) cmd.text = sanitizeTextSlot(cmd.text);
      commands.push(cmd);
    }
    const out = { type: 'canvas', width, height, commands };
    if (tone !== 'default') out.tone = tone;
    if (typeof node.command === 'string') out.command = sanitizeCommand(node.command);
    return attachSkylineMeta(out, node);
  }
  if (t === 'button' || t === 'action') {
    const out = {
      type: t,
      command: sanitizeCommand(node.command)
    };
    if (t === 'button') out.text = sanitizeTextSlot(node.text ?? node.title ?? 'Run');
    else out.title = String(sanitizeTextSlot(node.title ?? node.text ?? 'Run'));
    const args = sanitizeArgs(node.args ?? node.arguments);
    if (args) {
      if (t === 'button') out.args = args;
      else out.arguments = args;
    }
    if (tone !== 'default') out.tone = tone;
    return attachSkylineMeta(out, node);
  }
  if (t === 'table') {
    const headers = Array.isArray(node.headers) ? node.headers.slice(0, 32).map(h => sanitizeTextSlot(h)) : [];
    const rows = Array.isArray(node.rows)
      ? node.rows.slice(0, 200).map(r => (Array.isArray(r) ? r.slice(0, 32).map(c => sanitizeTextSlot(c)) : []))
      : [];
    return attachSkylineMeta({ type: 'table', headers, rows }, node);
  }
  if (t === 'input') {
    return attachSkylineMeta({
      type: 'input',
      id: sanitizeId(node.id, 'input_' + budget.count),
      label: String(sanitizeTextSlot(node.label || 'Input')),
      secret: Boolean(node.secret) || undefined,
      multiline: Boolean(node.multiline) || undefined
    }, node);
  }
  if (t === 'checkbox') {
    return {
      type: 'checkbox',
      id: sanitizeId(node.id, 'cb_' + budget.count),
      label: String(sanitizeTextSlot(node.label || 'Option')),
      checked: Boolean(node.checked),
      command: typeof node.command === 'string' ? sanitizeCommand(node.command) : undefined
    };
  }
  if (t === 'option_group') {
    return {
      type: 'option_group',
      id: sanitizeId(node.id, 'opt_' + budget.count),
      label: node.label !== undefined ? String(sanitizeTextSlot(node.label)) : undefined,
      multiSelect: Boolean(node.multiSelect),
      command: typeof node.command === 'string' ? sanitizeCommand(node.command) : undefined,
      options: (Array.isArray(node.options) ? node.options : []).slice(0, 50).map((o, idx) => ({
        id: sanitizeId(String(o?.id ?? idx), 'opt_' + idx),
        label: String(sanitizeTextSlot(o?.label ?? ('Option ' + (idx + 1)))),
        value: typeof o?.value === 'string' ? o.value : undefined,
        checked: typeof o?.checked === 'boolean' ? o.checked : undefined,
        selected: typeof o?.selected === 'boolean' ? o.selected : undefined
      })),
      autoSubmitTimeoutSeconds: typeof node.autoSubmitTimeoutSeconds === 'number' && Number.isFinite(node.autoSubmitTimeoutSeconds)
        ? node.autoSubmitTimeoutSeconds
        : undefined
    };
  }
  if (t === 'progress') {
    const v = typeof node.value === 'number' && Number.isFinite(node.value) ? Math.max(0, Math.min(1, node.value)) : 0;
    const out = { type: 'progress', value: v };
    if (tone !== 'default') out.tone = tone;
    return out;
  }
  if (t === 'divider') return { type: 'divider' };
  return null;
}

export function adaptExternalUi(raw) {
  if (typeof raw === 'string') {
    return parseMarkdownLines(raw);
  }
  if (!isPlainObject(raw)) {
    throw new Error('External UI payload must be an object or markdown string');
  }
  if (raw.format === 'markdown' || typeof raw.markdown === 'string') {
    return parseMarkdownLines(raw.markdown || '');
  }
  if (raw.type === 'AdaptiveCard') {
    return adaptAdaptiveCard(raw);
  }
  if (isA2uiPayload(raw)) {
    const surface = isPlainObject(raw.surfaceUpdate) ? raw.surfaceUpdate : raw;
    if (Array.isArray(surface.components)) {
      const byId = new Map();
      for (const entry of surface.components) {
        if (isPlainObject(entry) && typeof entry.id === 'string') {
          byId.set(entry.id, entry);
        }
      }
      const rootId = typeof surface.root === 'string'
        ? surface.root
        : (byId.has('root') ? 'root' : (surface.components[0]?.id || null));
      if (!rootId) return { type: 'column', children: [] };
      return adaptA2uiNode(rootId, byId, new Set(), 0, { count: 0 }) || { type: 'column', children: [] };
    }
    return adaptA2uiNode(raw, new Map(), new Set(), 0, { count: 0 }) || { type: 'column', children: [] };
  }
  const normalized = normalizeCanonicalNode(raw, 0, { count: 0 });
  if (!normalized) {
    throw new Error('Unsupported or empty UI view node');
  }
  return normalized;
}

function resolveSlot(val, resolveSealed) {
  if (isSealedHandle(val)) {
    if (typeof resolveSealed !== 'function') {
      return { text: '', sealed: true, sealedResolved: false };
    }
    const resolved = resolveSealed(val.sealed, val);
    if (resolved === null || resolved === undefined || String(resolved) === '') {
      return { text: '', sealed: true, sealedResolved: false };
    }
    return { text: String(resolved), sealed: true, sealedResolved: true };
  }
  return {
    text: val === null || val === undefined ? '' : String(val),
    sealed: false,
    sealedResolved: false
  };
}

export function resolveViewTree(view, { resolveSealed } = {}) {
  const canonical = adaptExternalUi(view);
  function walk(node) {
    if (!node || typeof node !== 'object') return null;
    const t = node.type;
    if (t === 'column' || t === 'row' || t === 'card') {
      return {
        type: t,
        tone: normalizeTone(node.tone),
        children: (Array.isArray(node.children) ? node.children : []).map(walk).filter(Boolean)
      };
    }
    if (t === 'heading' || t === 'text' || t === 'badge') {
      const slot = resolveSlot(node.text, resolveSealed);
      return {
        type: t,
        tone: normalizeTone(node.tone),
        text: slot.text,
        sealed: slot.sealed,
        sealedResolved: slot.sealedResolved,
        strong: Boolean(node.strong),
        mono: Boolean(node.mono)
      };
    }
    if (t === 'stat') {
      const labelSlot = resolveSlot(node.label, resolveSealed);
      const valSlot = resolveSlot(node.value, resolveSealed);
      return {
        type: 'stat',
        tone: normalizeTone(node.tone),
        label: labelSlot.text,
        labelSealed: labelSlot.sealed,
        labelSealedResolved: labelSlot.sealedResolved,
        value: valSlot.text,
        valueSealed: valSlot.sealed,
        valueSealedResolved: valSlot.sealedResolved
      };
    }
    if (t === 'bar') {
      const labelSlot = resolveSlot(node.label, resolveSealed);
      const capSlot = node.caption !== undefined ? resolveSlot(node.caption, resolveSealed) : null;
      const max = typeof node.max === 'number' && node.max > 0 ? node.max : 1;
      const ratio = Math.max(0, Math.min(1, (typeof node.value === 'number' ? node.value : 0) / max));
      return {
        type: 'bar',
        tone: normalizeTone(node.tone),
        label: labelSlot.text,
        labelSealed: labelSlot.sealed,
        labelSealedResolved: labelSlot.sealedResolved,
        caption: capSlot ? capSlot.text : '',
        captionSealed: capSlot ? capSlot.sealed : false,
        captionSealedResolved: capSlot ? capSlot.sealedResolved : false,
        value: typeof node.value === 'number' ? node.value : 0,
        max,
        ratio,
        swatch: node.swatch
      };
    }
    if (t === 'sparkline') {
      return {
        type: 'sparkline',
        tone: normalizeTone(node.tone),
        values: Array.isArray(node.values) ? node.values.slice() : []
      };
    }
    if (t === 'canvas') {
      return {
        type: 'canvas',
        tone: normalizeTone(node.tone),
        width: node.width || 260,
        height: node.height || 56,
        bindtap: node.bindtap,
        command: node.command,
        dataset: node.dataset,
        commands: (node.commands || []).map(cmd => {
          if (cmd.text === undefined) return { ...cmd };
          const slot = resolveSlot(cmd.text, resolveSealed);
          return { ...cmd, text: slot.text, sealed: slot.sealed, sealedResolved: slot.sealedResolved };
        })
      };
    }
    if (t === 'button' || t === 'action') {
      const textSlot = resolveSlot(t === 'button' ? node.text : node.title, resolveSealed);
      return {
        type: 'button',
        tone: normalizeTone(node.tone),
        text: textSlot.text,
        sealed: textSlot.sealed,
        sealedResolved: textSlot.sealedResolved,
        command: node.command,
        args: node.args || node.arguments || {}
      };
    }
    if (t === 'table') {
      return {
        type: 'table',
        headers: (node.headers || []).map(h => resolveSlot(h, resolveSealed)),
        rows: (node.rows || []).map(r => (r || []).map(c => resolveSlot(c, resolveSealed)))
      };
    }
    return { ...node };
  }
  return walk(canonical);
}

function renderSlotWithH(h, slot, prefix) {
  if (slot.sealed) {
    if (!slot.sealedResolved) return '';
    return h('span', { className: prefix + '-sealed' }, slot.text);
  }
  return slot.text;
}

export function renderWithH(h, view, { resolveSealed, onCommand, onInput, classPrefix = 'vk' } = {}) {
  if (typeof h !== 'function') {
    throw new Error('renderWithH requires a hyperscript/createElement function h');
  }
  const tree = resolveViewTree(view, { resolveSealed });

  function renderNode(node, key) {
    if (!node) return null;
    const toneCls = node.tone && node.tone !== 'default' ? ' ' + classPrefix + '-tone-' + node.tone : '';
    const t = node.type;

    if (t === 'column' || t === 'row' || t === 'card') {
      return h(
        'div',
        { key, className: classPrefix + '-' + t + toneCls },
        ...(node.children || []).map((c, idx) => renderNode(c, idx))
      );
    }
    if (t === 'heading') {
      return h('div', { key, className: classPrefix + '-heading' + toneCls }, renderSlotWithH(h, node, classPrefix));
    }
    if (t === 'text') {
      let cls = classPrefix + '-text' + toneCls;
      if (node.strong) cls += ' ' + classPrefix + '-strong';
      if (node.mono) cls += ' ' + classPrefix + '-mono';
      return h('div', { key, className: cls }, renderSlotWithH(h, node, classPrefix));
    }
    if (t === 'badge') {
      return h('span', { key, className: classPrefix + '-badge' + toneCls }, renderSlotWithH(h, node, classPrefix));
    }
    if (t === 'stat') {
      return h(
        'div',
        { key, className: classPrefix + '-stat' + toneCls },
        h('div', { className: classPrefix + '-stat-value' }, renderSlotWithH(h, { text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved }, classPrefix)),
        h('div', { className: classPrefix + '-stat-label' }, renderSlotWithH(h, { text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }, classPrefix))
      );
    }
    if (t === 'bar') {
      const headKids = [];
      if (node.swatch) {
        headKids.push(h('span', { className: classPrefix + '-bar-swatch', style: { backgroundColor: node.swatch } }));
      }
      headKids.push(h('span', { className: classPrefix + '-bar-label' }, renderSlotWithH(h, { text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }, classPrefix)));
      if (node.caption || node.captionSealed) {
        headKids.push(h('span', { className: classPrefix + '-bar-caption' }, renderSlotWithH(h, { text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved }, classPrefix)));
      }
      return h(
        'div',
        { key, className: classPrefix + '-bar' + toneCls },
        h('div', { className: classPrefix + '-bar-head' }, ...headKids),
        h(
          'div',
          { className: classPrefix + '-bar-track' },
          h('div', { className: classPrefix + '-bar-fill', style: { width: Math.round(node.ratio * 1000) / 10 + '%' } })
        )
      );
    }
    if (t === 'sparkline') {
      const vals = node.values || [];
      let pts = '';
      if (vals.length >= 2) {
        const min = Math.min(...vals);
        const max = Math.max(...vals);
        const span = max - min || 1;
        pts = vals.map((v, idx) => {
          const x = (idx / (vals.length - 1)) * 100;
          const y = 26 - ((v - min) / span) * 24;
          return x.toFixed(1) + ',' + y.toFixed(1);
        }).join(' ');
      }
      return h(
        'svg',
        { key, className: classPrefix + '-sparkline' + toneCls, viewBox: '0 0 100 28', preserveAspectRatio: 'none' },
        h('polyline', { points: pts, fill: 'none' })
      );
    }
    if (t === 'canvas') {
      const w = node.width || 260;
      const hgt = node.height || 56;
      const svgKids = [];
      (node.commands || []).slice(0, MAX_CANVAS_COMMANDS).forEach((cmd, idx) => {
        if (cmd.op === 'clear') {
          svgKids.push(h('rect', { key: idx, x: 0, y: 0, width: w, height: hgt, fill: cmd.fill || 'transparent' }));
        } else if (cmd.op === 'rect' || cmd.op === 'rrect') {
          svgKids.push(h('rect', { key: idx, x: cmd.x || 0, y: cmd.y || 0, width: cmd.w ?? cmd.width ?? w, height: cmd.h ?? cmd.height ?? hgt, rx: cmd.radius || cmd.r || 0, fill: cmd.fill || 'none', stroke: cmd.stroke }));
        } else if (cmd.op === 'circle') {
          svgKids.push(h('circle', { key: idx, cx: cmd.cx ?? cmd.x ?? 0, cy: cmd.cy ?? cmd.y ?? 0, r: cmd.r ?? cmd.radius ?? 4, fill: cmd.fill || 'none', stroke: cmd.stroke }));
        } else if (cmd.op === 'line') {
          svgKids.push(h('line', { key: idx, x1: cmd.x1 || 0, y1: cmd.y1 || 0, x2: cmd.x2 || 0, y2: cmd.y2 || 0, stroke: cmd.stroke || cmd.fill || 'currentColor', strokeWidth: cmd.strokeWidth || 1.5 }));
        } else if (cmd.op === 'bars' && Array.isArray(cmd.values) && cmd.values.length > 0) {
          const vals = cmd.values.filter(v => typeof v === 'number' && Number.isFinite(v));
          const max = typeof cmd.max === 'number' && cmd.max > 0 ? cmd.max : Math.max(1, ...vals);
          const bx = cmd.x || 0, by = cmd.y || 0, bw = cmd.w ?? cmd.width ?? (w - bx), bh = cmd.h ?? cmd.height ?? (hgt - by), gap = cmd.gap ?? 2;
          const barW = Math.max(1, (bw - gap * (vals.length - 1)) / Math.max(1, vals.length));
          vals.forEach((v, j) => {
            const barH = Math.max(1.5, Math.min(1, Math.max(0, v / max)) * bh);
            svgKids.push(h('rect', { key: `${idx}_${j}`, x: bx + j * (barW + gap), y: by + (bh - barH), width: barW, height: barH, rx: cmd.radius ?? 2, fill: cmd.fill || 'currentColor' }));
          });
        } else if (cmd.op === 'text' && cmd.text) {
          svgKids.push(h('text', { key: idx, x: cmd.x || 0, y: (cmd.y || 0) + (cmd.fontSize || 11), fill: cmd.fill || 'currentColor', fontSize: cmd.fontSize || 11 }, cmd.text));
        }
      });
      return h(
        'svg',
        {
          key,
          className: classPrefix + '-canvas' + toneCls,
          viewBox: `0 0 ${w} ${hgt}`,
          width: w,
          height: hgt,
          onClick: (node.bindtap || node.command) && typeof onCommand === 'function'
            ? () => {
                if (node.bindtap) onCommand(`mp:tap:${node.bindtap}`, { __mpEvent: true, type: 'tap', handler: node.bindtap, dataset: node.dataset || {} });
                else onCommand(node.command, {});
              }
            : undefined
        },
        ...svgKids
      );
    }
    if (t === 'button') {
      return h(
        'button',
        {
          key,
          type: 'button',
          className: classPrefix + '-button' + toneCls,
          onClick: () => {
            if (typeof onCommand === 'function') onCommand(node.command, node.args || {});
          }
        },
        renderSlotWithH(h, node, classPrefix)
      );
    }
    if (t === 'table') {
      return h(
        'table',
        { key, className: classPrefix + '-table' },
        h('thead', null, h('tr', null, ...node.headers.map((hdr, i) => h('th', { key: i }, renderSlotWithH(h, hdr, classPrefix))))),
        h('tbody', null, ...node.rows.map((r, rIdx) => h('tr', { key: rIdx }, ...r.map((c, cIdx) => h('td', { key: cIdx }, renderSlotWithH(h, c, classPrefix))))))
      );
    }
    if (t === 'divider') {
      return h('hr', { key, className: classPrefix + '-divider' });
    }
    if (t === 'progress') {
      return h(
        'div',
        { key, className: classPrefix + '-progress' + toneCls },
        h('div', { className: classPrefix + '-progress-fill', style: { width: Math.round((node.value || 0) * 100) + '%' } })
      );
    }
    if (t === 'input') {
      return h(
        'label',
        { key, className: classPrefix + '-field' },
        h('span', { className: classPrefix + '-field-label' }, node.label || ''),
        h('input', {
          type: node.secret ? 'password' : 'text',
          className: classPrefix + '-input',
          onInput: e => {
            if (typeof onInput === 'function') onInput(node.id, e?.target?.value ?? '');
          }
        })
      );
    }
    if (t === 'checkbox') {
      return h(
        'label',
        { key, className: classPrefix + '-checkbox' },
        h('input', {
          type: 'checkbox',
          checked: Boolean(node.checked),
          onChange: e => {
            const val = Boolean(e?.target?.checked);
            if (typeof onInput === 'function') onInput(node.id, val);
            if (node.command && typeof onCommand === 'function') onCommand(node.command, { id: node.id, checked: val });
          }
        }),
        h('span', null, node.label || '')
      );
    }
    return null;
  }

  return renderNode(tree, 0);
}

function formatTerminalSlot(slot) {
  if (!slot.sealed) return slot.text;
  return slot.sealedResolved ? '\ud83d\udd12 ' + slot.text : '';
}

function wrapAnsi(text, tone, ansi) {
  if (!ansi) return text;
  if (tone === 'ok') return '\x1b[32m' + text + '\x1b[0m';
  if (tone === 'warn') return '\x1b[33m' + text + '\x1b[0m';
  if (tone === 'danger') return '\x1b[31m' + text + '\x1b[0m';
  return text;
}

export function renderToTerminal(view, { resolveSealed, ansi = false, width = 72 } = {}) {
  const tree = resolveViewTree(view, { resolveSealed });
  const lines = [];
  const barWidth = Math.max(10, Math.min(28, Math.floor(width / 3)));
  const sparks = '\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588';

  function emit(node) {
    if (!node) return;
    const t = node.type;
    if (t === 'column' || t === 'row' || t === 'card') {
      if (t === 'card') lines.push('\u250c' + '\u2500'.repeat(Math.max(12, Math.min(width - 2, 40))));
      for (const c of node.children || []) emit(c);
      if (t === 'card') lines.push('\u2514' + '\u2500'.repeat(Math.max(12, Math.min(width - 2, 40))));
      return;
    }
    if (t === 'heading') {
      lines.push(wrapAnsi(formatTerminalSlot(node).toUpperCase(), node.tone, ansi));
      return;
    }
    if (t === 'text' || t === 'badge') {
      const txt = formatTerminalSlot(node);
      lines.push(wrapAnsi(t === 'badge' ? '[' + txt + ']' : txt, node.tone, ansi));
      return;
    }
    if (t === 'stat') {
      const l = formatTerminalSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
      const v = formatTerminalSlot({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved });
      lines.push(l + ': ' + wrapAnsi(v, node.tone, ansi));
      return;
    }
    if (t === 'bar') {
      const lbl = formatTerminalSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
      const cap = formatTerminalSlot({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved });
      const filled = Math.round(node.ratio * barWidth);
      const track = '\u2588'.repeat(filled) + '\u2591'.repeat(Math.max(0, barWidth - filled));
      lines.push(lbl + ' ' + wrapAnsi(track, node.tone, ansi) + (cap ? ' ' + cap : ''));
      return;
    }
    if (t === 'sparkline') {
      const vals = node.values || [];
      if (vals.length === 0) return;
      const min = Math.min(...vals);
      const max = Math.max(...vals);
      const span = max - min || 1;
      const s = vals.map(v => sparks[Math.max(0, Math.min(7, Math.round(((v - min) / span) * 7)))]).join('');
      lines.push(wrapAnsi(s, node.tone, ansi));
      return;
    }
    if (t === 'canvas') {
      const parts = [];
      for (const cmd of node.commands || []) {
        if (cmd.op === 'bars' && Array.isArray(cmd.values) && cmd.values.length > 0) {
          const min = Math.min(...cmd.values);
          const max = Math.max(...cmd.values);
          const span = max - min || 1;
          parts.push(cmd.values.map(v => sparks[Math.max(0, Math.min(7, Math.round(((v - min) / span) * 7)))]).join(''));
        } else if (cmd.op === 'text' && cmd.text) {
          parts.push(cmd.sealed ? (cmd.sealedResolved ? '\ud83d\udd12 ' + cmd.text : '') : cmd.text);
        }
      }
      lines.push(wrapAnsi(parts.filter(Boolean).join(' ') || `[canvas ${node.width}x${node.height}]`, node.tone, ansi));
      return;
    }
    if (t === 'table') {
      if (node.headers.length > 0) {
        lines.push(node.headers.map(formatTerminalSlot).join(' | '));
        lines.push(node.headers.map(() => '---').join('-|-'));
      }
      for (const r of node.rows) {
        lines.push(r.map(formatTerminalSlot).join(' | '));
      }
      return;
    }
    if (t === 'divider') {
      lines.push('\u2500'.repeat(Math.min(width, 40)));
      return;
    }
    if (t === 'button') {
      lines.push('[ ' + formatTerminalSlot(node) + ' ]');
      return;
    }
    if (t === 'progress') {
      const filled = Math.round((node.value || 0) * barWidth);
      lines.push('\u2588'.repeat(filled) + '\u2591'.repeat(Math.max(0, barWidth - filled)) + ' ' + Math.round((node.value || 0) * 100) + '%');
    }
  }

  emit(tree);
  return lines.join('\n');
}

export function renderToMarkdown(view, { resolveSealed } = {}) {
  const tree = resolveViewTree(view, { resolveSealed });
  const lines = [];

  function emit(node) {
    if (!node) return;
    const t = node.type;
    if (t === 'column' || t === 'row' || t === 'card') {
      for (const c of node.children || []) emit(c);
      return;
    }
    if (t === 'heading') {
      lines.push('## ' + formatTerminalSlot(node));
      return;
    }
    if (t === 'text') {
      lines.push(formatTerminalSlot(node));
      return;
    }
    if (t === 'badge') {
      lines.push('`' + formatTerminalSlot(node) + '`');
      return;
    }
    if (t === 'stat') {
      const l = formatTerminalSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
      const v = formatTerminalSlot({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved });
      lines.push('- **' + l + ':** ' + v);
      return;
    }
    if (t === 'bar') {
      const lbl = formatTerminalSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
      const cap = formatTerminalSlot({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved });
      lines.push('- **' + lbl + '**: ' + (cap || Math.round(node.ratio * 100) + '%'));
      return;
    }
    if (t === 'table') {
      const hdrs = node.headers.map(formatTerminalSlot);
      if (hdrs.length > 0) {
        lines.push('| ' + hdrs.join(' | ') + ' |');
        lines.push('| ' + hdrs.map(() => '---').join(' | ') + ' |');
      }
      for (const r of node.rows) {
        lines.push('| ' + r.map(formatTerminalSlot).join(' | ') + ' |');
      }
      return;
    }
    if (t === 'divider') {
      lines.push('---');
      return;
    }
    if (t === 'button') {
      lines.push('[' + formatTerminalSlot(node) + ']');
      return;
    }
    if (t === 'canvas') {
      lines.push('`[canvas ' + node.width + 'x' + node.height + ']`');
    }
  }

  emit(tree);
  return lines.join('\n');
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderSlotHtml(slot) {
  if (slot.sealed) {
    if (!slot.sealedResolved) return '';
    return '<span class="vk-sealed">' + escapeHtml(slot.text) + '</span>';
  }
  return escapeHtml(slot.text);
}

export function renderToHtmlString(view, { resolveSealed } = {}) {
  const tree = resolveViewTree(view, { resolveSealed });

  function emit(node) {
    if (!node) return '';
    const toneCls = node.tone && node.tone !== 'default' ? ' vk-tone-' + escapeHtml(node.tone) : '';
    const t = node.type;

    if (t === 'column' || t === 'row' || t === 'card') {
      return '<div class="vk-' + t + toneCls + '">' + (node.children || []).map(emit).join('') + '</div>';
    }
    if (t === 'heading') {
      return '<div class="vk-heading' + toneCls + '">' + renderSlotHtml(node) + '</div>';
    }
    if (t === 'text') {
      let cls = 'vk-text' + toneCls;
      if (node.strong) cls += ' vk-strong';
      if (node.mono) cls += ' vk-mono';
      return '<div class="' + cls + '">' + renderSlotHtml(node) + '</div>';
    }
    if (t === 'badge') {
      return '<span class="vk-badge' + toneCls + '">' + renderSlotHtml(node) + '</span>';
    }
    if (t === 'stat') {
      return '<div class="vk-stat' + toneCls + '"><div class="vk-stat-value">' +
        renderSlotHtml({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved }) +
        '</div><div class="vk-stat-label">' +
        renderSlotHtml({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) +
        '</div></div>';
    }
    if (t === 'bar') {
      const swatch = node.swatch && VALID_HEX_COLOR.test(node.swatch)
        ? '<span class="vk-bar-swatch" style="background-color:' + node.swatch + '"></span>'
        : '';
      const cap = node.caption || node.captionSealed
        ? '<span class="vk-bar-caption">' + renderSlotHtml({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved }) + '</span>'
        : '';
      return '<div class="vk-bar' + toneCls + '"><div class="vk-bar-head">' + swatch +
        '<span class="vk-bar-label">' + renderSlotHtml({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) + '</span>' +
        cap + '</div><div class="vk-bar-track"><div class="vk-bar-fill" style="width:' +
        (Math.round(node.ratio * 1000) / 10) + '%"></div></div></div>';
    }
    if (t === 'sparkline') {
      const vals = node.values || [];
      let pts = '';
      if (vals.length >= 2) {
        const min = Math.min(...vals);
        const max = Math.max(...vals);
        const span = max - min || 1;
        pts = vals.map((v, idx) => ((idx / (vals.length - 1)) * 100).toFixed(1) + ',' + (26 - ((v - min) / span) * 24).toFixed(1)).join(' ');
      }
      return '<svg class="vk-sparkline' + toneCls + '" viewBox="0 0 100 28" preserveAspectRatio="none"><polyline points="' + pts + '"></polyline></svg>';
    }
    if (t === 'canvas') {
      const w = Number(node.width) || 260;
      const hgt = Number(node.height) || 56;
      const inner = (node.commands || []).slice(0, MAX_CANVAS_COMMANDS).map(cmd => {
        if (cmd.op === 'clear') return '<rect x="0" y="0" width="' + w + '" height="' + hgt + '" fill="' + escapeHtml(cmd.fill || 'transparent') + '"/>';
        if (cmd.op === 'rect' || cmd.op === 'rrect') return '<rect x="' + (Number(cmd.x) || 0) + '" y="' + (Number(cmd.y) || 0) + '" width="' + (Number(cmd.w ?? cmd.width) || w) + '" height="' + (Number(cmd.h ?? cmd.height) || hgt) + '" rx="' + (Number(cmd.radius ?? cmd.r) || 0) + '" fill="' + escapeHtml(cmd.fill || 'none') + '"/>';
        if (cmd.op === 'text' && cmd.text) return '<text x="' + (Number(cmd.x) || 0) + '" y="' + ((Number(cmd.y) || 0) + (Number(cmd.fontSize) || 11)) + '">' + escapeHtml(cmd.text) + '</text>';
        return '';
      }).join('');
      return '<svg class="vk-canvas' + toneCls + '" viewBox="0 0 ' + w + ' ' + hgt + '" width="' + w + '" height="' + hgt + '">' + inner + '</svg>';
    }
    if (t === 'table') {
      const ths = node.headers.map(h => '<th>' + renderSlotHtml(h) + '</th>').join('');
      const trs = node.rows.map(r => '<tr>' + r.map(c => '<td>' + renderSlotHtml(c) + '</td>').join('') + '</tr>').join('');
      return '<table class="vk-table"><thead><tr>' + ths + '</tr></thead><tbody>' + trs + '</tbody></table>';
    }
    if (t === 'button') {
      return '<button type="button" class="vk-button' + toneCls + '">' + renderSlotHtml(node) + '</button>';
    }
    if (t === 'divider') {
      return '<hr class="vk-divider">';
    }
    if (t === 'progress') {
      return '<div class="vk-progress' + toneCls + '"><div class="vk-progress-fill" style="width:' + Math.round((node.value || 0) * 100) + '%"></div></div>';
    }
    return '';
  }

  return emit(tree);
}

export function isRtlLocale(locale) {
  if (typeof locale !== 'string' || !locale.trim()) return false;
  const base = locale.trim().toLowerCase().split(/[-_]/)[0];
  return base === 'ar' || base === 'he' || base === 'fa' || base === 'ur';
}

export function getVibeStrings(locale = 'en', overrides = undefined) {
  const base = typeof locale === 'string' && locale.trim()
    ? locale.trim().toLowerCase().split(/[-_]/)[0]
    : 'en';
  const pack = LOCALE_PACKS[base] || LOCALE_PACKS.en;
  const merged = { ...pack };
  if (isPlainObject(overrides)) {
    for (const [k, v] of Object.entries(overrides)) {
      if (typeof v === 'string') merged[k] = v;
      else if (k === 'rtl' && typeof v === 'boolean') merged.rtl = v;
    }
  }
  return merged;
}

export function defineVibeWebComponents(env = globalThis) {
  if (!env || !env.customElements || typeof env.HTMLElement !== 'function') {
    return false;
  }
  const BaseElement = env.HTMLElement;
  const registry = env.customElements;

  class VibeViewElement extends BaseElement {
    constructor() {
      super();
      this._view = null;
      this._resolveSealed = null;
    }
    set view(v) {
      this._view = v;
      this.render();
    }
    get view() {
      return this._view;
    }
    set resolveSealed(fn) {
      this._resolveSealed = fn;
      this.render();
    }
    connectedCallback() {
      this.render();
    }
    render() {
      const doc = this.ownerDocument || env.document;
      if (!doc) return;
      const viewAttr = typeof this.getAttribute === 'function' ? this.getAttribute('view') : null;
      let raw = this._view;
      if (!raw && viewAttr) {
        try {
          raw = JSON.parse(viewAttr);
        } catch (_) {
          raw = viewAttr;
        }
      }
      if (!raw) return;
      const kit = env.VibeKit;
      if (kit && typeof kit.renderView === 'function') {
        kit.renderView(raw, this, { resolve: this._resolveSealed });
        return;
      }
      const tree = resolveViewTree(raw, { resolveSealed: this._resolveSealed });
      this.textContent = '';
      this.appendChild(renderDomWithDoc(doc, tree));
    }
  }

  class VibeEmbedElement extends BaseElement {
    constructor() {
      super();
      this._host = null;
      this._vibe = null;
      this._options = {};
      this._run = null;
    }
    mount(host, vibe, options = {}) {
      this._host = host;
      this._vibe = vibe;
      this._options = options;
      this.render();
    }
    disconnectedCallback() {
      if (this._run && typeof this._run.stop === 'function') this._run.stop();
    }
    render() {
      if (!this._host || !this._vibe) return;
      const space = env.VibeSpace;
      if (space && typeof space.embed === 'function') {
        if (this._run && typeof this._run.stop === 'function') this._run.stop();
        this._run = space.embed(this._host, this, this._vibe, this._options);
      }
    }
  }

  class VibeSpaceElement extends BaseElement {
    constructor() {
      super();
      this._host = null;
      this._options = {};
      this._panel = null;
    }
    mount(host, options = {}) {
      this._host = host;
      this._options = options;
      this.render();
    }
    disconnectedCallback() {
      if (this._panel && typeof this._panel.stop === 'function') this._panel.stop();
    }
    render() {
      if (!this._host) return;
      const space = env.VibeSpace;
      if (space && typeof space.mountPanel === 'function') {
        if (this._panel && typeof this._panel.stop === 'function') this._panel.stop();
        this._panel = space.mountPanel(this._host, this, this._options);
      }
    }
  }

  const defs = [
    ['vibe-view', VibeViewElement],
    ['vibe-embed', VibeEmbedElement],
    ['vibe-space', VibeSpaceElement]
  ];
  for (const [tag, Cls] of defs) {
    if (typeof registry.get !== 'function' || !registry.get(tag)) {
      registry.define(tag, Cls);
    }
  }
  return { VibeViewElement, VibeEmbedElement, VibeSpaceElement };
}

function renderDomWithDoc(doc, node) {
  if (!node) return doc.createTextNode('');
  const toneCls = node.tone && node.tone !== 'default' ? ' vk-tone-' + node.tone : '';
  const t = node.type;
  if (t === 'column' || t === 'row' || t === 'card') {
    const el = doc.createElement('div');
    el.className = 'vk-' + t + toneCls;
    for (const c of node.children || []) el.appendChild(renderDomWithDoc(doc, c));
    return el;
  }
  const el = doc.createElement('div');
  el.className = 'vk-' + t + toneCls;
  el.textContent = formatTerminalSlot(node);
  return el;
}
