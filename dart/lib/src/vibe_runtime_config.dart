import 'dart:convert';
import 'dart:math';

import 'vibe_trigger_condition.dart';
import 'vibe_wasm_evaluator.dart';

export 'vibe_wasm_evaluator.dart';

/// Maximum UTF-8 byte length for a `setData` incremental patch (64 KiB).
const int kMaxVibeSetDataBytes = 64 * 1024;

/// Maximum `setData` mutations per second per Mini Program instance.
const int kMaxVibeSetDataRatePerSec = 30;

/// Maximum vector draw commands per `canvas` frame (`<= 2,000`).
const int kMaxVibeCanvasCommands = 2000;

/// Maximum UTF-8 byte length for a `dom` / `html` or `jsGlue` source payload (512 KiB).
const int kMaxVibeDomSourceBytes = 512 * 1024;

/// Maximum byte length for a `wasm` binary module (16 MiB).
const int kMaxVibeWasmBytes = 16 * 1024 * 1024;

/// Maximum linear memory byte length for a sandboxed `wasm` guest (32 MiB).
const int kMaxVibeWasmMemoryBytes = 32 * 1024 * 1024;

/// Maximum instruction steps per synchronous Wasm guest invocation.
const int kMaxVibeWasmFuel = 100000;

/// Strict zero-exfiltration Content-Security-Policy for Vibe-Space DOM viewports.
const String kVibeZeroExfilCsp = "default-src 'none'; "
    "script-src 'unsafe-inline' 'wasm-unsafe-eval' blob:; "
    "style-src 'unsafe-inline'; "
    "img-src data: blob:; "
    "font-src data:; "
    "media-src 'none'; "
    "connect-src 'none'; "
    "form-action 'none'; "
    "frame-src 'none'; "
    "child-src blob:; "
    "worker-src blob:; "
    "object-src 'none'; "
    "base-uri 'none';";

final Random _runtimeRandom = Random.secure();

String _randomActionToken() {
  final buf = StringBuffer();
  for (var i = 0; i < 24; i++) {
    buf.write(_runtimeRandom.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// Runtime kinds supported inside a standardized Vibe-Space conditional config
/// envelope (`id`, `name`, `enabled`, `isPreset`, `needs`, `when`).
///
/// The primary Skyline Native architecture uses [miniProgram] (WeChat Dual-Layer
/// `AppService` logic + `setData` + `VXML` template + native Skia `canvas`),
/// [vxml] (data-bound Skyline template), [wasm], [js], [a2ui], [vibeUi], and
/// [markdown] — zero iframes/WebViews!
enum VibeRuntimeKind {
  /// WeChat Mini Program Dual-Layer (`defineMiniProgram` + `setData` + `VXML`
  /// template rendered natively via Skyline Flutter widgets & Skia `CustomPaint`).
  miniProgram('miniprogram'),

  /// Declarative Skyline `VXML` template (`{{path}}`, `if`/`v-if`, `for`/`v-for`,
  /// `style` tokens, and native `canvas` 2D draw-lists).
  vxml('vxml'),

  /// WebAssembly (`wasm32`) guest using the `vibe_alloc` / `vibe_invoke` ABI.
  wasm('wasm'),

  /// Air-gapped JavaScript `function invoke(input)` worker script.
  js('js'),

  /// Declarative Google A2UI (`surfaceUpdate` + `dataModelUpdate`).
  a2ui('a2ui'),

  /// Declarative canonical `VibeView` JSON.
  vibeUi('vibe_ui'),

  /// Declarative Markdown / Mermaid document.
  markdown('markdown'),

  /// Opt-in HTML/DOM viewport (`window.vibeSpace` + `vibe:dataModelUpdate`).
  dom('dom');

  const VibeRuntimeKind(this.wireName);

  final String wireName;

  /// True when this runtime executes imperative guest logic (`miniprogram`, `wasm`, `js`, `dom`).
  bool get isExecutable =>
      this == VibeRuntimeKind.miniProgram ||
      this == VibeRuntimeKind.wasm ||
      this == VibeRuntimeKind.js ||
      this == VibeRuntimeKind.dom;

  /// True when rendered natively on the Skyline Flutter tree without any WebView/iframe.
  bool get isSkylineNative => this != VibeRuntimeKind.dom;

  static VibeRuntimeKind? tryFromWireName(String? raw) {
    final norm = raw?.trim().toLowerCase();
    return switch (norm) {
      'miniprogram' ||
      'mini_program' ||
      'wechat' =>
        VibeRuntimeKind.miniProgram,
      'vxml' || 'template' || 'wxml' => VibeRuntimeKind.vxml,
      'wasm' || 'webassembly' => VibeRuntimeKind.wasm,
      'js' || 'javascript' => VibeRuntimeKind.js,
      'a2ui' => VibeRuntimeKind.a2ui,
      'vibe_ui' || 'vibeui' => VibeRuntimeKind.vibeUi,
      'markdown' || 'md' => VibeRuntimeKind.markdown,
      'dom' || 'html' => VibeRuntimeKind.dom,
      _ => null,
    };
  }

  static VibeRuntimeKind fromWireName(String? raw) =>
      tryFromWireName(raw) ?? VibeRuntimeKind.vibeUi;
}

/// Encodes [value] as JSON safe for embedding inside an inline `<script>` tag,
/// neutralizing `</script>`, `<!--`, and Unicode line-terminator breakouts.
String escapeJsonForHtmlScript(Object? value) {
  return jsonEncode(value)
      .replaceAll('&', r'\u0026')
      .replaceAll('<', r'\u003c')
      .replaceAll('>', r'\u003e')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
}

/// Validates DOM/HTML or JS glue source size bounds (`<= 512 KiB`).
void validateVibeDomSource(String source, {String label = 'DOM source'}) {
  final byteLen = utf8.encode(source).length;
  if (byteLen > kMaxVibeDomSourceBytes) {
    throw FormatException(
      '$label exceeds ${kMaxVibeDomSourceBytes ~/ 1024} KiB limit ($byteLen bytes)',
    );
  }
}

/// Live data-push envelope sent to active `dom` / `html` viewports via
/// `postMessage` whenever declared `needs` capabilities or [context] update.
class VibeDomDataModelMessage {
  const VibeDomDataModelMessage({
    required this.vibeId,
    required this.data,
    required this.context,
    this.timestampMs = 0,
  });

  final String vibeId;
  final Map<String, Object?> data;
  final VibeTriggerContext context;
  final int timestampMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'vibe:dataModelUpdate',
        'vibeId': vibeId,
        'data': data,
        'context': context.toJson(),
        if (timestampMs > 0) 'timestampMs': timestampMs,
      };
}

/// Builds a sandboxed HTML document for an opt-in `dom` Vibe-Space view with
/// zero-exfiltration CSP (`connect-src 'none'`, `frame-src 'none'`), popup/WebRTC
/// neutralization, and live `window.vibeSpace` data-push bridge.
String buildVibeSpaceDomHtml({
  required String vibeId,
  required String htmlContent,
  List<String> needs = const <String>[],
  Map<String, Object?> initialData = const <String, Object?>{},
  VibeTriggerContext initialContext = const VibeTriggerContext(),
  String? wasmBase64,
  String? jsGlue,
  String? actionToken,
}) {
  validateVibeDomSource(htmlContent, label: 'HTML source');
  final cleanGlue = jsGlue?.trim() ?? '';
  if (cleanGlue.isNotEmpty) {
    validateVibeDomSource(cleanGlue, label: 'JS glue');
  }
  if (cleanGlue.toLowerCase().contains('</script')) {
    throw const FormatException('JS glue must not contain </script>');
  }

  final cleanWasmB64 = wasmBase64?.trim() ?? '';
  if (cleanWasmB64.isNotEmpty) {
    validateVibeWasmBytes(base64Decode(cleanWasmB64));
  }

  final vibeIdJson = escapeJsonForHtmlScript(vibeId);
  final needsJson = escapeJsonForHtmlScript(needs);
  final dataJson = escapeJsonForHtmlScript(initialData);
  final ctxJson = escapeJsonForHtmlScript(initialContext.toJson());
  final tokenJson = escapeJsonForHtmlScript(
    (actionToken != null && actionToken.trim().isNotEmpty)
        ? actionToken.trim()
        : _randomActionToken(),
  );

  final wasmBootstrap = cleanWasmB64.isNotEmpty
      ? '''
<script>
(async function() {
  try {
    const b64 = ${escapeJsonForHtmlScript(cleanWasmB64)};
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const mod = await WebAssembly.instantiate(bytes, {});
    window.vibeWasmInstance = mod.instance;
    window.vibeWasmExports = mod.instance.exports;
    if (window.vibeSpace && typeof window.vibeSpace._notifyWasm === 'function') {
      window.vibeSpace._notifyWasm('open');
    }
    $cleanGlue
  } catch (err) {
    console.error('Vibe-Space Wasm bootstrap error:', err);
  }
})();
</script>'''
      : '';

  return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="$kVibeZeroExfilCsp">
<style>
  html, body {
    margin: 0;
    padding: 8px;
    background: transparent;
    color: #f1f5f9;
    font-family: system-ui, -apple-system, sans-serif;
    font-variant-numeric: tabular-nums;
  }
</style>
<script>
(function() {
  'use strict';
  const noopNull = function() { return null; };
  const noopVoid = function() { return undefined; };
  try { Object.defineProperty(window, 'open', { value: noopNull, writable: false, configurable: false }); } catch (_) { window.open = noopNull; }
  for (const fn of ['alert', 'confirm', 'prompt', 'print']) {
    try { Object.defineProperty(window, fn, { value: noopVoid, writable: false, configurable: false }); } catch (_) { window[fn] = noopVoid; }
  }
  for (const api of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'mozRTCPeerConnection', 'RTCDataChannel', 'SharedWorker', 'BroadcastChannel', 'EventSource']) {
    try { Object.defineProperty(window, api, { value: undefined, writable: false, configurable: false }); } catch (_) { try { delete window[api]; } catch (__) {} }
  }
  if (typeof navigator === 'object' && navigator) {
    try { Object.defineProperty(navigator, 'sendBeacon', { value: function() { return false; }, writable: false, configurable: false }); } catch (_) {}
    try { Object.defineProperty(navigator, 'serviceWorker', { get: function() { return undefined; }, configurable: false }); } catch (_) {}
  }

  const _vibeId = $vibeIdJson;
  const _actionToken = $tokenJson;
  const _needs = Object.freeze($needsJson);
  let _data = $dataJson;
  let _context = $ctxJson;
  const _subscribers = new Set();

  function invokeWasmGuest(command) {
    const e = window.vibeWasmExports;
    if (!e) return null;
    const alloc = e.vibe_alloc || e.leap_alloc || e.leapterm_alloc || e.omni_alloc;
    const invoke = e.vibe_invoke || e.leap_invoke || e.leapterm_invoke || e.omni_invoke;
    if (!e.memory || typeof alloc !== 'function' || typeof invoke !== 'function') return null;
    const payload = new TextEncoder().encode(JSON.stringify({ command: command || 'refresh', data: _data, context: _context }));
    const ptr = alloc(payload.length);
    new Uint8Array(e.memory.buffer, ptr, payload.length).set(payload);
    const packed = BigInt.asUintN(64, invoke(ptr, payload.length));
    const offset = Number(packed & 0xffffffffn);
    const length = Number(packed >> 32n);
    return JSON.parse(new TextDecoder('utf-8').decode(new Uint8Array(e.memory.buffer, offset, length)));
  }

  const vibeSpace = {
    vibeId: _vibeId,
    needs: _needs,
    get data() { return _data; },
    get context() { return _context; },
    onUpdate: function(cb) {
      if (typeof cb !== 'function') return function() {};
      _subscribers.add(cb);
      try { cb({ data: _data, context: _context }); } catch (_) {}
      return function() { _subscribers.delete(cb); };
    },
    subscribe: function(cb) { return this.onUpdate(cb); },
    sendAction: function(command, args) {
      const msg = {
        type: 'vibe:action',
        vibeId: _vibeId,
        actionToken: _actionToken,
        command: String(command || ''),
        arguments: (args && typeof args === 'object') ? args : {}
      };
      if (window.parent && window.parent !== window) {
        window.parent.postMessage(msg, '*');
      }
      return msg;
    },
    _notifyWasm: function(cmd) {
      const out = invokeWasmGuest(cmd);
      if (out) {
        window.dispatchEvent(new CustomEvent('vibe:wasmOutput', { detail: out }));
      }
    }
  };
  Object.freeze(vibeSpace);
  try { Object.defineProperty(window, 'vibeSpace', { value: vibeSpace, writable: false, configurable: false }); } catch (_) { window.vibeSpace = vibeSpace; }

  window.addEventListener('message', function(ev) {
    const msg = ev && ev.data;
    if (!msg || typeof msg !== 'object') return;
    if (msg.type === 'vibe:dataModelUpdate') {
      if (msg.vibeId && msg.vibeId !== _vibeId) return;
      if (msg.data && typeof msg.data === 'object') _data = msg.data;
      if (msg.context && typeof msg.context === 'object') _context = msg.context;
      const detail = { data: _data, context: _context };
      for (const cb of Array.from(_subscribers)) {
        try { cb(detail); } catch (_) {}
      }
      window.dispatchEvent(new CustomEvent('vibe:dataModelUpdate', { detail: detail }));
      vibeSpace._notifyWasm('refresh');
    }
  });
})();
</script>
</head>
<body>
$htmlContent
$wasmBootstrap
</body>
</html>''';
}
