import 'dart:async';
import 'dart:convert';

import 'host.dart';
import 'mcp_tool_catalog.dart';

/// Rendering tier supported by Vibe Canvas (`vibe.canvas` / `client.canvas.render`).
enum VibeCanvasFormat {
  /// Rich Markdown document (with optional Mermaid diagrams and syntax highlighting).
  markdown('markdown', 'Markdown & Mermaid'),

  /// Declarative native Flutter UI (`VibeView` JSON schema).
  vibeUi('vibe_ui', 'Vibe Declarative UI'),

  /// Sandboxed HTML / CSS / JavaScript inside an isolated viewport.
  html('html', 'Sandboxed HTML'),

  /// Sandboxed WebAssembly module (`wasmBase64` + `jsGlue` / Vibe Wasm mini-app).
  wasm('wasm', 'Vibe Wasm Mini-App');

  const VibeCanvasFormat(this.id, this.label);

  final String id;
  final String label;

  static VibeCanvasFormat fromId(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in VibeCanvasFormat.values) {
      if (value.id == normalized) return value;
    }
    return VibeCanvasFormat.markdown;
  }
}

/// Host placement requested for a [VibeCanvasPayload].
enum VibeCanvasLayout {
  splitRight('split_right', 'Split Right'),
  tab('tab', 'Workspace Tab'),
  modal('modal', 'Modal Sheet');

  const VibeCanvasLayout(this.id, this.label);

  final String id;
  final String label;

  static VibeCanvasLayout fromId(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in VibeCanvasLayout.values) {
      if (value.id == normalized) return value;
    }
    return VibeCanvasLayout.splitRight;
  }
}

/// Structured payload for Vibe Canvas (`vibe.canvas` host API & AI MCP skill).
class VibeCanvasPayload {
  const VibeCanvasPayload({
    required this.canvasId,
    this.taskId = '',
    required this.title,
    required this.format,
    required this.content,
    this.wasmBase64,
    this.jsGlue,
    this.layout = VibeCanvasLayout.splitRight,
    this.updatedAtIso = '',
  });

  factory VibeCanvasPayload.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final contentString = rawContent is String
        ? rawContent
        : (rawContent is Map || rawContent is List)
            ? jsonEncode(rawContent)
            : (rawContent?.toString() ?? '');
    return VibeCanvasPayload(
      canvasId: json['canvasId']?.toString().trim().isNotEmpty == true
          ? json['canvasId']!.toString().trim()
          : (json['canvas_id']?.toString().trim().isNotEmpty == true
              ? json['canvas_id']!.toString().trim()
              : 'canvas-default'),
      taskId: json['taskId']?.toString().trim().isNotEmpty == true
          ? json['taskId']!.toString().trim()
          : (json['task_id']?.toString().trim() ?? ''),
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title']!.toString().trim()
          : 'Vibe Canvas',
      format: VibeCanvasFormat.fromId(json['format']?.toString()),
      content: contentString,
      wasmBase64: _optionalString(json['wasmBase64'] ?? json['wasm_base64']),
      jsGlue: _optionalString(json['jsGlue'] ?? json['js_glue']),
      layout: VibeCanvasLayout.fromId(json['layout']?.toString()),
      updatedAtIso: json['updatedAtIso']?.toString().trim().isNotEmpty == true
          ? json['updatedAtIso']!.toString().trim()
          : (json['updated_at_iso']?.toString().trim() ?? ''),
    );
  }

  final String canvasId;
  final String taskId;
  final String title;
  final VibeCanvasFormat format;
  final String content;
  final String? wasmBase64;
  final String? jsGlue;
  final VibeCanvasLayout layout;
  final String updatedAtIso;

  /// Parses [content] as a declarative `VibeView` JSON map when [format] is [VibeCanvasFormat.vibeUi].
  Map<String, dynamic>? tryDecodeVibeUi() {
    if (format != VibeCanvasFormat.vibeUi) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map<String, dynamic>((k, v) => MapEntry('$k', v));
      }
    } on Object {
      return null;
    }
    return null;
  }

  VibeCanvasPayload copyWith({
    String? canvasId,
    String? taskId,
    String? title,
    VibeCanvasFormat? format,
    String? content,
    String? wasmBase64,
    String? jsGlue,
    VibeCanvasLayout? layout,
    String? updatedAtIso,
  }) {
    return VibeCanvasPayload(
      canvasId: canvasId ?? this.canvasId,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      format: format ?? this.format,
      content: content ?? this.content,
      wasmBase64: wasmBase64 ?? this.wasmBase64,
      jsGlue: jsGlue ?? this.jsGlue,
      layout: layout ?? this.layout,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'canvasId': canvasId,
        'taskId': taskId,
        'title': title,
        'format': format.id,
        'content': content,
        if (wasmBase64 != null) 'wasmBase64': wasmBase64,
        if (jsGlue != null) 'jsGlue': jsGlue,
        'layout': layout.id,
        'updatedAtIso': updatedAtIso,
      };

  static String? _optionalString(Object? raw) {
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}

/// Action emitted back from an interactive [VibeCanvasPayload] (`VibeView` button
/// or HTML/WASM `window.vibeCanvas.sendAction(...)` bridge) to the host or AI task.
class VibeCanvasActionEvent {
  const VibeCanvasActionEvent({
    required this.canvasId,
    this.taskId = '',
    required this.actionName,
    this.arguments = const <String, Object?>{},
  });

  final String canvasId;
  final String taskId;
  final String actionName;
  final Map<String, Object?> arguments;
}

/// Read-only MCP query emitted from an interactive [VibeCanvasPayload]
/// (`window.vibeCanvas.callMcp(...)` / `window.vibeCanvas.execReadOnly(...)`).
class VibeCanvasMcpReadRequest {
  const VibeCanvasMcpReadRequest({
    required this.requestId,
    required this.canvasId,
    this.taskId = '',
    required this.toolName,
    this.arguments = const <String, Object?>{},
  });

  final String requestId;
  final String canvasId;
  final String taskId;
  final String toolName;
  final Map<String, Object?> arguments;
}

/// Response returned to a [VibeCanvasMcpReadRequest] inside a Vibe Canvas.
class VibeCanvasMcpReadResponse {
  const VibeCanvasMcpReadResponse({
    required this.requestId,
    required this.ok,
    this.data = const <String, Object?>{},
    this.error,
  });

  final String requestId;
  final bool ok;
  final Map<String, Object?> data;
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
        'requestId': requestId,
        'ok': ok,
        'data': data,
        if (error != null) 'error': error,
      };
}

/// Callback that executes a validated read-only MCP query on behalf of a Vibe Canvas.
typedef VibeCanvasMcpReadHandler = Future<VibeCanvasMcpReadResponse> Function(
  VibeCanvasMcpReadRequest request,
);

/// Allowed read-only MCP tools callable from inside a Vibe Canvas object,
/// including canonical ChatGPT/Claude MCP tool names and backward-compatible aliases.
const Set<String> kAllowedReadOnlyCanvasMcpTools = <String>{
  'host_process_list',
  'runner_info',
  'runner_ping',
  'runner_usage',
  'server.network.sockets',
  'ssh_resource',
  'server.telemetry.snapshot',
  'server.process.inspect',
  'mcp.ssh.exec_readonly',
  'mcp.server.metrics',
  'mcp.server.network_bandwidth',
  'mcp.server.processes',
  'client.canvas.read_metrics',
  'list_devices',
  'list_runners',
  'list_projects',
  'runtime_status',
  'list_tools',
  'tool_manifest',
  'project_overview',
  'list_project_files',
  'read_files',
  'search_project_texts',
  'git_status',
  'git_diff_hunks',
  'git_log',
  'list_jobs',
  'observe_jobs',
  'job_tail',
  'session_shell_status',
};

/// Returns `true` if [toolName] is on the strict read-only MCP allowlist
/// evaluated by [VibeMcpToolCatalog] under [condition] (defaults to
/// [VibeMcpSelectionCondition.canvasReadOnly]).
bool isReadOnlyCanvasMcpTool(
  String toolName, {
  VibeMcpSelectionCondition? condition,
}) {
  return VibeMcpToolCatalog.instance.isAllowed(
    toolName,
    condition: condition ?? VibeMcpSelectionCondition.canvasReadOnly(),
  );
}

/// Validates that [command] is strictly read-only and safe to execute via MCP
/// from a live Vibe Canvas component.
bool isReadOnlyCanvasShellCommand(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty || trimmed.length > 2000) return false;

  // Reject output redirection, subshell mutation, or backgrounding
  if (RegExp(r'(?:^|[^0-9])>>?|<\(|`\s*rm\b|\$\(\s*rm\b').hasMatch(trimmed)) {
    return false;
  }

  // Reject mutating/destructive binaries or subcommands
  final forbiddenPattern = RegExp(
    r'(?:^|[;&|\s])('
    r'rm|mv|cp|dd|mkfs|fdisk|parted|mount|umount|chmod|chown|chgrp|'
    r'kill|pkill|killall|reboot|shutdown|poweroff|halt|init|'
    r'sudo|su|useradd|usermod|userdel|groupadd|passwd|visudo|'
    r'apt|apt-get|dpkg|yum|dnf|apk|pacman|snap|flatpak|brew|'
    r'pip|pip3|npm|pnpm|yarn|cargo|'
    r'tee|truncate|shred|unlink|mkdir|rmdir|touch|ln|'
    r'iptables|ip6tables|ufw|nft|firewall-cmd|'
    r'crontab|at|nc|netcat|socat|curl\s+-[^\n]*?(?:-X|--request|-d|--data|--upload-file)|'
    r'wget\s+|--post-data|--post-file|'
    r'systemctl\s+(?:start|stop|restart|reload|enable|disable|mask|unmask|daemon-reload|kill|reset-failed)|'
    r'service\s+\S+\s+(?:start|stop|restart|reload)|'
    r'docker\s+(?:run|exec|rm|rmi|stop|start|restart|kill|build|pull|push|compose)|'
    r'git\s+(?:push|commit|reset|clean|checkout|merge|rebase|cherry-pick|tag|branch\s+-[dD])'
    r')(?:\s|$)',
    caseSensitive: false,
  );
  if (forbiddenPattern.hasMatch(trimmed)) {
    return false;
  }
  return true;
}

/// JSON Schema for the `vibe.canvas` v1 host API input.
const JsonMap vibeCanvasInputSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['title', 'format', 'content'],
  'properties': <String, dynamic>{
    'canvasId': <String, dynamic>{
      'type': 'string',
      'minLength': 1,
      'maxLength': 128,
      'description': 'Stable canvas identifier for in-place updates.',
    },
    'taskId': <String, dynamic>{
      'type': 'string',
      'maxLength': 128,
      'description': 'Optional owning AI task or mini-app session ID.',
    },
    'title': <String, dynamic>{
      'type': 'string',
      'minLength': 1,
      'maxLength': 256,
      'description': 'Human-readable canvas title.',
    },
    'format': <String, dynamic>{
      'type': 'string',
      'enum': <String>['markdown', 'vibe_ui', 'html', 'wasm'],
      'description': 'Canvas rendering format.',
    },
    'content': <String, dynamic>{
      'type': 'string',
      'maxLength': 64000,
      'description':
          'Markdown source, VibeView JSON string, HTML document, or Wasm shell HTML.',
    },
    'wasmBase64': <String, dynamic>{
      'type': 'string',
      'maxLength': 64000,
      'description': 'Optional base64-encoded WebAssembly module.',
    },
    'jsGlue': <String, dynamic>{
      'type': 'string',
      'maxLength': 64000,
      'description': 'Optional JavaScript bootstrap for Wasm format.',
    },
    'layout': <String, dynamic>{
      'type': 'string',
      'enum': <String>['split_right', 'tab', 'modal'],
      'description': 'Preferred host placement for the canvas.',
    },
  },
};

/// JSON Schema for the `vibe.canvas` v1 host API output.
const JsonMap vibeCanvasOutputSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['rendered', 'canvasId'],
  'properties': <String, dynamic>{
    'rendered': <String, dynamic>{'type': 'boolean'},
    'canvasId': <String, dynamic>{'type': 'string', 'maxLength': 128},
  },
};

/// Creates the standard `vibe.canvas` v1 [VibeHostApi] so any Vibe Space host
/// application can let Wasm mini-apps and AI agents render interactive canvases.
VibeHostApi createVibeCanvasHostApi({
  required FutureOr<bool> Function(
    VibeCanvasPayload payload,
    VibeCallContext context,
  ) onRender,
  bool readOnly = false,
}) {
  return VibeHostApi(
    name: 'vibe.canvas',
    version: 1,
    title: 'Render interactive Vibe Canvas',
    description:
        'Open or update an interactive Vibe Canvas with Markdown, VibeView declarative UI, sandboxed HTML, or WebAssembly.',
    inputSchema: vibeCanvasInputSchema,
    outputSchema: vibeCanvasOutputSchema,
    readOnly: readOnly,
    handler: (input, context) async {
      await context.check();
      final payload = VibeCanvasPayload.fromJson(input).copyWith(
        taskId: (input['taskId'] as String?)?.trim().isNotEmpty == true
            ? (input['taskId'] as String).trim()
            : context.pluginId,
        updatedAtIso: DateTime.now().toUtc().toIso8601String(),
      );
      final rendered = await onRender(payload, context);
      return <String, dynamic>{
        'rendered': rendered,
        'canvasId': payload.canvasId,
      };
    },
  );
}
