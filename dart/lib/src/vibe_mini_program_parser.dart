import 'dart:convert';
import 'dart:math' as math;

import 'vibe_mini_program.dart';
import 'vibe_runtime_config.dart';
import 'vibe_vxml_template.dart';

const Set<String> _kForbiddenMiniProgramGlobals = <String>{
  'window',
  'document',
  'fetch',
  'XMLHttpRequest',
  'WebSocket',
  'RTCPeerConnection',
  'webkitRTCPeerConnection',
  'EventSource',
  'SharedWorker',
  'BroadcastChannel',
  'sendBeacon',
  'localStorage',
  'sessionStorage',
  'indexedDB',
  'alert',
  'confirm',
  'prompt',
  'eval',
  'Function',
  'importScripts',
};

/// Validates air-gapped `AppService` Mini Program source: enforces `<= 64 KiB`
/// and rejects any DOM, network, storage, popup, or dynamic code-gen globals.
void validateMiniProgramSource(String source) {
  final byteLen = utf8.encode(source).length;
  if (byteLen > kMaxVibeSetDataBytes) {
    throw FormatException(
      'Mini Program source exceeds 64 KiB limit ($byteLen bytes)',
    );
  }
  final stripped = _stripCommentsAndStrings(source);
  final identRe = RegExp(r'(?<![.\w$])([A-Za-z_$][A-Za-z0-9_$]*)\b');
  for (final m in identRe.allMatches(stripped)) {
    final ident = m.group(1)!;
    var k = m.end;
    while (k < stripped.length && stripped.codeUnitAt(k) <= 32) {
      k++;
    }
    final isObjectKey = k < stripped.length && stripped[k] == ':';
    if (!isObjectKey && _kForbiddenMiniProgramGlobals.contains(ident)) {
      throw FormatException(
        'Mini Program logic forbids browser/network global "$ident"',
      );
    }
  }
  final globalPropRe = RegExp(
    r'\bglobalThis\s*\.\s*([A-Za-z_$][A-Za-z0-9_$]*)',
  );
  for (final m in globalPropRe.allMatches(stripped)) {
    final prop = m.group(1)!;
    if (_kForbiddenMiniProgramGlobals.contains(prop) || prop == 'open') {
      throw FormatException('Mini Program logic forbids globalThis.$prop');
    }
  }
}

String _stripCommentsAndStrings(String src) {
  final buf = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final ch = src[i];
    if (ch == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (ch == '/' && i + 1 < src.length && src[i + 1] == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      buf.write(' ');
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`') {
      final quote = ch;
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
      i++;
      buf.write('""');
      continue;
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}

/// Parses an air-gapped `defineMiniProgram({ ... })` script into a pure-Dart
/// [VibeMiniProgramDefinition].
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
        // Fall through to JS defineMiniProgram parser.
      }
    }

    final defMatch = RegExp(
      r'(?:defineMiniProgram|VibeMiniApp|MiniProgram)\s*\(',
    ).firstMatch(src);
    final objStart = defMatch != null
        ? src.indexOf('{', defMatch.end - 1)
        : src.indexOf('{');
    if (objStart < 0) {
      throw const FormatException(
        'Mini Program source must call defineMiniProgram({ ... })',
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
              methods[sub.name] = _ParsedHandler(sub.params, sub.fnBody!);
            }
          }
        }
      } else if (m.fnBody != null) {
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
      if (src[i] == ',') {
        i++;
        continue;
      }
      final keyRes = readPropertyName(src, i);
      if (keyRes == null) break;
      final name = keyRes.name;
      i = _skipWsAndComments(src, keyRes.next);
      if (i >= src.length) break;

      if (src[i] == '(') {
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

      if (src[i] == ':') {
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
    final ch = src[pos];
    if (ch == "'" || ch == '"') {
      final end = _skipString(src, pos);
      return (name: src.substring(pos + 1, end - 1), next: end);
    }
    final m = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*').matchAsPrefix(src, pos);
    if (m == null) return null;
    return (name: m.group(0)!, next: m.end);
  }
}

class _MiniProgramBodyRunner {
  _MiniProgramBodyRunner(this.scope, this.locals);
  final VibeMiniProgramScope scope;
  final Map<String, Object?> locals;

  void runBlock(String block) {
    var i = 0;
    var steps = 0;
    while (i < block.length) {
      if (++steps > 500) {
        throw const FormatException('Mini Program statement budget exceeded');
      }
      i = _skipWsAndComments(block, i);
      if (i >= block.length) break;
      if (block[i] == ';') {
        i++;
        continue;
      }
      if (block.startsWith('return', i) &&
          (i + 6 == block.length || !RegExp(r'[\w$]').hasMatch(block[i + 6]))) {
        return;
      }
      if (block.startsWith('if', i) &&
          (i + 2 < block.length && !RegExp(r'[\w$]').hasMatch(block[i + 2]))) {
        final pStart = block.indexOf('(', i + 2);
        final pEnd = _findMatchingBrace(block, pStart, '(', ')');
        final cond = evalExpr(block.substring(pStart + 1, pEnd));
        var after = _skipWsAndComments(block, pEnd + 1);
        String thenBody;
        if (block[after] == '{') {
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
                !RegExp(r'[\w$]').hasMatch(block[after + 4]))) {
          after = _skipWsAndComments(block, after + 4);
          if (after < block.length && block[after] == '{') {
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
          runBlock(thenBody);
        } else if (elseBody != null) {
          runBlock(elseBody);
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

      final setDataMatch = RegExp(
        r'^(?:this\s*\.\s*)?setData\s*\((.*)\)$',
        dotAll: true,
      ).firstMatch(stmt);
      if (setDataMatch != null) {
        final patchVal = evalExpr(setDataMatch.group(1)!);
        if (patchVal is Map) {
          scope.setData(
            patchVal.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        continue;
      }

      final declMatch = RegExp(
        r'^(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.+)$',
        dotAll: true,
      ).firstMatch(stmt);
      if (declMatch != null) {
        locals[declMatch.group(1)!] = evalExpr(declMatch.group(2)!);
        continue;
      }

      final assignMatch = RegExp(
        r'^([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(.+)$',
        dotAll: true,
      ).firstMatch(stmt);
      if (assignMatch != null && !stmt.contains('==')) {
        locals[assignMatch.group(1)!] = evalExpr(assignMatch.group(2)!);
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
    final mathMatch = RegExp(
      r'^Math\.(round|floor|ceil|abs|min|max)\(([\s\S]*)\)$',
    ).firstMatch(s);
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
    final normalized = s.replaceAll(RegExp(r'\bthis\.data\b'), '__pageData');
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
      if (inner[i] == ',') {
        i++;
        continue;
      }
      String key;
      if (inner[i] == '[') {
        final kEnd = _findMatchingBrace(inner, i, '[', ']');
        key = evalExpr(inner.substring(i + 1, kEnd))?.toString() ?? '';
        i = kEnd + 1;
      } else {
        final kRes = _MiniProgramScriptParser.readPropertyName(inner, i);
        if (kRes == null) break;
        key = kRes.name;
        i = kRes.next;
      }
      i = _skipWsAndComments(inner, i);
      if (i < inner.length && inner[i] == ':') {
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
    if (s.codeUnitAt(i) <= 32) {
      i++;
    } else if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
    } else if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '*') {
      i += 2;
      while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
        i++;
      }
      i += 2;
    } else {
      break;
    }
  }
  return i;
}

int _skipString(String s, int start) {
  final quote = s[start];
  var i = start + 1;
  while (i < s.length && s[i] != quote) {
    if (s[i] == r'\') i++;
    i++;
  }
  return i < s.length ? i + 1 : i;
}

int _findMatchingBrace(String s, int openIdx, String openCh, String closeCh) {
  if (openIdx < 0 || openIdx >= s.length || s[openIdx] != openCh) {
    throw FormatException('Expected "$openCh" in Mini Program source');
  }
  var depth = 0;
  var i = openIdx;
  while (i < s.length) {
    final ch = s[i];
    if (ch == "'" || ch == '"' || ch == '`') {
      i = _skipString(s, i);
      continue;
    }
    if (ch == '/' && i + 1 < s.length && (s[i + 1] == '/' || s[i + 1] == '*')) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (ch == openCh) {
      depth++;
    } else if (ch == closeCh) {
      if (--depth == 0) return i;
    }
    i++;
  }
  throw FormatException('Unmatched "$openCh" in Mini Program source');
}

int _findTopLevelCommaOrEnd(String s, int start) {
  var depthCurly = 0, depthBrack = 0, depthParen = 0;
  var i = start;
  while (i < s.length) {
    final ch = s[i];
    if (ch == "'" || ch == '"' || ch == '`') {
      i = _skipString(s, i);
      continue;
    }
    if (ch == '/' && i + 1 < s.length && (s[i + 1] == '/' || s[i + 1] == '*')) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (ch == '{') depthCurly++;
    if (ch == '}') depthCurly--;
    if (ch == '[') depthBrack++;
    if (ch == ']') depthBrack--;
    if (ch == '(') depthParen++;
    if (ch == ')') depthParen--;
    if (ch == ',' && depthCurly == 0 && depthBrack == 0 && depthParen == 0) {
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
    final ch = s[i];
    if (ch == "'" || ch == '"' || ch == '`') {
      i = _skipString(s, i);
      continue;
    }
    if (ch == '/' && i + 1 < s.length && (s[i + 1] == '/' || s[i + 1] == '*')) {
      i = _skipWsAndComments(s, i);
      continue;
    }
    if (ch == '{') depthCurly++;
    if (ch == '}') depthCurly--;
    if (ch == '[') depthBrack++;
    if (ch == ']') depthBrack--;
    if (ch == '(') depthParen++;
    if (ch == ')') depthParen--;
    if ((ch == ';' || ch == '\n') &&
        depthCurly == 0 &&
        depthBrack == 0 &&
        depthParen == 0) {
      if (ch == '\n') {
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
