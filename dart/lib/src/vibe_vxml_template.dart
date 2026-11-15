import 'compatibility_adapter.dart';
import 'vibe_protocol.dart';
import 'vibe_mini_program.dart'
    show isValidMiniProgramHandlerName, kForbiddenVibeMethodNames;

const int _kMaxForLoopItems = 200;
const int _kMaxBindingExprLength = 2048;
const int _kMaxBindingExprDepth = 16;

const Set<String> _kBlockedScopeSegments = <String>{
  '__proto__',
  'constructor',
  'prototype',
};

final RegExp _kSafeColorHexRe = RegExp(
  r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);
final RegExp _kHyphenLetterRe = RegExp(r'-([a-zA-Z])');
final RegExp _kVueForLoopRe = RegExp(
  r'^\(?\s*([a-zA-Z_$][a-zA-Z0-9_$]*)(?:\s*,\s*([a-zA-Z_$][a-zA-Z0-9_$]*))?\s*\)?\s+in\s+(.+)$',
);
final RegExp _kTemplateMustacheRe = RegExp(r'\{\{([^}]+)\}\}');

String _stripPxSuffix(String raw) =>
    raw.endsWith('px') ? raw.substring(0, raw.length - 2) : raw;

bool _isNumOrDotCodeUnit(int u) => (u >= 48 && u <= 57) || u == 46;

bool _isIdentOrPathCodeUnit(int u) =>
    (u >= 97 && u <= 122) ||
    (u >= 65 && u <= 90) ||
    (u >= 48 && u <= 57) ||
    u == 95 ||
    u == 36 ||
    u == 46;
const Set<String> _kSemanticStyleColors = <String>{
  'accent',
  'ok',
  'warn',
  'danger',
  'surface',
  'card',
  'border',
  'text',
  'muted',
  'transparent',
};
const Set<String> _kAllowedFontWeights = <String>{
  'normal',
  'medium',
  'semibold',
  'bold',
  '400',
  '500',
  '600',
  '700',
};
const Set<String> _kAllowedAligns = <String>{
  'start',
  'center',
  'end',
  'stretch',
  'spaceBetween',
  'space_between',
};

/// Sanitizes scoped `WXSS`-style visual/layout tokens on a declarative node.
/// External URLs (`url(...)`), CSS expressions, and unknown keys are stripped.
Map<String, Object?>? normalizeVibeStyleTokens(Object? rawStyle) {
  if (rawStyle == null) return null;
  Map<String, Object?> map;
  if (rawStyle is String) {
    map = <String, Object?>{};
    for (final part in rawStyle.split(';')) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      final rawKey = part.substring(0, idx).trim();
      final rawVal = part.substring(idx + 1).trim();
      if (rawKey.isEmpty || rawVal.isEmpty) continue;
      final camel = rawKey.replaceAllMapped(
        _kHyphenLetterRe,
        (m) => m.group(1)!.toUpperCase(),
      );
      final asNum = double.tryParse(_stripPxSuffix(rawVal));
      map[camel] = asNum ?? rawVal;
    }
  } else if (rawStyle is Map) {
    map = <String, Object?>{
      for (final e in rawStyle.entries) e.key.toString(): e.value,
    };
  } else {
    return null;
  }

  final out = <String, Object?>{};
  double? numIn(String key, double minV, double maxV) {
    final v = map[key];
    if (v is num && v.isFinite) return v.toDouble().clamp(minV, maxV);
    if (v is String) {
      final p = double.tryParse(_stripPxSuffix(v.trim()));
      if (p != null && p.isFinite) return p.clamp(minV, maxV);
    }
    return null;
  }

  String? colorIn(String key) {
    final v = map[key]?.toString().trim();
    if (v == null || v.isEmpty) return null;
    if (_kSafeColorHexRe.hasMatch(v) || _kSemanticStyleColors.contains(v)) {
      return v;
    }
    return null;
  }

  for (final k in const <String>[
    'padding',
    'paddingHorizontal',
    'paddingVertical',
    'gap',
    'borderRadius',
    'borderWidth',
    'fontSize',
    'width',
    'height',
    'minHeight',
    'maxWidth',
  ]) {
    final n = numIn(k, 0, 2048);
    if (n != null) out[k] = n;
  }
  final flex = numIn('flex', 0, 24);
  if (flex != null && flex > 0) out['flex'] = flex.round();
  final opacity = numIn('opacity', 0, 1);
  if (opacity != null) out['opacity'] = opacity;

  for (final ck in const <String>['backgroundColor', 'borderColor', 'color']) {
    final c = colorIn(ck);
    if (c != null) out[ck] = c;
  }
  final fw = map['fontWeight']?.toString().trim().toLowerCase();
  if (fw != null && _kAllowedFontWeights.contains(fw)) {
    out['fontWeight'] = fw;
  }
  final align = map['align']?.toString().trim();
  if (align != null && _kAllowedAligns.contains(align)) {
    out['align'] = align;
  }
  return out.isEmpty ? null : out;
}

/// Resolves a dotted/bracket path (e.g. `bars[0].value`, `metrics.cluster.rps`)
/// against [scope] without executing code or unsealing `{ 'sealed': 'h_...' }`.
(bool, Object?) lookupVibeScopePath(
  Map<String, Object?> scope,
  String rawPath, [
  int lookupDepth = 0,
]) {
  if (lookupDepth > 8) return (false, null);
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty || trimmed.length > 512) return (false, null);
  if (_kBlockedScopeSegments.contains(trimmed)) return (false, null);
  if (scope.containsKey(trimmed)) return (true, scope[trimmed]);

  final segments = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < trimmed.length; i++) {
    final ch = trimmed[i];
    if (ch == '.') {
      if (buf.isNotEmpty) {
        segments.add(buf.toString());
        buf.clear();
      }
    } else if (ch == '[') {
      if (buf.isNotEmpty) {
        segments.add(buf.toString());
        buf.clear();
      }
      final end = trimmed.indexOf(']', i + 1);
      if (end < 0) return (false, null);
      var idxExpr = trimmed.substring(i + 1, end).trim();
      if ((idxExpr.startsWith("'") && idxExpr.endsWith("'")) ||
          (idxExpr.startsWith('"') && idxExpr.endsWith('"'))) {
        idxExpr = idxExpr.substring(1, idxExpr.length - 1);
      } else if (int.tryParse(idxExpr) == null) {
        final (foundIdx, dynIdx) =
            lookupVibeScopePath(scope, idxExpr, lookupDepth + 1);
        if (foundIdx && dynIdx != null) idxExpr = dynIdx.toString();
      }
      segments.add(idxExpr);
      i = end;
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) segments.add(buf.toString());
  if (segments.isEmpty || segments.length > 32) return (false, null);

  Object? cursor = scope;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (_kBlockedScopeSegments.contains(seg)) return (false, null);
    if (cursor == null) return (false, null);
    if (VibeSealedHandle.tryParse(cursor) != null) return (false, null);
    if (seg == 'length') {
      if (cursor is List) return (true, cursor.length);
      if (cursor is String) return (true, cursor.length);
      if (cursor is Map && !cursor.containsKey('length')) {
        return (true, cursor.length);
      }
    }
    if (cursor is Map) {
      if (cursor.containsKey(seg)) {
        cursor = cursor[seg];
        continue;
      }
      if (i + 1 < segments.length) {
        final joined2 = '$seg.${segments[i + 1]}';
        if (cursor.containsKey(joined2)) {
          cursor = cursor[joined2];
          i += 1;
          continue;
        }
      }
      return (false, null);
    }
    if (cursor is List) {
      final idx = int.tryParse(seg);
      if (idx == null || idx < 0 || idx >= cursor.length) return (false, null);
      cursor = cursor[idx];
      continue;
    }
    return (false, null);
  }
  return (true, cursor);
}

/// Evaluates a side-effect-free WeChat `WXML`/`VXML` data-binding expression
/// against [scope] (paths, `!`, comparisons, `&&`/`||`/`??`, arithmetic, `?:`).
Object? evaluateVibeBindingExpression(
  String expr,
  Map<String, Object?> scope,
) {
  final trimmed = expr.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > _kMaxBindingExprLength) {
    throw const FormatException('Binding expression exceeds length limit');
  }
  final parser = _BindingExprParser(trimmed, scope);
  return parser.parseExpression(0);
}

/// Truthiness semantics for `if` / `v-if` / `wx:if` directives.
bool isVibeBindingTruthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0 && !value.isNaN;
  if (value is String) return value.isNotEmpty && value != 'false';
  return true;
}

/// Compiles a declarative WeChat-style `VXML` JSON [template] against [scope]
/// into a canonical `VibeView` tree (with native Skyline `canvas` & `style` support).
Map<String, Object?> compileVibeTemplate(
  Map<String, Object?> template,
  Map<String, Object?> scope, {
  bool validate = true,
}) {
  final expanded = _expandTemplateNode(template, scope, 0);
  Map<String, Object?> root;
  if (expanded.isEmpty) {
    root = const <String, Object?>{
      'type': 'column',
      'children': <Map<String, Object?>>[],
    };
  } else if (expanded.length == 1) {
    root = expanded.first;
  } else {
    root = <String, Object?>{'type': 'column', 'children': expanded};
  }
  return validate ? VibeUiCompatibilityAdapter.adapt(root) : root;
}

List<Map<String, Object?>> _expandTemplateNode(
  Map<String, Object?> node,
  Map<String, Object?> scope,
  int depth,
) {
  if (depth > kMaxAdaptedViewDepth) {
    throw const FormatException('VXML template exceeds maximum nesting depth');
  }

  final rawFor = node['for'] ?? node['v-for'] ?? node['wx:for'];
  if (rawFor != null) {
    final withoutFor = <String, Object?>{
      for (final e in node.entries)
        if (e.key != 'for' &&
            e.key != 'v-for' &&
            e.key != 'wx:for' &&
            e.key != 'forItem' &&
            e.key != 'wx:for-item' &&
            e.key != 'forIndex' &&
            e.key != 'wx:for-index')
          e.key: e.value,
    };
    final spec = _parseForDirective(
      rawFor,
      itemAlias: (node['forItem'] ?? node['wx:for-item'])?.toString(),
      indexAlias: (node['forIndex'] ?? node['wx:for-index'])?.toString(),
      scope: scope,
    );
    final results = <Map<String, Object?>>[];
    final childScope = <String, Object?>{...scope};
    for (var i = 0; i < spec.items.length && i < _kMaxForLoopItems; i++) {
      childScope[spec.itemVar] = spec.items[i];
      childScope[spec.indexVar] = i;
      results.addAll(_expandTemplateNode(withoutFor, childScope, depth));
    }
    return results;
  }

  final rawIf = node['if'] ?? node['v-if'] ?? node['wx:if'];
  if (rawIf != null) {
    final condVal = _evalDirectiveValue(rawIf, scope);
    if (!isVibeBindingTruthy(condVal)) return const <Map<String, Object?>>[];
  }

  final rawType =
      _interpolateValue(node['type'] ?? 'column', scope)?.toString().trim();
  final type = switch (rawType) {
    'view' || 'vstack' || 'block' => 'column',
    'hstack' || 'flex' => 'row',
    null || '' => 'column',
    final String t => t,
  };

  final dataset = <String, Object?>{};
  if (node['dataset'] is Map) {
    for (final e in (node['dataset'] as Map).entries) {
      dataset[e.key.toString()] = _interpolateValue(e.value, scope);
    }
  }
  for (final e in node.entries) {
    if (e.key.startsWith('data-') && e.key.length > 5) {
      final camel = e.key.substring(5).replaceAllMapped(
            _kHyphenLetterRe,
            (m) => m.group(1)!.toUpperCase(),
          );
      dataset[camel] = _interpolateValue(e.value, scope);
    }
  }

  final bindTap = _cleanHandlerName(node['bindtap'] ?? node['catchtap'], scope);
  final bindInput = _cleanHandlerName(node['bindinput'], scope);
  final bindChange = _cleanHandlerName(node['bindchange'], scope);

  final out = <String, Object?>{'type': type};
  const skippedKeys = <String>{
    'type',
    'if',
    'v-if',
    'wx:if',
    'for',
    'v-for',
    'wx:for',
    'forItem',
    'wx:for-item',
    'forIndex',
    'wx:for-index',
    'children',
    'style',
    'dataset',
    'bindtap',
    'catchtap',
    'bindinput',
    'bindchange',
  };

  for (final entry in node.entries) {
    final k = entry.key;
    if (skippedKeys.contains(k) || k.startsWith('data-')) continue;
    out[k] = _interpolateValue(entry.value, scope);
  }

  final interpolatedStyle = _interpolateValue(node['style'], scope);
  final normalizedStyle = normalizeVibeStyleTokens(interpolatedStyle);
  if (normalizedStyle != null) {
    out['style'] = normalizedStyle;
  }

  if (node['children'] is List) {
    final compiledChildren = <Map<String, Object?>>[];
    for (final rawChild in node['children'] as List) {
      if (rawChild is Map) {
        compiledChildren.addAll(
          _expandTemplateNode(
            rawChild.map((k, v) => MapEntry(k.toString(), v)),
            scope,
            depth + 1,
          ),
        );
      }
    }
    out['children'] = compiledChildren;
  }

  final nodeId = out['id']?.toString();
  if (dataset.isNotEmpty) out['dataset'] = dataset;
  if (bindTap != null) out['bindtap'] = bindTap;
  if (bindInput != null) out['bindinput'] = bindInput;
  if (bindChange != null) out['bindchange'] = bindChange;

  if (bindTap != null &&
      (type == 'button' || type == 'action' || type == 'canvas')) {
    out['command'] ??= 'vibe:tap:$bindTap';
    final existingArgs = out['args'] is Map
        ? Map<String, Object?>.from(
            (out['args'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, Object?>{};
    existingArgs['__vibeEvent'] = true;
    existingArgs['type'] = 'tap';
    existingArgs['handler'] = bindTap;
    if (nodeId != null) existingArgs['id'] = nodeId;
    if (dataset.isNotEmpty) existingArgs['dataset'] = dataset;
    if (type == 'action') {
      out['arguments'] = existingArgs;
    } else {
      out['args'] = existingArgs;
    }
  }
  if (bindChange != null &&
      (type == 'checkbox' || type == 'option_group') &&
      out['command'] == null) {
    out['command'] = 'vibe:change:$bindChange';
  }

  return <Map<String, Object?>>[out];
}

String? _cleanHandlerName(Object? raw, Map<String, Object?> scope) {
  if (raw == null) return null;
  final resolved = _interpolateValue(raw, scope)?.toString().trim() ?? '';
  return isValidMiniProgramHandlerName(resolved) ? resolved : null;
}

Object? _evalDirectiveValue(Object? raw, Map<String, Object?> scope) {
  if (raw is bool || raw is num) return raw;
  if (raw is List) return raw;
  if (raw is! String) return raw;
  final trimmed = raw.trim();
  if (trimmed.startsWith('{{') &&
      trimmed.endsWith('}}') &&
      !trimmed.substring(2, trimmed.length - 2).contains('{{')) {
    return evaluateVibeBindingExpression(
      trimmed.substring(2, trimmed.length - 2),
      scope,
    );
  }
  if (trimmed.contains('{{')) {
    return _interpolateString(trimmed, scope);
  }
  return evaluateVibeBindingExpression(trimmed, scope);
}

({List<Object?> items, String itemVar, String indexVar}) _parseForDirective(
  Object? raw, {
  String? itemAlias,
  String? indexAlias,
  required Map<String, Object?> scope,
}) {
  var itemVar = (itemAlias != null && itemAlias.trim().isNotEmpty)
      ? itemAlias.trim()
      : 'item';
  var indexVar = (indexAlias != null && indexAlias.trim().isNotEmpty)
      ? indexAlias.trim()
      : 'index';

  if (_kBlockedScopeSegments.contains(itemVar) ||
      kForbiddenVibeMethodNames.contains(itemVar)) {
    throw FormatException('Forbidden VXML loop variable "$itemVar"');
  }
  if (_kBlockedScopeSegments.contains(indexVar) ||
      kForbiddenVibeMethodNames.contains(indexVar)) {
    throw FormatException('Forbidden VXML loop variable "$indexVar"');
  }

  if (raw is List) {
    return (items: raw, itemVar: itemVar, indexVar: indexVar);
  }
  final str = raw?.toString().trim() ?? '';
  final vueMatch = _kVueForLoopRe.firstMatch(str);
  Object? resolvedList;
  if (vueMatch != null) {
    itemVar = vueMatch.group(1)!;
    if (vueMatch.group(2) != null) indexVar = vueMatch.group(2)!;
    if (_kBlockedScopeSegments.contains(itemVar) ||
        kForbiddenVibeMethodNames.contains(itemVar) ||
        _kBlockedScopeSegments.contains(indexVar) ||
        kForbiddenVibeMethodNames.contains(indexVar)) {
      throw const FormatException('Forbidden VXML loop variable');
    }
    resolvedList = _evalDirectiveValue(vueMatch.group(3)!, scope);
  } else {
    resolvedList = _evalDirectiveValue(str, scope);
  }
  final items = resolvedList is List ? resolvedList : const <Object?>[];
  return (items: items, itemVar: itemVar, indexVar: indexVar);
}

Object? _interpolateValue(Object? value, Map<String, Object?> scope) {
  if (value == null || value is num || value is bool) return value;
  if (VibeSealedHandle.tryParse(value) != null) return value;
  if (value is String) return _interpolateString(value, scope);
  if (value is List) {
    return <Object?>[for (final v in value) _interpolateValue(v, scope)];
  }
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries)
        e.key.toString(): _interpolateValue(e.value, scope),
    };
  }
  return value;
}

Object? _interpolateString(String raw, Map<String, Object?> scope) {
  if (!raw.contains('{{')) return raw;
  final trimmed = raw.trim();
  if (trimmed.startsWith('{{') && trimmed.endsWith('}}')) {
    final inner = trimmed.substring(2, trimmed.length - 2);
    if (!inner.contains('{{') && !inner.contains('}}')) {
      return evaluateVibeBindingExpression(inner, scope);
    }
  }
  return raw.replaceAllMapped(_kTemplateMustacheRe, (match) {
    final val = evaluateVibeBindingExpression(match.group(1)!, scope);
    if (val == null) return '';
    if (VibeSealedHandle.tryParse(val) != null) return '';
    if (val is double && val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toString();
  });
}

class _BindingExprParser {
  _BindingExprParser(this.source, this.scope);

  final String source;
  final Map<String, Object?> scope;
  int _pos = 0;

  void _skipWs() {
    while (_pos < source.length && source.codeUnitAt(_pos) <= 32) {
      _pos++;
    }
  }

  bool _match(String token) {
    _skipWs();
    if (source.startsWith(token, _pos)) {
      if (token.length == 2 &&
          (token == '==' || token == '!=' || token == '<' || token == '>') &&
          _pos + 2 < source.length &&
          source[_pos + 2] == '=') {
        return false;
      }
      if (token.length == 1 &&
          (token == '<' || token == '>' || token == '!') &&
          _pos + 1 < source.length &&
          source[_pos + 1] == '=') {
        return false;
      }
      _pos += token.length;
      return true;
    }
    return false;
  }

  Object? parseExpression([int depth = 0]) {
    if (depth > _kMaxBindingExprDepth) {
      throw const FormatException('Binding expression exceeds nesting limit');
    }
    final cond = _parseNullishOrLogicalOr(depth);
    _skipWs();
    if (_match('?')) {
      final whenTrue = parseExpression(depth + 1);
      _match(':');
      final whenFalse = parseExpression(depth + 1);
      return isVibeBindingTruthy(cond) ? whenTrue : whenFalse;
    }
    return cond;
  }

  Object? _parseNullishOrLogicalOr(int depth) {
    var left = _parseLogicalAnd(depth);
    while (true) {
      if (_match('||')) {
        final right = _parseLogicalAnd(depth);
        left = isVibeBindingTruthy(left) ? left : right;
      } else if (_match('??')) {
        final right = _parseLogicalAnd(depth);
        left = left ?? right;
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseLogicalAnd(int depth) {
    var left = _parseEquality(depth);
    while (_match('&&')) {
      final right = _parseEquality(depth);
      left = isVibeBindingTruthy(left) ? right : left;
    }
    return left;
  }

  Object? _parseEquality(int depth) {
    var left = _parseRelational(depth);
    while (true) {
      if (_match('===') || _match('==')) {
        left = _equals(left, _parseRelational(depth));
      } else if (_match('!==') || _match('!=')) {
        left = !_equals(left, _parseRelational(depth));
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseRelational(int depth) {
    var left = _parseAdditive(depth);
    while (true) {
      if (_match('>=')) {
        left = _toNum(left) >= _toNum(_parseAdditive(depth));
      } else if (_match('<=')) {
        left = _toNum(left) <= _toNum(_parseAdditive(depth));
      } else if (_match('>')) {
        left = _toNum(left) > _toNum(_parseAdditive(depth));
      } else if (_match('<')) {
        left = _toNum(left) < _toNum(_parseAdditive(depth));
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseAdditive(int depth) {
    var left = _parseMultiplicative(depth);
    while (true) {
      if (_match('+')) {
        final right = _parseMultiplicative(depth);
        if (left is String || right is String) {
          left = '${left ?? ''}${right ?? ''}';
        } else if (left is int && right is int) {
          left = left + right;
        } else {
          left = _toNum(left) + _toNum(right);
        }
      } else if (_match('-')) {
        final right = _parseMultiplicative(depth);
        if (left is int && right is int) {
          left = left - right;
        } else {
          left = _toNum(left) - _toNum(right);
        }
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseMultiplicative(int depth) {
    var left = _parseUnary(depth);
    while (true) {
      if (_match('*')) {
        final right = _parseUnary(depth);
        if (left is int && right is int) {
          left = left * right;
        } else {
          left = _toNum(left) * _toNum(right);
        }
      } else if (_match('/')) {
        final denom = _toNum(_parseUnary(depth));
        left = denom == 0 ? 0.0 : _toNum(left) / denom;
      } else if (_match('%')) {
        final denom = _toNum(_parseUnary(depth));
        left = denom == 0 ? 0.0 : _toNum(left) % denom;
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseUnary(int depth) {
    if (depth > _kMaxBindingExprDepth) {
      throw const FormatException('Binding expression exceeds nesting limit');
    }
    if (_match('!')) return !isVibeBindingTruthy(_parseUnary(depth + 1));
    if (_match('-')) return -_toNum(_parseUnary(depth + 1));
    if (_match('+')) return _toNum(_parseUnary(depth + 1));
    return _parsePrimary(depth);
  }

  Object? _parsePrimary(int depth) {
    _skipWs();
    if (_pos >= source.length) return null;
    final ch = source[_pos];
    if (ch == '(') {
      _pos++;
      final inner = parseExpression(depth + 1);
      _match(')');
      return inner;
    }
    if (ch == "'" || ch == '"') {
      final quote = ch;
      _pos++;
      final buf = StringBuffer();
      while (_pos < source.length && source[_pos] != quote) {
        if (source[_pos] == r'\' && _pos + 1 < source.length) {
          _pos++;
        }
        buf.write(source[_pos++]);
      }
      if (_pos < source.length) _pos++;
      return buf.toString();
    }
    if ((ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) || ch == '.') {
      final start = _pos;
      while (_pos < source.length &&
          _isNumOrDotCodeUnit(source.codeUnitAt(_pos))) {
        _pos++;
      }
      final rawNum = source.substring(start, _pos);
      return int.tryParse(rawNum) ?? double.tryParse(rawNum) ?? 0;
    }
    final start = _pos;
    var bracketDepth = 0;
    while (_pos < source.length) {
      final cu = source.codeUnitAt(_pos);
      if (cu == 91) {
        bracketDepth++;
        _pos++;
      } else if (cu == 93 && bracketDepth > 0) {
        bracketDepth--;
        _pos++;
      } else if (bracketDepth > 0) {
        _pos++;
      } else if (_isIdentOrPathCodeUnit(cu)) {
        _pos++;
      } else {
        break;
      }
    }
    final ident = source.substring(start, _pos).trim();
    if (ident == 'true') return true;
    if (ident == 'false') return false;
    if (ident == 'null' || ident == 'undefined') return null;
    if (ident.isEmpty) return null;
    final (found, val) = lookupVibeScopePath(scope, ident);
    return found ? val : null;
  }

  static double _toNum(Object? v) {
    if (v is num && v.isFinite) return v.toDouble();
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  static bool _equals(Object? a, Object? b) {
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return a == b;
  }
}
