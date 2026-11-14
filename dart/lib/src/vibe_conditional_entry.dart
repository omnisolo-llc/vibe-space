import 'dart:convert';

import 'canvas.dart';
import 'vibe_mini_program.dart';
import 'vibe_protocol.dart';
import 'vibe_runtime_config.dart';
import 'vibe_trigger_condition.dart';
import 'vibe_vxml_template.dart';

String _sanitizeVibeSpecId(String raw) {
  final cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (cleaned.isEmpty) return 'custom-vibe';
  return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40);
}

/// Standardized Vibe-Space conditional config envelope (`id`, `name`/`title`,
/// `enabled`, `isPreset`, `needs`, `when`) decoupled from its inner runtime
/// (`miniprogram`, `vxml`, `wasm`, `js`, `a2ui`, `vibe_ui`, `markdown`, `dom`).
class VibeConditionalEntry {
  const VibeConditionalEntry({
    required this.id,
    String? title,
    String? name,
    this.subtitle = '',
    this.condition,
    this.needs = const <String>[],
    this.runtime,
    this.template,
    this.initialData,
    this.miniProgram,
    this.style,
    this.source,
    this.wasmBase64,
    this.jsGlue,
    this.dataModel,
    this.isPreset = false,
    this.enabled = true,
    this.trusted = true,
    this.pinned = false,
    this.priority = 0,
    this.order = 0,
    this.holdMs = 0,
    this.vibe,
    this.canvas,
    this.view,
    this.args,
    this.metadata = const <String, Object?>{},
  }) : title = title ?? name ?? 'Custom Vibe';

  factory VibeConditionalEntry.fromJson(Map<String, Object?> json) {
    final rawVibe = json['vibe'];
    final rawCanvas = json['canvas'];
    final rawView = json['view'] ?? json['a2ui'];
    final rawTemplate = json['template'] ?? json['vxml'];
    final rawInitialData =
        json['data'] ?? json['initialData'] ?? json['initial_data'];
    final rawArgs = json['args'];
    final rawMeta = json['metadata'];
    final rawNeeds = json['needs'];
    final rawDataModel = json['dataModel'] ?? json['data_model'];
    final rawTitle =
        (json['name'] ?? json['title'] ?? 'Custom Vibe').toString().trim();
    final parsedRuntime = VibeRuntimeKind.tryFromWireName(
      (json['runtime'] ?? json['format'])?.toString(),
    );
    final rawSource =
        (json['source'] ?? json['html'] ?? json['content'])?.toString();
    final rawWasm =
        (json['wasmBase64'] ?? json['wasm_base64'])?.toString().trim();
    final rawGlue = (json['jsGlue'] ?? json['js_glue'])?.toString();
    final isPresetFlag =
        json['isPreset'] == true || json['isBuiltInPreset'] == true;
    final origin = json['origin']?.toString();
    final trustedFlag = isPresetFlag
        ? true
        : (json['trusted'] is bool
            ? json['trusted'] as bool
            : origin != 'shared');

    Map<String, Object?>? parsedView;
    if (rawView is Map) {
      parsedView = Map<String, Object?>.unmodifiable(
        rawView.map((k, v) => MapEntry(k.toString(), v)),
      );
    } else if (rawView is List) {
      parsedView = Map<String, Object?>.unmodifiable(<String, Object?>{
        'a2ui': List<Object?>.unmodifiable(rawView),
      });
    }

    return VibeConditionalEntry(
      id: (json['id'] ?? '').toString().trim(),
      title: rawTitle.isEmpty ? 'Custom Vibe' : rawTitle,
      subtitle: (json['subtitle'] ?? '').toString(),
      condition:
          VibeTriggerCondition.tryParse(json['when'] ?? json['condition']),
      needs: rawNeeds is List
          ? List<String>.unmodifiable(
              rawNeeds
                  .map((e) => e?.toString().trim() ?? '')
                  .where((s) => s.isNotEmpty),
            )
          : const <String>[],
      runtime: parsedRuntime,
      template: rawTemplate is Map
          ? Map<String, Object?>.unmodifiable(
              rawTemplate.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      initialData: rawInitialData is Map
          ? Map<String, Object?>.unmodifiable(
              rawInitialData.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      style: normalizeVibeStyleTokens(json['style']),
      source: rawSource,
      wasmBase64: (rawWasm != null && rawWasm.isNotEmpty) ? rawWasm : null,
      jsGlue: rawGlue,
      dataModel: rawDataModel is Map
          ? Map<String, Object?>.unmodifiable(
              rawDataModel.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      isPreset: isPresetFlag,
      enabled: json['enabled'] != false,
      trusted: trustedFlag,
      pinned: json['pinned'] == true,
      priority: json['priority'] is int ? json['priority'] as int : 0,
      order: json['order'] is int ? json['order'] as int : 0,
      holdMs: json['holdMs'] is int && (json['holdMs'] as int) > 0
          ? json['holdMs'] as int
          : 0,
      vibe: rawVibe is Map
          ? VibeSpec.fromJson(rawVibe.map((k, v) => MapEntry(k.toString(), v)))
          : null,
      canvas: rawCanvas is Map
          ? VibeCanvasPayload.fromJson(
              rawCanvas.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      view: parsedView,
      args: rawArgs is Map
          ? Map<String, Object?>.unmodifiable(
              rawArgs.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
      metadata: rawMeta is Map
          ? Map<String, Object?>.unmodifiable(
              rawMeta.map((k, v) => MapEntry(k.toString(), v)),
            )
          : const <String, Object?>{},
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final VibeTriggerCondition? condition;
  final List<String> needs;
  final VibeRuntimeKind? runtime;
  final Map<String, Object?>? template;
  final Map<String, Object?>? initialData;
  final VibeMiniProgramDefinition? miniProgram;
  final Map<String, Object?>? style;
  final String? source;
  final String? wasmBase64;
  final String? jsGlue;
  final Map<String, Object?>? dataModel;
  final bool isPreset;
  final bool enabled;
  final bool trusted;
  final bool pinned;
  final int priority;
  final int order;
  final int holdMs;
  final VibeSpec? vibe;
  final VibeCanvasPayload? canvas;
  final Map<String, Object?>? view;
  final Map<String, Object?>? args;
  final Map<String, Object?> metadata;

  /// Standardized outer-envelope `name` alias for [title].
  String get name => title;

  /// Standardized outer-envelope `when` alias for [condition].
  VibeTriggerCondition? get when => condition;

  /// Alias for [isPreset].
  bool get isBuiltInPreset => isPreset;

  /// Deduplicated capability streams requested by this config (`needs` + `vibe.needs`).
  List<String> get effectiveNeeds {
    if (needs.isEmpty && (vibe == null || vibe!.needs.isEmpty)) {
      return const <String>[];
    }
    final seen = <String>{};
    final out = <String>[];
    for (final cap in needs) {
      final c = cap.trim();
      if (c.isNotEmpty && seen.add(c)) out.add(c);
    }
    if (vibe != null) {
      for (final cap in vibe!.needs) {
        final c = cap.trim();
        if (c.isNotEmpty && seen.add(c)) out.add(c);
      }
    }
    return List<String>.unmodifiable(out);
  }

  /// Resolved inner UI runtime for this entry.
  VibeRuntimeKind get effectiveRuntime {
    if (runtime != null) return runtime!;
    if (miniProgram != null) return VibeRuntimeKind.miniProgram;
    final src = source?.trimLeft() ?? '';
    if (src.contains('defineMiniProgram') || src.contains('VibeMiniApp')) {
      return VibeRuntimeKind.miniProgram;
    }
    if (template != null) {
      if ((wasmBase64 != null && wasmBase64!.isNotEmpty) || src.isNotEmpty) {
        return VibeRuntimeKind.miniProgram;
      }
      return VibeRuntimeKind.vxml;
    }
    if ((wasmBase64 != null && wasmBase64!.isNotEmpty) ||
        canvas?.format == VibeCanvasFormat.wasm) {
      return VibeRuntimeKind.wasm;
    }
    if (vibe != null) return VibeRuntimeKind.js;
    if (canvas != null) {
      return switch (canvas!.format) {
        VibeCanvasFormat.html => VibeRuntimeKind.dom,
        VibeCanvasFormat.wasm => VibeRuntimeKind.wasm,
        VibeCanvasFormat.markdown => VibeRuntimeKind.markdown,
        VibeCanvasFormat.vibeUi => VibeRuntimeKind.vibeUi,
      };
    }
    if (view != null) {
      if (view!.containsKey('surfaceUpdate') ||
          view!.containsKey('dataModelUpdate') ||
          view!.containsKey('a2ui')) {
        return VibeRuntimeKind.a2ui;
      }
      return VibeRuntimeKind.vibeUi;
    }
    if (src.startsWith('<')) return VibeRuntimeKind.dom;
    if (src.contains('function invoke')) return VibeRuntimeKind.js;
    return VibeRuntimeKind.vibeUi;
  }

  /// Effective WeChat Mini Program definition when [effectiveRuntime] is
  /// [VibeRuntimeKind.miniProgram] or [VibeRuntimeKind.vxml].
  VibeMiniProgramDefinition? get effectiveMiniProgram {
    if (miniProgram != null) {
      if (initialData == null && template == null) return miniProgram;
      return VibeMiniProgramDefinition(
        initialData: <String, Object?>{
          ...miniProgram!.initialData,
          if (initialData != null) ...initialData!,
        },
        template: template ?? miniProgram!.template,
        onLoad: miniProgram!.onLoad,
        onShow: miniProgram!.onShow,
        onHide: miniProgram!.onHide,
        onDataUpdate: miniProgram!.onDataUpdate,
        methods: miniProgram!.methods,
        rawSource: miniProgram!.rawSource ?? source,
      );
    }
    final rt = effectiveRuntime;
    if (rt != VibeRuntimeKind.miniProgram && rt != VibeRuntimeKind.vxml) {
      return null;
    }
    final mergedInit = <String, Object?>{
      if (dataModel != null) ...dataModel!,
      if (initialData != null) ...initialData!,
    };
    if (source != null && source!.trim().isNotEmpty) {
      return VibeMiniProgramDefinition.fromSource(
        source!,
        initialDataOverride: mergedInit.isEmpty ? null : mergedInit,
        templateOverride: template,
      );
    }
    return VibeMiniProgramDefinition(
      initialData: mergedInit,
      template: template ?? view,
    );
  }

  /// Effective [VibeSpec] for `js` runtime entries.
  VibeSpec? get effectiveJsVibe {
    if (vibe != null) {
      if (needs.isEmpty) return vibe;
      return vibe!.copyWith(needs: effectiveNeeds);
    }
    if (effectiveRuntime == VibeRuntimeKind.js &&
        source != null &&
        source!.trim().isNotEmpty) {
      return VibeSpec(
        id: _sanitizeVibeSpecId(id),
        name: title,
        version: 1,
        needs: effectiveNeeds,
        when: condition,
        source: source!,
      );
    }
    return null;
  }

  /// Validates trigger conditions and inner runtime resource/ABI/sandbox invariants.
  void validate() {
    condition?.validate();
    vibe?.validate();
    final rt = effectiveRuntime;
    if (rt == VibeRuntimeKind.miniProgram || rt == VibeRuntimeKind.vxml) {
      final def = effectiveMiniProgram;
      final tpl = template ?? def?.template;
      if (tpl != null) {
        compileVibeTemplate(tpl, <String, Object?>{
          if (dataModel != null) ...dataModel!,
          if (def != null) ...def.initialData,
        });
      }
    }
    if (rt == VibeRuntimeKind.dom && source != null) {
      validateVibeDomSource(source!, label: 'DOM source');
    }
    if (jsGlue != null && jsGlue!.isNotEmpty) {
      validateVibeDomSource(jsGlue!, label: 'JS glue');
    }
    final wb64 = wasmBase64 ?? canvas?.wasmBase64;
    if (wb64 != null && wb64.trim().isNotEmpty) {
      validateVibeWasmBytes(base64Decode(wb64.trim()));
    }
    if (rt == VibeRuntimeKind.js && vibe == null && source != null) {
      effectiveJsVibe?.validate();
    }
  }

  /// Hydrates `{{variable}}` placeholders in [canvas] against [context].
  VibeCanvasPayload? hydratedCanvas(VibeTriggerContext context) {
    final c = canvas;
    if (c == null) return null;
    if (!c.content.contains('{{') && !c.title.contains('{{')) return c;
    return c.copyWith(
      title: hydrateVibeTemplateString(c.title, context),
      content: hydrateVibeTemplateString(
        c.content,
        context,
        escapeJson: c.format == VibeCanvasFormat.vibeUi,
        escapeHtml: c.format == VibeCanvasFormat.html,
      ),
    );
  }

  /// Hydrates `{{variable}}` placeholders in [view] (or JSON [source]) against [context].
  Map<String, Object?>? hydratedView(VibeTriggerContext context) {
    Map<String, Object?>? target = view;
    if (target == null &&
        source != null &&
        (effectiveRuntime == VibeRuntimeKind.a2ui ||
            effectiveRuntime == VibeRuntimeKind.vibeUi)) {
      try {
        final decoded = jsonDecode(source!);
        if (decoded is Map) {
          target = decoded.map((k, val) => MapEntry(k.toString(), val));
        } else if (decoded is List) {
          target = <String, Object?>{'a2ui': decoded};
        }
      } on Object {
        target = null;
      }
    }
    if (target == null) return null;
    final rawJson = jsonEncode(target);
    if (!rawJson.contains('{{')) return target;
    final hydrated = hydrateVibeTemplateString(
      rawJson,
      context,
      escapeJson: true,
    );
    final decoded = jsonDecode(hydrated);
    return decoded is Map
        ? decoded.map((k, val) => MapEntry(k.toString(), val))
        : target;
  }

  VibeConditionalEntry copyWith({
    String? id,
    String? title,
    String? name,
    String? subtitle,
    VibeTriggerCondition? condition,
    bool clearCondition = false,
    List<String>? needs,
    VibeRuntimeKind? runtime,
    Map<String, Object?>? template,
    Map<String, Object?>? initialData,
    VibeMiniProgramDefinition? miniProgram,
    Map<String, Object?>? style,
    String? source,
    String? wasmBase64,
    String? jsGlue,
    Map<String, Object?>? dataModel,
    bool? isPreset,
    bool? enabled,
    bool? trusted,
    bool? pinned,
    int? priority,
    int? order,
    int? holdMs,
    VibeSpec? vibe,
    VibeCanvasPayload? canvas,
    Map<String, Object?>? view,
    Map<String, Object?>? args,
    Map<String, Object?>? metadata,
  }) {
    return VibeConditionalEntry(
      id: id ?? this.id,
      title: title ?? name ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      condition: clearCondition ? null : (condition ?? this.condition),
      needs: needs ?? this.needs,
      runtime: runtime ?? this.runtime,
      template: template ?? this.template,
      initialData: initialData ?? this.initialData,
      miniProgram: miniProgram ?? this.miniProgram,
      style: style ?? this.style,
      source: source ?? this.source,
      wasmBase64: wasmBase64 ?? this.wasmBase64,
      jsGlue: jsGlue ?? this.jsGlue,
      dataModel: dataModel ?? this.dataModel,
      isPreset: isPreset ?? this.isPreset,
      enabled: enabled ?? this.enabled,
      trusted: trusted ?? this.trusted,
      pinned: pinned ?? this.pinned,
      priority: priority ?? this.priority,
      order: order ?? this.order,
      holdMs: holdMs ?? this.holdMs,
      vibe: vibe ?? this.vibe,
      canvas: canvas ?? this.canvas,
      view: view ?? this.view,
      args: args ?? this.args,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': title,
        'title': title,
        if (subtitle.isNotEmpty) 'subtitle': subtitle,
        if (needs.isNotEmpty) 'needs': List<String>.from(needs),
        if (condition != null) 'when': condition!.toJson(),
        if (runtime != null) 'runtime': runtime!.wireName,
        if (template != null) 'template': template,
        if (initialData != null) 'data': initialData,
        if (style != null) 'style': style,
        if (source != null || miniProgram?.rawSource != null)
          'source': source ?? miniProgram?.rawSource,
        if (wasmBase64 != null) 'wasmBase64': wasmBase64,
        if (jsGlue != null) 'jsGlue': jsGlue,
        if (dataModel != null) 'dataModel': dataModel,
        if (isPreset) 'isPreset': true,
        'enabled': enabled,
        if (!trusted) 'trusted': false,
        'pinned': pinned,
        'priority': priority,
        'order': order,
        if (holdMs > 0) 'holdMs': holdMs,
        if (vibe != null) 'vibe': vibe!.toJson(),
        if (canvas != null) 'canvas': canvas!.toJson(),
        if (view != null) 'view': view,
        if (args != null) 'args': args,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
