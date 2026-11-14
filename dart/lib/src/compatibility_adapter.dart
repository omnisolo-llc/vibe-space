import 'dart:convert';
import 'dart:math';

import 'vibe_protocol.dart';
import 'vibe_runtime_config.dart' show kMaxVibeCanvasCommands;
import 'vibe_vxml_template.dart' show normalizeVibeStyleTokens;

/// Depth and node limits matching `validateVibeView` in `vibe_space_flutter`.
const int kMaxAdaptedViewDepth = 16;
const int kMaxAdaptedViewNodes = 1024;

const Set<String> _kCanonicalViewTypes = <String>{
  'column',
  'row',
  'card',
  'heading',
  'text',
  'badge',
  'stat',
  'bar',
  'sparkline',
  'canvas',
  'table',
  'divider',
  'progress',
  'button',
  'action',
  'input',
  'checkbox',
  'option_group',
};

const Set<String> _kCanonicalTones = <String>{
  'default',
  'ok',
  'warn',
  'danger',
};

final RegExp _kHexSwatchRegex = RegExp(r'^#[0-9a-fA-F]{6}$');
final RegExp _kSafeIdRegex = RegExp(r'^[a-zA-Z0-9_.-]{1,64}$');
final RegExp _kUnsafeSchemeRegex = RegExp(
  r'^\s*(?:javascript|vbscript|data)\s*:',
  caseSensitive: false,
);

/// Bidirectional compatibility adapter converting **A2UI**, **Adaptive Cards**,
/// **Markdown**, and canonical `VibeView` trees into validated canonical
/// `VibeView` maps while preserving `{ 'sealed': 'h_...' }` handles.
class VibeUiCompatibilityAdapter {
  const VibeUiCompatibilityAdapter._();

  /// Adapts [raw] (canonical `VibeView`, A2UI payload, Adaptive Card, or
  /// Markdown) into a validated canonical `VibeView` map.
  ///
  /// When [dataModel] is supplied (for example, live host `needs` capability
  /// streams + trigger context), A2UI `{ "path": "/..." }` bindings resolve
  /// against the merged `dataModelUpdate` + [dataModel] state.
  ///
  /// Throws [FormatException] when [raw] cannot be converted safely or exceeds
  /// depth/node limits.
  static Map<String, Object?> adapt(
    Object? raw, {
    Map<String, Object?>? dataModel,
  }) {
    if (raw == null) {
      throw const FormatException('View payload cannot be null');
    }

    if (raw is String) {
      return _adaptMarkdown(raw);
    }

    if (raw is List) {
      return _adaptA2UiMessageList(raw, dataModel: dataModel);
    }

    if (raw is! Map) {
      throw FormatException(
          'Unsupported view payload type: ${raw.runtimeType}');
    }

    final map = _stringifyMap(raw);

    // Markdown wrapper object
    if (map['format'] == 'markdown' ||
        map['type'] == 'markdown' ||
        (map.containsKey('markdown') &&
            map['markdown'] is String &&
            !map.containsKey('type'))) {
      final md = (map['markdown'] ?? map['content'] ?? '').toString();
      return _adaptMarkdown(md);
    }

    // Unwrap { "a2ui": ... } envelope if present
    if (map.containsKey('a2ui') &&
        (map['a2ui'] is Map || map['a2ui'] is List)) {
      final embeddedModel = map['dataModel'] is Map
          ? _stringifyMap(map['dataModel'] as Map)
          : const <String, Object?>{};
      final merged = <String, Object?>{
        ...embeddedModel,
        if (dataModel != null) ...dataModel,
      };
      return adapt(map['a2ui'], dataModel: merged);
    }

    // Adaptive Card
    if (map['type'] == 'AdaptiveCard') {
      return _adaptAdaptiveCard(map);
    }

    // A2UI surfaceUpdate / dataModelUpdate / components adjacency list / nested component
    if (map.containsKey('surfaceUpdate') ||
        map.containsKey('dataModelUpdate') ||
        map.containsKey('beginRendering') ||
        (map['components'] is List) ||
        map.containsKey('component')) {
      return _adaptA2Ui(map, dataModel: dataModel);
    }

    // PascalCase A2UI nested node (e.g. { "type": "Column", "children": [...] })
    final rawType = map['type']?.toString();
    if (rawType != null &&
        !_kCanonicalViewTypes.contains(rawType) &&
        _isA2UiComponentName(rawType)) {
      return _adaptA2UiNode(
        map,
        <String, Map<String, Object?>>{},
        0,
        _NodeBudget(),
        <String>{},
        dataModel: dataModel ?? const <String, Object?>{},
      );
    }

    // Canonical VibeView
    return _normalizeCanonicalNode(map, 0, _NodeBudget(), <String>{});
  }

  /// Like [adapt], returning `null` instead of throwing on invalid input.
  static Map<String, Object?>? tryAdapt(
    Object? raw, {
    Map<String, Object?>? dataModel,
  }) {
    try {
      return adapt(raw, dataModel: dataModel);
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _normalizeCanonicalNode(
    Map<String, Object?> node,
    int depth,
    _NodeBudget budget,
    Set<String> seenInputIds,
  ) {
    if (depth > kMaxAdaptedViewDepth) {
      throw const FormatException('Extension view limit exceeded (depth)');
    }
    budget.consume();

    final type = node['type']?.toString();
    if (type == null || !_kCanonicalViewTypes.contains(type)) {
      throw FormatException('Unsupported extension view type: $type');
    }

    final tone = _validTone(node['tone']);

    Map<String, Object?> result;
    switch (type) {
      case 'column':
      case 'row':
      case 'card':
        final rawChildren = node['children'];
        final children = <Map<String, Object?>>[];
        if (rawChildren is List) {
          if (rawChildren.length > 100) {
            throw const FormatException('Container exceeds 100 children limit');
          }
          for (final child in rawChildren) {
            if (child is Map) {
              children.add(
                _normalizeCanonicalNode(
                  _stringifyMap(child),
                  depth + 1,
                  budget,
                  seenInputIds,
                ),
              );
            }
          }
        }
        result = <String, Object?>{
          'type': type,
          if (tone != null) 'tone': tone,
          'children': children,
        };

      case 'heading':
      case 'badge':
      case 'text':
        result = <String, Object?>{
          'type': type,
          'text': _normalizeTextOrSealed(node['text']),
          if (tone != null) 'tone': tone,
          if (node['bold'] == true) 'bold': true,
          if (node['strong'] == true) 'strong': true,
          if (node['italic'] == true) 'italic': true,
          if (node['code'] == true) 'code': true,
          if (node['mono'] == true) 'mono': true,
        };

      case 'stat':
        result = <String, Object?>{
          'type': 'stat',
          'label': _normalizeTextOrSealed(node['label']),
          'value': _normalizeTextOrSealed(node['value']),
          if (tone != null) 'tone': tone,
        };

      case 'bar':
        final val = node['value'] is num && (node['value'] as num).isFinite
            ? node['value'] as num
            : 0;
        final maxVal = node['max'] is num &&
                (node['max'] as num).isFinite &&
                (node['max'] as num) > 0
            ? node['max'] as num
            : 1;
        final swatch = node['swatch']?.toString();
        result = <String, Object?>{
          'type': 'bar',
          'label': _normalizeTextOrSealed(node['label']),
          'value': val,
          'max': maxVal,
          if (node['caption'] != null)
            'caption': _normalizeTextOrSealed(node['caption']),
          if (tone != null) 'tone': tone,
          if (swatch != null && _kHexSwatchRegex.hasMatch(swatch))
            'swatch': swatch,
        };

      case 'sparkline':
        final rawVals = node['values'];
        final vals = <double>[];
        if (rawVals is List) {
          for (final v in rawVals.take(240)) {
            if (v is num && v.isFinite) vals.add(v.toDouble());
          }
        }
        result = <String, Object?>{
          'type': 'sparkline',
          'values': vals,
          if (tone != null) 'tone': tone,
        };

      case 'canvas':
        result = _normalizeCanvasNode(node, tone, budget);

      case 'progress':
        final rawVal = node['value'];
        final val = rawVal is num && rawVal.isFinite
            ? rawVal.toDouble().clamp(0.0, 1.0)
            : 0.0;
        result = <String, Object?>{
          'type': 'progress',
          'value': val,
        };

      case 'divider':
        result = <String, Object?>{'type': 'divider'};

      case 'table':
        final rawHeaders =
            node['headers'] is List ? node['headers'] as List : const [];
        final headers = <Object?>[
          for (final h in rawHeaders.take(32)) _normalizeTextOrSealed(h),
        ];
        final rawRows = node['rows'] is List ? node['rows'] as List : const [];
        final rows = <List<Object?>>[];
        for (final row in rawRows.take(200)) {
          if (row is List) {
            rows.add(<Object?>[
              for (final cell in row.take(32)) _normalizeCellOrSealed(cell),
            ]);
          }
        }
        result = <String, Object?>{
          'type': 'table',
          'headers': headers,
          'rows': rows,
        };

      case 'button':
      case 'action':
        final title = _normalizePlainString(
            node['text'] ?? node['title'] ?? 'Action', 256);
        final cmd = _normalizePlainString(node['command'] ?? 'action', 128);
        final rawArgs = node['arguments'] ?? node['args'];
        final Map<String, Object?>? args =
            rawArgs is Map ? _stringifyMap(rawArgs) : null;
        if (args != null &&
            args['url'] is String &&
            _kUnsafeSchemeRegex.hasMatch(args['url'] as String)) {
          args.remove('url');
        }
        result = <String, Object?>{
          'type': type,
          if (type == 'button') 'text': title else 'title': title,
          'command': cmd,
          if (tone != null) 'tone': tone,
          if (node['disabled'] == true) 'disabled': true,
          if (args != null) (type == 'button' ? 'args' : 'arguments'): args,
        };

      case 'input':
        final id = _claimUniqueId(node['id']?.toString(), seenInputIds, budget);
        result = <String, Object?>{
          'type': 'input',
          'id': id,
          'label': _normalizePlainString(node['label'] ?? 'Input', 256),
          if (node['secret'] == true) 'secret': true,
          if (node['multiline'] == true) 'multiline': true,
        };

      case 'checkbox':
        final id = _claimUniqueId(node['id']?.toString(), seenInputIds, budget);
        result = <String, Object?>{
          'type': 'checkbox',
          'id': id,
          'label': _normalizePlainString(node['label'] ?? 'Option', 256),
          if (node['checked'] == true) 'checked': true,
          if (node['command'] is String &&
              (node['command'] as String).isNotEmpty)
            'command': _normalizePlainString(node['command'], 128),
        };

      case 'option_group':
        final id = _claimUniqueId(node['id']?.toString(), seenInputIds, budget);
        final rawOptions =
            node['options'] is List ? node['options'] as List : const [];
        final options = <Map<String, Object?>>[];
        for (var i = 0; i < rawOptions.length && options.length < 50; i++) {
          final opt = rawOptions[i];
          if (opt is Map) {
            final om = _stringifyMap(opt);
            final optId = _normalizePlainString(om['id'] ?? 'opt_$i', 64);
            final optLabel = _normalizePlainString(om['label'] ?? optId, 256);
            options.add(<String, Object?>{
              'id': optId.isEmpty ? 'opt_$i' : optId,
              'label': optLabel.isEmpty ? optId : optLabel,
              if (om['value'] != null) 'value': om['value'].toString(),
              if (om['checked'] == true) 'checked': true,
              if (om['selected'] == true) 'selected': true,
            });
          }
        }
        if (options.isEmpty) {
          options
              .add(const <String, Object?>{'id': 'opt_0', 'label': 'Option'});
        }
        result = <String, Object?>{
          'type': 'option_group',
          'id': id,
          if (node['label'] is String)
            'label': _normalizePlainString(node['label'], 256),
          if (node['multiSelect'] == true) 'multiSelect': true,
          if (node['command'] is String &&
              (node['command'] as String).isNotEmpty)
            'command': _normalizePlainString(node['command'], 128),
          'options': options,
        };

      default:
        throw FormatException('Unsupported view node type: $type');
    }

    return _withMiniProgramMeta(node, result);
  }

  static const Set<String> _kCanvasOps = <String>{
    'clear',
    'rect',
    'rrect',
    'circle',
    'arc',
    'line',
    'path',
    'polygon',
    'bars',
    'text',
  };

  static Map<String, Object?> _normalizeCanvasNode(
    Map<String, Object?> node,
    String? tone,
    _NodeBudget budget,
  ) {
    final w = node['width'] is num && (node['width'] as num).isFinite
        ? (node['width'] as num).toDouble().clamp(16.0, 2048.0)
        : 240.0;
    final h = node['height'] is num && (node['height'] as num).isFinite
        ? (node['height'] as num).toDouble().clamp(16.0, 2048.0)
        : 64.0;
    final rawCommands = node['commands'] ?? node['draw'];
    if (rawCommands is! List) {
      throw const FormatException('Canvas node requires a commands list');
    }
    budget.consumeCanvasCommands(rawCommands.length);
    final commands = <Map<String, Object?>>[];
    for (final item in rawCommands) {
      if (item is! Map) continue;
      final cm = _stringifyMap(item);
      final op = (cm['op'] ?? cm['type'])?.toString().trim().toLowerCase();
      if (op == null || !_kCanvasOps.contains(op)) {
        throw FormatException('Unsupported canvas command op: $op');
      }
      final normalizedCmd = <String, Object?>{'op': op};
      for (final entry in cm.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k == 'op' || k == 'type' || v == null) continue;
        if (v is num) {
          if (v.isFinite) normalizedCmd[k] = v.toDouble();
        } else if (v is bool) {
          normalizedCmd[k] = v;
        } else if (k == 'text') {
          normalizedCmd['text'] = _normalizeTextOrSealed(v);
        } else if (v is String) {
          normalizedCmd[k] = _normalizePlainString(v, 256);
        } else if (k == 'values' && v is List) {
          normalizedCmd['values'] = <double>[
            for (final n in v.take(512))
              if (n is num && n.isFinite) n.toDouble(),
          ];
        } else if (k == 'points' && v is List) {
          final pts = <List<double>>[];
          for (final pt in v.take(512)) {
            if (pt is List && pt.length >= 2 && pt[0] is num && pt[1] is num) {
              final px = (pt[0] as num).toDouble();
              final py = (pt[1] as num).toDouble();
              if (px.isFinite && py.isFinite) pts.add(<double>[px, py]);
            } else if (pt is Map && pt['x'] is num && pt['y'] is num) {
              final px = (pt['x'] as num).toDouble();
              final py = (pt['y'] as num).toDouble();
              if (px.isFinite && py.isFinite) pts.add(<double>[px, py]);
            }
          }
          normalizedCmd['points'] = pts;
        } else if (k == 'linearGradient' && v is Map) {
          final gm = _stringifyMap(v);
          final rawColors = gm['colors'];
          if (rawColors is List) {
            final colors = <String>[
              for (final c in rawColors.take(8))
                if (c != null) _normalizePlainString(c, 32),
            ];
            if (colors.length >= 2) {
              normalizedCmd['linearGradient'] = <String, Object?>{
                'colors': colors,
                if (gm['begin'] is List)
                  'begin': <double>[
                    for (final b in (gm['begin'] as List).take(2))
                      if (b is num && b.isFinite) b.toDouble(),
                  ],
                if (gm['end'] is List)
                  'end': <double>[
                    for (final b in (gm['end'] as List).take(2))
                      if (b is num && b.isFinite) b.toDouble(),
                  ],
              };
            }
          }
        }
      }
      commands.add(normalizedCmd);
    }

    final rawArgs = node['args'] ?? node['arguments'];
    return <String, Object?>{
      'type': 'canvas',
      'width': w,
      'height': h,
      'commands': commands,
      if (tone != null) 'tone': tone,
      if (node['alt'] != null) 'alt': _normalizeTextOrSealed(node['alt']),
      if (node['label'] != null) 'label': _normalizeTextOrSealed(node['label']),
      if (node['command'] is String && (node['command'] as String).isNotEmpty)
        'command': _normalizePlainString(node['command'], 128),
      if (rawArgs is Map) 'args': _stringifyMap(rawArgs),
    };
  }

  static Map<String, Object?> _withMiniProgramMeta(
    Map<String, Object?> sourceNode,
    Map<String, Object?> normalized,
  ) {
    final style = normalizeVibeStyleTokens(sourceNode['style']);
    final bindTap = sourceNode['bindtap'];
    final bindInput = sourceNode['bindinput'];
    final bindChange = sourceNode['bindchange'];
    final dataset = sourceNode['dataset'];
    if (style == null &&
        bindTap == null &&
        bindInput == null &&
        bindChange == null &&
        dataset == null) {
      return normalized;
    }
    final out = Map<String, Object?>.from(normalized);
    if (style != null) out['style'] = style;
    for (final entry in <String, Object?>{
      'bindtap': bindTap,
      'bindinput': bindInput,
      'bindchange': bindChange,
    }.entries) {
      final s = entry.value?.toString().trim();
      if (s != null && RegExp(r'^[a-zA-Z_$][a-zA-Z0-9_$]{0,63}$').hasMatch(s)) {
        out[entry.key] = s;
      }
    }
    if (dataset is Map && dataset.isNotEmpty) {
      out['dataset'] = _stringifyMap(dataset);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // A2UI Adapter
  // ---------------------------------------------------------------------------

  static bool _isA2UiComponentName(String raw) {
    const names = <String>{
      'column',
      'row',
      'card',
      'text',
      'heading',
      'badge',
      'button',
      'textfield',
      'checkbox',
      'multiplechoice',
      'choicepicker',
      'progressbar',
      'linearprogress',
      'metric',
      'stat',
      'table',
      'divider',
      'bar',
      'sparkline',
    };
    return names.contains(raw.toLowerCase());
  }

  static void _applyA2UiDataModelUpdate(
    Map<String, Object?> target,
    Map<String, Object?> dmu,
  ) {
    final rawPath = dmu['path']?.toString().trim() ?? '';
    final segments = rawPath
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    Map<String, Object?> bucket = target;
    for (final seg in segments) {
      final next = bucket[seg];
      if (next is Map) {
        final copy = _stringifyMap(next);
        bucket[seg] = copy;
        bucket = copy;
      } else {
        final created = <String, Object?>{};
        bucket[seg] = created;
        bucket = created;
      }
    }

    Object? decodeEntryValue(Map<String, Object?> entry) {
      if (entry.containsKey('valueString')) return entry['valueString'];
      if (entry.containsKey('valueNumber')) return entry['valueNumber'];
      if (entry.containsKey('valueBoolean')) return entry['valueBoolean'];
      if (entry.containsKey('value')) return entry['value'];
      if (entry['valueList'] is List) return entry['valueList'];
      if (entry['valueMap'] is List) {
        final nested = <String, Object?>{};
        for (final sub in entry['valueMap'] as List) {
          if (sub is Map) {
            final sm = _stringifyMap(sub);
            final k = sm['key']?.toString();
            if (k != null && k.isNotEmpty) {
              nested[k] = decodeEntryValue(sm);
            }
          }
        }
        return nested;
      }
      if (entry['valueMap'] is Map) {
        return _stringifyMap(entry['valueMap'] as Map);
      }
      return null;
    }

    if (dmu['contents'] is List) {
      for (final item in dmu['contents'] as List) {
        if (item is! Map) continue;
        final em = _stringifyMap(item);
        final key = em['key']?.toString();
        if (key != null && key.isNotEmpty) {
          bucket[key] = decodeEntryValue(em);
        }
      }
    } else if (dmu['data'] is Map) {
      bucket.addAll(_stringifyMap(dmu['data'] as Map));
    } else if (dmu['values'] is Map) {
      bucket.addAll(_stringifyMap(dmu['values'] as Map));
    } else {
      for (final entry in dmu.entries) {
        if (entry.key == 'surfaceId' || entry.key == 'path') continue;
        bucket[entry.key] = entry.value;
      }
    }
  }

  static (bool, Object?) _lookupA2UiPath(
    Map<String, Object?> model,
    String rawPath,
  ) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || model.isEmpty) return (false, null);
    if (trimmed == '/') return (true, model);

    List<String> segments;
    if (trimmed.startsWith('/')) {
      segments = trimmed
          .substring(1)
          .split('/')
          .map((s) => s.replaceAll('~1', '/').replaceAll('~0', '~'))
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (model.containsKey(trimmed)) {
      return (true, model[trimmed]);
    } else {
      segments = trimmed.split('.').where((s) => s.isNotEmpty).toList();
    }

    Object? cursor = model;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (cursor is Map) {
        if (cursor.containsKey(seg)) {
          cursor = cursor[seg];
          continue;
        }
        // Support dotted capability keys like `terminal.agy` in dot-notation paths
        if (!trimmed.startsWith('/') && i + 1 < segments.length) {
          final joined = '$seg.${segments[i + 1]}';
          if (cursor.containsKey(joined)) {
            cursor = cursor[joined];
            i++;
            continue;
          }
        }
        return (false, null);
      }
      if (cursor is List) {
        final idx = int.tryParse(seg);
        if (idx == null || idx < 0 || idx >= cursor.length) {
          return (false, null);
        }
        cursor = cursor[idx];
        continue;
      }
      return (false, null);
    }
    return (cursor != null, cursor);
  }

  static Object? _resolveA2UiBoundValue(
    Object? raw,
    Map<String, Object?> dataModel,
  ) {
    if (raw is! Map) return raw;
    if (VibeSealedHandle.tryParse(raw) != null) return raw;
    final m = _stringifyMap(raw);
    if (m['path'] is String) {
      final (found, bound) = _lookupA2UiPath(dataModel, m['path'] as String);
      if (found) return bound;
    }
    if (m.containsKey('literalNumber')) return m['literalNumber'];
    if (m.containsKey('literalBoolean')) return m['literalBoolean'];
    if (m.containsKey('literalString')) return m['literalString'];
    if (m.containsKey('literalArray')) return m['literalArray'];
    return raw;
  }

  static Map<String, Object?> _adaptA2UiMessageList(
    List<dynamic> messages, {
    Map<String, Object?>? dataModel,
  }) {
    final merged = <String, Object?>{};
    final allComponents = <Object?>[];
    final resolvedModel = <String, Object?>{};
    String? rootId;

    for (final msg in messages) {
      if (msg is! Map) continue;
      final m = _stringifyMap(msg);
      if (m['surfaceUpdate'] is Map) {
        final su = _stringifyMap(m['surfaceUpdate'] as Map);
        if (su['components'] is List) {
          allComponents.addAll(su['components'] as List);
        }
        if (su['root'] is String) rootId ??= su['root'] as String;
      }
      if (m['dataModelUpdate'] is Map) {
        _applyA2UiDataModelUpdate(
          resolvedModel,
          _stringifyMap(m['dataModelUpdate'] as Map),
        );
      }
      if (m['beginRendering'] is Map) {
        final br = _stringifyMap(m['beginRendering'] as Map);
        if (br['root'] is String) rootId = br['root'] as String;
      }
      if (m['components'] is List) {
        allComponents.addAll(m['components'] as List);
      }
      if (m['root'] is String) rootId ??= m['root'] as String;
    }

    if (dataModel != null) {
      resolvedModel.addAll(dataModel);
    }

    if (allComponents.isEmpty) {
      throw const FormatException('A2UI message list contains no components');
    }
    merged['components'] = allComponents;
    if (rootId != null) merged['root'] = rootId;
    return _adaptA2Ui(merged, dataModel: resolvedModel);
  }

  static Map<String, Object?> _adaptA2Ui(
    Map<String, Object?> doc, {
    Map<String, Object?>? dataModel,
  }) {
    final budget = _NodeBudget();
    final seenIds = <String>{};
    final resolvedModel = <String, Object?>{};
    if (doc['dataModel'] is Map) {
      resolvedModel.addAll(_stringifyMap(doc['dataModel'] as Map));
    }
    if (doc['dataModelUpdate'] is Map) {
      _applyA2UiDataModelUpdate(
        resolvedModel,
        _stringifyMap(doc['dataModelUpdate'] as Map),
      );
    }
    if (dataModel != null) {
      resolvedModel.addAll(dataModel);
    }

    if (doc.containsKey('component') &&
        doc['components'] is! List &&
        !doc.containsKey('surfaceUpdate')) {
      return _adaptA2UiNode(
        doc,
        <String, Map<String, Object?>>{},
        0,
        budget,
        seenIds,
        dataModel: resolvedModel,
      );
    }

    Map<String, Object?> source = doc;
    String? rootId = doc['root']?.toString();
    if (doc['beginRendering'] is Map) {
      final br = _stringifyMap(doc['beginRendering'] as Map);
      if (br['root'] is String) rootId = br['root'] as String;
    }
    if (doc['surfaceUpdate'] is Map) {
      source = _stringifyMap(doc['surfaceUpdate'] as Map);
      rootId ??= source['root']?.toString();
    }

    final rawList = source['components'];
    if (rawList is! List || rawList.isEmpty) {
      throw const FormatException('A2UI payload contains no components');
    }

    final byId = <String, Map<String, Object?>>{};
    String? firstId;
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) continue;
      final comp = _stringifyMap(item);
      final id = comp['id']?.toString() ?? 'comp_$i';
      firstId ??= id;
      byId[id] = comp;
    }

    rootId ??= byId.containsKey('root') ? 'root' : firstId;
    if (rootId == null || !byId.containsKey(rootId)) {
      throw const FormatException('A2UI root component not found');
    }

    return _adaptA2UiById(
      rootId,
      byId,
      0,
      budget,
      seenIds,
      <String>{},
      dataModel: resolvedModel,
    );
  }

  static Map<String, Object?> _adaptA2UiById(
    String id,
    Map<String, Map<String, Object?>> byId,
    int depth,
    _NodeBudget budget,
    Set<String> seenInputIds,
    Set<String> activePath, {
    Map<String, Object?> dataModel = const <String, Object?>{},
  }) {
    if (!activePath.add(id)) {
      throw FormatException('Cycle detected in A2UI component graph at "$id"');
    }
    final comp = byId[id];
    if (comp == null) {
      activePath.remove(id);
      return <String, Object?>{'type': 'text', 'text': ''};
    }
    final result = _adaptA2UiNode(
      comp,
      byId,
      depth,
      budget,
      seenInputIds,
      activePath: activePath,
      dataModel: dataModel,
    );
    activePath.remove(id);
    return result;
  }

  static Map<String, Object?> _adaptA2UiNode(
    Map<String, Object?> node,
    Map<String, Map<String, Object?>> byId,
    int depth,
    _NodeBudget budget,
    Set<String> seenInputIds, {
    Set<String>? activePath,
    Map<String, Object?> dataModel = const <String, Object?>{},
  }) {
    if (depth > kMaxAdaptedViewDepth) {
      throw const FormatException('A2UI view exceeds maximum depth');
    }
    budget.consume();

    final path = activePath ?? <String>{};
    String compName;
    Map<String, Object?> props;

    if (node['component'] is Map) {
      final compMap = _stringifyMap(node['component'] as Map);
      if (compMap.isEmpty) {
        throw const FormatException('A2UI component entry is empty');
      }
      compName = compMap.keys.first;
      final rawProps = compMap[compName];
      props = rawProps is Map ? _stringifyMap(rawProps) : <String, Object?>{};
    } else {
      compName = node['type']?.toString() ?? 'Column';
      props = node;
    }

    final lower = compName.toLowerCase();
    final tone = _validTone(_resolveA2UiBoundValue(props['tone'], dataModel));

    List<Map<String, Object?>> resolveChildren() {
      final rawChildren = props['children'];
      final list = <Object?>[];
      if (rawChildren is Map && rawChildren['explicitList'] is List) {
        list.addAll(rawChildren['explicitList'] as List);
      } else if (rawChildren is List) {
        list.addAll(rawChildren);
      } else if (props['child'] != null) {
        list.add(props['child']);
      }
      if (list.length > 100) {
        throw const FormatException('A2UI container exceeds 100 children');
      }
      final out = <Map<String, Object?>>[];
      for (final item in list) {
        if (item is String && byId.containsKey(item)) {
          out.add(
            _adaptA2UiById(
              item,
              byId,
              depth + 1,
              budget,
              seenInputIds,
              path,
              dataModel: dataModel,
            ),
          );
        } else if (item is Map) {
          out.add(
            _adaptA2UiNode(
              _stringifyMap(item),
              byId,
              depth + 1,
              budget,
              seenInputIds,
              activePath: path,
              dataModel: dataModel,
            ),
          );
        }
      }
      return out;
    }

    Object? resolveA2UiText(Object? raw) {
      if (raw is Map) {
        final sealed = VibeSealedHandle.tryParse(raw);
        if (sealed != null) return sealed.toJson();
        final m = _stringifyMap(raw);
        if (m['path'] is String) {
          final (found, bound) =
              _lookupA2UiPath(dataModel, m['path'] as String);
          if (found) return _normalizeTextOrSealed(bound);
        }
        if (m.containsKey('literalString'))
          return resolveA2UiText(m['literalString']);
        if (m.containsKey('literalNumber'))
          return m['literalNumber']?.toString() ?? '';
        if (m.containsKey('literalBoolean'))
          return m['literalBoolean']?.toString() ?? '';
        if (m.containsKey('text')) return resolveA2UiText(m['text']);
      }
      return _normalizeTextOrSealed(raw);
    }

    num? resolveA2UiNum(Object? raw) {
      final bound = _resolveA2UiBoundValue(raw, dataModel);
      if (bound is num && bound.isFinite) return bound;
      if (bound is String) {
        final parsed = double.tryParse(bound);
        if (parsed != null && parsed.isFinite) return parsed;
      }
      return null;
    }

    switch (lower) {
      case 'column':
      case 'row':
      case 'card':
        return <String, Object?>{
          'type': lower,
          if (tone != null) 'tone': tone,
          'children': resolveChildren(),
        };

      case 'heading':
        return <String, Object?>{
          'type': 'heading',
          'text': resolveA2UiText(props['text'] ?? props['title']),
        };

      case 'badge':
        return <String, Object?>{
          'type': 'badge',
          'text': resolveA2UiText(props['text'] ?? props['label']),
          if (tone != null) 'tone': tone,
        };

      case 'text':
        final hint = props['usageHint']?.toString().toLowerCase() ?? '';
        final textVal = resolveA2UiText(props['text']);
        if (hint == 'h1' ||
            hint == 'h2' ||
            hint == 'h3' ||
            hint == 'heading' ||
            hint == 'title') {
          return <String, Object?>{'type': 'heading', 'text': textVal};
        }
        return <String, Object?>{
          'type': 'text',
          'text': textVal,
          if (tone != null) 'tone': tone,
          if (hint == 'strong' || hint == 'bold') 'strong': true,
          if (hint == 'code' || hint == 'mono') 'mono': true,
        };

      case 'metric':
      case 'stat':
        return <String, Object?>{
          'type': 'stat',
          'label': resolveA2UiText(props['label'] ?? props['title']),
          'value': resolveA2UiText(props['value']),
          if (tone != null) 'tone': tone,
        };

      case 'bar':
        final resolvedMax = resolveA2UiNum(props['max']);
        final maxV = resolvedMax != null && resolvedMax > 0
            ? resolvedMax.toDouble()
            : 1.0;
        final resolvedVal = resolveA2UiNum(props['value']);
        final val = resolvedVal != null ? resolvedVal.toDouble() : 0.0;
        final swatch = props['swatch']?.toString();
        return <String, Object?>{
          'type': 'bar',
          'label': resolveA2UiText(props['label']),
          'value': val,
          'max': maxV,
          if (props['caption'] != null)
            'caption': resolveA2UiText(props['caption']),
          if (tone != null) 'tone': tone,
          if (swatch != null && _kHexSwatchRegex.hasMatch(swatch))
            'swatch': swatch,
        };

      case 'sparkline':
        final rawVals = _resolveA2UiBoundValue(props['values'], dataModel);
        final vals = <double>[
          if (rawVals is List)
            for (final v in rawVals.take(240))
              if (v is num && v.isFinite) v.toDouble(),
        ];
        return <String, Object?>{
          'type': 'sparkline',
          'values': vals,
          if (tone != null) 'tone': tone,
        };

      case 'progressbar':
      case 'linearprogress':
      case 'progress':
        final resolvedVal = resolveA2UiNum(props['value'] ?? props['progress']);
        final val =
            resolvedVal != null ? resolvedVal.toDouble().clamp(0.0, 1.0) : 0.0;
        return <String, Object?>{'type': 'progress', 'value': val};

      case 'divider':
        return const <String, Object?>{'type': 'divider'};

      case 'table':
        final rawHeaders =
            props['headers'] is List ? props['headers'] as List : const [];
        final boundRows = _resolveA2UiBoundValue(props['rows'], dataModel);
        final rawRows = boundRows is List ? boundRows : const [];
        return <String, Object?>{
          'type': 'table',
          'headers': <Object?>[
            for (final h in rawHeaders.take(32)) resolveA2UiText(h),
          ],
          'rows': <List<Object?>>[
            for (final r in rawRows.take(200))
              if (r is List)
                <Object?>[
                  for (final c in r.take(32))
                    VibeSealedHandle.tryParse(c)?.toJson() ??
                        _normalizeCellOrSealed(c),
                ],
          ],
        };

      case 'button':
        var label = props['text'] ?? props['label'] ?? props['title'];
        if (label == null &&
            props['child'] is String &&
            byId.containsKey(props['child'])) {
          final childNode = _adaptA2UiById(
            props['child'] as String,
            byId,
            depth + 1,
            budget,
            seenInputIds,
            path,
            dataModel: dataModel,
          );
          label = childNode['text'];
        }
        final actionMap = props['action'] is Map
            ? _stringifyMap(props['action'] as Map)
            : const <String, Object?>{};
        final cmd = _normalizePlainString(
          props['command'] ?? actionMap['name'] ?? 'action',
          128,
        );
        final args = actionMap['context'] is Map
            ? _stringifyMap(actionMap['context'] as Map)
            : (props['args'] is Map
                ? _stringifyMap(props['args'] as Map)
                : null);
        return <String, Object?>{
          'type': 'button',
          'text':
              _normalizePlainString(resolveA2UiText(label ?? 'Action'), 256),
          'command': cmd,
          if (tone != null) 'tone': tone,
          if (args != null) 'args': args,
        };

      case 'textfield':
      case 'input':
        final id = _claimUniqueId(
          (props['id'] ?? node['id'])?.toString(),
          seenInputIds,
          budget,
        );
        final fieldType =
            props['textFieldType']?.toString().toLowerCase() ?? '';
        return <String, Object?>{
          'type': 'input',
          'id': id,
          'label': _normalizePlainString(
              resolveA2UiText(props['label'] ?? 'Input'), 256),
          if (fieldType == 'obscured' || props['secret'] == true)
            'secret': true,
          if (fieldType == 'longtext' || props['multiline'] == true)
            'multiline': true,
        };

      case 'checkbox':
        final id = _claimUniqueId(
          (props['id'] ?? node['id'])?.toString(),
          seenInputIds,
          budget,
        );
        final boundChecked = _resolveA2UiBoundValue(
          props['value'] ?? props['checked'],
          dataModel,
        );
        return <String, Object?>{
          'type': 'checkbox',
          'id': id,
          'label': _normalizePlainString(
              resolveA2UiText(props['label'] ?? 'Option'), 256),
          if (boundChecked == true) 'checked': true,
        };

      case 'multiplechoice':
      case 'choicepicker':
      case 'option_group':
        final id = _claimUniqueId(
          (props['id'] ?? node['id'])?.toString(),
          seenInputIds,
          budget,
        );
        final rawOpts =
            props['options'] is List ? props['options'] as List : const [];
        final options = <Map<String, Object?>>[];
        for (var i = 0; i < rawOpts.length && options.length < 50; i++) {
          final opt = rawOpts[i];
          if (opt is Map) {
            final om = _stringifyMap(opt);
            final val =
                om['value']?.toString() ?? om['id']?.toString() ?? 'opt_$i';
            final lbl = resolveA2UiText(om['label'] ?? val).toString();
            options.add(<String, Object?>{
              'id': val.isEmpty ? 'opt_$i' : val,
              'label': lbl.isEmpty ? val : lbl,
              if (om['selected'] == true) 'selected': true,
            });
          }
        }
        if (options.isEmpty) {
          options
              .add(const <String, Object?>{'id': 'opt_0', 'label': 'Option'});
        }
        final maxSel = props['maxAllowedSelections'];
        final multi =
            props['multiSelect'] == true || (maxSel is int && maxSel > 1);
        return <String, Object?>{
          'type': 'option_group',
          'id': id,
          if (props['label'] != null)
            'label':
                _normalizePlainString(resolveA2UiText(props['label']), 256),
          if (multi) 'multiSelect': true,
          'options': options,
        };

      default:
        throw FormatException('Unsupported A2UI component: $compName');
    }
  }

  // ---------------------------------------------------------------------------
  // Adaptive Card Adapter
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _adaptAdaptiveCard(Map<String, Object?> card) {
    final budget = _NodeBudget();
    final seenInputIds = <String>{};
    budget.consume();

    final children = <Map<String, Object?>>[];
    final rawBody = card['body'];
    if (rawBody is List) {
      for (final item in rawBody) {
        if (item is Map) {
          final converted = _adaptAdaptiveElement(
            _stringifyMap(item),
            1,
            budget,
            seenInputIds,
          );
          if (converted != null) children.add(converted);
        }
      }
    }

    final rawActions = card['actions'];
    if (rawActions is List && rawActions.isNotEmpty) {
      final buttons = <Map<String, Object?>>[];
      for (final act in rawActions) {
        if (act is Map) {
          final btn = _adaptAdaptiveAction(_stringifyMap(act), budget);
          if (btn != null) buttons.add(btn);
        }
      }
      if (buttons.isNotEmpty) {
        budget.consume();
        children.add(<String, Object?>{'type': 'row', 'children': buttons});
      }
    }

    return <String, Object?>{'type': 'column', 'children': children};
  }

  static Map<String, Object?>? _adaptAdaptiveElement(
    Map<String, Object?> el,
    int depth,
    _NodeBudget budget,
    Set<String> seenInputIds,
  ) {
    if (depth > kMaxAdaptedViewDepth) {
      throw const FormatException('AdaptiveCard exceeds maximum depth');
    }
    budget.consume();

    final type = el['type']?.toString() ?? '';
    switch (type) {
      case 'TextBlock':
        final size = el['size']?.toString().toLowerCase() ?? '';
        final weight = el['weight']?.toString().toLowerCase() ?? '';
        final style = el['style']?.toString().toLowerCase() ?? '';
        final color = el['color']?.toString().toLowerCase() ?? '';
        final tone = switch (color) {
          'good' => 'ok',
          'warning' => 'warn',
          'attention' => 'danger',
          _ => null,
        };
        final textVal = _normalizeTextOrSealed(el['text']);
        if (style == 'heading' || size == 'large' || size == 'extralarge') {
          return <String, Object?>{'type': 'heading', 'text': textVal};
        }
        return <String, Object?>{
          'type': 'text',
          'text': textVal,
          if (tone != null) 'tone': tone,
          if (weight == 'bolder') 'strong': true,
        };

      case 'Container':
        final items = el['items'] is List ? el['items'] as List : const [];
        final children = <Map<String, Object?>>[];
        for (final item in items) {
          if (item is Map) {
            final child = _adaptAdaptiveElement(
              _stringifyMap(item),
              depth + 1,
              budget,
              seenInputIds,
            );
            if (child != null) children.add(child);
          }
        }
        final isEmphasis = el['style']?.toString().toLowerCase() == 'emphasis';
        return <String, Object?>{
          'type': isEmphasis ? 'card' : 'column',
          'children': children,
        };

      case 'ColumnSet':
        final cols = el['columns'] is List ? el['columns'] as List : const [];
        final rowChildren = <Map<String, Object?>>[];
        for (final col in cols) {
          if (col is Map) {
            final cm = _stringifyMap(col);
            budget.consume();
            final items = cm['items'] is List ? cm['items'] as List : const [];
            final colChildren = <Map<String, Object?>>[];
            for (final item in items) {
              if (item is Map) {
                final child = _adaptAdaptiveElement(
                  _stringifyMap(item),
                  depth + 2,
                  budget,
                  seenInputIds,
                );
                if (child != null) colChildren.add(child);
              }
            }
            rowChildren.add(<String, Object?>{
              'type': 'column',
              'children': colChildren,
            });
          }
        }
        return <String, Object?>{'type': 'row', 'children': rowChildren};

      case 'FactSet':
        final facts = el['facts'] is List ? el['facts'] as List : const [];
        final rows = <List<Object?>>[
          for (final fact in facts.take(200))
            if (fact is Map)
              <Object?>[
                _normalizeTextOrSealed(fact['title']),
                _normalizeTextOrSealed(fact['value']),
              ],
        ];
        return <String, Object?>{
          'type': 'table',
          'headers': const <String>['Item', 'Value'],
          'rows': rows,
        };

      case 'Table':
        final rawCols =
            el['columns'] is List ? el['columns'] as List : const [];
        final headers = <Object?>[];
        for (var i = 0; i < rawCols.length && headers.length < 32; i++) {
          final c = rawCols[i];
          if (c is Map && c['title'] != null) {
            headers.add(_normalizeTextOrSealed(c['title']));
          } else {
            headers.add('Col ${i + 1}');
          }
        }
        final rawRows = el['rows'] is List ? el['rows'] as List : const [];
        final rows = <List<Object?>>[];
        for (final r in rawRows.take(200)) {
          if (r is Map && r['cells'] is List) {
            final rowCells = <Object?>[];
            for (final cell in (r['cells'] as List).take(32)) {
              if (cell is Map &&
                  cell['items'] is List &&
                  (cell['items'] as List).isNotEmpty) {
                final first = (cell['items'] as List).first;
                rowCells.add(
                  first is Map
                      ? _normalizeTextOrSealed(first['text'] ?? '')
                      : _normalizeCellOrSealed(first),
                );
              } else {
                rowCells.add(_normalizeCellOrSealed(cell));
              }
            }
            rows.add(rowCells);
          }
        }
        return <String, Object?>{
          'type': 'table',
          'headers': headers.isEmpty ? const <String>['Value'] : headers,
          'rows': rows,
        };

      case 'ProgressBar':
        final val = el['value'] is num && (el['value'] as num).isFinite
            ? (el['value'] as num).toDouble().clamp(0.0, 1.0)
            : 0.0;
        if (el['title'] != null) {
          return <String, Object?>{
            'type': 'bar',
            'label': _normalizeTextOrSealed(el['title']),
            'value': val,
            'max': 1,
          };
        }
        return <String, Object?>{'type': 'progress', 'value': val};

      case 'Input.Text':
        final id = _claimUniqueId(el['id']?.toString(), seenInputIds, budget);
        final style = el['style']?.toString().toLowerCase() ?? '';
        return <String, Object?>{
          'type': 'input',
          'id': id,
          'label': _normalizePlainString(
              el['label'] ?? el['placeholder'] ?? id, 256),
          if (style == 'password') 'secret': true,
          if (el['isMultiline'] == true) 'multiline': true,
        };

      case 'Input.Toggle':
        final id = _claimUniqueId(el['id']?.toString(), seenInputIds, budget);
        return <String, Object?>{
          'type': 'checkbox',
          'id': id,
          'label': _normalizePlainString(el['title'] ?? el['label'] ?? id, 256),
          if (el['value'] == true || el['value'] == 'true') 'checked': true,
        };

      case 'Input.ChoiceSet':
        final id = _claimUniqueId(el['id']?.toString(), seenInputIds, budget);
        final choices =
            el['choices'] is List ? el['choices'] as List : const [];
        final options = <Map<String, Object?>>[];
        for (var i = 0; i < choices.length && options.length < 50; i++) {
          final ch = choices[i];
          if (ch is Map) {
            final val = _normalizePlainString(ch['value'] ?? 'opt_$i', 64);
            final title = _normalizePlainString(ch['title'] ?? val, 256);
            options.add(<String, Object?>{
              'id': val.isEmpty ? 'opt_$i' : val,
              'label': title.isEmpty ? val : title,
            });
          }
        }
        if (options.isEmpty) {
          options
              .add(const <String, Object?>{'id': 'opt_0', 'label': 'Option'});
        }
        return <String, Object?>{
          'type': 'option_group',
          'id': id,
          if (el['label'] != null)
            'label': _normalizePlainString(el['label'], 256),
          if (el['isMultiSelect'] == true) 'multiSelect': true,
          'options': options,
        };

      case 'ActionSet':
        final acts = el['actions'] is List ? el['actions'] as List : const [];
        final buttons = <Map<String, Object?>>[];
        for (final a in acts) {
          if (a is Map) {
            final btn = _adaptAdaptiveAction(_stringifyMap(a), budget);
            if (btn != null) buttons.add(btn);
          }
        }
        return <String, Object?>{'type': 'row', 'children': buttons};

      default:
        if (el['text'] != null) {
          return <String, Object?>{
            'type': 'text',
            'text': _normalizeTextOrSealed(el['text']),
          };
        }
        return null;
    }
  }

  static Map<String, Object?>? _adaptAdaptiveAction(
    Map<String, Object?> act,
    _NodeBudget budget,
  ) {
    final type = act['type']?.toString() ?? '';
    final title = _normalizePlainString(act['title'] ?? 'Action', 256);
    if (type == 'Action.OpenUrl') {
      final url = act['url']?.toString() ?? '';
      if (_kUnsafeSchemeRegex.hasMatch(url)) {
        return null;
      }
      budget.consume();
      return <String, Object?>{
        'type': 'button',
        'text': title,
        'command': 'open_url',
        if (url.isNotEmpty) 'args': <String, Object?>{'url': url},
      };
    }
    budget.consume();
    final data = act['data'] is Map ? _stringifyMap(act['data'] as Map) : null;
    final cmd = _normalizePlainString(
      (data != null ? data['command'] : null) ?? act['verb'] ?? 'submit',
      128,
    );
    return <String, Object?>{
      'type': 'button',
      'text': title,
      'command': cmd,
      if (data != null) 'args': data,
    };
  }

  // ---------------------------------------------------------------------------
  // Markdown Adapter
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _adaptMarkdown(String markdown) {
    final budget = _NodeBudget();
    budget.consume();
    final cleaned = markdown
        .replaceAll(
            RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
            '')
        .trim();
    if (cleaned.isEmpty) {
      return const <String, Object?>{
        'type': 'column',
        'children': <Map<String, Object?>>[],
      };
    }

    final lines = const LineSplitter().convert(cleaned);
    final children = <Map<String, Object?>>[];
    var inCode = false;
    final codeBuf = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        if (!inCode) {
          inCode = true;
          codeBuf.clear();
        } else {
          inCode = false;
          budget.consume();
          children.add(<String, Object?>{
            'type': 'text',
            'text': codeBuf.join('\n'),
            'mono': true,
          });
        }
        continue;
      }
      if (inCode) {
        codeBuf.add(line);
        continue;
      }
      if (trimmed.isEmpty) continue;

      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        budget.consume();
        children.add(const <String, Object?>{'type': 'divider'});
        continue;
      }

      final headingMatch = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        budget.consume();
        children.add(<String, Object?>{
          'type': 'heading',
          'text': headingMatch.group(1)!.trim(),
        });
        continue;
      }

      if (trimmed.contains('|') &&
          i + 1 < lines.length &&
          RegExp(r'^\s*\|?[\s:-]+\|[\s|:-]*$').hasMatch(lines[i + 1])) {
        final headers = _splitMarkdownRow(trimmed);
        final rows = <List<String>>[];
        var j = i + 2;
        while (j < lines.length && lines[j].trim().contains('|')) {
          rows.add(_splitMarkdownRow(lines[j].trim()));
          j++;
        }
        i = j - 1;
        budget.consume();
        children.add(<String, Object?>{
          'type': 'table',
          'headers': headers,
          'rows': rows,
        });
        continue;
      }

      budget.consume();
      children.add(<String, Object?>{
        'type': 'text',
        'text': trimmed,
      });
    }

    if (inCode && codeBuf.isNotEmpty) {
      budget.consume();
      children.add(<String, Object?>{
        'type': 'text',
        'text': codeBuf.join('\n'),
        'mono': true,
      });
    }

    return <String, Object?>{'type': 'column', 'children': children};
  }

  static List<String> _splitMarkdownRow(String row) {
    var inner = row.trim();
    if (inner.startsWith('|')) inner = inner.substring(1);
    if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
    return inner.split('|').map((c) => c.trim()).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _stringifyMap(Map<dynamic, dynamic> raw) {
    return <String, Object?>{
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
  }

  static String? _validTone(Object? raw) {
    final s = raw?.toString();
    return s != null && _kCanonicalTones.contains(s) ? s : null;
  }

  static Object _normalizeTextOrSealed(Object? raw) {
    final sealed = VibeSealedHandle.tryParse(raw);
    if (sealed != null) return sealed.toJson();
    if (raw == null) return '';
    return raw.toString();
  }

  static Object? _normalizeCellOrSealed(Object? raw) {
    final sealed = VibeSealedHandle.tryParse(raw);
    if (sealed != null) return sealed.toJson();
    if (raw == null || raw is bool || raw is num) return raw;
    return raw.toString();
  }

  static String _normalizePlainString(Object? raw, int maxLen) {
    final s = (raw?.toString() ?? '').trim();
    return s.length <= maxLen ? s : s.substring(0, maxLen);
  }

  static String _claimUniqueId(
    String? raw,
    Set<String> seenIds,
    _NodeBudget budget,
  ) {
    var base = (raw ?? '').trim();
    if (!_kSafeIdRegex.hasMatch(base)) {
      base = 'field_${budget.count}';
    }
    var candidate = base;
    var suffix = 1;
    while (!seenIds.add(candidate)) {
      candidate = '${base}_${suffix++}';
      if (candidate.length > 64) {
        candidate = 'field_${budget.count}_$suffix';
      }
    }
    return candidate;
  }
}

class _NodeBudget {
  int count = 0;
  int canvasCommands = 0;

  void consume() {
    if (++count > kMaxAdaptedViewNodes) {
      throw const FormatException('Extension view limit exceeded (nodes)');
    }
  }

  void consumeCanvasCommands(int n) {
    canvasCommands += n;
    if (canvasCommands > kMaxVibeCanvasCommands) {
      throw FormatException(
        'Canvas exceeds $kMaxVibeCanvasCommands commands limit ($canvasCommands)',
      );
    }
  }
}

/// Toolkit-neutral resolved view IR for SwiftUI, Jetpack Compose, Qt, GTK,
/// WinUI, React Native, or custom canvases. Forged/unknown sealed handles
/// always resolve to `""` with `sealedResolved == false`.
class VibeResolvedNode {
  const VibeResolvedNode({
    required this.type,
    this.text,
    this.label,
    this.value,
    this.caption,
    this.tone = 'default',
    this.strong = false,
    this.mono = false,
    this.sealedResolved = false,
    this.textSealed = false,
    this.labelSealed = false,
    this.valueSealed = false,
    this.captionSealed = false,
    this.headerSealed = const <bool>[],
    this.cellSealed = const <List<bool>>[],
    this.numValue,
    this.maxValue,
    this.swatch,
    this.values = const <double>[],
    this.canvasWidth,
    this.canvasHeight,
    this.canvasCommands = const <Map<String, Object?>>[],
    this.headers = const <String>[],
    this.rows = const <List<String>>[],
    this.command,
    this.arguments,
    this.id,
    this.checked,
    this.options = const <Map<String, Object?>>[],
    this.children = const <VibeResolvedNode>[],
  });

  final String type;
  final String? text;
  final String? label;
  final String? value;
  final String? caption;
  final String tone;
  final bool strong;
  final bool mono;
  final bool sealedResolved;
  final bool textSealed;
  final bool labelSealed;
  final bool valueSealed;
  final bool captionSealed;
  final List<bool> headerSealed;
  final List<List<bool>> cellSealed;
  final double? numValue;
  final double? maxValue;
  final String? swatch;
  final List<double> values;
  final double? canvasWidth;
  final double? canvasHeight;
  final List<Map<String, Object?>> canvasCommands;
  final List<String> headers;
  final List<List<String>> rows;
  final String? command;
  final Map<String, Object?>? arguments;
  final String? id;
  final bool? checked;
  final List<Map<String, Object?>> options;
  final List<VibeResolvedNode> children;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        if (text != null) 'text': text,
        if (label != null) 'label': label,
        if (value != null) 'value': value,
        if (caption != null) 'caption': caption,
        'tone': tone,
        if (strong) 'strong': strong,
        if (mono) 'mono': mono,
        'sealedResolved': sealedResolved,
        if (numValue != null) 'numValue': numValue,
        if (maxValue != null) 'maxValue': maxValue,
        if (swatch != null) 'swatch': swatch,
        if (values.isNotEmpty) 'values': values,
        if (canvasWidth != null) 'width': canvasWidth,
        if (canvasHeight != null) 'height': canvasHeight,
        if (canvasCommands.isNotEmpty) 'commands': canvasCommands,
        if (headers.isNotEmpty) 'headers': headers,
        if (rows.isNotEmpty) 'rows': rows,
        if (command != null) 'command': command,
        if (arguments != null) 'arguments': arguments,
        if (id != null) 'id': id,
        if (checked != null) 'checked': checked,
        if (options.isNotEmpty) 'options': options,
        if (children.isNotEmpty)
          'children': <Map<String, Object?>>[
            for (final c in children) c.toJson(),
          ],
      };
}

/// Resolves a canonical or external UI [view] into a toolkit-neutral
/// [VibeResolvedNode] IR tree. Unknown/forged sealed handles resolve to `""`.
VibeResolvedNode resolveVibeViewTree(
  Object? view, {
  String? Function(Object? handle)? resolveSealed,
}) {
  final adapted = VibeUiCompatibilityAdapter.adapt(view);
  return _resolveNode(adapted, resolveSealed);
}

({String text, bool resolved}) _resolveSlot(
  Object? raw,
  String? Function(Object? handle)? resolveSealed,
) {
  final handle = VibeSealedHandle.tryParse(raw);
  if (handle != null) {
    final resolved = resolveSealed?.call(handle.toJson());
    if (resolved == null || resolved.isEmpty) {
      return (text: '', resolved: false);
    }
    return (text: resolved, resolved: true);
  }
  if (raw == null) return (text: '', resolved: false);
  return (text: raw.toString(), resolved: false);
}

VibeResolvedNode _resolveNode(
  Map<String, Object?> node,
  String? Function(Object? handle)? resolveSealed,
) {
  final type = node['type']?.toString() ?? 'text';
  final tone = node['tone']?.toString() ?? 'default';

  switch (type) {
    case 'column':
    case 'row':
    case 'card':
      final rawChildren =
          node['children'] is List ? node['children'] as List : const [];
      return VibeResolvedNode(
        type: type,
        tone: tone,
        children: <VibeResolvedNode>[
          for (final c in rawChildren)
            if (c is Map)
              _resolveNode(
                c.map((k, v) => MapEntry(k.toString(), v)),
                resolveSealed,
              ),
        ],
      );

    case 'heading':
    case 'badge':
    case 'text':
      final slot = _resolveSlot(node['text'], resolveSealed);
      return VibeResolvedNode(
        type: type,
        text: slot.text,
        tone: tone,
        strong: node['bold'] == true || node['strong'] == true,
        mono: node['code'] == true || node['mono'] == true,
        sealedResolved: slot.resolved,
        textSealed: slot.resolved,
      );

    case 'stat':
      final lbl = _resolveSlot(node['label'], resolveSealed);
      final val = _resolveSlot(node['value'], resolveSealed);
      return VibeResolvedNode(
        type: 'stat',
        label: lbl.text,
        value: val.text,
        tone: tone,
        sealedResolved: lbl.resolved || val.resolved,
        labelSealed: lbl.resolved,
        valueSealed: val.resolved,
      );

    case 'bar':
      final lbl = _resolveSlot(node['label'], resolveSealed);
      final cap = node.containsKey('caption')
          ? _resolveSlot(node['caption'], resolveSealed)
          : (text: null, resolved: false);
      return VibeResolvedNode(
        type: 'bar',
        label: lbl.text,
        caption: cap.text,
        numValue: (node['value'] as num?)?.toDouble() ?? 0.0,
        maxValue: (node['max'] as num?)?.toDouble() ?? 1.0,
        swatch: node['swatch']?.toString(),
        tone: tone,
        sealedResolved: lbl.resolved || cap.resolved,
        labelSealed: lbl.resolved,
        captionSealed: cap.resolved,
      );

    case 'progress':
      return VibeResolvedNode(
        type: 'progress',
        numValue: (node['value'] as num?)?.toDouble() ?? 0.0,
        maxValue: 1.0,
        tone: tone,
      );

    case 'sparkline':
      final vals = <double>[
        if (node['values'] is List)
          for (final v in node['values'] as List)
            if (v is num && v.isFinite) v.toDouble(),
      ];
      return VibeResolvedNode(
        type: 'sparkline',
        values: vals,
        tone: tone,
      );

    case 'canvas':
      final altSlot = _resolveSlot(node['alt'] ?? node['label'], resolveSealed);
      var anyCmdSealed = altSlot.resolved;
      final resolvedCmds = <Map<String, Object?>>[];
      if (node['commands'] is List) {
        for (final rawCmd in node['commands'] as List) {
          if (rawCmd is! Map) continue;
          final cm = rawCmd.map((k, v) => MapEntry(k.toString(), v));
          if (cm.containsKey('text')) {
            final ts = _resolveSlot(cm['text'], resolveSealed);
            cm['text'] = ts.text;
            if (ts.resolved) anyCmdSealed = true;
          }
          resolvedCmds.add(cm);
        }
      }
      return VibeResolvedNode(
        type: 'canvas',
        label: altSlot.text.isEmpty ? null : altSlot.text,
        labelSealed: altSlot.resolved,
        sealedResolved: anyCmdSealed,
        canvasWidth: (node['width'] as num?)?.toDouble() ?? 240.0,
        canvasHeight: (node['height'] as num?)?.toDouble() ?? 64.0,
        canvasCommands: resolvedCmds,
        command: node['command']?.toString(),
        tone: tone,
      );

    case 'table':
      final rawHeaders =
          node['headers'] is List ? node['headers'] as List : const [];
      final headers = <String>[];
      final hSealed = <bool>[];
      var anySealed = false;
      for (final h in rawHeaders) {
        final s = _resolveSlot(h, resolveSealed);
        headers.add(s.text);
        hSealed.add(s.resolved);
        if (s.resolved) anySealed = true;
      }
      final rawRows = node['rows'] is List ? node['rows'] as List : const [];
      final rows = <List<String>>[];
      final cSealed = <List<bool>>[];
      for (final r in rawRows) {
        if (r is List) {
          final rOut = <String>[];
          final rSealed = <bool>[];
          for (final cell in r) {
            final s = _resolveSlot(cell, resolveSealed);
            rOut.add(s.text);
            rSealed.add(s.resolved);
            if (s.resolved) anySealed = true;
          }
          rows.add(rOut);
          cSealed.add(rSealed);
        }
      }
      return VibeResolvedNode(
        type: 'table',
        headers: headers,
        rows: rows,
        headerSealed: hSealed,
        cellSealed: cSealed,
        sealedResolved: anySealed,
      );

    case 'divider':
      return const VibeResolvedNode(type: 'divider');

    case 'button':
    case 'action':
      final rawArgs = node['args'] ?? node['arguments'];
      return VibeResolvedNode(
        type: type,
        text: (node['text'] ?? node['title'] ?? '').toString(),
        command: node['command']?.toString(),
        arguments: rawArgs is Map
            ? rawArgs.map((k, v) => MapEntry(k.toString(), v))
            : null,
        tone: tone,
      );

    case 'input':
      return VibeResolvedNode(
        type: 'input',
        id: node['id']?.toString(),
        label: node['label']?.toString(),
      );

    case 'checkbox':
      return VibeResolvedNode(
        type: 'checkbox',
        id: node['id']?.toString(),
        label: node['label']?.toString(),
        checked: node['checked'] == true,
        command: node['command']?.toString(),
      );

    case 'option_group':
      final rawOpts =
          node['options'] is List ? node['options'] as List : const [];
      return VibeResolvedNode(
        type: 'option_group',
        id: node['id']?.toString(),
        label: node['label']?.toString(),
        command: node['command']?.toString(),
        options: <Map<String, Object?>>[
          for (final o in rawOpts)
            if (o is Map) o.map((k, v) => MapEntry(k.toString(), v)),
        ],
      );

    default:
      return VibeResolvedNode(type: type, tone: tone);
  }
}

/// Renders a canonical or external UI [view] into ANSI/Unicode terminal TUI text.
class VibeTerminalRenderer {
  const VibeTerminalRenderer._();

  static const List<String> _sparkChars = <String>[
    '▁',
    '▂',
    '▃',
    '▄',
    '▅',
    '▆',
    '▇',
    '█',
  ];

  static String render(
    Map<String, Object?> view, {
    String? Function(Object? handle)? resolveSealed,
    bool ansi = false,
    int width = 72,
  }) {
    final resolved = resolveVibeViewTree(view, resolveSealed: resolveSealed);
    final safeWidth = width.clamp(24, 160);
    final lines = <String>[];
    _renderNode(resolved, lines, ansi: ansi, width: safeWidth);
    return lines.join('\n');
  }

  static String _withLock(String text, bool sealedResolved) {
    if (!sealedResolved || text.isEmpty) return text;
    return '🔒 $text';
  }

  static String _colorize(String text, String tone, bool ansi) {
    if (!ansi || text.isEmpty) return text;
    return switch (tone) {
      'ok' => '\x1b[32m$text\x1b[0m',
      'warn' => '\x1b[33m$text\x1b[0m',
      'danger' => '\x1b[31m$text\x1b[0m',
      _ => text,
    };
  }

  static void _renderNode(
    VibeResolvedNode node,
    List<String> lines, {
    required bool ansi,
    required int width,
  }) {
    switch (node.type) {
      case 'column':
        for (final child in node.children) {
          _renderNode(child, lines, ansi: ansi, width: width);
        }
      case 'row':
        final rowParts = <String>[];
        for (final child in node.children) {
          final sub = <String>[];
          _renderNode(child, sub,
              ansi: ansi,
              width: max(20, width ~/ max(1, node.children.length)));
          if (sub.isNotEmpty) rowParts.add(sub.join(' '));
        }
        if (rowParts.isNotEmpty) {
          lines.add(rowParts.join('  |  '));
        }
      case 'card':
        final innerLines = <String>[];
        for (final child in node.children) {
          _renderNode(child, innerLines, ansi: ansi, width: max(20, width - 4));
        }
        final boxW = width;
        lines.add('┌${'─' * (boxW - 2)}┐');
        for (final l in innerLines) {
          lines.add('│ $l');
        }
        lines.add('└${'─' * (boxW - 2)}┘');
      case 'heading':
        final txt = _withLock(node.text ?? '', node.textSealed);
        lines.add(ansi ? '\x1b[1m$txt\x1b[0m' : txt);
      case 'text':
        final txt = _withLock(node.text ?? '', node.textSealed);
        lines.add(_colorize(txt, node.tone, ansi));
      case 'badge':
        final txt = _withLock(node.text ?? '', node.textSealed);
        lines.add(_colorize('[$txt]', node.tone, ansi));
      case 'stat':
        final lbl = _withLock(node.label ?? '', node.labelSealed);
        final val = _withLock(node.value ?? '', node.valueSealed);
        lines.add('$lbl: ${_colorize(val, node.tone, ansi)}');
      case 'bar':
      case 'progress':
        final lbl = _withLock(node.label ?? 'Progress', node.labelSealed);
        final cap = node.caption != null
            ? _withLock(node.caption!, node.captionSealed)
            : '';
        final maxV = (node.maxValue ?? 1.0) > 0 ? node.maxValue! : 1.0;
        final frac = ((node.numValue ?? 0.0) / maxV).clamp(0.0, 1.0);
        final barWidth = max(10, min(28, width ~/ 3));
        final filled = (frac * barWidth).round().clamp(0, barWidth);
        final bar = '${'█' * filled}${'░' * (barWidth - filled)}';
        final coloredBar = _colorize(bar, node.tone, ansi);
        final suffix = cap.isNotEmpty ? ' $cap' : ' ${(frac * 100).round()}%';
        lines.add('$lbl  $coloredBar$suffix');
      case 'sparkline':
        if (node.values.isEmpty) {
          lines.add('');
        } else {
          final minV = node.values.reduce(min);
          final maxV = node.values.reduce(max);
          final span = maxV - minV;
          final buf = StringBuffer();
          for (final v in node.values) {
            final idx = span == 0
                ? 3
                : (((v - minV) / span) * (_sparkChars.length - 1))
                    .round()
                    .clamp(0, _sparkChars.length - 1);
            buf.write(_sparkChars[idx]);
          }
          lines.add(_colorize(buf.toString(), node.tone, ansi));
        }
      case 'canvas':
        final header = node.label != null
            ? '${_withLock(node.label!, node.labelSealed)}: '
            : '';
        final barVals = <double>[];
        final textItems = <String>[];
        for (final cmd in node.canvasCommands) {
          if (cmd['op'] == 'bars' && cmd['values'] is List) {
            for (final v in cmd['values'] as List) {
              if (v is num && v.isFinite) barVals.add(v.toDouble());
            }
          } else if (cmd['op'] == 'text' && cmd['text'] is String) {
            final t = (cmd['text'] as String).trim();
            if (t.isNotEmpty) textItems.add(t);
          }
        }
        if (barVals.isNotEmpty) {
          final minV = barVals.reduce(min);
          final maxV = barVals.reduce(max);
          final span = maxV - minV;
          final spark = barVals
              .map(
                (v) => _sparkChars[span == 0
                    ? 3
                    : (((v - minV) / span) * (_sparkChars.length - 1))
                        .round()
                        .clamp(0, _sparkChars.length - 1)],
              )
              .join();
          final suffix = textItems.isNotEmpty ? ' ${textItems.join(' ')}' : '';
          lines.add('$header${_colorize(spark, node.tone, ansi)}$suffix');
        } else {
          final summary = textItems.isNotEmpty
              ? textItems.join(' · ')
              : '[canvas ${(node.canvasWidth ?? 240).round()}x${(node.canvasHeight ?? 64).round()}]';
          lines.add('$header${_colorize(summary, node.tone, ansi)}');
        }
      case 'table':
        final colCount = node.headers.length;
        if (colCount == 0) break;
        final widths = List<int>.filled(colCount, 3);
        final formattedHeaders = <String>[
          for (var c = 0; c < colCount; c++)
            _withLock(node.headers[c],
                c < node.headerSealed.length && node.headerSealed[c]),
        ];
        for (var c = 0; c < colCount; c++) {
          widths[c] = max(widths[c], formattedHeaders[c].length);
        }
        final formattedRows = <List<String>>[];
        for (var r = 0; r < node.rows.length; r++) {
          final row = node.rows[r];
          final rowSealed =
              r < node.cellSealed.length ? node.cellSealed[r] : const <bool>[];
          final cells = <String>[];
          for (var c = 0; c < colCount; c++) {
            final raw = c < row.length ? row[c] : '';
            final isS = c < rowSealed.length && rowSealed[c];
            final cell = _withLock(raw, isS);
            cells.add(cell);
            widths[c] = max(widths[c], cell.length);
          }
          formattedRows.add(cells);
        }
        String formatRow(List<String> cells) => cells
            .asMap()
            .entries
            .map((e) => e.value.padRight(widths[e.key]))
            .join(' | ');
        lines.add(formatRow(formattedHeaders));
        lines.add(widths.map((w) => '─' * w).join('─┼─'));
        for (final r in formattedRows) {
          lines.add(formatRow(r));
        }
      case 'divider':
        lines.add('─' * min(40, width));
      case 'button':
      case 'action':
        lines.add(_colorize('[${node.text ?? 'Action'}]', node.tone, ansi));
      case 'input':
        lines.add('${node.label ?? 'Input'}: [________]');
      case 'checkbox':
        lines
            .add('${node.checked == true ? '[x]' : '[ ]'} ${node.label ?? ''}');
      case 'option_group':
        if (node.label != null && node.label!.isNotEmpty) {
          lines.add('${node.label}:');
        }
        for (final opt in node.options) {
          final sel = opt['selected'] == true || opt['checked'] == true;
          lines.add('  ${sel ? '(*)' : '( )'} ${opt['label'] ?? opt['id']}');
        }
    }
  }
}

/// Renders a canonical or external UI [view] into clean Markdown.
class VibeMarkdownRenderer {
  const VibeMarkdownRenderer._();

  static String render(
    Map<String, Object?> view, {
    String? Function(Object? handle)? resolveSealed,
  }) {
    final resolved = resolveVibeViewTree(view, resolveSealed: resolveSealed);
    final lines = <String>[];
    _renderNode(resolved, lines);
    return lines.join('\n');
  }

  static String _withLock(String text, bool sealedResolved) {
    if (!sealedResolved || text.isEmpty) return text;
    return '🔒 $text';
  }

  static void _renderNode(VibeResolvedNode node, List<String> lines) {
    switch (node.type) {
      case 'column':
      case 'card':
        for (final c in node.children) {
          _renderNode(c, lines);
        }
      case 'row':
        final parts = <String>[];
        for (final c in node.children) {
          final sub = <String>[];
          _renderNode(c, sub);
          if (sub.isNotEmpty) parts.add(sub.join(' '));
        }
        if (parts.isNotEmpty) lines.add(parts.join(' · '));
      case 'heading':
        lines.add('## ${_withLock(node.text ?? '', node.textSealed)}');
      case 'text':
        final t = _withLock(node.text ?? '', node.textSealed);
        lines.add(node.mono ? '`$t`' : (node.strong ? '**$t**' : t));
      case 'badge':
        lines.add('`${_withLock(node.text ?? '', node.textSealed)}`');
      case 'stat':
        final lbl = _withLock(node.label ?? '', node.labelSealed);
        final val = _withLock(node.value ?? '', node.valueSealed);
        lines.add('**$lbl:** $val');
      case 'bar':
      case 'progress':
        final maxV = (node.maxValue ?? 1.0) > 0 ? node.maxValue! : 1.0;
        final pct =
            (((node.numValue ?? 0.0) / maxV).clamp(0.0, 1.0) * 100).round();
        final capText = _withLock(node.caption ?? '', node.captionSealed);
        final cap = capText.isNotEmpty ? ' ($capText)' : '';
        final barLabel = _withLock(node.label ?? 'Progress', node.labelSealed);
        lines.add('- **$barLabel:** $pct%$cap');
      case 'sparkline':
        final pts = node.values.map((v) => v.toStringAsFixed(2)).join(', ');
        lines.add('`[$pts]`');
      case 'canvas':
        final lbl = node.label != null
            ? _withLock(node.label!, node.labelSealed)
            : 'Canvas';
        lines.add(
          '- **$lbl:** `[canvas ${(node.canvasWidth ?? 240).round()}x${(node.canvasHeight ?? 64).round()}, ${node.canvasCommands.length} cmds]`',
        );
      case 'table':
        if (node.headers.isEmpty) break;
        final hdrs = <String>[
          for (var i = 0; i < node.headers.length; i++)
            _withLock(
              node.headers[i],
              i < node.headerSealed.length && node.headerSealed[i],
            ),
        ];
        lines.add('| ${hdrs.join(' | ')} |');
        lines.add('| ${hdrs.map((_) => '---').join(' | ')} |');
        for (var rIdx = 0; rIdx < node.rows.length; rIdx++) {
          final r = node.rows[rIdx];
          final cs = rIdx < node.cellSealed.length
              ? node.cellSealed[rIdx]
              : const <bool>[];
          final cells = <String>[
            for (var i = 0; i < hdrs.length; i++)
              i < r.length ? _withLock(r[i], i < cs.length && cs[i]) : '',
          ];
          lines.add('| ${cells.join(' | ')} |');
        }
      case 'divider':
        lines.add('---');
      case 'button':
      case 'action':
        lines.add('[${node.text ?? 'Action'}]');
      case 'input':
        lines.add('- **${node.label ?? 'Input'}:** `...`');
      case 'checkbox':
        lines
            .add('- [${node.checked == true ? 'x' : ' '}] ${node.label ?? ''}');
      case 'option_group':
        if (node.label != null && node.label!.isNotEmpty) {
          lines.add('**${node.label}**');
        }
        for (final opt in node.options) {
          final sel = opt['selected'] == true || opt['checked'] == true;
          lines.add('- [${sel ? 'x' : ' '}] ${opt['label'] ?? opt['id']}');
        }
    }
  }
}

/// Pluggable UI string table supporting `en`, `zh`, `ja`, `ko`, `es`, `fr`,
/// `de`, and `ar` (RTL).
class VibeStrings {
  const VibeStrings({
    required this.locale,
    this.isRtl = false,
    required this.panelTitle,
    required this.whatHostOffers,
    required this.wishPlaceholder,
    required this.sendLabel,
    required this.previewTitle,
    required this.showCode,
    required this.hideCode,
    required this.readsLabel,
    required this.showsLabel,
    required this.cannotLabel,
    required this.allowAndAdd,
    required this.updateLabel,
    required this.cancelLabel,
    required this.installedHeading,
    required this.filterPlaceholder,
    required this.emptyInstalled,
    required this.sealedLegend,
    required this.temporaryBadge,
    required this.pinnedBadge,
    required this.pausedBadge,
    required this.sampleDataBadge,
    required this.sourceOfflineBadge,
    required this.sourceUnavailableBadge,
    required this.pinToVibeSpace,
    required this.pinnedToVibeSpace,
    required this.madeByAgent,
    required this.inspectLabel,
    required this.hideInspectLabel,
    required this.shareLabel,
    required this.editLabel,
    required this.renameLabel,
    required this.pauseLabel,
    required this.resumeLabel,
    required this.pinToTopLabel,
    required this.unpinLabel,
    required this.moveUpLabel,
    required this.moveDownLabel,
    required this.revertLabel,
    required this.deleteLabel,
    required this.undoLabel,
    required this.retryLabel,
    required this.previewSampleLabel,
    required this.returnToLiveLabel,
    required this.portableGalleryTitle,
    required this.portableGallerySubtitle,
    required this.addLabel,
  });

  const VibeStrings.en()
      : locale = 'en',
        isRtl = false,
        panelTitle = 'Vibe Space',
        whatHostOffers = 'What {host} offers',
        wishPlaceholder = 'I wish {host} would…',
        sendLabel = 'Send',
        previewTitle = 'Preview on sample data',
        showCode = 'Show code',
        hideCode = 'Hide code',
        readsLabel = 'Reads',
        showsLabel = 'Shows',
        cannotLabel = 'Cannot',
        allowAndAdd = 'Allow and add',
        updateLabel = 'Update',
        cancelLabel = 'Cancel',
        installedHeading = 'Installed',
        filterPlaceholder = 'Filter installed vibes…',
        emptyInstalled = 'Nothing here yet. Make a wish.',
        sealedLegend =
            'Values with a lock are sealed. {host} draws them. The vibe never sees them.',
        temporaryBadge = 'Temporary',
        pinnedBadge = 'Pinned',
        pausedBadge = 'Paused',
        sampleDataBadge = 'Sample data',
        sourceOfflineBadge = 'Source offline',
        sourceUnavailableBadge = 'Source unavailable',
        pinToVibeSpace = 'Pin to Vibe Space',
        pinnedToVibeSpace = 'Pinned to Vibe Space',
        madeByAgent = 'Made by the agent for this answer',
        inspectLabel = 'Inspect',
        hideInspectLabel = 'Hide inspect',
        shareLabel = 'Share…',
        editLabel = 'Edit…',
        renameLabel = 'Rename',
        pauseLabel = 'Pause',
        resumeLabel = 'Resume',
        pinToTopLabel = 'Pin to top',
        unpinLabel = 'Unpin',
        moveUpLabel = 'Move up',
        moveDownLabel = 'Move down',
        revertLabel = 'Revert to v{version}',
        deleteLabel = 'Delete',
        undoLabel = 'Undo',
        retryLabel = 'Retry',
        previewSampleLabel = 'Preview sample',
        returnToLiveLabel = 'Return to live',
        portableGalleryTitle = 'Portable vibes',
        portableGallerySubtitle =
            'These need nothing from the app, so they run anywhere.',
        addLabel = 'Add';

  factory VibeStrings.forLocale(
    String locale, {
    Map<String, String>? overrides,
  }) {
    final normalized = locale.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    final base = switch (normalized) {
      'zh' => const VibeStrings(
          locale: 'zh',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: '{host} 提供的能力',
          wishPlaceholder: '我希望 {host} 能够…',
          sendLabel: '发送',
          previewTitle: '使用示例数据预览',
          showCode: '查看代码',
          hideCode: '隐藏代码',
          readsLabel: '读取',
          showsLabel: '显示',
          cannotLabel: '无法执行',
          allowAndAdd: '允许并添加',
          updateLabel: '更新',
          cancelLabel: '取消',
          installedHeading: '已安装',
          filterPlaceholder: '筛选已安装的 Vibe…',
          emptyInstalled: '这里还没有内容，先提一个愿望吧。',
          sealedLegend: '带锁的值已密封，由 {host} 渲染，Vibe 本身无法看到真实值。',
          temporaryBadge: '临时',
          pinnedBadge: '已置顶',
          pausedBadge: '已暂停',
          sampleDataBadge: '示例数据',
          sourceOfflineBadge: '数据源离线',
          sourceUnavailableBadge: '数据源不可用',
          pinToVibeSpace: '固定到 Vibe Space',
          pinnedToVibeSpace: '已固定到 Vibe Space',
          madeByAgent: '由智能体为此回答生成',
          inspectLabel: '检查',
          hideInspectLabel: '收起检查',
          shareLabel: '分享…',
          editLabel: '编辑…',
          renameLabel: '重命名',
          pauseLabel: '暂停',
          resumeLabel: '恢复',
          pinToTopLabel: '置顶',
          unpinLabel: '取消置顶',
          moveUpLabel: '上移',
          moveDownLabel: '下移',
          revertLabel: '恢复到 v{version}',
          deleteLabel: '删除',
          undoLabel: '撤销',
          retryLabel: '重试',
          previewSampleLabel: '预览示例',
          returnToLiveLabel: '切回实时数据',
          portableGalleryTitle: '可移植 Vibe',
          portableGallerySubtitle: '无需应用权限，可在任何宿主中运行。',
          addLabel: '添加',
        ),
      'ja' => const VibeStrings(
          locale: 'ja',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: '{host} が提供するもの',
          wishPlaceholder: '{host} に追加したい機能…',
          sendLabel: '送信',
          previewTitle: 'サンプルデータでプレビュー',
          showCode: 'コードを表示',
          hideCode: 'コードを隠す',
          readsLabel: '読み取り',
          showsLabel: '表示先',
          cannotLabel: '許可されない操作',
          allowAndAdd: '許可して追加',
          updateLabel: '更新',
          cancelLabel: 'キャンセル',
          installedHeading: 'インストール済み',
          filterPlaceholder: 'インストール済み Vibe を絞り込む…',
          emptyInstalled: 'まだありません。願いを入力してください。',
          sealedLegend: '鍵付きの値は保護されています。{host} が描画し、Vibe には見えません。',
          temporaryBadge: '一時的',
          pinnedBadge: '固定済み',
          pausedBadge: '一時停止',
          sampleDataBadge: 'サンプル',
          sourceOfflineBadge: 'ソースオフライン',
          sourceUnavailableBadge: 'ソース利用不可',
          pinToVibeSpace: 'Vibe Space に固定',
          pinnedToVibeSpace: 'Vibe Space に固定済み',
          madeByAgent: 'この回答のためにエージェントが作成',
          inspectLabel: '検査',
          hideInspectLabel: '検査を隠す',
          shareLabel: '共有…',
          editLabel: '編集…',
          renameLabel: '名前変更',
          pauseLabel: '一時停止',
          resumeLabel: '再開',
          pinToTopLabel: '先頭に固定',
          unpinLabel: '固定解除',
          moveUpLabel: '上へ移動',
          moveDownLabel: '下へ移動',
          revertLabel: 'v{version} に戻す',
          deleteLabel: '削除',
          undoLabel: '元に戻す',
          retryLabel: '再試行',
          previewSampleLabel: 'サンプル表示',
          returnToLiveLabel: 'ライブに戻る',
          portableGalleryTitle: 'ポータブル Vibe',
          portableGallerySubtitle: 'アプリデータ不要でどこでも動作します。',
          addLabel: '追加',
        ),
      'ko' => const VibeStrings(
          locale: 'ko',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: '{host} 제공 항목',
          wishPlaceholder: '{host}에 바라는 기능…',
          sendLabel: '보내기',
          previewTitle: '샘플 데이터 미리보기',
          showCode: '코드 보기',
          hideCode: '코드 숨기기',
          readsLabel: '읽기',
          showsLabel: '표시',
          cannotLabel: '불가 항목',
          allowAndAdd: '허용 후 추가',
          updateLabel: '업데이트',
          cancelLabel: '취소',
          installedHeading: '설치됨',
          filterPlaceholder: '설치된 Vibe 필터…',
          emptyInstalled: '아직 항목이 없습니다. 원하는 기능을 입력해 보세요.',
          sealedLegend: '자물쇠 값은 봉인되어 {host}가 직접 그리며 Vibe는 볼 수 없습니다.',
          temporaryBadge: '임시',
          pinnedBadge: '고정됨',
          pausedBadge: '일시중지',
          sampleDataBadge: '샘플 데이터',
          sourceOfflineBadge: '소스 오프라인',
          sourceUnavailableBadge: '소스 사용 불가',
          pinToVibeSpace: 'Vibe Space에 고정',
          pinnedToVibeSpace: 'Vibe Space에 고정됨',
          madeByAgent: '이 답변을 위해 에이전트가 생성함',
          inspectLabel: '검사',
          hideInspectLabel: '검사 숨기기',
          shareLabel: '공유…',
          editLabel: '편집…',
          renameLabel: '이름 변경',
          pauseLabel: '일시중지',
          resumeLabel: '재개',
          pinToTopLabel: '상단 고정',
          unpinLabel: '고정 해제',
          moveUpLabel: '위로 이동',
          moveDownLabel: '아래로 이동',
          revertLabel: 'v{version}(으)로 복원',
          deleteLabel: '삭제',
          undoLabel: '실행 취소',
          retryLabel: '다시 시도',
          previewSampleLabel: '샘플 미리보기',
          returnToLiveLabel: '실시간으로 돌아가기',
          portableGalleryTitle: '이식 가능 Vibe',
          portableGallerySubtitle: '앱 권한 없이 어디서나 실행됩니다.',
          addLabel: '추가',
        ),
      'es' => const VibeStrings(
          locale: 'es',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: 'Qué ofrece {host}',
          wishPlaceholder: 'Quisiera que {host}…',
          sendLabel: 'Enviar',
          previewTitle: 'Vista previa con datos de muestra',
          showCode: 'Ver código',
          hideCode: 'Ocultar código',
          readsLabel: 'Lee',
          showsLabel: 'Muestra',
          cannotLabel: 'No puede',
          allowAndAdd: 'Permitir y añadir',
          updateLabel: 'Actualizar',
          cancelLabel: 'Cancelar',
          installedHeading: 'Instalados',
          filterPlaceholder: 'Filtrar vibes instalados…',
          emptyInstalled: 'Nada por aquí aún. Pide un deseo.',
          sealedLegend:
              'Los valores con candado están sellados. {host} los dibuja; el vibe nunca los ve.',
          temporaryBadge: 'Temporal',
          pinnedBadge: 'Fijado',
          pausedBadge: 'En pausa',
          sampleDataBadge: 'Datos de muestra',
          sourceOfflineBadge: 'Fuente desconectada',
          sourceUnavailableBadge: 'Fuente no disponible',
          pinToVibeSpace: 'Fijar en Vibe Space',
          pinnedToVibeSpace: 'Fijado en Vibe Space',
          madeByAgent: 'Creado por el agente para esta respuesta',
          inspectLabel: 'Inspeccionar',
          hideInspectLabel: 'Ocultar inspección',
          shareLabel: 'Compartir…',
          editLabel: 'Editar…',
          renameLabel: 'Renombrar',
          pauseLabel: 'Pausar',
          resumeLabel: 'Reanudar',
          pinToTopLabel: 'Fijar arriba',
          unpinLabel: 'Desfijar',
          moveUpLabel: 'Subir',
          moveDownLabel: 'Bajar',
          revertLabel: 'Revertir a v{version}',
          deleteLabel: 'Eliminar',
          undoLabel: 'Deshacer',
          retryLabel: 'Reintentar',
          previewSampleLabel: 'Ver muestra',
          returnToLiveLabel: 'Volver a vivo',
          portableGalleryTitle: 'Vibes portátiles',
          portableGallerySubtitle:
              'No necesitan nada de la app, funcionan en todas partes.',
          addLabel: 'Añadir',
        ),
      'fr' => const VibeStrings(
          locale: 'fr',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: 'Ce que {host} propose',
          wishPlaceholder: 'J’aimerais que {host}…',
          sendLabel: 'Envoyer',
          previewTitle: 'Aperçu sur données fictives',
          showCode: 'Afficher le code',
          hideCode: 'Masquer le code',
          readsLabel: 'Lit',
          showsLabel: 'Affiche',
          cannotLabel: 'Ne peut pas',
          allowAndAdd: 'Autoriser et ajouter',
          updateLabel: 'Mettre à jour',
          cancelLabel: 'Annuler',
          installedHeading: 'Installés',
          filterPlaceholder: 'Filtrer les vibes installés…',
          emptyInstalled: 'Rien ici pour le moment. Faites un vœu.',
          sealedLegend:
              'Les valeurs avec cadenas sont scellées. {host} les affiche ; le vibe ne les voit jamais.',
          temporaryBadge: 'Temporaire',
          pinnedBadge: 'Épinglé',
          pausedBadge: 'En pause',
          sampleDataBadge: 'Données fictives',
          sourceOfflineBadge: 'Source hors ligne',
          sourceUnavailableBadge: 'Source indisponible',
          pinToVibeSpace: 'Épingler dans Vibe Space',
          pinnedToVibeSpace: 'Épinglé dans Vibe Space',
          madeByAgent: 'Créé par l’agent pour cette réponse',
          inspectLabel: 'Inspecter',
          hideInspectLabel: 'Masquer l’inspection',
          shareLabel: 'Partager…',
          editLabel: 'Modifier…',
          renameLabel: 'Renommer',
          pauseLabel: 'Pause',
          resumeLabel: 'Reprendre',
          pinToTopLabel: 'Épingler en haut',
          unpinLabel: 'Désépingler',
          moveUpLabel: 'Monter',
          moveDownLabel: 'Descendre',
          revertLabel: 'Revenir à v{version}',
          deleteLabel: 'Supprimer',
          undoLabel: 'Annuler',
          retryLabel: 'Réessayer',
          previewSampleLabel: 'Aperçu fictif',
          returnToLiveLabel: 'Revenir au direct',
          portableGalleryTitle: 'Vibes portables',
          portableGallerySubtitle: 'Aucune donnée requise, fonctionne partout.',
          addLabel: 'Ajouter',
        ),
      'de' => const VibeStrings(
          locale: 'de',
          isRtl: false,
          panelTitle: 'Vibe Space',
          whatHostOffers: 'Was {host} bietet',
          wishPlaceholder: 'Ich wünsche mir, dass {host}…',
          sendLabel: 'Senden',
          previewTitle: 'Vorschau mit Beispieldaten',
          showCode: 'Code anzeigen',
          hideCode: 'Code verbergen',
          readsLabel: 'Liest',
          showsLabel: 'Zeigt',
          cannotLabel: 'Kann nicht',
          allowAndAdd: 'Erlauben & hinzufügen',
          updateLabel: 'Aktualisieren',
          cancelLabel: 'Abbrechen',
          installedHeading: 'Installiert',
          filterPlaceholder: 'Installierte Vibes filtern…',
          emptyInstalled: 'Noch nichts hier. Äußere einen Wunsch.',
          sealedLegend:
              'Werte mit Schloss sind versiegelt. {host} zeichnet sie; der Vibe sieht sie nie.',
          temporaryBadge: 'Temporär',
          pinnedBadge: 'Angeheftet',
          pausedBadge: 'Pausiert',
          sampleDataBadge: 'Beispieldaten',
          sourceOfflineBadge: 'Quelle offline',
          sourceUnavailableBadge: 'Quelle nicht verfügbar',
          pinToVibeSpace: 'An Vibe Space anheften',
          pinnedToVibeSpace: 'An Vibe Space angeheftet',
          madeByAgent: 'Vom Agenten für diese Antwort erstellt',
          inspectLabel: 'Prüfen',
          hideInspectLabel: 'Prüfung ausblenden',
          shareLabel: 'Teilen…',
          editLabel: 'Bearbeiten…',
          renameLabel: 'Umbenennen',
          pauseLabel: 'Pausieren',
          resumeLabel: 'Fortsetzen',
          pinToTopLabel: 'Oben anheften',
          unpinLabel: 'Lösen',
          moveUpLabel: 'Nach oben',
          moveDownLabel: 'Nach unten',
          revertLabel: 'Zurück zu v{version}',
          deleteLabel: 'Löschen',
          undoLabel: 'Rückgängig',
          retryLabel: 'Erneut versuchen',
          previewSampleLabel: 'Beispiel-Vorschau',
          returnToLiveLabel: 'Zurück zu Live',
          portableGalleryTitle: 'Portierbare Vibes',
          portableGallerySubtitle:
              'Benötigen keine App-Daten und laufen überall.',
          addLabel: 'Hinzufügen',
        ),
      'ar' => const VibeStrings(
          locale: 'ar',
          isRtl: true,
          panelTitle: 'Vibe Space',
          whatHostOffers: 'ما يقدمه {host}',
          wishPlaceholder: 'أتمنى لو أن {host}…',
          sendLabel: 'إرسال',
          previewTitle: 'معاينة على بيانات تجريبية',
          showCode: 'عرض الشيفرة',
          hideCode: 'إخفاء الشيفرة',
          readsLabel: 'يقرأ',
          showsLabel: 'يعرض',
          cannotLabel: 'لا يمكنه',
          allowAndAdd: 'السماح والإضافة',
          updateLabel: 'تحديث',
          cancelLabel: 'إلغاء',
          installedHeading: 'المثبتة',
          filterPlaceholder: 'تصفية العناصر المثبتة…',
          emptyInstalled: 'لا يوجد شيء هنا بعد. اطلب ميزة.',
          sealedLegend:
              'القيم ذات القفل مختومة. يعرضها {host} ولا يراها البرنامج أبداً.',
          temporaryBadge: 'مؤقت',
          pinnedBadge: 'مثبت',
          pausedBadge: 'متوقف',
          sampleDataBadge: 'بيانات تجريبية',
          sourceOfflineBadge: 'المصدر غير متصل',
          sourceUnavailableBadge: 'المصدر غير متاح',
          pinToVibeSpace: 'تثبيت في Vibe Space',
          pinnedToVibeSpace: 'مثبت في Vibe Space',
          madeByAgent: 'أنشأه الوكيل لهذه الإجابة',
          inspectLabel: 'فحص',
          hideInspectLabel: 'إخفاء الفحص',
          shareLabel: 'مشاركة…',
          editLabel: 'تعديل…',
          renameLabel: 'إعادة تسمية',
          pauseLabel: 'إيقاف مؤقت',
          resumeLabel: 'استئناف',
          pinToTopLabel: 'تثبيت في الأعلى',
          unpinLabel: 'إلغاء التثبيت',
          moveUpLabel: 'تحريك للأعلى',
          moveDownLabel: 'تحريك للأسفل',
          revertLabel: 'الرجوع إلى v{version}',
          deleteLabel: 'حذف',
          undoLabel: 'تراجع',
          retryLabel: 'إعادة المحاولة',
          previewSampleLabel: 'معاينة عينة',
          returnToLiveLabel: 'العودة للبيانات الحية',
          portableGalleryTitle: 'برامج محمولة',
          portableGallerySubtitle:
              'لا تحتاج لصلاحيات التطبيق وتعمل في أي مكان.',
          addLabel: 'إضافة',
        ),
      _ => const VibeStrings.en(),
    };

    if (overrides == null || overrides.isEmpty) return base;
    return VibeStrings(
      locale: overrides['locale'] ?? base.locale,
      isRtl: base.isRtl,
      panelTitle: overrides['panelTitle'] ?? base.panelTitle,
      whatHostOffers: overrides['whatHostOffers'] ?? base.whatHostOffers,
      wishPlaceholder: overrides['wishPlaceholder'] ?? base.wishPlaceholder,
      sendLabel: overrides['sendLabel'] ?? base.sendLabel,
      previewTitle: overrides['previewTitle'] ?? base.previewTitle,
      showCode: overrides['showCode'] ?? base.showCode,
      hideCode: overrides['hideCode'] ?? base.hideCode,
      readsLabel: overrides['readsLabel'] ?? base.readsLabel,
      showsLabel: overrides['showsLabel'] ?? base.showsLabel,
      cannotLabel: overrides['cannotLabel'] ?? base.cannotLabel,
      allowAndAdd: overrides['allowAndAdd'] ?? base.allowAndAdd,
      updateLabel: overrides['updateLabel'] ?? base.updateLabel,
      cancelLabel: overrides['cancelLabel'] ?? base.cancelLabel,
      installedHeading: overrides['installedHeading'] ?? base.installedHeading,
      filterPlaceholder:
          overrides['filterPlaceholder'] ?? base.filterPlaceholder,
      emptyInstalled: overrides['emptyInstalled'] ?? base.emptyInstalled,
      sealedLegend: overrides['sealedLegend'] ?? base.sealedLegend,
      temporaryBadge: overrides['temporaryBadge'] ?? base.temporaryBadge,
      pinnedBadge: overrides['pinnedBadge'] ?? base.pinnedBadge,
      pausedBadge: overrides['pausedBadge'] ?? base.pausedBadge,
      sampleDataBadge: overrides['sampleDataBadge'] ?? base.sampleDataBadge,
      sourceOfflineBadge:
          overrides['sourceOfflineBadge'] ?? base.sourceOfflineBadge,
      sourceUnavailableBadge:
          overrides['sourceUnavailableBadge'] ?? base.sourceUnavailableBadge,
      pinToVibeSpace: overrides['pinToVibeSpace'] ?? base.pinToVibeSpace,
      pinnedToVibeSpace:
          overrides['pinnedToVibeSpace'] ?? base.pinnedToVibeSpace,
      madeByAgent: overrides['madeByAgent'] ?? base.madeByAgent,
      inspectLabel: overrides['inspectLabel'] ?? base.inspectLabel,
      hideInspectLabel: overrides['hideInspectLabel'] ?? base.hideInspectLabel,
      shareLabel: overrides['shareLabel'] ?? base.shareLabel,
      editLabel: overrides['editLabel'] ?? base.editLabel,
      renameLabel: overrides['renameLabel'] ?? base.renameLabel,
      pauseLabel: overrides['pauseLabel'] ?? base.pauseLabel,
      resumeLabel: overrides['resumeLabel'] ?? base.resumeLabel,
      pinToTopLabel: overrides['pinToTopLabel'] ?? base.pinToTopLabel,
      unpinLabel: overrides['unpinLabel'] ?? base.unpinLabel,
      moveUpLabel: overrides['moveUpLabel'] ?? base.moveUpLabel,
      moveDownLabel: overrides['moveDownLabel'] ?? base.moveDownLabel,
      revertLabel: overrides['revertLabel'] ?? base.revertLabel,
      deleteLabel: overrides['deleteLabel'] ?? base.deleteLabel,
      undoLabel: overrides['undoLabel'] ?? base.undoLabel,
      retryLabel: overrides['retryLabel'] ?? base.retryLabel,
      previewSampleLabel:
          overrides['previewSampleLabel'] ?? base.previewSampleLabel,
      returnToLiveLabel:
          overrides['returnToLiveLabel'] ?? base.returnToLiveLabel,
      portableGalleryTitle:
          overrides['portableGalleryTitle'] ?? base.portableGalleryTitle,
      portableGallerySubtitle:
          overrides['portableGallerySubtitle'] ?? base.portableGallerySubtitle,
      addLabel: overrides['addLabel'] ?? base.addLabel,
    );
  }

  final String locale;
  final bool isRtl;
  final String panelTitle;
  final String whatHostOffers;
  final String wishPlaceholder;
  final String sendLabel;
  final String previewTitle;
  final String showCode;
  final String hideCode;
  final String readsLabel;
  final String showsLabel;
  final String cannotLabel;
  final String allowAndAdd;
  final String updateLabel;
  final String cancelLabel;
  final String installedHeading;
  final String filterPlaceholder;
  final String emptyInstalled;
  final String sealedLegend;
  final String temporaryBadge;
  final String pinnedBadge;
  final String pausedBadge;
  final String sampleDataBadge;
  final String sourceOfflineBadge;
  final String sourceUnavailableBadge;
  final String pinToVibeSpace;
  final String pinnedToVibeSpace;
  final String madeByAgent;
  final String inspectLabel;
  final String hideInspectLabel;
  final String shareLabel;
  final String editLabel;
  final String renameLabel;
  final String pauseLabel;
  final String resumeLabel;
  final String pinToTopLabel;
  final String unpinLabel;
  final String moveUpLabel;
  final String moveDownLabel;
  final String revertLabel;
  final String deleteLabel;
  final String undoLabel;
  final String retryLabel;
  final String previewSampleLabel;
  final String returnToLiveLabel;
  final String portableGalleryTitle;
  final String portableGallerySubtitle;
  final String addLabel;

  String format(String template, Map<String, String> vars) {
    var out = template;
    for (final entry in vars.entries) {
      out = out.replaceAll('{${entry.key}}', entry.value);
    }
    return out;
  }
}
