import 'dart:convert';

import 'host.dart';

/// Canonical MCP tool categories aligned with `deploy/mcp-worker/src/discovery-profile.js`
/// and `crates/service-contracts/src/project_tool_catalog.json`.
enum VibeMcpToolCategory {
  runtime('runtime', 'Runtime & Host Diagnostics'),
  project('project', 'Project & Filesystem Inspection'),
  git('git', 'Git & Diff Review'),
  job('job', 'Process & Job Observation'),
  provider('provider', 'Host Providers (SSH, LSP, Browser, Docs)'),
  edit('edit', 'Workspace File Editing'),
  validation('validation', 'Build & Test Validation'),
  session('session', 'Session & Context Continuity'),
  agent('agent', 'AI Agent & Goal Orchestration'),
  artifact('artifact', 'Project & Conversation Artifacts'),
  checkpoint('checkpoint', 'Workspace Checkpoints'),
  memory('memory', 'Scoped Agent Memory'),
  skill('skill', 'Reusable MCP Skills'),
  telemetry('telemetry', 'Live Host & Network Telemetry'),
  clientUi('client_ui', 'Client UI & Vibe Canvas Surface');

  const VibeMcpToolCategory(this.id, this.label);

  final String id;
  final String label;

  static VibeMcpToolCategory fromId(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in VibeMcpToolCategory.values) {
      if (value.id == normalized) return value;
    }
    return VibeMcpToolCategory.runtime;
  }
}

/// Execution location of an MCP tool, aligned with `scripts/generate-mcp-catalog.mjs`.
enum VibeMcpExecutionLocation {
  gateway('gateway'),
  runner('runner'),
  provider('provider'),
  client('client'),
  hybrid('hybrid');

  const VibeMcpExecutionLocation(this.id);

  final String id;

  static VibeMcpExecutionLocation fromId(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in VibeMcpExecutionLocation.values) {
      if (value.id == normalized) return value;
    }
    return VibeMcpExecutionLocation.runner;
  }
}

/// Frontend or runtime surface where an MCP tool may be exposed under conditions.
enum VibeMcpExposureSurface {
  /// External AI assistants (ChatGPT, Claude, Cursor) via `mcp-worker` / local stdio MCP.
  externalAssistant('external_assistant'),

  /// Sandboxed Vibe Canvas components polling/streaming live data (`window.vibeCanvas.callMcp`).
  /// Strictly restricted to non-mutating (`mutates == false`) read-only tools.
  canvasReadOnly('canvas_readonly'),

  /// Interactive Vibe Canvas action dispatch (`window.vibeCanvas.sendAction` / `VibeView` actions)
  /// mediated by user confirmation or controlling-task UI lease.
  canvasInteractive('canvas_interactive'),

  /// Unified Omnibox & AI Tasks planner inside the client app.
  omnibox('omnibox'),

  /// Unattended / background agent task execution.
  agentBackground('agent_background');

  const VibeMcpExposureSurface(this.id);

  final String id;
}

/// Semantic tags attached to MCP tools for fine-grained conditional selection.
enum VibeMcpToolTag {
  readOnly('read_only'),
  mutating('mutating'),
  telemetry('telemetry'),
  processInspect('process_inspect'),
  networkInspect('network_inspect'),
  sshReadOnly('ssh_readonly'),
  filesystemRead('filesystem_read'),
  gitRead('git_read'),
  jobObserve('job_observe'),
  uiWidget('ui_widget'),
  compactDiscovery('compact_discovery');

  const VibeMcpToolTag(this.id);

  final String id;
}

/// Canonical compact discovery tool names aligned with
/// `deploy/mcp-worker/src/discovery-profile.js`.
const Set<String> kVibeCompactDiscoveryToolNames = <String>{
  'list_devices',
  'list_projects',
  'list_tools',
  'tool_manifest',
  'call_runtime_tool',
  'mcp_tool',
  'read_operation',
  'work_on_project',
  'read_files',
  'search_project_texts',
  'apply_text_edits',
  'git_status',
  'git_diff_hunks',
  'observe_jobs',
  'wait_for_job_terminal',
  'job_tail',
  'stop_job',
  'project_artifact',
  'runtime_status',
  'run_process',
  'run_shell',
  'provider_catalog',
  'restart_provider',
};

/// Canonical discovery intents aligned with `deploy/mcp-worker/src/discovery-profile.js`,
/// extended with `telemetry` and `canvas` for frontend Vibe Space surfaces.
const Map<String, List<VibeMcpToolCategory>> kVibeDiscoveryIntentCategories =
    <String, List<VibeMcpToolCategory>>{
  'coding': <VibeMcpToolCategory>[
    VibeMcpToolCategory.project,
    VibeMcpToolCategory.edit,
    VibeMcpToolCategory.git,
    VibeMcpToolCategory.validation,
    VibeMcpToolCategory.job,
    VibeMcpToolCategory.session,
  ],
  'audit': <VibeMcpToolCategory>[
    VibeMcpToolCategory.project,
    VibeMcpToolCategory.git,
    VibeMcpToolCategory.validation,
    VibeMcpToolCategory.session,
    VibeMcpToolCategory.telemetry,
  ],
  'exploration': <VibeMcpToolCategory>[
    VibeMcpToolCategory.project,
    VibeMcpToolCategory.git,
    VibeMcpToolCategory.provider,
    VibeMcpToolCategory.telemetry,
    VibeMcpToolCategory.runtime,
  ],
  'release': <VibeMcpToolCategory>[
    VibeMcpToolCategory.git,
    VibeMcpToolCategory.validation,
    VibeMcpToolCategory.artifact,
    VibeMcpToolCategory.job,
  ],
  'discovery': <VibeMcpToolCategory>[
    VibeMcpToolCategory.runtime,
    VibeMcpToolCategory.project,
    VibeMcpToolCategory.provider,
    VibeMcpToolCategory.skill,
  ],
  'telemetry': <VibeMcpToolCategory>[
    VibeMcpToolCategory.telemetry,
    VibeMcpToolCategory.runtime,
    VibeMcpToolCategory.job,
    VibeMcpToolCategory.provider,
  ],
};

/// Classifies any canonical MCP tool name into a [VibeMcpToolCategory] using the
/// exact regex rules from `deploy/mcp-worker/src/discovery-profile.js` plus
/// client/telemetry namespaces.
VibeMcpToolCategory classifyVibeMcpToolCategory(String toolName) {
  final name = toolName.trim();
  if (name.startsWith('client.')) {
    return VibeMcpToolCategory.clientUi;
  }
  if (name.startsWith('server.telemetry.') ||
      name.startsWith('server.network.') ||
      name.startsWith('server.process.') ||
      name.startsWith('mcp.server.') ||
      name == 'host_process_list' ||
      name == 'runner_info' ||
      name == 'runner_ping' ||
      name == 'runner_usage') {
    return VibeMcpToolCategory.telemetry;
  }
  if (RegExp(r'^(git_|workspace_changes|review_changes)').hasMatch(name)) {
    return VibeMcpToolCategory.git;
  }
  if (RegExp(r'checkpoint').hasMatch(name)) {
    return VibeMcpToolCategory.checkpoint;
  }
  if (RegExp(r'artifact|conversation_files').hasMatch(name)) {
    return VibeMcpToolCategory.artifact;
  }
  if (RegExp(
          r'^(write_|apply_|replace_|create_directory|delete_project|move_project)')
      .hasMatch(name)) {
    return VibeMcpToolCategory.edit;
  }
  if (RegExp(r'^(cargo_|go_|run_project_tests)').hasMatch(name)) {
    return VibeMcpToolCategory.validation;
  }
  if (RegExp(
          r'job|coding_run|coding_agent_|shell|run_program|run_script|^run_(detached_)?process$')
      .hasMatch(name)) {
    return VibeMcpToolCategory.job;
  }
  if (RegExp(r'session|context|handoff').hasMatch(name)) {
    return VibeMcpToolCategory.session;
  }
  if (RegExp(r'^(agent_|.*agent_task|.*agent_goal)').hasMatch(name)) {
    return VibeMcpToolCategory.agent;
  }
  if (RegExp(r'^memory_').hasMatch(name)) {
    return VibeMcpToolCategory.memory;
  }
  if (RegExp(r'skill').hasMatch(name)) {
    return VibeMcpToolCategory.skill;
  }
  if (RegExp(
          r'^(browser_|computer_|document_|write_pdf$|lsp_|ssh_|mcp_|provider_|plugin_|restart_provider$)')
      .hasMatch(name)) {
    return VibeMcpToolCategory.provider;
  }
  if (RegExp(r'project|^read_files$|^search_and_read$').hasMatch(name)) {
    return VibeMcpToolCategory.project;
  }
  return VibeMcpToolCategory.runtime;
}

/// Derives canonical [VibeMcpToolTag]s from a tool's name, scope, and mutation flag.
Set<VibeMcpToolTag> deriveVibeMcpToolTags({
  required String name,
  required String scope,
  required bool mutates,
}) {
  final tags = <VibeMcpToolTag>{
    if (mutates) VibeMcpToolTag.mutating else VibeMcpToolTag.readOnly,
    if (kVibeCompactDiscoveryToolNames.contains(name))
      VibeMcpToolTag.compactDiscovery,
  };

  if (!mutates) {
    if (name == 'host_process_list' ||
        name == 'server.process.inspect' ||
        name == 'mcp.server.processes') {
      tags.add(VibeMcpToolTag.processInspect);
      tags.add(VibeMcpToolTag.telemetry);
    }
    if (name == 'server.network.sockets' ||
        name == 'mcp.server.network_bandwidth') {
      tags.add(VibeMcpToolTag.networkInspect);
      tags.add(VibeMcpToolTag.telemetry);
    }
    if (name == 'runner_info' ||
        name == 'runner_ping' ||
        name == 'runner_usage' ||
        name == 'runtime_status' ||
        name == 'get_usage_stats' ||
        name == 'server.telemetry.snapshot' ||
        name == 'mcp.server.metrics' ||
        name == 'client.canvas.read_metrics') {
      tags.add(VibeMcpToolTag.telemetry);
    }
    if (name == 'ssh_resource' ||
        name == 'session_shell_status' ||
        name == 'mcp.ssh.exec_readonly') {
      tags.add(VibeMcpToolTag.sshReadOnly);
    }
    if (name == 'read_files' ||
        name == 'read_file' ||
        name == 'read_file_tail' ||
        name == 'read_multiple_files' ||
        name == 'list_project_files' ||
        name == 'list_project_tracked_files' ||
        name == 'project_overview' ||
        name == 'search_project_texts' ||
        name == 'search_and_read' ||
        name == 'get_file_info' ||
        name == 'project_file_info' ||
        name == 'inspect_project_path') {
      tags.add(VibeMcpToolTag.filesystemRead);
    }
    if (name == 'git_status' ||
        name == 'git_diff_hunks' ||
        name == 'git_log' ||
        name == 'git_review_summary' ||
        name == 'show_changes' ||
        name == 'changes_file_diff') {
      tags.add(VibeMcpToolTag.gitRead);
    }
    if (name == 'list_jobs' ||
        name == 'observe_jobs' ||
        name == 'job_tail' ||
        name == 'list_process_sessions' ||
        name == 'read_process_output' ||
        name == 'session_shell_status' ||
        name == 'coding_agent_observe') {
      tags.add(VibeMcpToolTag.jobObserve);
    }
  }

  if (name.startsWith('present_') ||
      name == 'goal_plan_state' ||
      name == 'goal_plan_set' ||
      name == 'read_operation' ||
      name.startsWith('client.canvas.')) {
    tags.add(VibeMcpToolTag.uiWidget);
  }

  return Set<VibeMcpToolTag>.unmodifiable(tags);
}

/// Derives which [VibeMcpExposureSurface]s a tool can be exposed to.
///
/// Key invariant: [VibeMcpExposureSurface.canvasReadOnly] NEVER includes mutating tools.
Set<VibeMcpExposureSurface> deriveVibeMcpExposureSurfaces({
  required String name,
  required bool mutates,
  required VibeMcpToolCategory category,
  required Set<VibeMcpToolTag> tags,
}) {
  final surfaces = <VibeMcpExposureSurface>{
    VibeMcpExposureSurface.externalAssistant,
    VibeMcpExposureSurface.omnibox,
    VibeMcpExposureSurface.agentBackground,
  };

  if (!mutates) {
    // Non-mutating tools tagged with telemetry, process/network inspection,
    // ssh read-only, filesystem read, git read, job observe, or runtime discovery
    // can be exposed to read-only frontend surfaces like Vibe Canvas under policy.
    if (tags.contains(VibeMcpToolTag.telemetry) ||
        tags.contains(VibeMcpToolTag.processInspect) ||
        tags.contains(VibeMcpToolTag.networkInspect) ||
        tags.contains(VibeMcpToolTag.sshReadOnly) ||
        tags.contains(VibeMcpToolTag.filesystemRead) ||
        tags.contains(VibeMcpToolTag.gitRead) ||
        tags.contains(VibeMcpToolTag.jobObserve) ||
        category == VibeMcpToolCategory.runtime ||
        category == VibeMcpToolCategory.project ||
        category == VibeMcpToolCategory.git ||
        category == VibeMcpToolCategory.job ||
        category == VibeMcpToolCategory.telemetry) {
      surfaces.add(VibeMcpExposureSurface.canvasReadOnly);
    }
  } else if (category == VibeMcpToolCategory.clientUi ||
      tags.contains(VibeMcpToolTag.uiWidget)) {
    surfaces.add(VibeMcpExposureSurface.canvasInteractive);
  }

  return Set<VibeMcpExposureSurface>.unmodifiable(surfaces);
}

/// Unified descriptor for an MCP tool in Vibe Space, compatible with
/// `crates/service-contracts/src/project_tool_catalog.json` and `deploy/mcp-worker`.
class VibeMcpToolDescriptor {
  VibeMcpToolDescriptor({
    required this.name,
    required this.scope,
    required this.mutates,
    required this.description,
    this.inputSchema = const <String, dynamic>{'type': 'object'},
    this.location = VibeMcpExecutionLocation.runner,
    VibeMcpToolCategory? category,
    Set<VibeMcpToolTag>? tags,
    Set<VibeMcpExposureSurface>? surfaces,
    this.requiresActiveSshSession = false,
    this.requiresProjectContext = false,
    this.aliases = const <String>{},
  })  : category = category ?? classifyVibeMcpToolCategory(name),
        tags = tags ??
            deriveVibeMcpToolTags(
              name: name,
              scope: scope,
              mutates: mutates,
            ),
        surfaces = surfaces ??
            deriveVibeMcpExposureSurfaces(
              name: name,
              mutates: mutates,
              category: category ?? classifyVibeMcpToolCategory(name),
              tags: tags ??
                  deriveVibeMcpToolTags(
                    name: name,
                    scope: scope,
                    mutates: mutates,
                  ),
            );

  /// Constructs a [VibeMcpToolDescriptor] directly from an entry in
  /// `crates/service-contracts/src/project_tool_catalog.json`.
  factory VibeMcpToolDescriptor.fromCatalogJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final scope = (json['scope'] ?? 'project:read').toString().trim();
    final mutates = json['mutates'] == true;
    final description = (json['description'] ?? '').toString().trim();
    final rawSchema = json['input_schema'];
    final schema = rawSchema is Map<String, dynamic>
        ? rawSchema
        : (rawSchema is Map
            ? rawSchema.map<String, dynamic>((k, v) => MapEntry('$k', v))
            : const <String, dynamic>{'type': 'object'});
    final props = schema['properties'];
    final requiresProject =
        props is Map && props.containsKey('project_id') && name != 'list_projects';
    return VibeMcpToolDescriptor(
      name: name,
      scope: scope,
      mutates: mutates,
      description: description,
      inputSchema: schema,
      location: VibeMcpExecutionLocation.fromId(json['location']?.toString()),
      requiresProjectContext: requiresProject,
    );
  }

  final String name;
  final String scope;
  final bool mutates;
  final String description;
  final JsonMap inputSchema;
  final VibeMcpExecutionLocation location;
  final VibeMcpToolCategory category;
  final Set<VibeMcpToolTag> tags;
  final Set<VibeMcpExposureSurface> surfaces;
  final bool requiresActiveSshSession;
  final bool requiresProjectContext;
  final Set<String> aliases;

  /// True when this tool is strictly read-only (`mutates == false`).
  bool get isReadOnly => !mutates;

  /// Matches [candidateName] against [name] or any registered [aliases] (case-insensitive).
  bool matchesName(String candidateName) {
    final normalized = candidateName.trim().toLowerCase();
    if (name.toLowerCase() == normalized) return true;
    for (final alias in aliases) {
      if (alias.toLowerCase() == normalized) return true;
    }
    return false;
  }

  JsonMap toJson() => <String, dynamic>{
        'name': name,
        'scope': scope,
        'mutates': mutates,
        'description': description,
        'location': location.id,
        'category': category.id,
        'tags': tags.map((t) => t.id).toList(growable: false),
        'surfaces': surfaces.map((s) => s.id).toList(growable: false),
        if (aliases.isNotEmpty) 'aliases': aliases.toList(growable: false),
      };
}

/// Runtime condition used to select which MCP tools are exposed to a frontend
/// surface (such as Vibe Canvas, Omnibox, or external ChatGPT/Claude MCP).
class VibeMcpSelectionCondition {
  const VibeMcpSelectionCondition({
    required this.surface,
    this.allowMutating = false,
    this.hasActiveSshSession = true,
    this.hasProjectContext = true,
    this.grantedScopes,
    this.categories,
    this.anyTags,
    this.requiredTags,
    this.intent,
  });

  /// Convenience condition for live Vibe Canvas components (`window.vibeCanvas.callMcp`).
  /// Enforces `allowMutating: false` and `surface: VibeMcpExposureSurface.canvasReadOnly`.
  factory VibeMcpSelectionCondition.canvasReadOnly({
    bool hasActiveSshSession = true,
    bool hasProjectContext = true,
    Set<String>? grantedScopes,
    Set<VibeMcpToolCategory>? categories,
    Set<VibeMcpToolTag>? anyTags,
  }) {
    return VibeMcpSelectionCondition(
      surface: VibeMcpExposureSurface.canvasReadOnly,
      allowMutating: false,
      hasActiveSshSession: hasActiveSshSession,
      hasProjectContext: hasProjectContext,
      grantedScopes: grantedScopes,
      categories: categories,
      anyTags: anyTags,
    );
  }

  final VibeMcpExposureSurface surface;
  final bool allowMutating;
  final bool hasActiveSshSession;
  final bool hasProjectContext;
  final Set<String>? grantedScopes;
  final Set<VibeMcpToolCategory>? categories;
  final Set<VibeMcpToolTag>? anyTags;
  final Set<VibeMcpToolTag>? requiredTags;
  final String? intent;

  /// Evaluates whether [tool] satisfies this selection condition.
  bool allows(VibeMcpToolDescriptor tool) {
    // 1. Surface check
    if (!tool.surfaces.contains(surface)) {
      return false;
    }

    // 2. Hard read-only enforcement for canvasReadOnly or when allowMutating is false
    if ((surface == VibeMcpExposureSurface.canvasReadOnly || !allowMutating) &&
        tool.mutates) {
      return false;
    }

    // 3. Contextual prerequisite checks
    if (tool.requiresActiveSshSession && !hasActiveSshSession) {
      return false;
    }
    if (tool.requiresProjectContext && !hasProjectContext) {
      return false;
    }

    // 4. OAuth / MCP scope check (if caller specifies grantedScopes)
    if (grantedScopes != null && !grantedScopes!.contains(tool.scope)) {
      return false;
    }

    // 5. Category & discovery intent filter
    if (categories != null &&
        categories!.isNotEmpty &&
        !categories!.contains(tool.category)) {
      return false;
    }
    if (intent != null && intent!.trim().isNotEmpty) {
      final allowedForIntent =
          kVibeDiscoveryIntentCategories[intent!.trim().toLowerCase()];
      if (allowedForIntent != null &&
          !allowedForIntent.contains(tool.category)) {
        return false;
      }
    }

    // 6. Tag filters
    if (requiredTags != null &&
        requiredTags!.isNotEmpty &&
        !tool.tags.containsAll(requiredTags!)) {
      return false;
    }
    if (anyTags != null &&
        anyTags!.isNotEmpty &&
        tool.tags.intersection(anyTags!).isEmpty) {
      return false;
    }

    return true;
  }
}

/// Canonical Vibe Space MCP Tool Catalog that aligns the ChatGPT/Claude MCP Server
/// tool definitions (`deploy/mcp-worker/src/project-tools.js`) with frontend surfaces
/// like Vibe Canvas and Unified Omnibox without duplicating schemas.
class VibeMcpToolCatalog {
  VibeMcpToolCatalog({Iterable<VibeMcpToolDescriptor>? tools}) {
    for (final tool in tools ?? defaultTools) {
      register(tool);
    }
  }

  /// Creates a catalog populated from the JSON string of
  /// `crates/service-contracts/src/project_tool_catalog.json` merged with the
  /// standard Vibe Space telemetry/canvas descriptors.
  factory VibeMcpToolCatalog.fromProjectToolCatalogJson(String jsonSource) {
    final decoded = jsonDecode(jsonSource);
    final descriptors = <VibeMcpToolDescriptor>[...defaultTools];
    if (decoded is Map && decoded['tools'] is List) {
      for (final raw in decoded['tools'] as List) {
        if (raw is Map) {
          final map = raw.map<String, dynamic>((k, v) => MapEntry('$k', v));
          descriptors.add(VibeMcpToolDescriptor.fromCatalogJson(map));
        }
      }
    }
    return VibeMcpToolCatalog(tools: descriptors);
  }

  /// Singleton default catalog aligned with the canonical ChatGPT/Claude MCP server.
  static final VibeMcpToolCatalog instance = VibeMcpToolCatalog();

  final Map<String, VibeMcpToolDescriptor> _byName =
      <String, VibeMcpToolDescriptor>{};
  final Map<String, String> _aliasToCanonical = <String, String>{};

  /// Registers or updates a [VibeMcpToolDescriptor] in the catalog.
  void register(VibeMcpToolDescriptor descriptor) {
    final key = descriptor.name.trim().toLowerCase();
    _byName[key] = descriptor;
    for (final alias in descriptor.aliases) {
      _aliasToCanonical[alias.trim().toLowerCase()] = key;
    }
  }

  /// Resolves a canonical or aliased tool name to its [VibeMcpToolDescriptor].
  VibeMcpToolDescriptor? find(String toolName) {
    final normalized = toolName.trim().toLowerCase();
    final direct = _byName[normalized];
    if (direct != null) return direct;
    final canonicalKey = _aliasToCanonical[normalized];
    if (canonicalKey != null) return _byName[canonicalKey];
    return null;
  }

  /// Resolves [toolName] to its canonical MCP tool name (or returns [toolName] trimmed).
  String resolveCanonicalName(String toolName) {
    return find(toolName)?.name ?? toolName.trim();
  }

  /// All registered tool descriptors sorted by canonical name.
  List<VibeMcpToolDescriptor> get allTools {
    final list = _byName.values.toList(growable: false);
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Selects all tools allowed under [condition].
  List<VibeMcpToolDescriptor> selectTools(VibeMcpSelectionCondition condition) {
    return allTools.where(condition.allows).toList(growable: false);
  }

  /// Returns `true` if [toolName] (or its canonical alias) is registered and
  /// permitted under [condition].
  bool isAllowed(
    String toolName, {
    VibeMcpSelectionCondition? condition,
  }) {
    final descriptor = find(toolName);
    if (descriptor == null) return false;
    final effectiveCondition =
        condition ?? VibeMcpSelectionCondition.canvasReadOnly();
    return effectiveCondition.allows(descriptor);
  }

  /// Formats a concise LLM prompt section describing the canonical MCP tools
  /// exposed under [condition], so background LLM planners can generate live
  /// Vibe Canvas components that call canonical MCP tools.
  String buildLlmContextPrompt(VibeMcpSelectionCondition condition) {
    final selected = selectTools(condition);
    if (selected.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln(
        'Exposed MCP Tools for surface `${condition.surface.id}` '
        '(aligned with canonical ChatGPT/Claude MCP catalog):',
      );
    for (final tool in selected) {
      final tagsLabel = tool.tags.map((t) => t.id).join(', ');
      final aliasNote = tool.aliases.isNotEmpty
          ? ' (aliases: ${tool.aliases.join(", ")})'
          : '';
      buffer.writeln(
        '- `${tool.name}` [${tool.category.id} | scope: ${tool.scope} | tags: $tagsLabel]$aliasNote: ${tool.description}',
      );
    }
    return buffer.toString().trimRight();
  }

  /// Canonical MCP tools shared across the ChatGPT/Claude MCP Server
  /// (`deploy/mcp-worker/src/project-tools.js`) and Vibe Space frontend surfaces.
  static final List<VibeMcpToolDescriptor> defaultTools =
      <VibeMcpToolDescriptor>[
    // --- Host Admin & Live Telemetry Tools (Canonical in host-admin-tools.js & CUJ catalog) ---
    VibeMcpToolDescriptor(
      name: 'host_process_list',
      scope: 'runner:admin',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.telemetry,
      description:
          'List an allowlisted host process snapshot sorted by CPU and memory usage.',
      aliases: const <String>{
        'server.process.inspect',
        'mcp.server.processes',
      },
    ),
    VibeMcpToolDescriptor(
      name: 'runner_info',
      scope: 'runner:admin',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.telemetry,
      description:
          'Read sanitized runner/host identity, execution mode, version, uptime, CPU/RAM/disk metrics, and capabilities.',
      aliases: const <String>{
        'server.telemetry.snapshot',
        'mcp.server.metrics',
        'client.canvas.read_metrics',
      },
    ),
    VibeMcpToolDescriptor(
      name: 'runner_ping',
      scope: 'runner:admin',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.telemetry,
      description: 'Return a live heartbeat response from the executing runner.',
    ),
    VibeMcpToolDescriptor(
      name: 'runner_usage',
      scope: 'runner:admin',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.telemetry,
      description: 'Read connection-scoped journal counts and resource usage.',
    ),
    VibeMcpToolDescriptor(
      name: 'server.network.sockets',
      scope: 'host:tools',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.telemetry,
      requiresActiveSshSession: true,
      description:
          'Read live network interface RX/TX byte counters (`/proc/net/dev`) and listening sockets.',
      aliases: const <String>{
        'mcp.server.network_bandwidth',
      },
    ),
    VibeMcpToolDescriptor(
      name: 'ssh_resource',
      scope: 'host:tools',
      mutates: false,
      location: VibeMcpExecutionLocation.provider,
      category: VibeMcpToolCategory.provider,
      requiresActiveSshSession: true,
      description:
          'Execute a validated read-only inspection command over the active SSH resource (`isReadOnlyCanvasShellCommand`).',
      tags: const <VibeMcpToolTag>{
        VibeMcpToolTag.readOnly,
        VibeMcpToolTag.sshReadOnly,
        VibeMcpToolTag.telemetry,
      },
      surfaces: const <VibeMcpExposureSurface>{
        VibeMcpExposureSurface.externalAssistant,
        VibeMcpExposureSurface.canvasReadOnly,
        VibeMcpExposureSurface.omnibox,
        VibeMcpExposureSurface.agentBackground,
      },
      aliases: const <String>{
        'mcp.ssh.exec_readonly',
      },
    ),

    // --- Gateway & Device Discovery Tools (Canonical in project-tools.js) ---
    VibeMcpToolDescriptor(
      name: 'list_devices',
      scope: 'devices:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.runtime,
      description:
          'List all currently enrolled devices/servers owned by the connected account.',
    ),
    VibeMcpToolDescriptor(
      name: 'list_runners',
      scope: 'devices:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.runtime,
      description: 'Alias of list_devices: page account-owned enrolled devices.',
    ),
    VibeMcpToolDescriptor(
      name: 'list_projects',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.project,
      description:
          'List the registered projects explicitly authorized for this connection.',
    ),
    VibeMcpToolDescriptor(
      name: 'runtime_status',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.runtime,
      description:
          'Inspect available projects and their current registered capabilities.',
    ),
    VibeMcpToolDescriptor(
      name: 'list_tools',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.runtime,
      description:
          'List implemented MCP tool names, scopes, and execution locations.',
    ),
    VibeMcpToolDescriptor(
      name: 'tool_manifest',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.gateway,
      category: VibeMcpToolCategory.runtime,
      description: 'Inspect the implemented MCP tool catalog by category or intent.',
    ),

    // --- Project & Filesystem Read-Only Tools (Canonical in project-tools.js) ---
    VibeMcpToolDescriptor(
      name: 'project_overview',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.project,
      requiresProjectContext: true,
      description:
          'Inspect registered project metadata and a bounded recursive directory overview.',
    ),
    VibeMcpToolDescriptor(
      name: 'list_project_files',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.project,
      requiresProjectContext: true,
      description: 'List a bounded page of project directory entries.',
    ),
    VibeMcpToolDescriptor(
      name: 'read_files',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.project,
      requiresProjectContext: true,
      description: 'Read UTF-8 files with full-file SHA-256 revisions.',
    ),
    VibeMcpToolDescriptor(
      name: 'search_project_texts',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.project,
      requiresProjectContext: true,
      description:
          'Search bounded project text without following symbolic links.',
    ),

    // --- Git Read-Only Tools (Canonical in project-tools.js) ---
    VibeMcpToolDescriptor(
      name: 'git_status',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.git,
      requiresProjectContext: true,
      description: 'Read current Git status and bounded working-tree changes.',
    ),
    VibeMcpToolDescriptor(
      name: 'git_diff_hunks',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.git,
      requiresProjectContext: true,
      description:
          'Read bounded Git diffs with revision-fenced continuation pages.',
    ),
    VibeMcpToolDescriptor(
      name: 'git_log',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.git,
      requiresProjectContext: true,
      description: 'Read recent commit metadata.',
    ),

    // --- Job & Session Shell Read-Only Tools (Canonical in job-tools.js) ---
    VibeMcpToolDescriptor(
      name: 'list_jobs',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.job,
      requiresProjectContext: true,
      description: 'List durable job records for this project.',
    ),
    VibeMcpToolDescriptor(
      name: 'observe_jobs',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.job,
      requiresProjectContext: true,
      description: 'Read job state and captured output after UTF-8 offsets.',
    ),
    VibeMcpToolDescriptor(
      name: 'job_tail',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.job,
      requiresProjectContext: true,
      description: 'Read a resumable output page bounded by total bytes.',
    ),
    VibeMcpToolDescriptor(
      name: 'session_shell_status',
      scope: 'project:read',
      mutates: false,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.job,
      requiresProjectContext: true,
      description: 'Read a persistent shell state for the connection.',
    ),

    // --- Mutating Tools (Registered so selector explicitly filters them out of canvasReadOnly!) ---
    VibeMcpToolDescriptor(
      name: 'write_project_file',
      scope: 'project:write',
      mutates: true,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.edit,
      requiresProjectContext: true,
      description: 'Write a UTF-8 file only if its current revision matches.',
    ),
    VibeMcpToolDescriptor(
      name: 'apply_text_edits',
      scope: 'project:write',
      mutates: true,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.edit,
      requiresProjectContext: true,
      description:
          'Apply exact, unambiguous text replacements against an expected file revision.',
    ),
    VibeMcpToolDescriptor(
      name: 'run_shell',
      scope: 'job:run',
      mutates: true,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.job,
      requiresProjectContext: true,
      description: 'Run a command in a fresh project sandbox shell.',
    ),
    VibeMcpToolDescriptor(
      name: 'host_process_terminate',
      scope: 'runner:admin',
      mutates: true,
      location: VibeMcpExecutionLocation.runner,
      category: VibeMcpToolCategory.runtime,
      description:
          'Terminate only a freshly identified eligible process after explicit confirmation.',
    ),

    // --- Client UI / Vibe Canvas Interactive Tools ---
    VibeMcpToolDescriptor(
      name: 'client.canvas.render',
      scope: 'project:read',
      mutates: true,
      location: VibeMcpExecutionLocation.client,
      category: VibeMcpToolCategory.clientUi,
      description:
          'Render or update an interactive Vibe Canvas (`markdown`, `vibe_ui`, `html`, `wasm`).',
      aliases: const <String>{'vibe.canvas'},
    ),
  ];
}
