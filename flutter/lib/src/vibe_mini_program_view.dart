import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart';

import 'vibe_runtime_view.dart' show toVibeDynamicMap;
import 'vibe_widget_adapter.dart';
import 'view.dart';

/// Native Skyline renderer for a [VibeMiniProgramSession], memoizing compiled
/// `VibeView` trees by session revision and failing closed on invalid handlers.
class VibeMiniProgramView extends StatefulWidget {
  const VibeMiniProgramView({
    super.key,
    required this.session,
    this.resolveSealed,
    this.adapter,
    this.onCommand,
    this.onEvent,
    this.errorColor,
  });

  final VibeMiniProgramSession session;
  final String? Function(Object? handle)? resolveSealed;
  final VibeWidgetAdapter? adapter;
  final void Function(String command, Map<String, dynamic> args)? onCommand;
  final ValueChanged<VibeMiniProgramEvent>? onEvent;
  final Color? errorColor;

  @override
  State<VibeMiniProgramView> createState() => _VibeMiniProgramViewState();
}

class _VibeMiniProgramViewState extends State<VibeMiniProgramView> {
  VibeMiniProgramSession? _cachedSession;
  int _cachedRevision = -1;
  Map<String, dynamic>? _cachedDynamicView;
  String? _buildError;

  @override
  void didUpdateWidget(covariant VibeMiniProgramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _cachedSession = null;
      _cachedRevision = -1;
      _cachedDynamicView = null;
      _buildError = null;
    }
  }

  void _ensureCompiledView() {
    if (identical(_cachedSession, widget.session) &&
        _cachedRevision == widget.session.revision &&
        (_cachedDynamicView != null || _buildError != null)) {
      return;
    }
    _cachedSession = widget.session;
    _cachedRevision = widget.session.revision;
    try {
      final raw = widget.session.buildView();
      _cachedDynamicView = raw == null ? null : toVibeDynamicMap(raw);
      _buildError = null;
    } on Object catch (err) {
      _cachedDynamicView = null;
      _buildError = err.toString();
    }
  }

  void _handleCommand(String cmd, Map<String, dynamic> args) {
    final event = VibeMiniProgramEvent.tryFromCommand(cmd, args);
    if (event != null) {
      widget.onEvent?.call(event);
      try {
        widget.session.dispatchEvent(event);
        _buildError = null;
      } on Object catch (err) {
        _cachedDynamicView = null;
        _buildError = err.toString();
      }
      if (mounted) setState(() {});
    }
    widget.onCommand?.call(cmd, args);
  }

  @override
  Widget build(BuildContext context) {
    _ensureCompiledView();
    final err = _buildError;
    if (err != null) {
      return Text(
        err,
        style: TextStyle(
          fontSize: 12,
          color: widget.errorColor ?? Theme.of(context).colorScheme.error,
        ),
      );
    }
    final view = _cachedDynamicView;
    if (view == null) {
      return const SizedBox.shrink();
    }
    return VibeView(
      value: view,
      resolveSealed: widget.resolveSealed,
      adapter: widget.adapter,
      onCommand: _handleCommand,
    );
  }
}

/// Compatibility alias for [VibeMiniProgramView].
typedef VibeSnippetView = VibeMiniProgramView;
