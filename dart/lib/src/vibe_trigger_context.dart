import 'dart:convert';

final RegExp _kTemplatePlaceholderRe = RegExp(
  r'\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}',
);

/// Structural equality across JSON-like maps, lists, and scalar primitives.
bool vibeDeepEquals(Object? a, Object? b, [int depth = 0]) {
  if (identical(a, b)) return true;
  if (a == null || b == null || depth > 64) return false;
  if (a is List && b is List) {
    final len = a.length;
    if (len != b.length) return false;
    for (var i = 0; i < len; i++) {
      if (!vibeDeepEquals(a[i], b[i], depth + 1)) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final key = entry.key;
      if (!b.containsKey(key) ||
          !vibeDeepEquals(entry.value, b[key], depth + 1)) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// Structural hash matching [vibeDeepEquals] across maps, lists, and scalars.
int vibeDeepHash(Object? value, [int depth = 0]) {
  if (value == null || depth > 64) return 0;
  if (value is List) {
    return Object.hashAll(
      value.map((item) => vibeDeepHash(item, depth + 1)),
    );
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (e) => Object.hash(e.key, vibeDeepHash(e.value, depth + 1)),
      ),
    );
  }
  return value.hashCode;
}

/// Live host snapshot evaluated against registered `VibeTriggerCondition`s.
class VibeTriggerContext {
  const VibeTriggerContext({
    this.program,
    this.command,
    this.argv = const <String>[],
    this.window,
    this.surface,
    this.windowTitle,
    this.cwd,
    this.env = const <String, Object?>{},
    this.context = const <String, Object?>{},
    this.timestampMs = 0,
  });

  factory VibeTriggerContext.fromJson(Map<String, Object?> json) {
    final rawArgv = json['argv'];
    final argv = rawArgv is List
        ? List<String>.unmodifiable(rawArgv.map((e) => e.toString()))
        : const <String>[];
    final rawEnv = json['env'];
    final env = rawEnv is Map
        ? Map<String, Object?>.unmodifiable(
            rawEnv.map((k, v) => MapEntry(k.toString(), v)),
          )
        : const <String, Object?>{};
    final extra = <String, Object?>{};
    final rawCtx = json['context'];
    if (rawCtx is Map) {
      for (final entry in rawCtx.entries) {
        extra[entry.key.toString()] = entry.value;
      }
    }
    const reserved = <String>{
      'program',
      'command',
      'argv',
      'window',
      'surface',
      'windowTitle',
      'cwd',
      'env',
      'context',
      'timestampMs',
    };
    for (final entry in json.entries) {
      if (!reserved.contains(entry.key)) {
        extra.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return VibeTriggerContext(
      program: _nonEmpty(json['program']),
      command: _nonEmpty(json['command']),
      argv: argv,
      window: _nonEmpty(json['window']),
      surface: _nonEmpty(json['surface']),
      windowTitle: _nonEmpty(json['windowTitle']),
      cwd: _nonEmpty(json['cwd']),
      env: env,
      context: Map<String, Object?>.unmodifiable(extra),
      timestampMs: json['timestampMs'] is int ? json['timestampMs'] as int : 0,
    );
  }

  final String? program;
  final String? command;
  final List<String> argv;
  final String? window;
  final String? surface;
  final String? windowTitle;
  final String? cwd;
  final Map<String, Object?> env;
  final Map<String, Object?> context;
  final int timestampMs;

  List<String?> get programCandidates {
    final out = <String?>[];
    void addProg(String? p) {
      if (p == null) return;
      final trimmed = p.trim();
      if (trimmed.isEmpty) return;
      out.add(trimmed);
      final base = _executableBasename(trimmed);
      if (base != trimmed) out.add(base);
    }

    addProg(program);
    if (argv.isNotEmpty) addProg(argv.first);
    if (command != null) {
      addProg(_firstWhitespaceToken(command!));
    }
    return out;
  }

  List<String?> get commandCandidates {
    final joinedArgv = argv.isNotEmpty ? argv.join(' ') : null;
    return <String?>[command, joinedArgv, program];
  }

  Object? lookupEnv(String key) =>
      env.containsKey(key) ? env[key] : context[key];

  Object? lookupContext(String key) {
    if (context.containsKey(key)) return context[key];
    if (key == 'portOpen' && context.containsKey('ports')) {
      return context['ports'];
    }
    if (key == 'ports' && context.containsKey('portOpen')) {
      return context['portOpen'];
    }
    if (env.containsKey(key)) return env[key];
    if (key.startsWith('env.')) return env[key.substring(4)];
    if (key.startsWith('context.')) return lookupContext(key.substring(8));
    return switch (key) {
      'program' => programCandidates.firstOrNull,
      'command' => command ?? (argv.isNotEmpty ? argv.join(' ') : program),
      'window' => window ?? windowTitle ?? surface,
      'surface' => surface,
      'windowTitle' => windowTitle ?? window,
      'cwd' => cwd,
      _ => null,
    };
  }

  VibeTriggerContext copyWith({
    String? program,
    String? command,
    List<String>? argv,
    String? window,
    String? surface,
    String? windowTitle,
    String? cwd,
    Map<String, Object?>? env,
    Map<String, Object?>? context,
    int? timestampMs,
  }) {
    return VibeTriggerContext(
      program: program ?? this.program,
      command: command ?? this.command,
      argv: argv != null ? List<String>.unmodifiable(argv) : this.argv,
      window: window ?? this.window,
      surface: surface ?? this.surface,
      windowTitle: windowTitle ?? this.windowTitle,
      cwd: cwd ?? this.cwd,
      env: env != null ? Map<String, Object?>.unmodifiable(env) : this.env,
      context: context != null
          ? Map<String, Object?>.unmodifiable(context)
          : this.context,
      timestampMs: timestampMs ?? this.timestampMs,
    );
  }

  Map<String, Object?> toJson({bool includeTimestamp = false}) =>
      <String, Object?>{
        if (program != null) 'program': program,
        if (command != null) 'command': command,
        if (argv.isNotEmpty) 'argv': List<String>.from(argv),
        if (window != null) 'window': window,
        if (surface != null) 'surface': surface,
        if (windowTitle != null) 'windowTitle': windowTitle,
        if (cwd != null) 'cwd': cwd,
        if (env.isNotEmpty) 'env': Map<String, Object?>.from(env),
        if (context.isNotEmpty) 'context': Map<String, Object?>.from(context),
        if (includeTimestamp && timestampMs != 0) 'timestampMs': timestampMs,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeTriggerContext &&
          other.program == program &&
          other.command == command &&
          other.window == window &&
          other.surface == surface &&
          other.windowTitle == windowTitle &&
          other.cwd == cwd &&
          vibeDeepEquals(other.argv, argv) &&
          vibeDeepEquals(other.env, env) &&
          vibeDeepEquals(other.context, context);

  @override
  int get hashCode => Object.hash(
        program,
        command,
        window,
        surface,
        windowTitle,
        cwd,
        vibeDeepHash(argv),
        vibeDeepHash(env),
        vibeDeepHash(context),
      );
}

/// Substitutes `{{key}}` placeholders in [template] from [context] safely.
String hydrateVibeTemplateString(
  String template,
  VibeTriggerContext context, {
  bool escapeJson = false,
  bool escapeHtml = false,
}) {
  if (!template.contains('{{')) return template;
  return template.replaceAllMapped(
    _kTemplatePlaceholderRe,
    (match) {
      final key = match.group(1)!;
      final raw = context.lookupContext(key);
      final text = raw == null
          ? ''
          : (raw is Iterable ? raw.join(', ') : raw.toString());
      if (escapeHtml) {
        return const HtmlEscape().convert(text);
      }
      if (escapeJson) {
        final encoded = jsonEncode(text);
        return encoded.substring(1, encoded.length - 1);
      }
      return text;
    },
  );
}

String? _firstWhitespaceToken(String raw) {
  var start = 0;
  final len = raw.length;
  while (start < len && raw.codeUnitAt(start) <= 32) {
    start++;
  }
  if (start >= len) return null;
  var end = start;
  while (end < len && raw.codeUnitAt(end) > 32) {
    end++;
  }
  return raw.substring(start, end);
}

String _executableBasename(String raw) {
  final f = raw.replaceAll('\\', '/');
  final idx = f.lastIndexOf('/');
  return idx >= 0 ? f.substring(idx + 1) : f;
}

String? _nonEmpty(Object? raw) {
  final s = raw?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
