import 'dart:convert';

import 'vibe_trigger_context.dart';
export 'vibe_trigger_context.dart';

/// Maximum nesting depth for boolean combinators in [VibeTriggerCondition].
const int kMaxVibeTriggerDepth = 16;

/// Maximum pattern length for a [VibeTriggerMatcher] string or regex.
const int kMaxVibeTriggerPatternLength = 512;

/// Maximum list items in a `oneOf` [VibeTriggerMatcher] or combinator branch.
const int kMaxVibeTriggerBranchItems = 64;

/// Supported value matching operators for [VibeTriggerMatcher].
enum VibeTriggerMatchKind {
  exact('exact'),
  glob('glob'),
  regex('regex'),
  contains('contains'),
  prefix('prefix'),
  suffix('suffix'),
  exists('exists'),
  oneOf('oneOf');

  const VibeTriggerMatchKind(this.wireName);

  final String wireName;
}

/// Value or pattern predicate used inside a [VibeTriggerCondition].
class VibeTriggerMatcher {
  const VibeTriggerMatcher._({
    required this.kind,
    this.value,
    this.values = const <Object?>[],
    this.caseSensitive = true,
  });

  const VibeTriggerMatcher.exact(Object? value, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.exact,
          value: value,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.glob(String pattern, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.glob,
          value: pattern,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.regex(String pattern, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.regex,
          value: pattern,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.contains(Object? value, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.contains,
          value: value,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.prefix(String prefix, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.prefix,
          value: prefix,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.suffix(String suffix, {bool caseSensitive = true})
      : this._(
          kind: VibeTriggerMatchKind.suffix,
          value: suffix,
          caseSensitive: caseSensitive,
        );

  const VibeTriggerMatcher.exists([bool shouldExist = true])
      : this._(kind: VibeTriggerMatchKind.exists, value: shouldExist);

  factory VibeTriggerMatcher.oneOf(
    List<Object?> values, {
    bool caseSensitive = true,
  }) {
    return VibeTriggerMatcher._(
      kind: VibeTriggerMatchKind.oneOf,
      values: List<Object?>.unmodifiable(values),
      caseSensitive: caseSensitive,
    );
  }

  factory VibeTriggerMatcher.fromJson(Object? raw) {
    if (raw is VibeTriggerMatcher) return raw;
    if (raw is String) {
      return (raw.contains('*') || raw.contains('?'))
          ? VibeTriggerMatcher.glob(raw)
          : VibeTriggerMatcher.exact(raw);
    }
    if (raw is bool || raw is num) return VibeTriggerMatcher.exact(raw);
    if (raw is List) return VibeTriggerMatcher.oneOf(List<Object?>.from(raw));
    if (raw is Map) {
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      final cs =
          map['caseSensitive'] is bool ? map['caseSensitive'] as bool : true;
      if (map.containsKey('exists')) {
        final flag = map['exists'];
        if (flag is! bool) {
          throw const FormatException('Trigger matcher "exists" must be bool');
        }
        return VibeTriggerMatcher.exists(flag);
      }
      if (map.containsKey('exact') || map.containsKey('equals')) {
        final v = map.containsKey('exact') ? map['exact'] : map['equals'];
        return VibeTriggerMatcher.exact(v, caseSensitive: cs);
      }
      if (map.containsKey('glob') || map.containsKey('wildcard')) {
        final pat = map['glob'] ?? map['wildcard'];
        if (pat is! String) {
          throw const FormatException('Trigger matcher "glob" must be string');
        }
        return VibeTriggerMatcher.glob(pat, caseSensitive: cs);
      }
      if (map.containsKey('regex') || map.containsKey('pattern')) {
        final pat = map['regex'] ?? map['pattern'];
        if (pat is! String) {
          throw const FormatException('Trigger matcher "regex" must be string');
        }
        return VibeTriggerMatcher.regex(pat, caseSensitive: cs);
      }
      if (map.containsKey('contains')) {
        return VibeTriggerMatcher.contains(map['contains'], caseSensitive: cs);
      }
      if (map.containsKey('prefix') || map.containsKey('startsWith')) {
        final pat = map['prefix'] ?? map['startsWith'];
        if (pat is! String) {
          throw const FormatException(
              'Trigger matcher "prefix" must be string');
        }
        return VibeTriggerMatcher.prefix(pat, caseSensitive: cs);
      }
      if (map.containsKey('suffix') || map.containsKey('endsWith')) {
        final pat = map['suffix'] ?? map['endsWith'];
        if (pat is! String) {
          throw const FormatException(
              'Trigger matcher "suffix" must be string');
        }
        return VibeTriggerMatcher.suffix(pat, caseSensitive: cs);
      }
      if (map.containsKey('oneOf') || map.containsKey('in')) {
        final items = map['oneOf'] ?? map['in'];
        if (items is! List) {
          throw const FormatException('Trigger matcher "oneOf" must be a list');
        }
        return VibeTriggerMatcher.oneOf(
          List<Object?>.from(items),
          caseSensitive: cs,
        );
      }
    }
    throw FormatException('Invalid VibeTriggerMatcher: $raw');
  }

  final VibeTriggerMatchKind kind;
  final Object? value;
  final List<Object?> values;
  final bool caseSensitive;

  void validate() {
    switch (kind) {
      case VibeTriggerMatchKind.exact:
      case VibeTriggerMatchKind.contains:
        final v = value;
        if (v != null && v is! String && v is! num && v is! bool) {
          throw const FormatException('Matcher value must be scalar');
        }
        if (v is num && !v.isFinite) {
          throw const FormatException('Matcher number must be finite');
        }
        if (v is String && v.length > kMaxVibeTriggerPatternLength) {
          throw const FormatException('Matcher string exceeds 512 chars');
        }
      case VibeTriggerMatchKind.glob:
      case VibeTriggerMatchKind.prefix:
      case VibeTriggerMatchKind.suffix:
        final pat = value;
        if (pat is! String ||
            pat.isEmpty ||
            pat.length > kMaxVibeTriggerPatternLength) {
          throw FormatException(
              'Matcher ${kind.wireName} must be 1..512 chars');
        }
      case VibeTriggerMatchKind.regex:
        final pat = value;
        if (pat is! String ||
            pat.isEmpty ||
            pat.length > kMaxVibeTriggerPatternLength) {
          throw const FormatException('Matcher regex must be 1..512 chars');
        }
        RegExp(pat, caseSensitive: caseSensitive);
      case VibeTriggerMatchKind.exists:
        if (value is! bool) {
          throw const FormatException('Matcher exists must be boolean');
        }
      case VibeTriggerMatchKind.oneOf:
        if (values.isEmpty || values.length > kMaxVibeTriggerBranchItems) {
          throw const FormatException('Matcher oneOf must have 1..64 items');
        }
        for (final item in values) {
          if (item is! String && item is! num && item is! bool) {
            throw const FormatException('Matcher oneOf items must be scalars');
          }
          if (item is String && item.length > kMaxVibeTriggerPatternLength) {
            throw const FormatException('Matcher oneOf item exceeds 512 chars');
          }
        }
    }
  }

  bool matches(Object? actual) {
    if (kind == VibeTriggerMatchKind.exists) {
      final present = _valueExists(actual);
      return value == true ? present : !present;
    }
    if (actual == null) return false;
    if (actual is Iterable) {
      for (final item in actual) {
        if (matches(item)) return true;
      }
      return false;
    }
    switch (kind) {
      case VibeTriggerMatchKind.exists:
        return false;
      case VibeTriggerMatchKind.exact:
        return _scalarEquals(actual, value, caseSensitive: caseSensitive);
      case VibeTriggerMatchKind.glob:
        final text = _asMatchString(actual);
        return text != null &&
            _globToRegExp(value as String, caseSensitive: caseSensitive)
                .hasMatch(text);
      case VibeTriggerMatchKind.regex:
        final text = _asMatchString(actual);
        return text != null &&
            RegExp(value as String, caseSensitive: caseSensitive)
                .hasMatch(text);
      case VibeTriggerMatchKind.contains:
        final text = _asMatchString(actual);
        final needle = _asMatchString(value);
        if (text == null || needle == null) return false;
        return caseSensitive
            ? text.contains(needle)
            : text.toLowerCase().contains(needle.toLowerCase());
      case VibeTriggerMatchKind.prefix:
        final text = _asMatchString(actual);
        if (text == null) return false;
        final p = value as String;
        return caseSensitive
            ? text.startsWith(p)
            : text.toLowerCase().startsWith(p.toLowerCase());
      case VibeTriggerMatchKind.suffix:
        final text = _asMatchString(actual);
        if (text == null) return false;
        final s = value as String;
        return caseSensitive
            ? text.endsWith(s)
            : text.toLowerCase().endsWith(s.toLowerCase());
      case VibeTriggerMatchKind.oneOf:
        for (final item in values) {
          if (item is String && (item.contains('*') || item.contains('?'))) {
            final text = _asMatchString(actual);
            if (text != null &&
                _globToRegExp(item, caseSensitive: caseSensitive)
                    .hasMatch(text)) {
              return true;
            }
          } else if (_scalarEquals(actual, item,
              caseSensitive: caseSensitive)) {
            return true;
          }
        }
        return false;
    }
  }

  Object? toJson() {
    switch (kind) {
      case VibeTriggerMatchKind.exact:
        if (caseSensitive &&
            value is String &&
            !(value as String).contains('*') &&
            !(value as String).contains('?')) {
          return value;
        }
        if (caseSensitive && (value is bool || value is num)) return value;
        return <String, Object?>{
          'exact': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.glob:
        if (caseSensitive &&
            value is String &&
            ((value as String).contains('*') ||
                (value as String).contains('?'))) {
          return value;
        }
        return <String, Object?>{
          'glob': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.regex:
        return <String, Object?>{
          'regex': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.contains:
        return <String, Object?>{
          'contains': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.prefix:
        return <String, Object?>{
          'prefix': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.suffix:
        return <String, Object?>{
          'suffix': value,
          if (!caseSensitive) 'caseSensitive': false,
        };
      case VibeTriggerMatchKind.exists:
        return <String, Object?>{'exists': value == true};
      case VibeTriggerMatchKind.oneOf:
        if (caseSensitive) return List<Object?>.from(values);
        return <String, Object?>{
          'oneOf': List<Object?>.from(values),
          'caseSensitive': false,
        };
    }
  }

  String describe(String field) => switch (kind) {
        VibeTriggerMatchKind.exact => '$field = $value',
        VibeTriggerMatchKind.glob => '$field ~ $value',
        VibeTriggerMatchKind.regex => '$field ~= /$value/',
        VibeTriggerMatchKind.contains => '$field *= $value',
        VibeTriggerMatchKind.prefix => '$field ^= $value',
        VibeTriggerMatchKind.suffix => '$field \$= $value',
        VibeTriggerMatchKind.exists =>
          value == true ? '$field exists' : '!$field',
        VibeTriggerMatchKind.oneOf => '$field in [${values.join(', ')}]',
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeTriggerMatcher &&
          jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// Declarative `when` condition determining when a Vibe view or preset activates.
class VibeTriggerCondition {
  const VibeTriggerCondition({
    this.all = const <VibeTriggerCondition>[],
    this.any = const <VibeTriggerCondition>[],
    this.not,
    this.program,
    this.command,
    this.window,
    this.surface,
    this.windowTitle,
    this.cwd,
    this.pathPattern,
    this.env = const <String, VibeTriggerMatcher>{},
    this.context = const <String, VibeTriggerMatcher>{},
    this.always,
  });

  const VibeTriggerCondition.always() : this(always: true);
  const VibeTriggerCondition.never() : this(always: false);

  factory VibeTriggerCondition.allOf(List<VibeTriggerCondition> conditions) =>
      VibeTriggerCondition(
        all: List<VibeTriggerCondition>.unmodifiable(conditions),
      );

  factory VibeTriggerCondition.anyOf(List<VibeTriggerCondition> conditions) =>
      VibeTriggerCondition(
        any: List<VibeTriggerCondition>.unmodifiable(conditions),
      );

  factory VibeTriggerCondition.notCondition(VibeTriggerCondition condition) =>
      VibeTriggerCondition(not: condition);

  factory VibeTriggerCondition.fromJson(Map<String, Object?> json) {
    List<VibeTriggerCondition> parseList(Object? raw, String field) {
      if (raw == null) return const <VibeTriggerCondition>[];
      if (raw is! List) {
        throw FormatException('Trigger "$field" must be a list');
      }
      return List<VibeTriggerCondition>.unmodifiable(
        raw.map((item) {
          if (item is! Map) {
            throw FormatException('Each item in "$field" must be an object');
          }
          return VibeTriggerCondition.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          );
        }),
      );
    }

    Map<String, VibeTriggerMatcher> parseMap(Object? raw, String field) {
      if (raw == null) return const <String, VibeTriggerMatcher>{};
      if (raw is! Map) {
        throw FormatException('Trigger "$field" must be an object');
      }
      final out = <String, VibeTriggerMatcher>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        if (key.isNotEmpty) out[key] = VibeTriggerMatcher.fromJson(entry.value);
      }
      return Map<String, VibeTriggerMatcher>.unmodifiable(out);
    }

    VibeTriggerCondition? parsedNot;
    if (json['not'] != null) {
      final rawNot = json['not'];
      if (rawNot is! Map) {
        throw const FormatException('Trigger "not" must be an object');
      }
      parsedNot = VibeTriggerCondition.fromJson(
        rawNot.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final rawAlways = json['always'];
    if (rawAlways != null && rawAlways is! bool) {
      throw const FormatException('Trigger "always" must be boolean');
    }

    final cond = VibeTriggerCondition(
      all: parseList(json['all'], 'all'),
      any: parseList(json['any'], 'any'),
      not: parsedNot,
      program: json['program'] != null
          ? VibeTriggerMatcher.fromJson(json['program'])
          : null,
      command: json['command'] != null
          ? VibeTriggerMatcher.fromJson(json['command'])
          : null,
      window: json['window'] != null
          ? VibeTriggerMatcher.fromJson(json['window'])
          : null,
      surface: json['surface'] != null
          ? VibeTriggerMatcher.fromJson(json['surface'])
          : null,
      windowTitle: json['windowTitle'] != null
          ? VibeTriggerMatcher.fromJson(json['windowTitle'])
          : null,
      cwd:
          json['cwd'] != null ? VibeTriggerMatcher.fromJson(json['cwd']) : null,
      pathPattern: json['pathPattern'] != null
          ? VibeTriggerMatcher.fromJson(json['pathPattern'])
          : null,
      env: parseMap(json['env'], 'env'),
      context: parseMap(json['context'], 'context'),
      always: rawAlways as bool?,
    );
    cond.validate();
    return cond;
  }

  static VibeTriggerCondition? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is VibeTriggerCondition) return raw;
    try {
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return VibeTriggerCondition.fromJson(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        return null;
      }
      if (raw is Map) {
        return VibeTriggerCondition.fromJson(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } on Object {
      return null;
    }
    return null;
  }

  final List<VibeTriggerCondition> all;
  final List<VibeTriggerCondition> any;
  final VibeTriggerCondition? not;
  final VibeTriggerMatcher? program;
  final VibeTriggerMatcher? command;
  final VibeTriggerMatcher? window;
  final VibeTriggerMatcher? surface;
  final VibeTriggerMatcher? windowTitle;
  final VibeTriggerMatcher? cwd;
  final VibeTriggerMatcher? pathPattern;
  final Map<String, VibeTriggerMatcher> env;
  final Map<String, VibeTriggerMatcher> context;
  final bool? always;

  bool get isUnconditional =>
      always != false &&
      all.isEmpty &&
      any.isEmpty &&
      not == null &&
      program == null &&
      command == null &&
      window == null &&
      surface == null &&
      windowTitle == null &&
      cwd == null &&
      pathPattern == null &&
      env.isEmpty &&
      context.isEmpty;

  void validate([int depth = 0]) {
    if (depth > kMaxVibeTriggerDepth) {
      throw const FormatException('Trigger condition exceeds depth limit (16)');
    }
    if (all.length > kMaxVibeTriggerBranchItems ||
        any.length > kMaxVibeTriggerBranchItems ||
        env.length > kMaxVibeTriggerBranchItems ||
        context.length > kMaxVibeTriggerBranchItems) {
      throw const FormatException('Trigger condition exceeds 64 branch items');
    }
    for (final c in all) {
      c.validate(depth + 1);
    }
    for (final c in any) {
      c.validate(depth + 1);
    }
    not?.validate(depth + 1);
    program?.validate();
    command?.validate();
    window?.validate();
    surface?.validate();
    windowTitle?.validate();
    cwd?.validate();
    pathPattern?.validate();
    for (final m in env.values) {
      m.validate();
    }
    for (final m in context.values) {
      m.validate();
    }
  }

  bool matches(VibeTriggerContext ctx) {
    if (always == false) return false;
    if (program != null && !_matchCandidates(program!, ctx.programCandidates)) {
      return false;
    }
    if (command != null && !_matchCandidates(command!, ctx.commandCandidates)) {
      return false;
    }
    if (surface != null && !surface!.matches(ctx.surface)) return false;
    if (windowTitle != null &&
        !_matchCandidates(
            windowTitle!, <String?>[ctx.windowTitle, ctx.window])) {
      return false;
    }
    if (window != null &&
        !_matchCandidates(
          window!,
          <String?>[ctx.window, ctx.windowTitle, ctx.surface],
        )) {
      return false;
    }
    final normalizedCwd = _normalizePath(ctx.cwd);
    if (cwd != null && !cwd!.matches(normalizedCwd)) return false;
    if (pathPattern != null && !pathPattern!.matches(normalizedCwd)) {
      return false;
    }
    for (final entry in env.entries) {
      if (!entry.value.matches(ctx.lookupEnv(entry.key))) return false;
    }
    for (final entry in context.entries) {
      if (!entry.value.matches(ctx.lookupContext(entry.key))) return false;
    }
    for (final child in all) {
      if (!child.matches(ctx)) return false;
    }
    if (any.isNotEmpty && !any.any((child) => child.matches(ctx))) {
      return false;
    }
    if (not != null && not!.matches(ctx)) return false;
    return true;
  }

  bool evaluate(VibeTriggerContext ctx) => matches(ctx);

  Map<String, Object?> toJson() => <String, Object?>{
        if (always != null) 'always': always,
        if (program != null) 'program': program!.toJson(),
        if (command != null) 'command': command!.toJson(),
        if (window != null) 'window': window!.toJson(),
        if (surface != null) 'surface': surface!.toJson(),
        if (windowTitle != null) 'windowTitle': windowTitle!.toJson(),
        if (cwd != null) 'cwd': cwd!.toJson(),
        if (pathPattern != null) 'pathPattern': pathPattern!.toJson(),
        if (env.isNotEmpty)
          'env': <String, Object?>{
            for (final e in env.entries) e.key: e.value.toJson(),
          },
        if (context.isNotEmpty)
          'context': <String, Object?>{
            for (final e in context.entries) e.key: e.value.toJson(),
          },
        if (all.isNotEmpty)
          'all': <Map<String, Object?>>[for (final c in all) c.toJson()],
        if (any.isNotEmpty)
          'any': <Map<String, Object?>>[for (final c in any) c.toJson()],
        if (not != null) 'not': not!.toJson(),
      };

  String describe() {
    if (always == false) return 'never';
    final parts = <String>[
      if (program != null) program!.describe('program'),
      if (command != null) command!.describe('command'),
      if (surface != null) surface!.describe('surface'),
      if (window != null) window!.describe('window'),
      if (windowTitle != null) windowTitle!.describe('title'),
      if (cwd != null) cwd!.describe('cwd'),
      if (pathPattern != null) pathPattern!.describe('path'),
      for (final e in env.entries) e.value.describe('env.${e.key}'),
      for (final e in context.entries) e.value.describe(e.key),
      for (final c in all) c.describe(),
      if (any.isNotEmpty) '(${any.map((c) => c.describe()).join(' OR ')})',
      if (not != null) 'NOT (${not!.describe()})',
    ];
    return parts.isEmpty ? 'always' : parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeTriggerCondition &&
          jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

bool _valueExists(Object? v) => switch (v) {
      null => false,
      final String s => s.isNotEmpty,
      final Iterable<Object?> it => it.isNotEmpty,
      final Map<Object?, Object?> m => m.isNotEmpty,
      _ => true,
    };

String? _asMatchString(Object? v) =>
    v is String ? v : ((v is num || v is bool) ? v.toString() : null);

bool _scalarEquals(Object? actual, Object? expected,
    {required bool caseSensitive}) {
  if (actual == expected) return true;
  if (actual is String && expected is String) {
    return caseSensitive
        ? actual == expected
        : actual.toLowerCase() == expected.toLowerCase();
  }
  if (actual is num && expected is String) {
    final p = num.tryParse(expected.trim());
    return p != null && actual == p;
  }
  if (actual is String && expected is num) {
    final p = num.tryParse(actual.trim());
    return p != null && p == expected;
  }
  if (actual is String && expected is bool) {
    final norm = actual.trim().toLowerCase();
    return expected
        ? (norm == 'true' || norm == '1')
        : (norm == 'false' || norm == '0');
  }
  return false;
}

RegExp _globToRegExp(String glob, {required bool caseSensitive}) {
  final buf = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final ch = glob[i];
    if (ch == '*') {
      buf.write('.*');
    } else if (ch == '?') {
      buf.write('.');
    } else if (r'.+^$(){}[]|\'.contains(ch)) {
      buf.write('\\$ch');
    } else {
      buf.write(ch);
    }
  }
  buf.write('\$');
  return RegExp(buf.toString(), caseSensitive: caseSensitive);
}

bool _matchCandidates(VibeTriggerMatcher matcher, List<String?> candidates) {
  final nonEmpty = <String>[
    for (final c in candidates)
      if (c != null && c.isNotEmpty) c,
  ];
  if (matcher.kind == VibeTriggerMatchKind.exists) {
    return matcher.value == true ? nonEmpty.isNotEmpty : nonEmpty.isEmpty;
  }
  return nonEmpty.any(matcher.matches);
}

String? _normalizePath(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final f = raw.replaceAll('\\', '/');
  return (f.length > 1 && f.endsWith('/')) ? f.substring(0, f.length - 1) : f;
}
