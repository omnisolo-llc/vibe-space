import 'dart:convert';
import 'dart:math' as math;

import 'vibe_runtime_config.dart';
import 'vibe_mini_program.dart';
import 'vibe_vxml_template.dart';

const Set<String> _kForbiddenMiniProgramGlobals = <String>{
  'window',
  'document',
  'globalThis',
  'self',
  'top',
  'parent',
  'frames',
  'opener',
  'fetch',
  'XMLHttpRequest',
  'WebSocket',
  'EventSource',
  'WebTransport',
  'RTCPeerConnection',
  'webkitRTCPeerConnection',
  'RTCDataChannel',
  'Worker',
  'SharedWorker',
  'ServiceWorker',
  'ServiceWorkerContainer',
  'BroadcastChannel',
  'navigator',
  'location',
  'sendBeacon',
  'localStorage',
  'sessionStorage',
  'indexedDB',
  'caches',
  'cookieStore',
  'importScripts',
  'postMessage',
  'open',
  'alert',
  'confirm',
  'prompt',
  'eval',
  'Function',
  'WebAssembly',
  'Proxy',
  'Reflect',
};

const Set<String> _kForbiddenPrototypeTokens = <String>{
  '__proto__',
  'constructor',
  'prototype',
};

final RegExp _kLineContRe = RegExp(r'\\\r?\n');
final RegExp _kUnicodeBraceEscapeRe = RegExp(r'\\u\{([0-9a-fA-F]{1,6})\}');
final RegExp _kUnicode4EscapeRe = RegExp(r'\\u([0-9a-fA-F]{4})');
final RegExp _kHexEscapeRe = RegExp(r'\\x([0-9a-fA-F]{2})');
final RegExp _kOctalEscapeRe = RegExp(r'\\([0-3]?[0-7]{1,2})');
final RegExp _kTplStrInterpRe = RegExp(
  r'''`([a-zA-Z0-9_$]{0,32})\$\{\s*(?:'([a-zA-Z0-9_$]{0,32})'|"([a-zA-Z0-9_$]{0,32})")\s*\}([^`\\]{0,64})`''',
);
final RegExp _kConcatIdentStrRe = RegExp(
  r'''(['"`])([a-zA-Z0-9_$]{1,32})\1\s*\+\s*(['"`])([a-zA-Z0-9_$]{1,32})\3''',
);
final RegExp _kDynImportRe = RegExp(r'(?<![.\w$])import\s*\(');
final RegExp _kIdentRe = RegExp(r'(?<![.\w$])([A-Za-z_$][A-Za-z0-9_$]*)\b');
final RegExp _kProtoWordRe = RegExp(r'\b(__proto__|constructor|prototype)\b');
final RegExp _kProtoBracketRe = RegExp(
  r'''\[\s*['"`](__proto__|constructor|prototype)['"`]\s*\]''',
);
final RegExp _kDefMiniProgramRe = RegExp(
  r'(?:defineVibeSnippet|defineMiniProgram|VibeMiniApp|MiniProgram|VibeSnippet)\s*\(',
);
final RegExp _kPropIdentRe = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
final RegExp _kSetDataStmtRe = RegExp(
  r'^(?:this\s*\.\s*)?setData\s*\((.*)\)$',
  dotAll: true,
);
final RegExp _kDeclStmtRe = RegExp(
  r'^(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.+)$',
  dotAll: true,
);
final RegExp _kAssignStmtRe = RegExp(
  r'^([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.+)$',
  dotAll: true,
);
final RegExp _kMathCallRe = RegExp(
  r'^Math\.(round|floor|ceil|abs|min|max)\(([\s\S]*)\)$',
);
final RegExp _kThisDataRe = RegExp(r'\bthis\.data\b');

bool _isWordOrDollarCodeUnit(int cu) =>
    (cu >= 48 && cu <= 57) ||
    (cu >= 65 && cu <= 90) ||
    (cu >= 97 && cu <= 122) ||
    cu == 95 ||
    cu == 36;

bool _isObjectLiteralKey(String candidate, int start, int end) {
  var k = end;
  while (k < candidate.length && candidate.codeUnitAt(k) <= 32) {
    k++;
  }
  if (k >= candidate.length || candidate.codeUnitAt(k) != 58 /* ':' */) {
    return false;
  }
  var prev = start - 1;
  while (prev >= 0 && candidate.codeUnitAt(prev) <= 32) {
    prev--;
  }
  if (prev < 0) return false;
  final prevCu = candidate.codeUnitAt(prev);
  return prevCu == 123 /* '{' */ || prevCu == 44 /* ',' */;
}

String _decodeJsEscapes(String src) {
  var out = src
      .replaceAll(_kLineContRe, '')
      .replaceAllMapped(_kUnicodeBraceEscapeRe, (m) {
    final cp = int.tryParse(m.group(1)!, radix: 16);
    return (cp != null && cp <= 0x10ffff) ? String.fromCharCode(cp) : '';
  });
  out = out.replaceAllMapped(_kUnicode4EscapeRe, (m) {
    final cp = int.tryParse(m.group(1)!, radix: 16);
    return cp != null ? String.fromCharCode(cp) : '';
  });
  out = out.replaceAllMapped(_kHexEscapeRe, (m) {
    final cp = int.tryParse(m.group(1)!, radix: 16);
    return cp != null ? String.fromCharCode(cp) : '';
  });
  return out.replaceAllMapped(_kOctalEscapeRe, (m) {
    final cp = int.tryParse(m.group(1)!, radix: 8);
    return cp != null ? String.fromCharCode(cp) : '';
  });
}

String _collapseConcatStrings(String src) {
  var out = src;
  for (var pass = 0; pass < 4; pass++) {
    var next = out.replaceAllMapped(_kTplStrInterpRe, (m) {
      final head = m.group(1)!;
      final mid = m.group(2) ?? m.group(3) ?? '';
      final tail = m.group(4)!;
      return '`$head$mid$tail`';
    });
    next = next.replaceAllMapped(
      _kConcatIdentStrRe,
      (m) => "'${m.group(2)!}${m.group(4)!}'",
    );
    if (next == out) break;
    out = next;
  }
  return out;
}

/// Validates air-gapped `AppService` Vibe-Snippet source: enforces `<= 64 KiB`
/// and rejects any DOM, network, storage, popup, prototype, or dynamic code-gen globals.
void validateMiniProgramSource(String source) {
  if (source.trim().isEmpty) {
    throw const FormatException('Vibe-Snippet source must be non-empty');
  }
  final byteLen = utf8.encode(source).length;
  if (byteLen > kMaxVibeSetDataBytes) {
    throw FormatException(
      'Vibe-Snippet source exceeds 64 KiB limit ($byteLen bytes)',
    );
  }
  final (:noComments, :stripped) = _scanSourceForSecurity(source);
  final decodedStripped = _decodeJsEscapes(stripped);
  final decodedNoComments = _decodeJsEscapes(noComments);
  final collapsedAll = _collapseConcatStrings(decodedNoComments);

  if (_kDynImportRe.hasMatch(stripped) ||
      _kDynImportRe.hasMatch(decodedStripped)) {
    throw const FormatException(
      'Vibe-Snippet logic forbids dynamic import()',
    );
  }

  for (final candidate in <String>[stripped, decodedStripped]) {
    for (final m in _kIdentRe.allMatches(candidate)) {
      final ident = m.group(1)!;
      if (!_isObjectLiteralKey(candidate, m.start, m.end) &&
          _kForbiddenMiniProgramGlobals.contains(ident)) {
        throw FormatException(
          'Vibe-Snippet logic forbids browser/network global "$ident"',
        );
      }
    }
    final protoMatch = _kProtoWordRe.firstMatch(candidate);
    if (protoMatch != null) {
      throw FormatException(
        'Vibe-Snippet logic forbids prototype access "${protoMatch.group(1)}"',
      );
    }
  }

  final bracketMatch = _kProtoBracketRe.firstMatch(noComments) ??
      _kProtoBracketRe.firstMatch(decodedNoComments) ??
      _kProtoBracketRe.firstMatch(collapsedAll);
  if (bracketMatch != null) {
    throw FormatException(
      'Vibe-Snippet logic forbids prototype access "${bracketMatch.group(1)}"',
    );
  }
}

({String noComments, String stripped}) _scanSourceForSecurity(String src) {
  final noComments = StringBuffer();
  final stripped = StringBuffer();
  final tplBraceStack = <int>[];
  var i = 0;
  final len = src.length;

  while (i < len) {
    final cu = src.codeUnitAt(i);

    if (cu == 47 /* '/' */ && i + 1 < len) {
      final next = src.codeUnitAt(i + 1);
      if (next == 47 /* '/' */) {
        i += 2;
        while (i < len && src.codeUnitAt(i) != 10 /* '\n' */) {
          i++;
        }
        noComments.write(' ');
        stripped.write(' ');
        continue;
      }
      if (next == 42 /* '*' */) {
        i += 2;
        while (i + 1 < len &&
            !(src.codeUnitAt(i) == 42 && src.codeUnitAt(i + 1) == 47)) {
          i++;
        }
        i += 2;
        noComments.write(' ');
        stripped.write(' ');
        continue;
      }
    }

    if (cu == 39 /* "'" */ || cu == 34 /* '"' */) {
      final start = i;
      i++;
      while (i < len && src.codeUnitAt(i) != cu) {
        if (src.codeUnitAt(i) == 92 /* '\' */ && i + 1 < len) i++;
        i++;
      }
      if (i < len) i++;
      noComments.write(src.substring(start, i));
      stripped.write('""');
      continue;
    }

    if (cu == 96 /* '`' */) {
      final start = i;
      i++;
      var interpHit = false;
      while (i < len) {
        final cur = src.codeUnitAt(i);
        if (cur == 92 /* '\' */ && i + 1 < len) {
          i += 2;
          continue;
        }
        if (cur == 36 /* '$' */ &&
            i + 1 < len &&
            src.codeUnitAt(i + 1) == 123) {
          i += 2;
          noComments.write(src.substring(start, i));
          stripped.write('""+(');
          tplBraceStack.add(1);
          interpHit = true;
          break;
        }
        if (cur == 96) {
          i++;
          break;
        }
        i++;
      }
      if (!interpHit) {
        noComments.write(src.substring(start, i));
        stripped.write('""');
      }
      continue;
    }

    if (tplBraceStack.isNotEmpty) {
      if (cu == 123 /* '{' */) {
        tplBraceStack[tplBraceStack.length - 1] += 1;
      } else if (cu == 125 /* '}' */) {
        tplBraceStack[tplBraceStack.length - 1] -= 1;
        if (tplBraceStack.last == 0) {
          tplBraceStack.removeLast();
          i++;
          final tailStart = i;
          var nextInterp = false;
          while (i < len) {
            final cur = src.codeUnitAt(i);
            if (cur == 92 && i + 1 < len) {
              i += 2;
              continue;
            }
            if (cur == 36 && i + 1 < len && src.codeUnitAt(i + 1) == 123) {
              i += 2;
              noComments.write('}');
              noComments.write(src.substring(tailStart, i));
              stripped.write(')+""+(');
              tplBraceStack.add(1);
              nextInterp = true;
              break;
            }
            if (cur == 96) {
              i++;
              break;
            }
            i++;
          }
          if (!nextInterp) {
            noComments.write('}');
            noComments.write(src.substring(tailStart, i));
            stripped.write(')+""');
          }
          continue;
        }
      }
    }

    noComments.writeCharCode(cu);
    stripped.writeCharCode(cu);
    i++;
  }

  return (
    noComments: noComments.toString(),
    stripped: stripped.toString(),
  );
}

/// Validates air-gapped `AppService` Vibe Mini Program source (`<= 64 KiB` UTF-8)
/// and rejects DOM, network, storage, popup, prototype, escape obfuscation, and
/// dynamic `import()` / `eval` / `Function` vectors.
void validateVibeSnippetSource(String source) =>
    validateMiniProgramSource(source);

/// Parses an air-gapped `defineMiniProgram({ ... })` script (or
/// `defineVibeSnippet({ ... })` alias) into a pure-Dart [VibeMiniProgramDefinition].
VibeMiniProgramDefinition parseMiniProgramDefinitionFromSource(
  String source, {
  Map<String, Object?>? initialDataOverride,
  Map<String, Object?>? templateOverride,
}) {
  validateMiniProgramSource(source);
  final parsed = _MiniProgramScriptParser.parse(source);
  final mergedInitial = <String, Object?>{
    ...parsed.initialData,
    if (initialDataOverride != null) ...initialDataOverride,
  };
  return VibeMiniProgramDefinition(
    initialData: mergedInitial,
    template: templateOverride ?? parsed.template,
    rawSource: source,
    onLoad: parsed.hooks.containsKey('onLoad')
        ? (scope) => parsed.hooks['onLoad']!.execute(
              scope,
              <String, Object?>{'ctx': scope.context.toJson()},
            )
        : null,
    onShow: parsed.hooks.containsKey('onShow')
        ? (scope) => parsed.hooks['onShow']!.execute(
              scope,
              <String, Object?>{'ctx': scope.context.toJson()},
            )
        : null,
    onHide: parsed.hooks.containsKey('onHide')
        ? (scope) =>
            parsed.hooks['onHide']!.execute(scope, const <String, Object?>{})
        : null,
    onDataUpdate: parsed.hooks.containsKey('onDataUpdate')
        ? (scope, hostData, ctx) => parsed.hooks['onDataUpdate']!.execute(
              scope,
              <String, Object?>{
                'arg0': hostData,
                'arg1': ctx.toJson(),
              },
            )
        : null,
    methods: <String, VibeMiniProgramMethodHook>{
      for (final entry in parsed.methods.entries)
        entry.key: (scope, event) => entry.value.execute(
              scope,
              <String, Object?>{'arg0': event.toJson()},
            ),
    },
  );
}

/// Compatibility alias for [parseMiniProgramDefinitionFromSource].
VibeMiniProgramDefinition parseVibeSnippetDefinitionFromSource(
  String source, {
  Map<String, Object?>? initialDataOverride,
  Map<String, Object?>? templateOverride,
}) =>
    parseMiniProgramDefinitionFromSource(
      source,
      initialDataOverride: initialDataOverride,
      templateOverride: templateOverride,
    );

class _ParsedHandler {
  const _ParsedHandler(this.params, this.body);
  final List<String> params;
  final String body;

  void execute(VibeMiniProgramScope scope, Map<String, Object?> callArgs) {
    final locals = <String, Object?>{
      'data': scope.hostData,
      'hostData': scope.hostData,
      'context': scope.context.toJson(),
      'ctx': scope.context.toJson(),
    };
    if (params.isNotEmpty && callArgs.containsKey('arg0')) {
      locals[params[0]] = callArgs['arg0'];
    } else if (params.isNotEmpty && callArgs.containsKey('ctx')) {
      locals[params[0]] = callArgs['ctx'];
    }
    if (params.length >= 2 && callArgs.containsKey('arg1')) {
      locals[params[1]] = callArgs['arg1'];
    }
    _MiniProgramBodyRunner(scope, locals).runBlock(body);
  }
}

class _MiniProgramScriptParser {
  static ({
    Map<String, Object?> initialData,
    Map<String, Object?>? template,
    Map<String, _ParsedHandler> hooks,
    Map<String, _ParsedHandler> methods,
  }) parse(String raw) {
    final src = raw.trim();
    if (src.startsWith('{')) {
      try {
        final decoded = jsonDecode(src);
        if (decoded is Map) {
          final m = deepCloneVibeMap(decoded);
          return (
            initialData: m['data'] is Map
                ? deepCloneVibeMap(m['data'] as Map)
                : const <String, Object?>{},
            template: m['template'] is Map
                ? deepCloneVibeMap(m['template'] as Map)
                : null,
            hooks: const <String, _ParsedHandler>{},
            methods: const <String, _ParsedHandler>{},
          );
        }
      } on Object {
        // Fall through to JS defineVibeSnippet parser.
      }
    }

    final defMatch = _kDefMiniProgramRe.firstMatch(src);
    final objStart = defMatch != null
        ? src.indexOf('{', defMatch.end - 1)
        : src.indexOf('{');
    if (objStart < 0) {
      throw const FormatException(
        'Vibe-Snippet source must call defineVibeSnippet({ ... })',
      );
    }
    final objEnd = _findMatchingBrace(src, objStart, '{', '}');
    final body = src.substring(objStart + 1, objEnd);

    var initialData = const <String, Object?>{};
    Map<String, Object?>? template;
    final hooks = <String, _ParsedHandler>{};
    final methods = <String, _ParsedHandler>{};

    for (final m in _scanObjectMembers(body)) {
      if (m.name == 'data' && m.value != null) {
        final val = _evalStaticLiteral(m.value!);
        if (val is Map<String, Object?>) initialData = val;
      } else if (m.name == 'template' && m.value != null) {
        final val = _evalStaticLiteral(m.value!);
        if (val is Map<String, Object?>) template = val;
      } else if (const <String>{
            'onLoad',
            'onShow',
            'onHide',
            'onDataUpdate',
          }.contains(m.name) &&
          m.fnBody != null) {
        hooks[m.name] = _ParsedHandler(m.params, m.fnBody!);
      } else if (m.name == 'methods' && m.value != null) {
        final trimmed = m.value!.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
          final inner = trimmed.substring(1, trimmed.length - 1);
          for (final sub in _scanObjectMembers(inner)) {
            if (sub.fnBody != null) {
              if (!isValidMiniProgramHandlerName(sub.name)) {
                throw FormatException(
                  'Forbidden Vibe-Snippet method name "${sub.name}"',
                );
              }
              methods[sub.name] = _ParsedHandler(sub.params, sub.fnBody!);
            }
          }
        }
      } else if (m.fnBody != null) {
        if (!isValidMiniProgramHandlerName(m.name)) {
          throw FormatException(
            'Forbidden Vibe-Snippet method name "${m.name}"',
          );
        }
        methods[m.name] = _ParsedHandler(m.params, m.fnBody!);
      }
    }
    return (
      initialData: initialData,
      template: template,
      hooks: hooks,
      methods: methods,
    );
  }

  static List<
          ({String name, String? value, List<String> params, String? fnBody})>
      _scanObjectMembers(String src) {
    final out =
        <({String name, String? value, List<String> params, String? fnBody})>[];
    var i = 0;
    while (i < src.length) {
      i = _skipWsAndComments(src, i);
      if (i >= src.length) break;
      if (src.codeUnitAt(i) == 44 /* ',' */) {
        i++;
        continue;
      }
      final keyRes = readPropertyName(src, i);
      if (keyRes == null) break;
      final name = keyRes.name;
      i = _skipWsAndComments(src, keyRes.next);
      if (i >= src.length) break;

      final cu = src.codeUnitAt(i);
      if (cu == 40 /* '(' */) {
        final pEnd = _findMatchingBrace(src, i, '(', ')');
        final params = _splitParams(src.substring(i + 1, pEnd));
        i = _skipWsAndComments(src, pEnd + 1);
        final bEnd = _findMatchingBrace(src, i, '{', '}');
        out.add((
          name: name,
          value: null,
          params: params,
          fnBody: src.substring(i + 1, bEnd),
        ));
        i = bEnd + 1;
        continue;
      }

      if (cu == 58 /* ':' */) {
        i = _skipWsAndComments(src, i + 1);
        if (src.startsWith('function', i)) {
          final pStart = src.indexOf('(', i + 8);
          final pEnd = _findMatchingBrace(src, pStart, '(', ')');
          final params = _splitParams(src.substring(pStart + 1, pEnd));
          final bStart = _skipWsAndComments(src, pEnd + 1);
          final bEnd = _findMatchingBrace(src, bStart, '{', '}');
          out.add((
            name: name,
            value: null,
            params: params,
            fnBody: src.substring(bStart + 1, bEnd),
          ));
          i = bEnd + 1;
          continue;
        }
        final valEnd = _findTopLevelCommaOrEnd(src, i);
        out.add((
          name: name,
          value: src.substring(i, valEnd).trim(),
          params: const <String>[],
          fnBody: null,
        ));
        i = valEnd + 1;
        continue;
      }
      i++;
    }
    return out;
  }

  static List<String> _splitParams(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static ({String name, int next})? readPropertyName(String src, int pos) {
    if (pos >= src.length) return null;
    final cu = src.codeUnitAt(pos);
    if (cu == 39 || cu == 34) {
      final end = _skipString(src, pos);
      return (name: src.substring(pos + 1, end - 1), next: end);
    }
    final m = _kPropIdentRe.matchAsPrefix(src, pos);
    if (m == null) return null;
    return (name: m.group(0)!, next: m.end);
  }
}

class _MiniProgramBodyRunner {
  _MiniProgramBodyRunner(this.scope, this.locals);
  final VibeMiniProgramScope scope;
  final Map<String, Object?> locals;

  void runBlock(String block, [int depth = 0]) {
    if (depth > 16) {
      throw const FormatException('Vibe-Snippet block nesting limit exceeded');
    }
    var i = 0;
    var steps = 0;
    while (i < block.length) {
      if (++steps > 500) {
        throw const FormatException('Vibe-Snippet statement budget exceeded');
      }
      i = _skipWsAndComments(block, i);
      if (i >= block.length) break;
      if (block.codeUnitAt(i) == 59 /* ';' */) {
        i++;
        continue;
      }
      if (block.startsWith('return', i) &&
          (i + 6 == block.length ||
              !_isWordOrDollarCodeUnit(block.codeUnitAt(i + 6)))) {
        return;
      }
      if (block.startsWith('if', i) &&
          (i + 2 < block.length &&
              !_isWordOrDollarCodeUnit(block.codeUnitAt(i + 2)))) {
        final pStart = block.indexOf('(', i + 2);
        final pEnd = _findMatchingBrace(block, pStart, '(', ')');
        final cond = evalExpr(block.substring(pStart + 1, pEnd));
        var after = _skipWsAndComments(block, pEnd + 1);
        String thenBody;
        if (after < block.length && block.codeUnitAt(after) == 123 /* '{' */) {
          final bEnd = _findMatchingBrace(block, after, '{', '}');
          thenBody = block.substring(after + 1, bEnd);
          after = _skipWsAndComments(block, bEnd + 1);
        } else {
          final sEnd = _findStatementEnd(block, after);
          thenBody = block.substring(after, sEnd);
          after = _skipWsAndComments(block, sEnd + 1);
        }
        String? elseBody;
        if (block.startsWith('else', after) &&
            (after + 4 == block.length ||
                !_isWordOrDollarCodeUnit(block.codeUnitAt(after + 4)))) {
          after = _skipWsAndComments(block, after + 4);
          if (after < block.length &&
              block.codeUnitAt(after) == 123 /* '{' */) {
            final eEnd = _findMatchingBrace(block, after, '{', '}');
            elseBody = block.substring(after + 1, eEnd);
            after = eEnd + 1;
          } else {
            final sEnd = _findStatementEnd(block, after);
            elseBody = block.substring(after, sEnd);
            after = sEnd + 1;
          }
        }
        if (isVibeBindingTruthy(cond)) {
          runBlock(thenBody, depth + 1);
        } else if (elseBody != null) {
          runBlock(elseBody, depth + 1);
        }
        i = after;
        continue;
      }

      final stmtEnd = _findStatementEnd(block, i);
      var stmt = block.substring(i, stmtEnd).trim();
      if (stmt.endsWith(';')) {
        stmt = stmt.substring(0, stmt.length - 1).trim();
      }
      i = stmtEnd + 1;
      if (stmt.isEmpty) continue;

      final setDataMatch = _kSetDataStmtRe.firstMatch(stmt);
      if (setDataMatch != null) {
        final patchVal = evalExpr(setDataMatch.group(1)!);
        if (patchVal is Map) {
          scope.setData(
            patchVal.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        continue;
      }

      final declMatch = _kDeclStmtRe.firstMatch(stmt);
      if (declMatch != null) {
        final varName = declMatch.group(1)!;
        if (!_kForbiddenPrototypeTokens.contains(varName)) {
          locals[varName] = evalExpr(declMatch.group(2)!);
        }
        continue;
      }

      final assignMatch = _kAssignStmtRe.firstMatch(stmt);
      if (assignMatch != null && !stmt.contains('==')) {
        final varName = assignMatch.group(1)!;
        if (!_kForbiddenPrototypeTokens.contains(varName)) {
          locals[varName] = evalExpr(assignMatch.group(2)!);
        }
      }
    }
  }

  Object? evalExpr(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('{') && s.endsWith('}')) {
      return _evalObjectLiteral(s.substring(1, s.length - 1));
    }
    if (s.startsWith('[') && s.endsWith(']')) {
      return _evalArrayLiteral(s.substring(1, s.length - 1));
    }
    final mathMatch = _kMathCallRe.firstMatch(s);
    if (mathMatch != null) {
      final fn = mathMatch.group(1)!;
      final args = _splitTopLevelArgs(mathMatch.group(2)!)
          .map((a) => _asDouble(evalExpr(a)))
          .toList();
      if (args.isEmpty) return 0;
      return switch (fn) {
        'round' => args.first.round(),
        'floor' => args.first.floor(),
        'ceil' => args.first.ceil(),
        'abs' => args.first.abs(),
        'min' => args.reduce(math.min),
        'max' => args.reduce(math.max),
        _ => args.first,
      };
    }
    final normalized = s.replaceAll(_kThisDataRe, '__pageData');
    return evaluateVibeBindingExpression(normalized, <String, Object?>{
      ...locals,
      '__pageData': scope.data,
      'this': <String, Object?>{
        'data': scope.data,
        'hostData': scope.hostData,
        'context': scope.context.toJson(),
      },
    });
  }

  Map<String, Object?> _evalObjectLiteral(String inner) {
    final out = <String, Object?>{};
    var i = 0;
    while (i < inner.length) {
      i = _skipWsAndComments(inner, i);
      if (i >= inner.length) break;
      if (inner.codeUnitAt(i) == 44 /* ',' */) {
        i++;
        continue;
      }
      String key;
      if (inner.codeUnitAt(i) == 91 /* '[' */) {
        final kEnd = _findMatchingBrace(inner, i, '[', ']');
        key = evalExpr(inner.substring(i + 1, kEnd))?.toString() ?? '';
        i = kEnd + 1;
      } else {
        final kRes = _MiniProgramScriptParser.readPropertyName(inner, i);
        if (kRes == null) break;
        key = kRes.name;
        i = kRes.next;
      }
      if (_kForbiddenPrototypeTokens.contains(key)) {
        throw FormatException('Forbidden object key "$key"');
      }
      i = _skipWsAndComments(inner, i);
      if (i < inner.length && inner.codeUnitAt(i) == 58 /* ':' */) {
        i = _skipWsAndComments(inner, i + 1);
        final vEnd = _findTopLevelCommaOrEnd(inner, i);
        out[key] = evalExpr(inner.substring(i, vEnd));
        i = vEnd + 1;
      } else {
        final (_, val) = lookupVibeScopePath(locals, key);
        out[key] = val;
      }
    }
    return out;
  }

  List<Object?> _evalArrayLiteral(String inner) => _splitTopLevelArgs(inner)
      .map((item) => evalExpr(item))
      .toList(growable: false);

  static double _asDouble(Object? v) {
    if (v is num && v.isFinite) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }
}

Object? _evalStaticLiteral(String raw) {
  final dummySession = VibeMiniProgramSession(
    definition: const VibeMiniProgramDefinition(),
  );
  return _MiniProgramBodyRunner(
    VibeMiniProgramScope.internal(dummySession),
    const <String, Object?>{},
  ).evalExpr(raw);
}

List<String> _splitTopLevelArgs(String src) {
  final out = <String>[];
  var i = 0;
  while (i < src.length) {
    final end = _findTopLevelCommaOrEnd(src, i);
    final slice = src.substring(i, end).trim();
    if (slice.isNotEmpty) out.add(slice);
    i = end + 1;
  }
  return out;
}

int _skipWsAndComments(String s, int start) {
  var i = start;
  while (i < s.length) {
    final cu = s.codeUnitAt(i);
    if (cu <= 32) {
      i++;
    } else if (cu == 47 && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next == 47) {
        while (i < s.length && s.codeUnitAt(i) != 10) {
          i++;
        }
      } else if (next == 42) {
        i += 2;
        while (i + 1 < s.length &&
            !(s.codeUnitAt(i) == 42 && s.codeUnitAt(i + 1) == 47)) {
          i++;
        }
        i += 2;
      } else {
        break;
      }
    } else {
      break;
    }
  }
  return i;
}

int _skipString(String s, int start) {
  final quote = s.codeUnitAt(start);
  var i = start + 1;
  while (i < s.length && s.codeUnitAt(i) != quote) {
    if (s.codeUnitAt(i) == 92 /* '\' */) i++;
    i++;
  }
  return i < s.length ? i + 1 : i;
}

int _findMatchingBrace(String s, int openIdx, String openCh, String closeCh) {
  if (openIdx < 0 || openIdx >= s.length || s[openIdx] != openCh) {
    throw FormatException('Expected "$openCh" in Vibe-Snippet source');
  }
  final openCu = openCh.codeUnitAt(0);
  final closeCu = closeCh.codeUnitAt(0);
  var depth = 0;
  var i = openIdx;
  while (i < s.length) {
    final cu = s.codeUnitAt(i);
    if (cu == 39 || cu == 34 || cu == 96) {
      i = _skipString(s, i);
      continue;
    }
    if (cu == 47 &&
        i + 1 < s.length &&
        (s.codeUnitAt(i + 1) == 47 || s.codeUnitAt(i + 1) == 42)) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (cu == openCu) {
      depth++;
    } else if (cu == closeCu) {
      if (--depth == 0) return i;
    }
    i++;
  }
  throw FormatException('Unmatched "$openCh" in Vibe-Snippet source');
}

int _findTopLevelCommaOrEnd(String s, int start) {
  var depthCurly = 0, depthBrack = 0, depthParen = 0;
  var i = start;
  while (i < s.length) {
    final cu = s.codeUnitAt(i);
    if (cu == 39 || cu == 34 || cu == 96) {
      i = _skipString(s, i);
      continue;
    }
    if (cu == 47 &&
        i + 1 < s.length &&
        (s.codeUnitAt(i + 1) == 47 || s.codeUnitAt(i + 1) == 42)) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (cu == 123) depthCurly++;
    if (cu == 125) depthCurly--;
    if (cu == 91) depthBrack++;
    if (cu == 93) depthBrack--;
    if (cu == 40) depthParen++;
    if (cu == 41) depthParen--;
    if (cu == 44 && depthCurly == 0 && depthBrack == 0 && depthParen == 0) {
      return i;
    }
    i++;
  }
  return s.length;
}

int _findStatementEnd(String s, int start) {
  var depthCurly = 0, depthBrack = 0, depthParen = 0;
  var i = start;
  while (i < s.length) {
    final cu = s.codeUnitAt(i);
    if (cu == 39 || cu == 34 || cu == 96) {
      i = _skipString(s, i);
      continue;
    }
    if (cu == 47 &&
        i + 1 < s.length &&
        (s.codeUnitAt(i + 1) == 47 || s.codeUnitAt(i + 1) == 42)) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (cu == 123) depthCurly++;
    if (cu == 125) depthCurly--;
    if (cu == 91) depthBrack++;
    if (cu == 93) depthBrack--;
    if (cu == 40) depthParen++;
    if (cu == 41) depthParen--;
    if ((cu == 59 /* ';' */ || cu == 10 /* '\n' */) &&
        depthCurly == 0 &&
        depthBrack == 0 &&
        depthParen == 0) {
      if (cu == 10) {
        final nextIdx = _skipWsAndComments(s, i + 1);
        if (nextIdx < s.length && '.?:+-*/&|='.contains(s[nextIdx])) {
          i++;
          continue;
        }
      }
      return i;
    }
    i++;
  }
  return s.length;
}
