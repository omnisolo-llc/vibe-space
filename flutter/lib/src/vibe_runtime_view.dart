import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart';

import 'canvas_view.dart';
import 'vibe_space_widgets.dart';
import 'vibe_widget_adapter.dart';
import 'view.dart';

/// Tracks and dispatches live `{ type: 'vibe:dataModelUpdate', data, context }`
/// messages to active `dom` / `html` Vibe-Space viewports without iframe reloads.
class VibeDomBridgeController extends ChangeNotifier {
  VibeDomBridgeController({this.onDataPush});

  /// Optional host transport hook (e.g. `iframe.contentWindow.postMessage(...)`).
  void Function(VibeDomDataModelMessage message)? onDataPush;

  final Map<String, List<VibeDomDataModelMessage>> _historyByVibe =
      <String, List<VibeDomDataModelMessage>>{};
  final Map<String, int> _pushCounts = <String, int>{};

  VibeDomDataModelMessage? lastMessageFor(String vibeId) {
    final list = _historyByVibe[vibeId];
    return (list == null || list.isEmpty) ? null : list.last;
  }

  List<VibeDomDataModelMessage> historyFor(String vibeId) =>
      List<VibeDomDataModelMessage>.unmodifiable(
        _historyByVibe[vibeId] ?? const <VibeDomDataModelMessage>[],
      );

  int pushCountFor(String vibeId) => _pushCounts[vibeId] ?? 0;

  void push(VibeDomDataModelMessage message) {
    final list = _historyByVibe.putIfAbsent(
      message.vibeId,
      () => <VibeDomDataModelMessage>[],
    );
    list.add(message);
    if (list.length > 32) {
      list.removeRange(0, list.length - 32);
    }
    _pushCounts[message.vibeId] = (_pushCounts[message.vibeId] ?? 0) + 1;
    onDataPush?.call(message);
    notifyListeners();
  }

  void clear([String? vibeId]) {
    if (vibeId != null) {
      _historyByVibe.remove(vibeId);
      _pushCounts.remove(vibeId);
    } else {
      _historyByVibe.clear();
      _pushCounts.clear();
    }
    notifyListeners();
  }
}

/// Multi-runtime renderer for [VibeConditionalEntry] supporting WeChat-style
/// `miniProgram` (`AppService` + `Skyline` VXML + `canvas`), `vxml`, `wasm`,
/// `js`, `a2ui`, `vibe_ui`, `markdown`, and opt-in `dom`/`html`.
class VibeRuntimeBody extends StatefulWidget {
  const VibeRuntimeBody({
    super.key,
    required this.entry,
    required this.triggerContext,
    required this.theme,
    this.host,
    this.domBridge,
    this.onDomDataPush,
    this.adapter,
    this.onCommand,
    this.onCanvasAction,
    this.markdownBuilder,
    this.webViewportBuilder,
  });

  final VibeConditionalEntry entry;
  final VibeTriggerContext triggerContext;
  final VibeSpaceThemeData theme;
  final VibeProtocolHost? host;
  final VibeDomBridgeController? domBridge;
  final ValueChanged<VibeDomDataModelMessage>? onDomDataPush;
  final VibeWidgetAdapter? adapter;
  final void Function(String command, Map<String, dynamic> args)? onCommand;
  final ValueChanged<VibeCanvasActionEvent>? onCanvasAction;
  final VibeCanvasMarkdownBuilder? markdownBuilder;
  final VibeCanvasWebViewportBuilder? webViewportBuilder;

  @override
  State<VibeRuntimeBody> createState() => _VibeRuntimeBodyState();
}

class _VibeRuntimeBodyState extends State<VibeRuntimeBody> {
  VibeRunController? _jsRun;
  void Function()? _detachJsRun;
  void Function()? _detachHostSources;
  VibeMiniProgramSession? _mpSession;

  Map<String, Object?> _needsData = const <String, Object?>{};
  Object? _wasmState;
  Map<String, Object?>? _wasmView;
  String? _runtimeError;

  String? _cachedDomSignature;
  VibeCanvasPayload? _cachedDomPayload;
  String? _lastPushedDomStateJson;
  int _evalGen = 0;

  String get _effectiveDataMode => widget.entry.trusted ? 'live' : 'sample';

  @override
  void initState() {
    super.initState();
    _bindHostSources();
    _syncRuntime(initial: true);
  }

  @override
  void didUpdateWidget(covariant VibeRuntimeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _detachHostSources?.call();
      _detachHostSources = null;
      _bindHostSources();
    }
    final entryChanged = oldWidget.entry.id != widget.entry.id ||
        oldWidget.entry.effectiveRuntime != widget.entry.effectiveRuntime ||
        oldWidget.entry.miniProgram != widget.entry.miniProgram ||
        oldWidget.entry.source != widget.entry.source ||
        oldWidget.entry.wasmBase64 != widget.entry.wasmBase64 ||
        oldWidget.entry.jsGlue != widget.entry.jsGlue ||
        oldWidget.entry.trusted != widget.entry.trusted ||
        oldWidget.entry.vibe != widget.entry.vibe ||
        oldWidget.entry.canvas != widget.entry.canvas ||
        jsonEncode(oldWidget.entry.template) !=
            jsonEncode(widget.entry.template) ||
        jsonEncode(oldWidget.entry.initialData) !=
            jsonEncode(widget.entry.initialData) ||
        jsonEncode(oldWidget.entry.view) != jsonEncode(widget.entry.view) ||
        jsonEncode(oldWidget.entry.dataModel) !=
            jsonEncode(widget.entry.dataModel) ||
        jsonEncode(oldWidget.entry.effectiveNeeds) !=
            jsonEncode(widget.entry.effectiveNeeds) ||
        jsonEncode(oldWidget.entry.args) != jsonEncode(widget.entry.args);

    final contextChanged = oldWidget.triggerContext != widget.triggerContext;
    if (entryChanged || oldWidget.host != widget.host) {
      _syncRuntime(initial: false);
    } else if (contextChanged) {
      _onContextOnlyUpdated();
    }
  }

  void _bindHostSources() {
    final h = widget.host;
    if (h != null && widget.entry.effectiveNeeds.isNotEmpty) {
      _detachHostSources = h.onSourceChange(_onHostSourcesChanged);
    }
  }

  void _onHostSourcesChanged() {
    if (!mounted) return;
    if (widget.entry.effectiveRuntime == VibeRuntimeKind.js && _jsRun != null) {
      return; // VibeRunController already refreshes via host.notifySourceChange().
    }
    _refreshNeedsAndEvaluate(command: 'refresh');
  }

  void _onContextOnlyUpdated() {
    final rt = widget.entry.effectiveRuntime;
    if (_mpSession != null &&
        (rt == VibeRuntimeKind.miniProgram || rt == VibeRuntimeKind.vxml)) {
      try {
        _mpSession!.updateHostData(_needsData, widget.triggerContext);
        _runtimeError = null;
      } on Object catch (err) {
        _runtimeError = err.toString();
      }
      setState(() {});
      return;
    }
    if (rt == VibeRuntimeKind.dom || _isWasmDomMode()) {
      _pushDomUpdateIfChanged();
      setState(() {});
      return;
    }
    if (rt == VibeRuntimeKind.js && _jsRun != null) {
      _jsRun!.dispatch('refresh', _mergedJsArgs());
      return;
    }
    _refreshNeedsAndEvaluate(command: 'refresh');
  }

  Map<String, Object?> _mergedJsArgs() {
    return <String, Object?>{
      if (widget.entry.args != null) ...widget.entry.args!,
      'context': widget.triggerContext.toJson(),
    };
  }

  bool _isWasmDomMode() {
    if (widget.entry.effectiveRuntime != VibeRuntimeKind.wasm) return false;
    final html = widget.entry.source ?? widget.entry.canvas?.content ?? '';
    return html.trimLeft().startsWith('<');
  }

  void _syncRuntime({required bool initial}) {
    _disposeJsRun();
    _disposeMiniProgram();
    _detachHostSources?.call();
    _detachHostSources = null;
    _bindHostSources();
    _runtimeError = null;

    final rt = widget.entry.effectiveRuntime;
    if (rt == VibeRuntimeKind.js) {
      final spec = widget.entry.effectiveJsVibe;
      if (spec != null && widget.host != null) {
        final ctrl = widget.host!.mount(
          spec,
          dataMode: _effectiveDataMode,
          args: _mergedJsArgs(),
        );
        _jsRun = ctrl;
        _detachJsRun = ctrl.onUpdate(() {
          if (mounted) setState(() {});
        });
        return;
      }
    }
    _refreshNeedsAndEvaluate(command: initial ? 'open' : 'refresh');
  }

  void _refreshNeedsAndEvaluate({required String command}) {
    final gen = ++_evalGen;
    final needs = widget.entry.effectiveNeeds;
    final host = widget.host;
    if (host == null || needs.isEmpty) {
      _applyNeedsData(const <String, Object?>{}, command: command, gen: gen);
      return;
    }
    final res = host.readCapabilities(needs, dataMode: _effectiveDataMode);
    if (res is Future<Map<String, Object?>>) {
      unawaited(
        res.then((data) {
          if (mounted && gen == _evalGen) {
            _applyNeedsData(data, command: command, gen: gen);
          }
        }),
      );
    } else {
      _applyNeedsData(res, command: command, gen: gen);
    }
  }

  void _applyNeedsData(
    Map<String, Object?> data, {
    required String command,
    required int gen,
    Map<String, Object?>? actionArgs,
  }) {
    _needsData = data;
    final rt = widget.entry.effectiveRuntime;

    if (rt == VibeRuntimeKind.miniProgram || rt == VibeRuntimeKind.vxml) {
      _syncOrUpdateMiniProgram(data);
      return;
    }

    if (rt == VibeRuntimeKind.dom || _isWasmDomMode()) {
      _ensureStableDomPayload();
      _pushDomUpdateIfChanged();
      if (mounted) setState(() {});
      return;
    }

    if (rt == VibeRuntimeKind.wasm) {
      _evaluateWasmGuest(command: command, actionArgs: actionArgs, gen: gen);
      return;
    }

    if (rt == VibeRuntimeKind.js && _jsRun == null) {
      _evaluateStandaloneJs(command: command, actionArgs: actionArgs);
      return;
    }

    if (mounted) setState(() {});
  }

  void _ensureStableDomPayload() {
    final entry = widget.entry;
    final rawHtml = entry.source ?? entry.canvas?.content ?? '';
    final wasmB64 = entry.wasmBase64 ?? entry.canvas?.wasmBase64;
    final glue = entry.jsGlue ?? entry.canvas?.jsGlue;
    final sig = '${entry.id}::$rawHtml::${wasmB64 ?? ''}::${glue ?? ''}';
    if (_cachedDomSignature == sig && _cachedDomPayload != null) {
      return;
    }
    try {
      final docHtml = buildVibeSpaceDomHtml(
        vibeId: entry.id,
        htmlContent: rawHtml,
        needs: entry.effectiveNeeds,
        initialData: _needsData,
        initialContext: widget.triggerContext,
        wasmBase64: wasmB64,
        jsGlue: glue,
      );
      _cachedDomSignature = sig;
      _cachedDomPayload = VibeCanvasPayload(
        canvasId: entry.canvas?.canvasId ?? 'vibe-${entry.id}',
        taskId: entry.canvas?.taskId ?? '',
        title: entry.title,
        format: (wasmB64 != null && wasmB64.trim().isNotEmpty)
            ? VibeCanvasFormat.wasm
            : VibeCanvasFormat.html,
        content: docHtml,
        wasmBase64: wasmB64,
        jsGlue: glue,
        when: entry.condition,
      );
      _lastPushedDomStateJson = null;
      _runtimeError = null;
    } on Object catch (err) {
      _runtimeError = err.toString();
    }
  }

  void _pushDomUpdateIfChanged() {
    final stateSnapshot = jsonEncode(<String, Object?>{
      'data': _needsData,
      'context': widget.triggerContext.toJson(),
    });
    if (_lastPushedDomStateJson == stateSnapshot) return;
    _lastPushedDomStateJson = stateSnapshot;
    final msg = VibeDomDataModelMessage(
      vibeId: widget.entry.id,
      data: _needsData,
      context: widget.triggerContext,
      timestampMs: widget.triggerContext.timestampMs > 0
          ? widget.triggerContext.timestampMs
          : DateTime.now().millisecondsSinceEpoch,
    );
    widget.domBridge?.push(msg);
    widget.onDomDataPush?.call(msg);
  }

  void _evaluateWasmGuest({
    required String command,
    Map<String, Object?>? actionArgs,
    required int gen,
  }) {
    final wb64 = widget.entry.wasmBase64 ?? widget.entry.canvas?.wasmBase64;
    if (wb64 == null || wb64.trim().isEmpty) {
      _runtimeError = 'Missing wasmBase64 module';
      if (mounted) setState(() {});
      return;
    }
    try {
      final bytes = Uint8List.fromList(base64Decode(wb64.trim()));
      final input = <String, Object?>{
        'command': command,
        'args': actionArgs ?? widget.entry.args,
        'state': _wasmState,
        'data': _needsData,
        'context': widget.triggerContext.toJson(),
      };
      final mergedModel = _mergedDeclarativeDataModel();
      final res = VibeWasmEvaluator.evaluate(
        bytes,
        input,
        customRunner: widget.host?.wasmRunner,
        dataModel: mergedModel,
      );
      if (res is Future<Map<String, Object?>>) {
        unawaited(
          res.then(
            (out) {
              if (!mounted || gen != _evalGen) return;
              setState(() {
                _wasmState = out['state'];
                _wasmView = out['view'] as Map<String, Object?>?;
                _runtimeError = null;
              });
            },
            onError: (Object err) {
              if (!mounted || gen != _evalGen) return;
              setState(() => _runtimeError = err.toString());
            },
          ),
        );
      } else {
        _wasmState = res['state'];
        _wasmView = res['view'] as Map<String, Object?>?;
        _runtimeError = null;
        if (mounted) setState(() {});
      }
    } on Object catch (err) {
      _runtimeError = err.toString();
      if (mounted) setState(() {});
    }
  }

  void _evaluateStandaloneJs({
    required String command,
    Map<String, Object?>? actionArgs,
  }) {
    final spec = widget.entry.effectiveJsVibe;
    if (spec == null) return;
    try {
      final res = VibeSandboxEvaluator.evaluate(spec, <String, Object?>{
        'command': command,
        'args': actionArgs ?? _mergedJsArgs(),
        'state': _wasmState,
        'data': _needsData,
        'context': widget.triggerContext.toJson(),
        'now': DateTime.now().millisecondsSinceEpoch,
      });
      if (res is Map<String, Object?>) {
        _wasmState = res['state'];
        _wasmView = res['view'] as Map<String, Object?>?;
        _runtimeError = null;
      }
    } on Object catch (err) {
      _runtimeError = err.toString();
    }
    if (mounted) setState(() {});
  }

  Map<String, Object?> _mergedDeclarativeDataModel() {
    return <String, Object?>{
      if (widget.entry.dataModel != null) ...widget.entry.dataModel!,
      ..._needsData,
      'context': widget.triggerContext.toJson(),
    };
  }

  void _syncOrUpdateMiniProgram(Map<String, Object?> data) {
    try {
      if (_mpSession == null) {
        final def = widget.entry.effectiveMiniProgram;
        if (def == null) {
          _runtimeError = 'Missing miniProgram definition or template';
          if (mounted) setState(() {});
          return;
        }
        final wb64 = widget.entry.wasmBase64 ?? widget.entry.canvas?.wasmBase64;
        final wasmBytes = (wb64 != null && wb64.trim().isNotEmpty)
            ? Uint8List.fromList(base64Decode(wb64.trim()))
            : null;
        final session = VibeMiniProgramSession(
          definition: def,
          template: widget.entry.template ?? def.template,
          wasmBytes: wasmBytes,
        );
        session.load(hostData: data, context: widget.triggerContext);
        _mpSession = session;
      } else {
        _mpSession!.updateHostData(data, widget.triggerContext);
      }
      _runtimeError = null;
    } on Object catch (err) {
      _runtimeError = err.toString();
    }
    if (mounted) setState(() {});
  }

  void _disposeMiniProgram() {
    if (_mpSession != null) {
      try {
        _mpSession!.hide();
      } on Object {
        // Ignore teardown hook errors on disposal.
      }
      _mpSession = null;
    }
  }

  void _disposeJsRun() {
    _detachJsRun?.call();
    _detachJsRun = null;
    _jsRun?.stop();
    _jsRun = null;
  }

  @override
  void dispose() {
    _detachHostSources?.call();
    _detachHostSources = null;
    _disposeJsRun();
    _disposeMiniProgram();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    if (_runtimeError != null) {
      return Text(
        _runtimeError!,
        style: TextStyle(fontSize: 12, color: t.danger),
      );
    }

    if (_mpSession != null) {
      try {
        final mpView = _mpSession!.buildView();
        if (mpView != null) {
          return VibeView(
            value: toVibeDynamicMap(mpView),
            resolveSealed: widget.host?.resolveSealed,
            adapter: widget.adapter,
            onCommand: (cmd, args) {
              final typedArgs = Map<String, Object?>.from(args);
              final mpEvent = VibeMiniProgramEvent.tryFromCommand(
                cmd,
                typedArgs,
              );
              if (mpEvent != null) {
                try {
                  _mpSession?.dispatchEvent(mpEvent);
                  _runtimeError = null;
                } on Object catch (err) {
                  _runtimeError = err.toString();
                }
                if (mounted) setState(() {});
              }
              widget.onCommand?.call(cmd, args);
            },
          );
        }
      } on Object catch (err) {
        return Text(
          err.toString(),
          style: TextStyle(fontSize: 12, color: t.danger),
        );
      }
    }

    if (_jsRun != null) {
      final view = _jsRun!.view;
      if (view != null) {
        return VibeView(
          value: toVibeDynamicMap(view),
          resolveSealed: widget.host?.resolveSealed,
          adapter: widget.adapter,
          onCommand: (cmd, args) {
            _jsRun!.dispatch(cmd, Map<String, Object?>.from(args));
            widget.onCommand?.call(cmd, args);
          },
        );
      }
      final err = _jsRun!.lastError ?? _jsRun!.unavailableReason;
      return Text(
        err ?? 'Evaluating vibe…',
        style: TextStyle(fontSize: 12, color: t.mutedText),
      );
    }

    final rt = widget.entry.effectiveRuntime;

    if (rt == VibeRuntimeKind.dom || _isWasmDomMode()) {
      final payload = _cachedDomPayload;
      if (payload != null) {
        if (widget.webViewportBuilder != null) {
          return widget.webViewportBuilder!(
            context,
            payload,
            widget.onCanvasAction,
          );
        }
        return SizedBox(
          key: ValueKey<String>('vibe-dom-viewport-${widget.entry.id}'),
          height: 200,
          child: VibeCanvasView(
            payload: payload,
            onAction: widget.onCanvasAction,
            adapter: widget.adapter,
          ),
        );
      }
    }

    if ((rt == VibeRuntimeKind.wasm || rt == VibeRuntimeKind.js) &&
        _wasmView != null) {
      return VibeView(
        value: toVibeDynamicMap(_wasmView!),
        resolveSealed: widget.host?.resolveSealed,
        adapter: widget.adapter,
        onCommand: (cmd, args) {
          final typedArgs = Map<String, Object?>.from(args);
          _applyNeedsData(
            _needsData,
            command: cmd,
            gen: ++_evalGen,
            actionArgs: typedArgs,
          );
          widget.onCommand?.call(cmd, args);
        },
      );
    }

    final mergedModel = _mergedDeclarativeDataModel();
    final hydratedCanvas = widget.entry.hydratedCanvas(widget.triggerContext);
    if (hydratedCanvas != null) {
      if (hydratedCanvas.format == VibeCanvasFormat.markdown) {
        if (widget.markdownBuilder != null) {
          return widget.markdownBuilder!(context, hydratedCanvas);
        }
        final adapted = VibeUiCompatibilityAdapter.tryAdapt(
          hydratedCanvas.content,
          dataModel: mergedModel,
        );
        if (adapted != null) {
          return _buildAdaptedView(adapted, canvas: hydratedCanvas);
        }
      } else if (hydratedCanvas.format == VibeCanvasFormat.vibeUi) {
        final rawDecoded = hydratedCanvas.tryDecodeVibeUi();
        final adapted = rawDecoded != null
            ? VibeUiCompatibilityAdapter.tryAdapt(
                rawDecoded,
                dataModel: mergedModel,
              )
            : null;
        if (adapted != null) {
          return _buildAdaptedView(adapted, canvas: hydratedCanvas);
        }
      }
    }

    if (rt == VibeRuntimeKind.markdown && widget.entry.source != null) {
      final hydratedMd = hydrateVibeTemplateString(
        widget.entry.source!,
        widget.triggerContext,
      );
      final mdCanvas = VibeCanvasPayload(
        canvasId: 'vibe-${widget.entry.id}',
        title: widget.entry.title,
        format: VibeCanvasFormat.markdown,
        content: hydratedMd,
      );
      if (widget.markdownBuilder != null) {
        return widget.markdownBuilder!(context, mdCanvas);
      }
      final adapted = VibeUiCompatibilityAdapter.tryAdapt(
        hydratedMd,
        dataModel: mergedModel,
      );
      if (adapted != null) return _buildAdaptedView(adapted);
    }

    final hydratedView = widget.entry.hydratedView(widget.triggerContext);
    if (hydratedView != null) {
      final adapted = VibeUiCompatibilityAdapter.tryAdapt(
        hydratedView,
        dataModel: mergedModel,
      );
      if (adapted != null) return _buildAdaptedView(adapted);
    }

    return Text(
      widget.entry.subtitle.isNotEmpty
          ? widget.entry.subtitle
          : 'Triggered Vibe view active',
      style: TextStyle(fontSize: 12, color: t.mutedText),
    );
  }

  Widget _buildAdaptedView(
    Map<String, Object?> adapted, {
    VibeCanvasPayload? canvas,
  }) {
    return VibeView(
      value: toVibeDynamicMap(adapted),
      resolveSealed: widget.host?.resolveSealed,
      adapter: widget.adapter,
      onCommand: (cmd, args) {
        widget.onCommand?.call(cmd, args);
        if (canvas != null) {
          widget.onCanvasAction?.call(
            VibeCanvasActionEvent(
              canvasId: canvas.canvasId,
              taskId: canvas.taskId,
              actionName: cmd,
              arguments: Map<String, Object?>.from(args),
            ),
          );
        }
      },
    );
  }
}

/// Converts a generic [Map] into a recursively typed `Map<String, dynamic>` for `VibeView`.
Map<String, dynamic> toVibeDynamicMap(Map<dynamic, dynamic> raw) {
  final out = <String, dynamic>{};
  for (final entry in raw.entries) {
    out[entry.key.toString()] = _toVibeDynamicValue(entry.value);
  }
  return out;
}

Object? _toVibeDynamicValue(Object? raw) {
  if (raw is Map) return toVibeDynamicMap(raw);
  if (raw is List) {
    return <dynamic>[for (final item in raw) _toVibeDynamicValue(item)];
  }
  return raw;
}
