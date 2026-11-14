import 'compatibility_adapter.dart';
import 'vibe_protocol.dart';

const int _kMaxForLoopItems = 200;

final RegExp _kSafeColorHexRe = RegExp(
  r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);
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
        RegExp(r'-([a-zA-Z])'),
        (m) => m.group(1)!.toUpperCase(),
      );
      final asNum = double.tryParse(rawVal.replaceAll(RegExp(r'px$'), ''));
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
      final p = double.tryParse(v.trim().replaceAll(RegExp(r'px$'), ''));
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

/// Resolves a dotted/bracket path (e.g. `bars[0].value`, `terminal.agy.tps`)
/// against [scope] without executing code or unsealing `{ 'sealed': 'h_...' }`.
(bool, Object?) lookupVibeScopePath(
  Map<String, Object?> scope,
  String rawPath,
) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) return (false, null);
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
        final (foundIdx, dynIdx) = lookupVibeScopePath(scope, idxExpr);
        if (foundIdx && dynIdx != null) idxExpr = dynIdx.toString();
      }
      segments.add(idxExpr);
      i = end;
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) segments.add(buf.toString());
  if (segments.isEmpty) return (false, null);

  Object? cursor = scope;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
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
  final parser = _BindingExprParser(expr.trim(), scope);
  if (parser.source.isEmpty) return null;
  return parser.parseExpression();
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
    for (var i = 0; i < spec.items.length && i < _kMaxForLoopItems; i++) {
      final childScope = <String, Object?>{
        ...scope,
        spec.itemVar: spec.items[i],
        spec.indexVar: i,
      };
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
            RegExp(r'-([a-zA-Z])'),
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
    out['command'] ??= 'mp:tap:$bindTap';
    final existingArgs = out['args'] is Map
        ? Map<String, Object?>.from(
            (out['args'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, Object?>{};
    existingArgs['__mpEvent'] = true;
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
    out['command'] = 'mp:change:$bindChange';
  }

  return <Map<String, Object?>>[out];
}

String? _cleanHandlerName(Object? raw, Map<String, Object?> scope) {
  if (raw == null) return null;
  final resolved = _interpolateValue(raw, scope)?.toString().trim() ?? '';
  if (resolved.isEmpty) return null;
  return RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]{0,63}$').hasMatch(resolved)
      ? resolved
      : null;
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

  if (raw is List) {
    return (items: raw, itemVar: itemVar, indexVar: indexVar);
  }
  final str = raw?.toString().trim() ?? '';
  final vueMatch = RegExp(
    r'^\(?\s*([a-zA-Z_$][a-zA-Z0-9_$]*)(?:\s*,\s*([a-zA-Z_$][a-zA-Z0-9_$]*))?\s*\)?\s+in\s+(.+)$',
  ).firstMatch(str);
  Object? resolvedList;
  if (vueMatch != null) {
    itemVar = vueMatch.group(1)!;
    if (vueMatch.group(2) != null) indexVar = vueMatch.group(2)!;
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
  return raw.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
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

  Object? parseExpression() {
    final cond = _parseNullishOrLogicalOr();
    _skipWs();
    if (_match('?')) {
      final whenTrue = parseExpression();
      _match(':');
      final whenFalse = parseExpression();
      return isVibeBindingTruthy(cond) ? whenTrue : whenFalse;
    }
    return cond;
  }

  Object? _parseNullishOrLogicalOr() {
    var left = _parseLogicalAnd();
    while (true) {
      if (_match('||')) {
        final right = _parseLogicalAnd();
        left = isVibeBindingTruthy(left) ? left : right;
      } else if (_match('??')) {
        final right = _parseLogicalAnd();
        left = left ?? right;
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseLogicalAnd() {
    var left = _parseEquality();
    while (_match('&&')) {
      final right = _parseEquality();
      left = isVibeBindingTruthy(left) ? right : left;
    }
    return left;
  }

  Object? _parseEquality() {
    var left = _parseRelational();
    while (true) {
      if (_match('===') || _match('==')) {
        left = _equals(left, _parseRelational());
      } else if (_match('!==') || _match('!=')) {
        left = !_equals(left, _parseRelational());
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseRelational() {
    var left = _parseAdditive();
    while (true) {
      if (_match('>=')) {
        left = _toNum(left) >= _toNum(_parseAdditive());
      } else if (_match('<=')) {
        left = _toNum(left) <= _toNum(_parseAdditive());
      } else if (_match('>')) {
        left = _toNum(left) > _toNum(_parseAdditive());
      } else if (_match('<')) {
        left = _toNum(left) < _toNum(_parseAdditive());
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      if (_match('+')) {
        final right = _parseMultiplicative();
        if (left is String || right is String) {
          left = '${left ?? ''}${right ?? ''}';
        } else {
          left = _toNum(left) + _toNum(right);
        }
      } else if (_match('-')) {
        left = _toNum(left) - _toNum(_parseMultiplicative());
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      if (_match('*')) {
        left = _toNum(left) * _toNum(_parseUnary());
      } else if (_match('/')) {
        final denom = _toNum(_parseUnary());
        left = denom == 0 ? 0.0 : _toNum(left) / denom;
      } else if (_match('%')) {
        final denom = _toNum(_parseUnary());
        left = denom == 0 ? 0.0 : _toNum(left) % denom;
      } else {
        break;
      }
    }
    return left;
  }

  Object? _parseUnary() {
    if (_match('!')) return !isVibeBindingTruthy(_parseUnary());
    if (_match('-')) return -_toNum(_parseUnary());
    if (_match('+')) return _toNum(_parseUnary());
    return _parsePrimary();
  }

  Object? _parsePrimary() {
    _skipWs();
    if (_pos >= source.length) return null;
    final ch = source[_pos];
    if (ch == '(') {
      _pos++;
      final inner = parseExpression();
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
      while (_pos < source.length && RegExp(r'[0-9.]').hasMatch(source[_pos])) {
        _pos++;
      }
      final rawNum = source.substring(start, _pos);
      return int.tryParse(rawNum) ?? double.tryParse(rawNum) ?? 0;
    }
    final start = _pos;
    var bracketDepth = 0;
    while (_pos < source.length) {
      final c = source[_pos];
      if (c == '[') {
        bracketDepth++;
        _pos++;
      } else if (c == ']' && bracketDepth > 0) {
        bracketDepth--;
        _pos++;
      } else if (bracketDepth > 0) {
        _pos++;
      } else if (RegExp(r'[a-zA-Z0-9_$.]').hasMatch(c)) {
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
