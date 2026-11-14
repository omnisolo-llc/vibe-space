import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart';

import 'canvas_view.dart';
import 'vibe_runtime_view.dart';
import 'vibe_space_widgets.dart';
import 'vibe_widget_adapter.dart';
import 'view.dart';

/// Layout mode for [VibeTriggeredViewDeck] when multiple entries match at once.
enum VibeTriggeredDeckLayout { stacked, tabbed }

/// Reactive Flutter [ChangeNotifier] controller backed by [VibeConditionalRegistry].
class VibeConditionalController extends ChangeNotifier {
  VibeConditionalController({
    VibeConditionalRegistry? registry,
    VibeProtocolHost? host,
    VibeStorageAdapter? storage,
    String storageKey = 'vibe_space.conditional_entries.v1',
  })  : _ownsRegistry = registry == null,
        registry = registry ??
            VibeConditionalRegistry(
              host: host,
              storage: storage,
              storageKey: storageKey,
            ) {
    _detach = this.registry.onChange(_onRegistryChanged);
  }

  final VibeConditionalRegistry registry;
  final bool _ownsRegistry;
  late final void Function() _detach;
  bool _disposed = false;

  VibeProtocolHost? get host => registry.host;
  VibeTriggerContext get currentContext => registry.currentContext;
  VibeTriggerEvaluationResult get lastResult => registry.lastResult;
  List<VibeConditionalEntry> get entries => registry.entries;
  List<VibeConditionalEntry> get presetEntries => registry.presetEntries;
  List<VibeConditionalEntry> get customEntries => registry.customEntries;
  List<VibeConditionalEntry> get activeEntries => registry.activeEntries;

  VibeConditionalEntry? entryById(String id) => registry.entryById(id);

  void registerPresets(
    Iterable<Object> presets, {
    bool preserveUserOverrides = true,
    int? nowMs,
  }) {
    registry.registerPresets(
      presets,
      preserveUserOverrides: preserveUserOverrides,
      nowMs: nowMs,
    );
  }

  void hydratePresetPayloads(Map<String, Object?> payloads, {int? nowMs}) {
    registry.hydratePresetPayloads(payloads, nowMs: nowMs);
  }

  void upsert(VibeConditionalEntry entry, {int? nowMs}) {
    registry.upsert(entry, nowMs: nowMs);
  }

  bool unregister(String id, {int? nowMs}) =>
      registry.unregister(id, nowMs: nowMs);

  void setEnabled(String id, bool enabled, {int? nowMs}) {
    registry.setEnabled(id, enabled, nowMs: nowMs);
  }

  void setPinned(String id, bool pinned, {int? nowMs}) {
    registry.setPinned(id, pinned, nowMs: nowMs);
  }

  void updateCondition(
    String id,
    VibeTriggerCondition? condition, {
    int? nowMs,
  }) {
    registry.updateCondition(id, condition, nowMs: nowMs);
  }

  void resetPresetOverride(String id, {int? nowMs}) {
    registry.resetPresetOverride(id, nowMs: nowMs);
  }

  void dismissCurrentActivation(String id, {int? nowMs}) {
    registry.dismissCurrentActivation(id, nowMs: nowMs);
  }

  void undismiss(String id, {int? nowMs}) {
    registry.undismiss(id, nowMs: nowMs);
  }

  VibeTriggerEvaluationResult updateContext(
    VibeTriggerContext nextContext, {
    int? nowMs,
  }) =>
      registry.updateContext(nextContext, nowMs: nowMs);

  VibeTriggerEvaluationResult updateContextFromJson(
    Map<String, Object?> contextJson, {
    int? nowMs,
  }) =>
      registry.updateContextFromJson(contextJson, nowMs: nowMs);

  void _onRegistryChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _detach();
    if (_ownsRegistry) {
      registry.dispose();
    }
    super.dispose();
  }
}

/// Compact pill displaying a human-readable [VibeTriggerCondition] summary.
class VibeTriggerRuleBadge extends StatelessWidget {
  const VibeTriggerRuleBadge({
    super.key,
    required this.condition,
    this.theme,
  });

  final VibeTriggerCondition condition;
  final VibeSpaceThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? VibeSpaceThemeData.fromTheme(Theme.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bolt, size: 12, color: t.accent),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              condition.describe(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.accent,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a single [VibeConditionalEntry] (`miniProgram`, `vxml`, `wasm`,
/// `js`, `a2ui`, `vibe_ui`, `markdown`, or opt-in `dom`) inside a themed,
/// `RepaintBoundary`-isolated card.
class VibeConditionalEntryCard extends StatelessWidget {
  const VibeConditionalEntryCard({
    super.key,
    required this.entry,
    this.triggerContext = const VibeTriggerContext(),
    this.host,
    this.domBridge,
    this.onDomDataPush,
    this.theme,
    this.adapter,
    this.showHeader = true,
    this.showRuleBadge = true,
    this.onDismiss,
    this.onTogglePin,
    this.onCommand,
    this.onCanvasAction,
    this.markdownBuilder,
    this.webViewportBuilder,
  });

  final VibeConditionalEntry entry;
  final VibeTriggerContext triggerContext;
  final VibeProtocolHost? host;
  final VibeDomBridgeController? domBridge;
  final ValueChanged<VibeDomDataModelMessage>? onDomDataPush;
  final VibeSpaceThemeData? theme;
  final VibeWidgetAdapter? adapter;
  final bool showHeader;
  final bool showRuleBadge;
  final VoidCallback? onDismiss;
  final ValueChanged<bool>? onTogglePin;
  final void Function(String command, Map<String, dynamic> args)? onCommand;
  final ValueChanged<VibeCanvasActionEvent>? onCanvasAction;
  final VibeCanvasMarkdownBuilder? markdownBuilder;
  final VibeCanvasWebViewportBuilder? webViewportBuilder;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? VibeSpaceThemeData.fromTheme(Theme.of(context));
    Widget body = VibeRuntimeBody(
      entry: entry,
      triggerContext: triggerContext,
      theme: t,
      host: host,
      domBridge: domBridge,
      onDomDataPush: onDomDataPush,
      adapter: adapter,
      onCommand: onCommand,
      onCanvasAction: onCanvasAction,
      markdownBuilder: markdownBuilder,
      webViewportBuilder: webViewportBuilder,
    );
    if (adapter != null) {
      body = VibeWidgetAdapterScope(adapter: adapter!, child: body);
    }
    body = VibeViewToneScope(
      accent: t.accent,
      ok: t.ok,
      warn: t.warn,
      danger: t.danger,
      border: t.border,
      surface: t.surface,
      text: t.text,
      mutedText: t.mutedText,
      radius: t.radius,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: t.text,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        child: body,
      ),
    );

    return RepaintBoundary(
      child: Container(
        key: ValueKey<String>('vibe-conditional-card-${entry.id}'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.cardBackground,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showHeader) ...<Widget>[
              _buildHeader(t),
              const SizedBox(height: 8),
            ],
            body,
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(VibeSpaceThemeData t) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                entry.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              if (entry.isPreset)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'Preset',
                    style: TextStyle(fontSize: 10.5, color: t.mutedText),
                  ),
                ),
              if (showRuleBadge && entry.condition != null)
                VibeTriggerRuleBadge(condition: entry.condition!, theme: t),
            ],
          ),
        ),
        if (onTogglePin != null)
          IconButton(
            key: ValueKey<String>('vibe-conditional-pin-${entry.id}'),
            tooltip: entry.pinned ? 'Unpin view' : 'Pin view',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.all(3),
            iconSize: 15,
            color: entry.pinned ? t.accent : t.mutedText,
            icon: Icon(entry.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => onTogglePin!(!entry.pinned),
          ),
        if (onDismiss != null)
          IconButton(
            key: ValueKey<String>('vibe-conditional-dismiss-${entry.id}'),
            tooltip: 'Dismiss until re-triggered',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.all(3),
            iconSize: 15,
            color: t.mutedText,
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
      ],
    );
  }
}

/// Reactive deck rendering all currently triggered [VibeConditionalEntry] views
/// from [controller].
class VibeTriggeredViewDeck extends StatefulWidget {
  const VibeTriggeredViewDeck({
    super.key,
    required this.controller,
    this.layout = VibeTriggeredDeckLayout.stacked,
    this.domBridge,
    this.onDomDataPush,
    this.theme,
    this.adapter,
    this.showRuleBadges = true,
    this.emptyBuilder,
    this.onCommand,
    this.onCanvasAction,
    this.markdownBuilder,
    this.webViewportBuilder,
  });

  final VibeConditionalController controller;
  final VibeTriggeredDeckLayout layout;
  final VibeDomBridgeController? domBridge;
  final ValueChanged<VibeDomDataModelMessage>? onDomDataPush;
  final VibeSpaceThemeData? theme;
  final VibeWidgetAdapter? adapter;
  final bool showRuleBadges;
  final WidgetBuilder? emptyBuilder;
  final void Function(
    VibeConditionalEntry entry,
    String command,
    Map<String, dynamic> args,
  )? onCommand;
  final ValueChanged<VibeCanvasActionEvent>? onCanvasAction;
  final VibeCanvasMarkdownBuilder? markdownBuilder;
  final VibeCanvasWebViewportBuilder? webViewportBuilder;

  @override
  State<VibeTriggeredViewDeck> createState() => _VibeTriggeredViewDeckState();
}

class _VibeTriggeredViewDeckState extends State<VibeTriggeredViewDeck> {
  String? _selectedTabId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final active = widget.controller.activeEntries;
        if (active.isEmpty) {
          return widget.emptyBuilder?.call(context) ?? const SizedBox.shrink();
        }
        final t =
            widget.theme ?? VibeSpaceThemeData.fromTheme(Theme.of(context));

        if (widget.layout == VibeTriggeredDeckLayout.tabbed &&
            active.length > 1) {
          final current = active.firstWhere(
            (e) => e.id == _selectedTabId,
            orElse: () => active.first,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < active.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 6),
                      ChoiceChip(
                        key: ValueKey<String>(
                          'vibe-triggered-tab-${active[i].id}',
                        ),
                        label: Text(active[i].title),
                        selected: active[i].id == current.id,
                        onSelected: (_) =>
                            setState(() => _selectedTabId = active[i].id),
                      ),
                    ],
                  ],
                ),
              ),
              _buildCard(current, t),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < active.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 8),
              _buildCard(active[i], t),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCard(VibeConditionalEntry entry, VibeSpaceThemeData t) {
    return VibeConditionalEntryCard(
      key: ValueKey<String>('vibe-deck-entry-${entry.id}'),
      entry: entry,
      triggerContext: widget.controller.currentContext,
      host: widget.controller.host,
      domBridge: widget.domBridge,
      onDomDataPush: widget.onDomDataPush,
      theme: t,
      adapter: widget.adapter,
      showRuleBadge: widget.showRuleBadges,
      onDismiss: () => widget.controller.dismissCurrentActivation(entry.id),
      onTogglePin: (pinned) => widget.controller.setPinned(entry.id, pinned),
      onCommand: widget.onCommand != null
          ? (cmd, args) => widget.onCommand!(entry, cmd, args)
          : null,
      onCanvasAction: widget.onCanvasAction,
      markdownBuilder: widget.markdownBuilder,
      webViewportBuilder: widget.webViewportBuilder,
    );
  }
}
