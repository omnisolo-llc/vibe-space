import 'dart:convert';
import 'dart:typed_data';

import 'vibe_mini_program_parser.dart';
import 'vibe_protocol.dart';
import 'vibe_runtime_config.dart';
import 'vibe_trigger_condition.dart';
import 'vibe_vxml_template.dart';

export 'vibe_mini_program_parser.dart' show validateMiniProgramSource;

const Set<String> _kBlockedPatchSegments = <String>{
  '__proto__',
  'constructor',
  'prototype',
};

/// Applies a WeChat Mini Program `setData(patch)` incremental state diff using
/// dotted and bracket paths (e.g. `'quota.used': 0.8`, `'bars[0].v': 42`).
///
/// Enforces serialized patch size `<= maxBytes` (`64 KiB` default) and preserves
/// sealed `{ 'sealed': 'h_...' }` handles intact.
Map<String, Object?> applyVibeSetData(
  Map<String, Object?> state,
  Map<String, Object?> patch, {
  int maxBytes = kMaxVibeSetDataBytes,
}) {
  final encodedBytes = utf8.encode(jsonEncode(patch)).length;
  if (encodedBytes > maxBytes) {
    throw FormatException(
      'setData patch exceeds ${maxBytes ~/ 1024} KiB limit ($encodedBytes bytes)',
    );
  }
  var next = deepCloneVibeMap(state);
  for (final entry in patch.entries) {
    final segments = _parsePatchPath(entry.key);
    if (segments.isEmpty) continue;
    next = _assignAtPath(
      next,
      segments,
      0,
      deepCloneVibeValue(entry.value),
    ) as Map<String, Object?>;
  }
  return next;
}

List<Object> _parsePatchPath(String rawPath) {
  final path = rawPath.trim();
  if (path.isEmpty) return const <Object>[];
  final out = <Object>[];
  final buf = StringBuffer();
  void flushKey() {
    if (buf.isEmpty) return;
    final key = buf.toString();
    if (_kBlockedPatchSegments.contains(key)) {
      throw FormatException('Forbidden setData path segment: "$key"');
    }
    out.add(key);
    buf.clear();
  }

  for (var i = 0; i < path.length; i++) {
    final ch = path[i];
    if (ch == '.') {
      flushKey();
    } else if (ch == '[') {
      flushKey();
      final end = path.indexOf(']', i + 1);
      if (end < 0) {
        throw FormatException('Unclosed bracket in setData path: $path');
      }
      final inner = path.substring(i + 1, end).trim();
      final idx = int.tryParse(inner);
      if (idx != null) {
        if (idx < 0 || idx > 2048) {
          throw FormatException('setData array index out of bounds: $idx');
        }
        out.add(idx);
      } else {
        final unquoted = (inner.length >= 2 &&
                ((inner.startsWith("'") && inner.endsWith("'")) ||
                    (inner.startsWith('"') && inner.endsWith('"'))))
            ? inner.substring(1, inner.length - 1)
            : inner;
        if (_kBlockedPatchSegments.contains(unquoted)) {
          throw FormatException('Forbidden setData path segment: "$unquoted"');
        }
        out.add(unquoted);
      }
      i = end;
    } else {
      buf.write(ch);
    }
  }
  flushKey();
  return out;
}

Object? _assignAtPath(
  Object? current,
  List<Object> segments,
  int index,
  Object? leafValue,
) {
  if (index >= segments.length) return leafValue;
  final seg = segments[index];
  if (seg is int) {
    final list = current is List ? List<Object?>.from(current) : <Object?>[];
    while (list.length <= seg) {
      list.add(null);
    }
    list[seg] = _assignAtPath(list[seg], segments, index + 1, leafValue);
    return list;
  }
  final key = seg as String;
  final map = (current is Map && VibeSealedHandle.tryParse(current) == null)
      ? <String, Object?>{
          for (final e in current.entries) e.key.toString(): e.value,
        }
      : <String, Object?>{};
  map[key] = _assignAtPath(map[key], segments, index + 1, leafValue);
  return map;
}

/// Deep-clones a JSON-like map while preserving `{ 'sealed': 'h_...' }` handles.
Map<String, Object?> deepCloneVibeMap(Map<dynamic, dynamic> src) {
  return <String, Object?>{
    for (final e in src.entries) e.key.toString(): deepCloneVibeValue(e.value),
  };
}

/// Deep-clones a JSON-like value while preserving `{ 'sealed': 'h_...' }` handles.
Object? deepCloneVibeValue(Object? v) {
  if (v == null || v is num || v is bool || v is String) return v;
  if (VibeSealedHandle.tryParse(v) != null) {
    return <String, Object?>{'sealed': (v as Map)['sealed'].toString()};
  }
  if (v is List)
    return <Object?>[for (final item in v) deepCloneVibeValue(item)];
  if (v is Map) return deepCloneVibeMap(v);
  return v.toString();
}

/// Sliding-window rate limiter enforcing `<= maxCallsPerSecond` `setData` mutations.
class VibeSetDataRateLimiter {
  VibeSetDataRateLimiter({this.maxCallsPerSecond = kMaxVibeSetDataRatePerSec});

  final int maxCallsPerSecond;
  final List<int> _timestampsMs = <int>[];

  void record({int? nowMs}) {
    final t = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _timestampsMs.removeWhere((prev) => (t - prev) >= 1000);
    if (_timestampsMs.length >= maxCallsPerSecond) {
      throw StateError(
        'setData rate limit exceeded (> $maxCallsPerSecond calls/s)',
      );
    }
    _timestampsMs.add(t);
  }

  void reset() => _timestampsMs.clear();
}

/// Structured UI event dispatched from Layer 2 (`Skyline` View) to Layer 1 (`AppService`).
class VibeMiniProgramEvent {
  const VibeMiniProgramEvent({
    required this.type,
    required this.handler,
    this.targetId,
    this.dataset = const <String, Object?>{},
    this.detail = const <String, Object?>{},
  });

  final String type;
  final String handler;
  final String? targetId;
  final Map<String, Object?> dataset;
  final Map<String, Object?> detail;

  static VibeMiniProgramEvent? tryFromCommand(
    String command,
    Map<String, Object?> args,
  ) {
    if (args['__mpEvent'] == true && args['handler'] is String) {
      return VibeMiniProgramEvent(
        type: (args['type'] ?? 'tap').toString(),
        handler: args['handler'] as String,
        targetId: args['id']?.toString(),
        dataset: args['dataset'] is Map
            ? deepCloneVibeMap(args['dataset'] as Map)
            : const <String, Object?>{},
        detail: args['detail'] is Map
            ? deepCloneVibeMap(args['detail'] as Map)
            : <String, Object?>{
                if (args.containsKey('value')) 'value': args['value'],
                if (args.containsKey('checked')) 'value': args['checked'],
                if (args.containsKey('selected')) 'value': args['selected'],
              },
      );
    }
    for (final prefix in const <String>['mp:tap:', 'mp:input:', 'mp:change:']) {
      if (command.startsWith(prefix) && command.length > prefix.length) {
        final evType = prefix.split(':')[1];
        return VibeMiniProgramEvent(
          type: evType,
          handler: command.substring(prefix.length),
          targetId: args['id']?.toString(),
          dataset: args['dataset'] is Map
              ? deepCloneVibeMap(args['dataset'] as Map)
              : const <String, Object?>{},
          detail: <String, Object?>{
            if (args.containsKey('value')) 'value': args['value'],
            if (args.containsKey('checked')) 'value': args['checked'],
            if (args.containsKey('selected')) 'value': args['selected'],
          },
        );
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'handler': handler,
        'target': <String, Object?>{
          if (targetId != null) 'id': targetId,
          'dataset': dataset,
        },
        'detail': detail,
      };
}

/// Execution context (`this`) exposed to Mini Program lifecycle hooks & methods.
class VibeMiniProgramScope {
  VibeMiniProgramScope.internal(this._session);

  final VibeMiniProgramSession _session;

  Map<String, Object?> get data => _session.data;
  Map<String, Object?> get hostData => _session.hostData;
  VibeTriggerContext get context => _session.triggerContext;

  void setData(Map<String, Object?> patch, {int? nowMs}) {
    _session.setData(patch, nowMs: nowMs);
  }
}

typedef VibeMiniProgramLifecycleHook = void Function(
    VibeMiniProgramScope scope);
typedef VibeMiniProgramDataHook = void Function(
  VibeMiniProgramScope scope,
  Map<String, Object?> hostData,
  VibeTriggerContext context,
);
typedef VibeMiniProgramMethodHook = void Function(
  VibeMiniProgramScope scope,
  VibeMiniProgramEvent event,
);

/// Declarative or JS-backed WeChat Mini Program (`AppService`) definition.
class VibeMiniProgramDefinition {
  const VibeMiniProgramDefinition({
    this.initialData = const <String, Object?>{},
    this.template,
    this.onLoad,
    this.onShow,
    this.onHide,
    this.onDataUpdate,
    this.methods = const <String, VibeMiniProgramMethodHook>{},
    this.rawSource,
  });

  /// Parses an air-gapped `defineMiniProgram({ data, template, onLoad, onShow,
  /// onHide, onDataUpdate, methods })` script (or JSON object) into a safe
  /// pure-Dart [VibeMiniProgramDefinition].
  factory VibeMiniProgramDefinition.fromSource(
    String source, {
    Map<String, Object?>? initialDataOverride,
    Map<String, Object?>? templateOverride,
  }) {
    return parseMiniProgramDefinitionFromSource(
      source,
      initialDataOverride: initialDataOverride,
      templateOverride: templateOverride,
    );
  }

  final Map<String, Object?> initialData;
  final Map<String, Object?>? template;
  final VibeMiniProgramLifecycleHook? onLoad;
  final VibeMiniProgramLifecycleHook? onShow;
  final VibeMiniProgramLifecycleHook? onHide;
  final VibeMiniProgramDataHook? onDataUpdate;
  final Map<String, VibeMiniProgramMethodHook> methods;
  final String? rawSource;
}

/// Stateful air-gapped Mini Program controller pairing Layer 1 (`AppService`
/// Dart/JS/Wasm logic + `setData`) with Layer 2 (`Skyline` VXML `template`).
class VibeMiniProgramSession {
  VibeMiniProgramSession({
    required this.definition,
    Map<String, Object?>? template,
    this.wasmBytes,
    this.customWasmRunner,
    VibeSetDataRateLimiter? rateLimiter,
  })  : _template = template ?? definition.template,
        rateLimiter = rateLimiter ?? VibeSetDataRateLimiter(),
        _data = deepCloneVibeMap(definition.initialData) {
    if (wasmBytes != null) {
      validateVibeWasmBytes(wasmBytes!);
    }
  }

  final VibeMiniProgramDefinition definition;
  final Map<String, Object?>? _template;
  final Uint8List? wasmBytes;
  final Map<String, Object?> Function(
    Uint8List wasmBytes,
    Map<String, Object?> input,
  )? customWasmRunner;
  final VibeSetDataRateLimiter rateLimiter;

  Map<String, Object?> _data;
  Map<String, Object?> _hostData = const <String, Object?>{};
  VibeTriggerContext _triggerContext = const VibeTriggerContext();
  String _lifecycle = 'created';
  int _setDataCount = 0;

  Map<String, Object?> get data => Map<String, Object?>.unmodifiable(_data);
  Map<String, Object?> get hostData => _hostData;
  VibeTriggerContext get triggerContext => _triggerContext;
  String get lifecycle => _lifecycle;
  int get setDataCount => _setDataCount;
  Map<String, Object?>? get template => _template;

  late final VibeMiniProgramScope _scope = VibeMiniProgramScope.internal(this);

  void setData(Map<String, Object?> patch, {int? nowMs}) {
    rateLimiter.record(nowMs: nowMs);
    _data = applyVibeSetData(_data, patch);
    _setDataCount++;
  }

  void load({
    Map<String, Object?> hostData = const <String, Object?>{},
    VibeTriggerContext context = const VibeTriggerContext(),
    int? nowMs,
  }) {
    _hostData = deepCloneVibeMap(hostData);
    _triggerContext = context;
    _lifecycle = 'loaded';
    definition.onLoad?.call(_scope);
    _invokeWasmHook('onLoad', nowMs: nowMs);
    show(context: context, nowMs: nowMs);
    if (_hostData.isNotEmpty) {
      definition.onDataUpdate?.call(_scope, _hostData, _triggerContext);
      _invokeWasmHook('onDataUpdate', nowMs: nowMs);
    }
  }

  void show({VibeTriggerContext? context, int? nowMs}) {
    if (context != null) _triggerContext = context;
    _lifecycle = 'shown';
    definition.onShow?.call(_scope);
    _invokeWasmHook('onShow', nowMs: nowMs);
  }

  void hide({int? nowMs}) {
    _lifecycle = 'hidden';
    definition.onHide?.call(_scope);
    _invokeWasmHook('onHide', nowMs: nowMs);
  }

  void updateHostData(
    Map<String, Object?> nextHostData,
    VibeTriggerContext nextContext, {
    int? nowMs,
  }) {
    _hostData = deepCloneVibeMap(nextHostData);
    _triggerContext = nextContext;
    definition.onDataUpdate?.call(_scope, _hostData, _triggerContext);
    _invokeWasmHook('onDataUpdate', nowMs: nowMs);
  }

  bool dispatchEvent(VibeMiniProgramEvent event, {int? nowMs}) {
    final fn = definition.methods[event.handler];
    if (fn != null) {
      fn(_scope, event);
      return true;
    }
    if (wasmBytes != null) {
      _invokeWasmHook(event.handler, event: event.toJson(), nowMs: nowMs);
      return true;
    }
    return false;
  }

  /// Merged read-only scope exposed to Layer 2 `VXML` template compilation.
  Map<String, Object?> buildTemplateScope() {
    return <String, Object?>{
      ..._hostData,
      ..._data,
      'data': _data,
      'hostData': _hostData,
      'context': _triggerContext.toJson(),
    };
  }

  /// Compiles [template] against [buildTemplateScope] into a validated canonical `VibeView`.
  Map<String, Object?>? buildView() {
    final tpl = _template;
    if (tpl == null) return null;
    return compileVibeTemplate(tpl, buildTemplateScope());
  }

  void _invokeWasmHook(
    String hookName, {
    Map<String, Object?>? event,
    int? nowMs,
  }) {
    final bytes = wasmBytes;
    if (bytes == null) return;
    final req = <String, Object?>{
      'hook': hookName,
      'command': hookName,
      'data': _data,
      'hostData': _hostData,
      'context': _triggerContext.toJson(),
      if (event != null) 'event': event,
    };
    final out = customWasmRunner != null
        ? customWasmRunner!(bytes, req)
        : VibeWasmEvaluator.evaluateRaw(bytes, req) as Map<String, Object?>;
    if (out['setData'] is Map) {
      setData(
        (out['setData'] as Map).map((k, v) => MapEntry(k.toString(), v)),
        nowMs: nowMs,
      );
    } else if (out['state'] is Map) {
      setData(
        (out['state'] as Map).map((k, v) => MapEntry(k.toString(), v)),
        nowMs: nowMs,
      );
    }
  }
}
