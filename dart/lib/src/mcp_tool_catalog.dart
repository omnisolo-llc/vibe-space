import 'dart:convert';

import 'host.dart';

/// Extensible category identifier for an MCP tool descriptor.
class VibeMcpToolCategory {
  const VibeMcpToolCategory(this.id, [this.label = '']);

  final String id;
  final String label;

  static const VibeMcpToolCategory runtime =
      VibeMcpToolCategory('runtime', 'Runtime & Host Diagnostics');
  static const VibeMcpToolCategory project =
      VibeMcpToolCategory('project', 'Project & Filesystem Inspection');
  static const VibeMcpToolCategory git =
      VibeMcpToolCategory('git', 'Git & Diff Review');
  static const VibeMcpToolCategory job =
      VibeMcpToolCategory('job', 'Process & Job Observation');
  static const VibeMcpToolCategory provider =
      VibeMcpToolCategory('provider', 'Host Providers');
  static const VibeMcpToolCategory edit =
      VibeMcpToolCategory('edit', 'Workspace File Editing');
  static const VibeMcpToolCategory validation =
      VibeMcpToolCategory('validation', 'Build & Test Validation');
  static const VibeMcpToolCategory session =
      VibeMcpToolCategory('session', 'Session & Context Continuity');
  static const VibeMcpToolCategory agent =
      VibeMcpToolCategory('agent', 'AI Agent & Goal Orchestration');
  static const VibeMcpToolCategory artifact =
      VibeMcpToolCategory('artifact', 'Project & Conversation Artifacts');
  static const VibeMcpToolCategory checkpoint =
      VibeMcpToolCategory('checkpoint', 'Workspace Checkpoints');
  static const VibeMcpToolCategory memory =
      VibeMcpToolCategory('memory', 'Scoped Agent Memory');
  static const VibeMcpToolCategory skill =
      VibeMcpToolCategory('skill', 'Reusable MCP Skills');
  static const VibeMcpToolCategory telemetry =
      VibeMcpToolCategory('telemetry', 'Live Host & Network Telemetry');
  static const VibeMcpToolCategory clientUi =
      VibeMcpToolCategory('client_ui', 'Client UI & Vibe Canvas Surface');

  static const List<VibeMcpToolCategory> builtInValues = <VibeMcpToolCategory>[
    runtime,
    project,
    git,
    job,
    provider,
    edit,
    validation,
    session,
    agent,
    artifact,
    checkpoint,
    memory,
    skill,
    telemetry,
    clientUi,
  ];

  static VibeMcpToolCategory fromId(
    String? raw, {
    VibeMcpToolCategory fallback = runtime,
  }) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return fallback;
    for (final value in builtInValues) {
      if (value.id == normalized) return value;
    }
    return VibeMcpToolCategory(normalized, normalized);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VibeMcpToolCategory && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VibeMcpToolCategory($id)';
}

/// Extensible execution location identifier for an MCP tool.
class VibeMcpExecutionLocation {
  const VibeMcpExecutionLocation(this.id);

  final String id;

  static const VibeMcpExecutionLocation host =
      VibeMcpExecutionLocation('host');
  static const VibeMcpExecutionLocation gateway =
      VibeMcpExecutionLocation('gateway');
  static const VibeMcpExecutionLocation runner =
      VibeMcpExecutionLocation('runner');
  static const VibeMcpExecutionLocation provider =
      VibeMcpExecutionLocation('provider');
  static const VibeMcpExecutionLocation client =
      VibeMcpExecutionLocation('client');
  static const VibeMcpExecutionLocation hybrid =
      VibeMcpExecutionLocation('hybrid');

  static VibeMcpExecutionLocation fromId(
    String? raw, {
    VibeMcpExecutionLocation fallback = host,
  }) {
    final normalized = raw?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return fallback;
    return VibeMcpExecutionLocation(normalized);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VibeMcpExecutionLocation && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VibeMcpExecutionLocation($id)';
}

/// Extensible surface identifier where an MCP tool may be exposed under policy.
class VibeMcpExposureSurface {
  const VibeMcpExposureSurface(this.id);

  final String id;

  /// External AI assistants (e.g. MCP clients over stdio or HTTP).
  static const VibeMcpExposureSurface externalAssistant =
      VibeMcpExposureSurface('external_assistant');

  /// Sandboxed Vibe Canvas components polling/streaming live data (`window.vibeCanvas.callMcp`).
  /// Strictly restricted to non-mutating (`mutates == false`) read-only tools.
  static const VibeMcpExposureSurface canvasReadOnly =
      VibeMcpExposureSurface('canvas_readonly');

  /// Interactive Vibe Canvas action dispatch mediated by user confirmation or lease.
  static const VibeMcpExposureSurface canvasInteractive =
      VibeMcpExposureSurface('canvas_interactive');

  /// Host-native planner / command palette surface.
  static const VibeMcpExposureSurface hostPlanner =
      VibeMcpExposureSurface('host_planner');

  /// Unattended / background agent task execution.
  static const VibeMcpExposureSurface agentBackground =
      VibeMcpExposureSurface('agent_background');

  static VibeMcpExposureSurface fromId(String raw) =>
      VibeMcpExposureSurface(raw.trim().toLowerCase());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VibeMcpExposureSurface && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VibeMcpExposureSurface($id)';
}

/// Extensible semantic tag attached to MCP tools for conditional selection.
class VibeMcpToolTag {
  const VibeMcpToolTag(this.id);

  final String id;

  static const VibeMcpToolTag readOnly = VibeMcpToolTag('read_only');
  static const VibeMcpToolTag mutating = VibeMcpToolTag('mutating');
  static const VibeMcpToolTag telemetry = VibeMcpToolTag('telemetry');
  static const VibeMcpToolTag processInspect =
      VibeMcpToolTag('process_inspect');
  static const VibeMcpToolTag networkInspect =
      VibeMcpToolTag('network_inspect');
  static const VibeMcpToolTag filesystemRead =
      VibeMcpToolTag('filesystem_read');
  static const VibeMcpToolTag gitRead = VibeMcpToolTag('git_read');
  static const VibeMcpToolTag jobObserve = VibeMcpToolTag('job_observe');
  static const VibeMcpToolTag runtimeDiscovery =
      VibeMcpToolTag('runtime_discovery');
  static const VibeMcpToolTag uiWidget = VibeMcpToolTag('ui_widget');
  static const VibeMcpToolTag compactDiscovery =
      VibeMcpToolTag('compact_discovery');

  static VibeMcpToolTag fromId(String raw) =>
      VibeMcpToolTag(raw.trim().toLowerCase());

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is VibeMcpToolTag && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'VibeMcpToolTag($id)';
}

typedef VibeMcpCategoryClassifier = VibeMcpToolCategory Function(
  String toolName,
);
typedef VibeMcpTagDeriver = Set<VibeMcpToolTag> Function({
  required String name,
  required String scope,
  required bool mutates,
});
typedef VibeMcpSurfaceDeriver = Set<VibeMcpExposureSurface> Function({
  required String name,
  required bool mutates,
  required VibeMcpToolCategory category,
  required Set<VibeMcpToolTag> tags,
});

/// Default generic discovery intent -> category groups (can be overridden per
/// [VibeMcpSelectionCondition] or [VibeMcpToolCatalog]).
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

/// Generic default category classifier based solely on neutral namespace
/// prefixes. Hosts with domain-specific tool naming should pass a custom
/// [VibeMcpCategoryClassifier] to [VibeMcpToolCatalog].
VibeMcpToolCategory classifyVibeMcpToolCategory(String toolName) {
  final name = toolName.trim().toLowerCase();
  if (name.startsWith('client.') || name.startsWith('vibe.')) {
    return VibeMcpToolCategory.clientUi;
  }
  if (name.startsWith('telemetry.')) {
    return VibeMcpToolCategory.telemetry;
  }
  if (name.startsWith('git_') || name.startsWith('git.')) {
    return VibeMcpToolCategory.git;
  }
  return VibeMcpToolCategory.runtime;
}

/// Generic default [VibeMcpToolTag] derivation from a tool's name and mutation
/// flag. Hosts can supply custom [VibeMcpTagDeriver] hooks to attach domain tags.
Set<VibeMcpToolTag> deriveVibeMcpToolTags({
  required String name,
  required String scope,
  required bool mutates,
  Set<String> compactDiscoveryNames = const <String>{},
}) {
  final normalized = name.trim().toLowerCase();
  final tags = <VibeMcpToolTag>{
    if (mutates) VibeMcpToolTag.mutating else VibeMcpToolTag.readOnly,
    if (compactDiscoveryNames.contains(name)) VibeMcpToolTag.compactDiscovery,
  };
  if (!mutates) {
    if (normalized.startsWith('telemetry.')) {
      tags.add(VibeMcpToolTag.telemetry);
    }
    if (normalized.startsWith('git_') || normalized.startsWith('git.')) {
      tags.add(VibeMcpToolTag.gitRead);
    }
  }
  if (normalized.startsWith('client.canvas.') || normalized == 'vibe.canvas') {
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
    VibeMcpExposureSurface.hostPlanner,
    VibeMcpExposureSurface.agentBackground,
  };

  if (!mutates) {
    if (tags.contains(VibeMcpToolTag.telemetry) ||
        tags.contains(VibeMcpToolTag.processInspect) ||
        tags.contains(VibeMcpToolTag.networkInspect) ||
        tags.contains(VibeMcpToolTag.filesystemRead) ||
        tags.contains(VibeMcpToolTag.gitRead) ||
        tags.contains(VibeMcpToolTag.jobObserve) ||
        tags.contains(VibeMcpToolTag.runtimeDiscovery) ||
        tags.contains(VibeMcpToolTag.readOnly) &&
            (category == VibeMcpToolCategory.runtime ||
                category == VibeMcpToolCategory.project ||
                category == VibeMcpToolCategory.git ||
                category == VibeMcpToolCategory.job ||
                category == VibeMcpToolCategory.telemetry)) {
      surfaces.add(VibeMcpExposureSurface.canvasReadOnly);
    }
  } else if (category == VibeMcpToolCategory.clientUi ||
      tags.contains(VibeMcpToolTag.uiWidget)) {
    surfaces.add(VibeMcpExposureSurface.canvasInteractive);
  }

  return Set<VibeMcpExposureSurface>.unmodifiable(surfaces);
}

/// Extensible descriptor for a host-registered MCP tool in Vibe Space.
class VibeMcpToolDescriptor {
  VibeMcpToolDescriptor({
    required this.name,
    required this.scope,
    required this.mutates,
    required this.description,
    this.inputSchema = const <String, dynamic>{'type': 'object'},
    this.location = VibeMcpExecutionLocation.host,
    VibeMcpToolCategory? category,
    Set<VibeMcpToolTag>? tags,
    Set<VibeMcpExposureSurface>? surfaces,
    Set<String> requiredContext = const <String>{},
    bool requiresProjectContext = false,
    this.aliases = const <String>{},
  })  : requiredContext = Set<String>.unmodifiable(<String>{
          ...requiredContext,
          if (requiresProjectContext) 'project',
        }),
        category = category ?? classifyVibeMcpToolCategory(name),
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

  /// Constructs a [VibeMcpToolDescriptor] from a JSON catalog entry, with
  /// optional host-supplied classification and tag/surface hooks.
  factory VibeMcpToolDescriptor.fromCatalogJson(
    Map<String, dynamic> json, {
    VibeMcpCategoryClassifier? classifyCategory,
    VibeMcpTagDeriver? deriveTags,
    VibeMcpSurfaceDeriver? deriveSurfaces,
    Set<String>? requiredContext,
    Set<String>? aliases,
  }) {
    final name = (json['name'] ?? '').toString().trim();
    final scope = (json['scope'] ?? 'read').toString().trim();
    final mutates = json['mutates'] == true;
    final description = (json['description'] ?? '').toString().trim();
    final rawSchema = json['input_schema'];
    final schema = rawSchema is Map<String, dynamic>
        ? rawSchema
        : (rawSchema is Map
            ? rawSchema.map<String, dynamic>((k, v) => MapEntry('$k', v))
            : const <String, dynamic>{'type': 'object'});

    final rawRequiredContext = <String>{
      ...?requiredContext,
      if (json['required_context'] is List)
        for (final item in json['required_context'] as List)
          if (item != null && item.toString().trim().isNotEmpty)
            item.toString().trim(),
    };

    final resolvedCategory = (classifyCategory ?? classifyVibeMcpToolCategory)(
      name,
    );
    final resolvedTags = (deriveTags ??
        ({required String name, required String scope, required bool mutates}) =>
            deriveVibeMcpToolTags(name: name, scope: scope, mutates: mutates))(
      name: name,
      scope: scope,
      mutates: mutates,
    );
    final resolvedSurfaces = (deriveSurfaces ?? deriveVibeMcpExposureSurfaces)(
      name: name,
      mutates: mutates,
      category: resolvedCategory,
      tags: resolvedTags,
    );

    final jsonAliases = <String>{
      ...?aliases,
      if (json['aliases'] is List)
        for (final alias in json['aliases'] as List)
          if (alias != null && alias.toString().trim().isNotEmpty)
            alias.toString().trim(),
    };

    return VibeMcpToolDescriptor(
      name: name,
      scope: scope,
      mutates: mutates,
      description: description,
      inputSchema: schema,
      location: VibeMcpExecutionLocation.fromId(json['location']?.toString()),
      category: resolvedCategory,
      tags: resolvedTags,
      surfaces: resolvedSurfaces,
      requiredContext: rawRequiredContext,
      aliases: Set<String>.unmodifiable(jsonAliases),
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
  final Set<String> requiredContext;
  final Set<String> aliases;

  /// True when this tool is strictly read-only (`mutates == false`).
  bool get isReadOnly => !mutates;

  /// Convenience getter for tools gated on `'project'` in [requiredContext].
  bool get requiresProjectContext => requiredContext.contains('project');

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
        if (requiredContext.isNotEmpty)
          'required_context': requiredContext.toList(growable: false),
        if (aliases.isNotEmpty) 'aliases': aliases.toList(growable: false),
      };
}

/// Runtime condition used to select which MCP tools are exposed to a surface.
class VibeMcpSelectionCondition {
  const VibeMcpSelectionCondition({
    required this.surface,
    this.allowMutating = false,
    this.activeContext = const <String>{},
    this.grantedScopes,
    this.categories,
    this.anyTags,
    this.requiredTags,
    this.intent,
    this.intentCategories,
  });

  /// Convenience condition for live Vibe Canvas components (`window.vibeCanvas.callMcp`).
  /// Enforces `allowMutating: false` and `surface: VibeMcpExposureSurface.canvasReadOnly`.
  factory VibeMcpSelectionCondition.canvasReadOnly({
    Set<String> activeContext = const <String>{},
    Set<String>? grantedScopes,
    Set<VibeMcpToolCategory>? categories,
    Set<VibeMcpToolTag>? anyTags,
  }) {
    return VibeMcpSelectionCondition(
      surface: VibeMcpExposureSurface.canvasReadOnly,
      allowMutating: false,
      activeContext: activeContext,
      grantedScopes: grantedScopes,
      categories: categories,
      anyTags: anyTags,
    );
  }

  final VibeMcpExposureSurface surface;
  final bool allowMutating;
  final Set<String> activeContext;
  final Set<String>? grantedScopes;
  final Set<VibeMcpToolCategory>? categories;
  final Set<VibeMcpToolTag>? anyTags;
  final Set<VibeMcpToolTag>? requiredTags;
  final String? intent;
  final Map<String, List<VibeMcpToolCategory>>? intentCategories;

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
    if (tool.requiredContext.isNotEmpty &&
        !activeContext.containsAll(tool.requiredContext)) {
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
      final intents = intentCategories ?? kVibeDiscoveryIntentCategories;
      final allowedForIntent = intents[intent!.trim().toLowerCase()];
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

/// Extensible MCP tool registry populated by the embedding host application.
///
/// Starts empty so Vibe Space remains completely independent of any specific
/// host's tool names, schemas, or compatibility aliases.
class VibeMcpToolCatalog {
  VibeMcpToolCatalog({
    Iterable<VibeMcpToolDescriptor> tools = const <VibeMcpToolDescriptor>[],
  }) {
    registerAll(tools);
  }

  /// Parses a host-supplied JSON catalog (`{ "tools": [ ... ] }`) using
  /// optional classification, tagging, and surface hooks.
  factory VibeMcpToolCatalog.fromCatalogJson(
    String jsonSource, {
    VibeMcpCategoryClassifier? classifyCategory,
    VibeMcpTagDeriver? deriveTags,
    VibeMcpSurfaceDeriver? deriveSurfaces,
    Iterable<VibeMcpToolDescriptor> baseTools = const <VibeMcpToolDescriptor>[],
  }) {
    final decoded = jsonDecode(jsonSource);
    final descriptors = <VibeMcpToolDescriptor>[...baseTools];
    if (decoded is Map && decoded['tools'] is List) {
      for (final raw in decoded['tools'] as List) {
        if (raw is Map) {
          final map = raw.map<String, dynamic>((k, v) => MapEntry('$k', v));
          descriptors.add(
            VibeMcpToolDescriptor.fromCatalogJson(
              map,
              classifyCategory: classifyCategory,
              deriveTags: deriveTags,
              deriveSurfaces: deriveSurfaces,
            ),
          );
        }
      }
    }
    return VibeMcpToolCatalog(tools: descriptors);
  }

  /// Shared default catalog instance (starts empty until populated by the host).
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

  /// Registers all [descriptors] in the catalog.
  void registerAll(Iterable<VibeMcpToolDescriptor> descriptors) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  /// Removes all registered descriptors and aliases.
  void clear() {
    _byName.clear();
    _aliasToCanonical.clear();
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

  /// Formats a concise LLM prompt section describing the MCP tools exposed under
  /// [condition].
  String buildLlmContextPrompt(VibeMcpSelectionCondition condition) {
    final selected = selectTools(condition);
    if (selected.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('Exposed MCP Tools for surface `${condition.surface.id}`:');
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
}
