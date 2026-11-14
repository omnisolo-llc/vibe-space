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

/// Returns `true` if [toolName] is permitted as a read-only MCP tool under
/// [allowedTools] or [catalog] (defaults to [VibeMcpToolCatalog.instance])
/// evaluated with [condition] (defaults to
/// [VibeMcpSelectionCondition.canvasReadOnly]).
bool isReadOnlyCanvasMcpTool(
  String toolName, {
  VibeMcpToolCatalog? catalog,
  Set<String>? allowedTools,
  VibeMcpSelectionCondition? condition,
}) {
  final targetCatalog = catalog ?? VibeMcpToolCatalog.instance;
  final effectiveCondition =
      condition ?? VibeMcpSelectionCondition.canvasReadOnly();
  final descriptor = targetCatalog.find(toolName);
  if (descriptor != null) {
    return effectiveCondition.allows(descriptor);
  }
  if (allowedTools != null) {
    final normalized = toolName.trim().toLowerCase();
    return allowedTools.any((t) => t.trim().toLowerCase() == normalized);
  }
  return false;
}

const Set<String> _kAllowedReadOnlySingleBinaries = <String>{
  'uname',
  'uptime',
  'hostname',
  'whoami',
  'id',
  'pwd',
  'date',
  'df',
  'free',
  'ps',
  'ls',
  'stat',
  'wc',
  'du',
  'cat',
  'head',
  'tail',
  'grep',
  'sort',
  'uniq',
  'cut',
  'lscpu',
  'lsblk',
  'lsof',
  'ss',
  'netstat',
  'vmstat',
  'iostat',
  'mpstat',
  'sar',
  'nproc',
  'arch',
  'lsmod',
  'lspci',
  'lsusb',
  'dmesg',
  'last',
  'w',
  'who',
  'groups',
};

final RegExp _kShellMetacharRegex = RegExp(r'[;&$`><()\\\n\r\x00]');
final RegExp _kSensitivePathRegex = RegExp(
  r'(?:^|[\s/\x27"=:])(?:'
  r'\.ssh|\.aws|\.gnupg|\.kube|\.docker|\.netrc|\.npmrc|\.pypirc|'
  r'\.git-credentials|\.env(?:\.[a-z0-9_-]+)?|'
  r'id_rsa(?:\.pub)?|id_ed25519(?:\.pub)?|id_ecdsa(?:\.pub)?|id_dsa(?:\.pub)?|'
  r'authorized_keys|known_hosts|shadow|gshadow|sudoers(?:\.d)?|master\.passwd|'
  r'environ|\.[a-z0-9_-]*_history|\.pgpass|\.my\.cnf|\.vault-token|'
  r'\.config/gh|\.config/gcloud|\.azure|\.terraform\.d|credentials(?:\.json)?'
  r')(?:$|[\s/\x27"])',
  caseSensitive: false,
);

/// Validates that [command] is strictly read-only and safe to execute via MCP
/// from a live Vibe Canvas component using an explicit binary and flag allowlist.
bool isReadOnlyCanvasShellCommand(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty || trimmed.length > 2000) return false;

  // Reject shell metacharacters, command chaining, subshells, redirection,
  // escaping, newlines, and NUL bytes.
  if (_kShellMetacharRegex.hasMatch(trimmed)) {
    return false;
  }

  // Reject access to sensitive credential, key, or auth files/directories.
  if (_kSensitivePathRegex.hasMatch(trimmed)) {
    return false;
  }

  final segments = trimmed.split('|');
  for (var segIndex = 0; segIndex < segments.length; segIndex++) {
    final segTrimmed = segments[segIndex].trim();
    if (segTrimmed.isEmpty) return false;

    final tokens = segTrimmed.split(RegExp(r'\s+'));
    var tokenOffset = 0;
    if (tokens[0] == 'LC_ALL=C' || tokens[0] == 'LANG=C') {
      tokenOffset = 1;
    }
    if (tokenOffset >= tokens.length) return false;

    final binary = tokens[tokenOffset].toLowerCase();
    final args = tokens.sublist(tokenOffset + 1);
    if (!_isAllowedReadOnlySegment(binary, args)) {
      return false;
    }
  }
  return true;
}

bool _hasShortFlag(String arg, Set<String> forbiddenChars) {
  if (!arg.startsWith('-') || arg.startsWith('--') || arg.length < 2) {
    return false;
  }
  for (var i = 1; i < arg.length; i++) {
    if (forbiddenChars.contains(arg[i])) {
      return true;
    }
  }
  return false;
}

String _longOptionLower(String arg) =>
    arg.startsWith('--') ? arg.toLowerCase() : arg;

bool _isAllowedReadOnlySegment(String binary, List<String> args) {
  for (final arg in args) {
    final lower = _longOptionLower(arg);
    if (lower == '--command' ||
        lower.startsWith('--command=') ||
        arg.startsWith('-exec') ||
        lower == '--exec' ||
        lower.startsWith('--exec=') ||
        lower.startsWith('--upload-pack') ||
        lower.startsWith('--receive-pack') ||
        lower.startsWith('--to-program') ||
        lower.startsWith('--compress-program')) {
      return false;
    }
  }

  if (_kAllowedReadOnlySingleBinaries.contains(binary)) {
    return _hasSafeSingleBinaryFlags(binary, args);
  }

  final subcommand = args.isNotEmpty ? args.first.toLowerCase() : '';
  switch (binary) {
    case 'git':
      const allowedGitSubcommands = <String>{
        'status',
        'log',
        'diff',
        'branch',
        'rev-parse',
        'show',
        'tag',
      };
      if (!allowedGitSubcommands.contains(subcommand)) return false;
      for (final arg in args.skip(1)) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'c', 'o'}) ||
            arg.startsWith('-c=') ||
            longLower.startsWith('--output')) {
          return false;
        }
      }
      if (subcommand == 'branch') {
        const allowedBranchFlags = <String>{
          '-a',
          '--all',
          '-r',
          '--remotes',
          '-v',
          '-vv',
          '--verbose',
          '--list',
          '--show-current',
          '--no-color',
        };
        for (final arg in args.skip(1)) {
          if (!allowedBranchFlags.contains(arg)) return false;
        }
      }
      return true;
    case 'systemctl':
      return const <String>{
        'status',
        'is-active',
        'is-enabled',
        'is-failed',
        'list-units',
        'list-unit-files',
        'list-timers',
        'show',
      }.contains(subcommand);
    case 'journalctl':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (longLower.startsWith('--flush') ||
            longLower.startsWith('--rotate') ||
            longLower.startsWith('--vacuum') ||
            longLower.startsWith('--sync') ||
            longLower.startsWith('--setup-keys')) {
          return false;
        }
      }
      return true;
    case 'docker':
      return const <String>{
        'ps',
        'stats',
        'images',
        'info',
        'version',
        'logs',
        'top',
      }.contains(subcommand);
    case 'kubectl':
      if (!const <String>{
        'get',
        'describe',
        'top',
        'version',
        'cluster-info',
        'logs',
        'api-resources',
        'explain',
      }.contains(subcommand)) {
        return false;
      }
      if (subcommand == 'get' || subcommand == 'describe') {
        for (final arg in args.skip(1)) {
          final parts = arg.toLowerCase().split(RegExp(r'[,/]'));
          if (parts.contains('secret') || parts.contains('secrets')) {
            return false;
          }
        }
      }
      return true;
    case 'ip':
      if (!const <String>{
        'addr',
        'address',
        'a',
        'route',
        'r',
        'link',
        'l',
        'neigh',
        'n',
        '-s',
        '-br',
        '-4',
        '-6',
      }.contains(subcommand)) {
        return false;
      }
      for (final arg in args) {
        if (const <String>{
          'add',
          'del',
          'delete',
          'set',
          'flush',
          'change',
          'replace',
        }.contains(arg.toLowerCase())) {
          return false;
        }
      }
      return true;
    case 'ifconfig':
      for (final arg in args) {
        if (const <String>{
          'up',
          'down',
          'add',
          'del',
          'mtu',
          'netmask',
          'hw',
          'promisc',
        }.contains(arg.toLowerCase())) {
          return false;
        }
      }
      return true;
    default:
      return false;
  }
}

bool _hasSafeSingleBinaryFlags(String binary, List<String> args) {
  switch (binary) {
    case 'hostname':
      const allowedHostnameFlags = <String>{
        '-f',
        '--fqdn',
        '-s',
        '--short',
        '-i',
        '--ip-address',
        '-I',
        '--all-ip-addresses',
      };
      return args.every(allowedHostnameFlags.contains);
    case 'date':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'s', 'f'}) ||
            longLower.startsWith('--set') ||
            longLower.startsWith('--file')) {
          return false;
        }
      }
      return true;
    case 'sort':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'o', 'T'}) ||
            longLower.startsWith('--output') ||
            longLower.startsWith('--files0-from') ||
            longLower.startsWith('--temporary-directory')) {
          return false;
        }
      }
      return true;
    case 'uniq':
      var positionalCount = 0;
      for (final arg in args) {
        if (!arg.startsWith('-') || arg == '-') {
          positionalCount++;
          if (positionalCount > 1) return false;
        }
      }
      return true;
    case 'wc':
    case 'cut':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (arg == '-o' || longLower.startsWith('--output')) {
          if (binary == 'cut' && longLower.startsWith('--output-delimiter')) {
            continue;
          }
          return false;
        }
      }
      return true;
    case 'ps':
      return true;
    case 'tail':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'f', 'F', 'o'}) ||
            longLower.startsWith('--follow') ||
            longLower.startsWith('--output')) {
          return false;
        }
      }
      return true;
    case 'grep':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'f'}) ||
            longLower.startsWith('--file') ||
            longLower.startsWith('--exclude-from')) {
          return false;
        }
      }
      return true;
    case 'dmesg':
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (_hasShortFlag(arg, const <String>{'c', 'C', 'D', 'E', 'n', 'F'}) ||
            longLower == '--clear' ||
            longLower == '--read-clear' ||
            longLower == '--console-off' ||
            longLower == '--console-on' ||
            longLower.startsWith('--console-level') ||
            longLower.startsWith('--file')) {
          return false;
        }
      }
      return true;
    default:
      for (final arg in args) {
        final longLower = _longOptionLower(arg);
        if (arg == '-c' ||
            arg == '-o' ||
            longLower.startsWith('--output')) {
          return false;
        }
      }
      return true;
  }
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
