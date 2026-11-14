import 'dart:convert';

import 'canvas.dart';
import 'vibe_conditional_entry.dart';
import 'vibe_protocol.dart';
import 'vibe_runtime_config.dart';
import 'vibe_trigger_condition.dart';

export 'vibe_conditional_entry.dart';
export 'vibe_runtime_config.dart';

/// Snapshot produced by [VibeTriggerEvaluator.evaluate].
class VibeTriggerEvaluationResult {
  const VibeTriggerEvaluationResult({
    required this.context,
    this.activeEntries = const <VibeConditionalEntry>[],
    this.newlyTriggeredIds = const <String>[],
    this.deactivatedIds = const <String>[],
    this.heldIds = const <String>[],
    this.dismissedIds = const <String>[],
  });

  final VibeTriggerContext context;
  final List<VibeConditionalEntry> activeEntries;
  final List<String> newlyTriggeredIds;
  final List<String> deactivatedIds;
  final List<String> heldIds;
  final List<String> dismissedIds;

  List<String> get activeIds =>
      List<String>.unmodifiable(activeEntries.map((e) => e.id));

  bool get changed => newlyTriggeredIds.isNotEmpty || deactivatedIds.isNotEmpty;
}

/// Evaluates [VibeTriggerCondition] rules against [VibeTriggerContext] snapshots
/// with hysteresis (`holdMs`), enablement gating, pinning, and per-episode dismissal.
class VibeTriggerEvaluator {
  final Set<String> _activeIds = <String>{};
  final Map<String, int> _lastMatchedAtMs = <String, int>{};
  final Set<String> _dismissedEpisodeIds = <String>{};

  static bool matches(VibeTriggerCondition condition, VibeTriggerContext ctx) =>
      condition.matches(ctx);

  static bool matchesJson(
    Map<String, Object?> whenJson,
    Map<String, Object?> contextJson,
  ) =>
      VibeTriggerCondition.fromJson(whenJson)
          .matches(VibeTriggerContext.fromJson(contextJson));

  void dismiss(String id) => _dismissedEpisodeIds.add(id);

  void undismiss(String id) => _dismissedEpisodeIds.remove(id);

  bool isDismissed(String id) => _dismissedEpisodeIds.contains(id);

  void reset() {
    _activeIds.clear();
    _lastMatchedAtMs.clear();
    _dismissedEpisodeIds.clear();
  }

  VibeTriggerEvaluationResult evaluate(
    Iterable<VibeConditionalEntry> entries,
    VibeTriggerContext context, {
    int? nowMs,
  }) {
    final clock = nowMs ??
        (context.timestampMs > 0
            ? context.timestampMs
            : DateTime.now().millisecondsSinceEpoch);

    final sorted = entries.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        if (a.priority != b.priority) return b.priority.compareTo(a.priority);
        if (a.order != b.order) return a.order.compareTo(b.order);
        return a.id.compareTo(b.id);
      });

    final seenIds = <String>{};
    final activeEntries = <VibeConditionalEntry>[];
    final nextActiveIds = <String>{};
    final heldIds = <String>[];
    final dismissedIds = <String>[];

    for (final entry in sorted) {
      seenIds.add(entry.id);
      if (!entry.enabled) {
        _lastMatchedAtMs.remove(entry.id);
        _dismissedEpisodeIds.remove(entry.id);
        continue;
      }

      final rawMatched = entry.pinned ||
          (entry.condition != null && entry.condition!.matches(context));

      if (rawMatched) {
        _lastMatchedAtMs[entry.id] = clock;
        if (_dismissedEpisodeIds.contains(entry.id) && !entry.pinned) {
          dismissedIds.add(entry.id);
          continue;
        }
        activeEntries.add(entry);
        nextActiveIds.add(entry.id);
      } else {
        final lastAt = _lastMatchedAtMs[entry.id];
        final withinHold = entry.holdMs > 0 &&
            lastAt != null &&
            (clock - lastAt) >= 0 &&
            (clock - lastAt) < entry.holdMs;
        if (withinHold) {
          if (_dismissedEpisodeIds.contains(entry.id)) {
            dismissedIds.add(entry.id);
          } else if (_activeIds.contains(entry.id)) {
            activeEntries.add(entry);
            nextActiveIds.add(entry.id);
            heldIds.add(entry.id);
          }
        } else {
          _lastMatchedAtMs.remove(entry.id);
          _dismissedEpisodeIds.remove(entry.id);
        }
      }
    }

    _lastMatchedAtMs.removeWhere((id, _) => !seenIds.contains(id));
    _dismissedEpisodeIds.removeWhere((id) => !seenIds.contains(id));

    final newlyTriggered = <String>[
      for (final e in activeEntries)
        if (!_activeIds.contains(e.id)) e.id,
    ];
    final deactivated = <String>[
      for (final prevId in _activeIds)
        if (!nextActiveIds.contains(prevId)) prevId,
    ];

    _activeIds
      ..clear()
      ..addAll(nextActiveIds);

    return VibeTriggerEvaluationResult(
      context: context,
      activeEntries: List<VibeConditionalEntry>.unmodifiable(activeEntries),
      newlyTriggeredIds: List<String>.unmodifiable(newlyTriggered),
      deactivatedIds: List<String>.unmodifiable(deactivated),
      heldIds: List<String>.unmodifiable(heldIds),
      dismissedIds: List<String>.unmodifiable(dismissedIds),
    );
  }
}

class _PresetOverride {
  const _PresetOverride({
    this.enabled,
    this.pinned,
    this.condition,
    this.conditionCleared = false,
  });

  final bool? enabled;
  final bool? pinned;
  final VibeTriggerCondition? condition;
  final bool conditionCleared;

  Map<String, Object?> toJson() => <String, Object?>{
        if (enabled != null) 'enabled': enabled,
        if (pinned != null) 'pinned': pinned,
        if (condition != null) 'when': condition!.toJson(),
        if (conditionCleared) 'conditionCleared': true,
      };

  factory _PresetOverride.fromJson(Map<String, Object?> json) =>
      _PresetOverride(
        enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
        pinned: json['pinned'] is bool ? json['pinned'] as bool : null,
        condition: VibeTriggerCondition.tryParse(json['when']),
        conditionCleared: json['conditionCleared'] == true,
      );
}

/// Host-side registry of default Vibe-Space presets and user-authored conditional
/// Vibe views with persistence and live [VibeProtocolHost] synchronization.
class VibeConditionalRegistry {
  VibeConditionalRegistry({
    this.host,
    VibeStorageAdapter? storage,
    this.storageKey = 'vibe_space.conditional_entries.v1',
    VibeTriggerEvaluator? evaluator,
  })  : _storage = storage,
        _evaluator = evaluator ?? VibeTriggerEvaluator() {
    _loadFromStorage();
    if (host != null) {
      _detachHost = host!.onChange(_onHostRecordsChanged);
    }
    _recompute();
  }

  final VibeProtocolHost? host;
  final VibeStorageAdapter? _storage;
  final String storageKey;
  final VibeTriggerEvaluator _evaluator;

  final Map<String, VibeConditionalEntry> _presets =
      <String, VibeConditionalEntry>{};
  final Map<String, VibeConditionalEntry> _presetDefaults =
      <String, VibeConditionalEntry>{};
  final Map<String, _PresetOverride> _presetOverrides =
      <String, _PresetOverride>{};
  final Map<String, VibeConditionalEntry> _customEntries =
      <String, VibeConditionalEntry>{};
  final Set<void Function()> _listeners = <void Function()>{};

  void Function()? _detachHost;
  VibeTriggerContext _context = const VibeTriggerContext();
  late VibeTriggerEvaluationResult _lastResult =
      VibeTriggerEvaluationResult(context: _context);

  VibeTriggerContext get currentContext => _context;
  VibeTriggerEvaluationResult get lastResult => _lastResult;
  List<VibeConditionalEntry> get activeEntries => _lastResult.activeEntries;
  List<VibeConditionalEntry> get presetEntries =>
      List<VibeConditionalEntry>.unmodifiable(_presets.values);
  List<VibeConditionalEntry> get customEntries =>
      List<VibeConditionalEntry>.unmodifiable(_customEntries.values);

  /// All registered presets, custom conditional entries, and conditional [host] records.
  List<VibeConditionalEntry> get entries {
    final merged = <String, VibeConditionalEntry>{
      ..._presets,
      ..._customEntries,
    };
    if (host != null) {
      for (final rec in host!.installed()) {
        final trig = rec.effectiveTrigger;
        if (trig == null) continue;
        merged.putIfAbsent(
          rec.instanceId,
          () => VibeConditionalEntry(
            id: rec.instanceId,
            title: rec.title,
            subtitle: rec.note,
            condition: trig,
            needs: rec.vibe.needs,
            runtime: VibeRuntimeKind.js,
            enabled: rec.triggerEnabled && !rec.paused,
            trusted: rec.origin != 'shared' || rec.triggerEnabled,
            pinned: rec.pinned,
            order: rec.order,
            vibe: rec.vibe,
            args: rec.args,
            metadata: <String, Object?>{
              'origin': rec.origin,
              'hostRecord': true,
            },
          ),
        );
      }
    }
    return List<VibeConditionalEntry>.unmodifiable(merged.values);
  }

  /// Computes the `Reads / Shows / Cannot` security label for [entry] against [host].
  VibePermissionLabel? permissionLabelFor(VibeConditionalEntry entry) {
    return host?.permissionLabelForNeeds(entry.effectiveNeeds);
  }

  /// Looks up a registered preset, custom entry, or host conditional entry by [id].
  VibeConditionalEntry? entryById(String id) {
    final direct = _presets[id] ?? _customEntries[id];
    if (direct != null) return direct;
    for (final item in entries) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Registers or refreshes built-in Vibe-Space preset configs while preserving
  /// user `enabled`/`pinned`/`when` overrides and leaving custom entries intact.
  void registerPresets(
    Iterable<Object> presets, {
    bool preserveUserOverrides = true,
    int? nowMs,
  }) {
    for (final raw in presets) {
      final parsed = switch (raw) {
        final VibeConditionalEntry e =>
          e.copyWith(isPreset: true, trusted: true),
        final Map<Object?, Object?> m => VibeConditionalEntry.fromJson(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ).copyWith(isPreset: true, trusted: true),
        _ => throw ArgumentError('Unsupported preset item: ${raw.runtimeType}'),
      };
      if (parsed.id.isEmpty) continue;
      parsed.validate();
      _presetDefaults[parsed.id] = parsed;

      final ov = preserveUserOverrides ? _presetOverrides[parsed.id] : null;
      _presets[parsed.id] = ov == null
          ? parsed
          : parsed.copyWith(
              enabled: ov.enabled ?? parsed.enabled,
              pinned: ov.pinned ?? parsed.pinned,
              condition: ov.condition,
              clearCondition: ov.conditionCleared,
            );
    }
    _recompute(nowMs: nowMs);
    _notify();
  }

  /// Hydrates live preset payloads (`VibeCanvasPayload`, `VibeSpec`, or JSON view)
  /// in-place without resetting user enablement, pin, or custom trigger overrides.
  void hydratePresetPayloads(
    Map<String, Object?> payloads, {
    int? nowMs,
  }) {
    var touched = false;
    for (final entry in payloads.entries) {
      final target = _presets[entry.key] ?? _customEntries[entry.key];
      if (target == null || entry.value == null) continue;
      final val = entry.value;
      VibeConditionalEntry updated = target;
      if (val is VibeCanvasPayload) {
        updated = target.copyWith(canvas: val);
      } else if (val is VibeSpec) {
        updated = target.copyWith(vibe: val);
      } else if (val is VibeConditionalEntry) {
        updated = target.copyWith(
          title: val.title,
          subtitle: val.subtitle,
          needs: val.needs.isNotEmpty ? val.needs : target.needs,
          runtime: val.runtime ?? target.runtime,
          template: val.template ?? target.template,
          initialData: val.initialData ?? target.initialData,
          miniProgram: val.miniProgram ?? target.miniProgram,
          style: val.style ?? target.style,
          source: val.source ?? target.source,
          wasmBase64: val.wasmBase64 ?? target.wasmBase64,
          jsGlue: val.jsGlue ?? target.jsGlue,
          dataModel: val.dataModel ?? target.dataModel,
          canvas: val.canvas,
          vibe: val.vibe,
          view: val.view,
          metadata: val.metadata,
        );
      } else if (val is Map) {
        final map = val.map((k, v) => MapEntry(k.toString(), v));
        if (map.containsKey('template') || map.containsKey('vxml')) {
          final tpl = map['template'] ?? map['vxml'];
          updated = target.copyWith(
            template: tpl is Map
                ? tpl.map((k, v) => MapEntry(k.toString(), v))
                : target.template,
            initialData: map['data'] is Map
                ? (map['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
                : target.initialData,
            source: map['source']?.toString() ?? target.source,
          );
        } else if (map.containsKey('canvasId') ||
            map.containsKey('canvas_id') ||
            map.containsKey('format') ||
            map.containsKey('content')) {
          updated = target.copyWith(canvas: VibeCanvasPayload.fromJson(map));
        } else {
          updated = target.copyWith(view: map);
        }
      }
      if (_presets.containsKey(entry.key)) {
        _presets[entry.key] = updated;
      } else {
        _customEntries[entry.key] = updated;
      }
      touched = true;
    }
    if (touched) {
      _recompute(nowMs: nowMs);
      _notify();
    }
  }

  void upsert(VibeConditionalEntry entry, {int? nowMs}) {
    if (entry.id.trim().isEmpty) {
      throw ArgumentError('VibeConditionalEntry.id must be non-empty');
    }
    entry.validate();
    if (entry.isPreset) {
      registerPresets(<VibeConditionalEntry>[entry], nowMs: nowMs);
      return;
    }
    _customEntries[entry.id] = entry;
    _saveToStorage();
    _recompute(nowMs: nowMs);
    _notify();
  }

  bool unregister(String id, {int? nowMs}) {
    final removed = _customEntries.remove(id) != null;
    if (removed) {
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
    }
    return removed;
  }

  void setEnabled(String id, bool enabled, {int? nowMs}) {
    final preset = _presets[id];
    if (preset != null) {
      if (preset.enabled == enabled) return;
      _presets[id] = preset.copyWith(enabled: enabled);
      final prev = _presetOverrides[id];
      _presetOverrides[id] = _PresetOverride(
        enabled: enabled,
        pinned: prev?.pinned,
        condition: prev?.condition,
        conditionCleared: prev?.conditionCleared ?? false,
      );
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    final custom = _customEntries[id];
    if (custom != null) {
      final nextTrusted = enabled ? true : custom.trusted;
      if (custom.enabled == enabled && custom.trusted == nextTrusted) return;
      _customEntries[id] = custom.copyWith(
        enabled: enabled,
        trusted: nextTrusted,
      );
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    host?.updateRecord(id, triggerEnabled: enabled);
  }

  void setTrusted(String id, bool trusted, {int? nowMs}) {
    final custom = _customEntries[id];
    if (custom == null || custom.trusted == trusted) return;
    _customEntries[id] = custom.copyWith(trusted: trusted);
    _saveToStorage();
    _recompute(nowMs: nowMs);
    _notify();
  }

  void setPinned(String id, bool pinned, {int? nowMs}) {
    final preset = _presets[id];
    if (preset != null) {
      if (preset.pinned == pinned) return;
      _presets[id] = preset.copyWith(pinned: pinned);
      final prev = _presetOverrides[id];
      _presetOverrides[id] = _PresetOverride(
        enabled: prev?.enabled,
        pinned: pinned,
        condition: prev?.condition,
        conditionCleared: prev?.conditionCleared ?? false,
      );
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    final custom = _customEntries[id];
    if (custom != null) {
      if (custom.pinned == pinned) return;
      _customEntries[id] = custom.copyWith(pinned: pinned);
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    host?.updateRecord(id, pinned: pinned);
  }

  void updateCondition(
    String id,
    VibeTriggerCondition? condition, {
    int? nowMs,
  }) {
    condition?.validate();
    final preset = _presets[id];
    if (preset != null) {
      _presets[id] = preset.copyWith(
        condition: condition,
        clearCondition: condition == null,
      );
      final prev = _presetOverrides[id];
      _presetOverrides[id] = _PresetOverride(
        enabled: prev?.enabled,
        pinned: prev?.pinned,
        condition: condition,
        conditionCleared: condition == null,
      );
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    final custom = _customEntries[id];
    if (custom != null) {
      _customEntries[id] = custom.copyWith(
        condition: condition,
        clearCondition: condition == null,
      );
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
      return;
    }
    host?.updateRecord(id, when: condition, clearWhen: condition == null);
  }

  void resetPresetOverride(String id, {int? nowMs}) {
    _presetOverrides.remove(id);
    final def = _presetDefaults[id];
    if (def != null) {
      _presets[id] = def;
      _saveToStorage();
      _recompute(nowMs: nowMs);
      _notify();
    }
  }

  void dismissCurrentActivation(String id, {int? nowMs}) {
    _evaluator.dismiss(id);
    _recompute(nowMs: nowMs);
    _notify();
  }

  void undismiss(String id, {int? nowMs}) {
    _evaluator.undismiss(id);
    _recompute(nowMs: nowMs);
    _notify();
  }

  VibeTriggerEvaluationResult updateContextFromJson(
    Map<String, Object?> contextJson, {
    int? nowMs,
  }) {
    return updateContext(
      VibeTriggerContext.fromJson(contextJson),
      nowMs: nowMs,
    );
  }

  VibeTriggerEvaluationResult updateContext(
    VibeTriggerContext nextContext, {
    int? nowMs,
  }) {
    final contextChanged = nextContext != _context;
    _context = nextContext;
    final prevActiveIds = _lastResult.activeIds;
    final prevHeld = _lastResult.heldIds;
    final result = _recompute(nowMs: nowMs);
    if (contextChanged ||
        result.changed ||
        prevActiveIds.join(',') != result.activeIds.join(',') ||
        prevHeld.join(',') != result.heldIds.join(',')) {
      _notify();
    }
    return result;
  }

  void Function() onChange(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void dispose() {
    _detachHost?.call();
    _detachHost = null;
    _listeners.clear();
  }

  VibeTriggerEvaluationResult _recompute({int? nowMs}) {
    _lastResult = _evaluator.evaluate(entries, _context, nowMs: nowMs);
    return _lastResult;
  }

  void _onHostRecordsChanged() {
    _recompute();
    _notify();
  }

  void _loadFromStorage() {
    final raw = _storage?.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final e = VibeConditionalEntry.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (e.id.isNotEmpty) _customEntries[e.id] = e;
          }
        }
      } else if (decoded is Map) {
        final rawCustom = decoded['custom'];
        if (rawCustom is List) {
          for (final item in rawCustom) {
            if (item is Map) {
              final e = VibeConditionalEntry.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              );
              if (e.id.isNotEmpty) _customEntries[e.id] = e;
            }
          }
        }
        final rawOverrides = decoded['presetOverrides'];
        if (rawOverrides is Map) {
          for (final entry in rawOverrides.entries) {
            if (entry.value is Map) {
              _presetOverrides[entry.key.toString()] = _PresetOverride.fromJson(
                (entry.value as Map).map((k, v) => MapEntry(k.toString(), v)),
              );
            }
          }
        }
      }
    } on Object {
      // Ignore malformed storage entries rather than crashing host startup.
    }
  }

  void _saveToStorage() {
    if (_storage == null) return;
    final payload = jsonEncode(<String, Object?>{
      'custom': <Map<String, Object?>>[
        for (final e in _customEntries.values) e.toJson(),
      ],
      if (_presetOverrides.isNotEmpty)
        'presetOverrides': <String, Object?>{
          for (final e in _presetOverrides.entries) e.key: e.value.toJson(),
        },
    });
    _storage.write(storageKey, payload);
  }

  void _notify() {
    for (final fn in List<void Function()>.from(_listeners)) {
      try {
        fn();
      } on Object {
        // Isolate listener failures.
      }
    }
  }
}
