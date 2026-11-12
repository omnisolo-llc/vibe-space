import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart' show VibeUiCompatibilityAdapter;

import 'vibe_widget_adapter.dart';

const Set<String> _validTones = <String>{'default', 'ok', 'warn', 'danger'};
final RegExp _hexColorRe = RegExp(r'^#[0-9a-fA-F]{6}$');

const Set<String> _kCanonicalVibeNodeTypes = <String>{
  'heading',
  'text',
  'badge',
  'stat',
  'bar',
  'sparkline',
  'row',
  'card',
  'column',
  'divider',
  'progress',
  'action',
  'button',
  'input',
  'checkbox',
  'option_group',
  'table',
};

/// Returns whether [map] looks like an external UI dialect (A2UI,
/// AdaptiveCard, Markdown wrapper, or PascalCase A2UI component).
bool isExternalUiPayloadMap(Map<dynamic, dynamic> map) {
  final rawType = map['type'];
  if (rawType == 'AdaptiveCard' || rawType == 'markdown') return true;
  if (map['format'] == 'markdown') return true;
  if (map.containsKey('surfaceUpdate') ||
      map.containsKey('beginRendering') ||
      map['components'] is List ||
      map.containsKey('component')) {
    return true;
  }
  if (rawType is String && !_kCanonicalVibeNodeTypes.contains(rawType)) {
    return true;
  }
  return false;
}

/// Normalizes canonical `VibeView`, A2UI, AdaptiveCard, or Markdown wrapper
/// maps into a canonical `VibeView` map.
Map<String, dynamic> normalizeVibeViewInput(Map<String, dynamic> raw) {
  if (isExternalUiPayloadMap(raw)) {
    return Map<String, dynamic>.from(VibeUiCompatibilityAdapter.adapt(raw));
  }
  return raw;
}

bool _isSealedHandleMap(Object? raw) {
  if (raw is! Map || raw.length != 1) return false;
  final sealed = raw['sealed'];
  return sealed is String && sealed.isNotEmpty && sealed.length <= 128;
}

/// Inherited tone palette scope so [VibeSpacePanel] and [VibeEmbedCard]
/// theme nested [VibeView] nodes consistently.
class VibeViewToneScope extends InheritedWidget {
  const VibeViewToneScope({
    super.key,
    required this.accent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.border,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.radius,
    required super.child,
  });

  final Color accent;
  final Color ok;
  final Color warn;
  final Color danger;
  final Color border;
  final Color surface;
  final Color text;
  final Color mutedText;
  final double radius;

  static VibeViewToneScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<VibeViewToneScope>();
  }

  @override
  bool updateShouldNotify(VibeViewToneScope oldWidget) {
    return accent != oldWidget.accent ||
        ok != oldWidget.ok ||
        warn != oldWidget.warn ||
        danger != oldWidget.danger ||
        border != oldWidget.border ||
        surface != oldWidget.surface ||
        text != oldWidget.text ||
        mutedText != oldWidget.mutedText ||
        radius != oldWidget.radius;
  }
}

/// Only declarative widgets cross the extension boundary; no downloaded Flutter widget code runs.
void validateVibeView(Map<String, dynamic> view) {
  var count = 0;
  final inputs = <String>{};
  void visit(Map<String, dynamic> node, int depth) {
    if (depth > 16 || ++count > 1024) {
      throw const FormatException('Extension view limit exceeded');
    }
    void text(String name, {int maximum = 64000}) {
      final value = node[name];
      if (value is! String || value.length > maximum) {
        throw FormatException('Invalid extension $name');
      }
    }

    void textOrSealed(
      String name, {
      int maximum = 64000,
      bool allowNull = false,
      bool allowNum = false,
    }) {
      final value = node[name];
      if (allowNull && value == null) return;
      if (_isSealedHandleMap(value)) return;
      if (allowNum && value is num && value.isFinite) return;
      if (value is String && value.length <= maximum) return;
      throw FormatException('Invalid extension $name');
    }

    void validateTone() {
      final tone = node['tone'];
      if (tone != null && (tone is! String || !_validTones.contains(tone))) {
        throw const FormatException('Invalid extension tone');
      }
    }

    switch (node['type']) {
      case 'heading':
      case 'badge':
      case 'text':
        textOrSealed('text');
        for (final key in ['bold', 'italic', 'code', 'strong', 'mono']) {
          if (node[key] != null && node[key] is! bool) {
            throw const FormatException('Invalid text style');
          }
        }
        validateTone();
      case 'stat':
        textOrSealed('label', maximum: 256);
        textOrSealed('value', maximum: 256, allowNum: true);
        validateTone();
      case 'bar':
        textOrSealed('label', maximum: 256);
        final barVal = node['value'];
        if (barVal is! num || !barVal.isFinite || barVal < 0) {
          throw const FormatException('Invalid extension bar value');
        }
        final barMax = node['max'];
        if (barMax != null && (barMax is! num || !barMax.isFinite || barMax <= 0)) {
          throw const FormatException('Invalid extension bar max');
        }
        textOrSealed('caption', maximum: 256, allowNull: true, allowNum: true);
        final swatch = node['swatch'];
        if (swatch != null && (swatch is! String || !_hexColorRe.hasMatch(swatch))) {
          throw const FormatException('Invalid extension bar swatch');
        }
        validateTone();
      case 'sparkline':
        final values = node['values'];
        if (values is! List || values.length < 2 || values.length > 240) {
          throw const FormatException('Invalid extension sparkline values');
        }
        for (final v in values) {
          if (v is! num || !v.isFinite) {
            throw const FormatException('Invalid extension sparkline point');
          }
        }
        validateTone();
      case 'input':
        text('id', maximum: 64);
        text('label', maximum: 256);
        if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(node['id'] as String) ||
            !inputs.add(node['id'] as String)) {
          throw const FormatException('Invalid extension input ID');
        }
        for (final key in ['secret', 'multiline']) {
          if (node[key] != null && node[key] is! bool) {
            throw const FormatException('Invalid input mode');
          }
        }
      case 'action':
      case 'button':
        if (node['title'] != null) {
          textOrSealed('title', maximum: 256);
        } else {
          textOrSealed('text', maximum: 256);
        }
        text('command', maximum: 128);
        if (node['arguments'] != null && node['arguments'] is! Map) {
          throw const FormatException('Invalid action arguments');
        }
        if (node['args'] != null && node['args'] is! Map) {
          throw const FormatException('Invalid action args');
        }
        validateTone();
      case 'checkbox':
        text('id', maximum: 64);
        text('label', maximum: 256);
        if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(node['id'] as String) ||
            !inputs.add(node['id'] as String)) {
          throw const FormatException('Invalid extension checkbox ID');
        }
        if (node['checked'] != null && node['checked'] is! bool) {
          throw const FormatException('Invalid checkbox checked state');
        }
        if (node['command'] != null) {
          text('command', maximum: 128);
        }
      case 'option_group':
        text('id', maximum: 64);
        if (node['label'] != null) {
          text('label', maximum: 256);
        }
        if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(node['id'] as String) ||
            !inputs.add(node['id'] as String)) {
          throw const FormatException('Invalid extension option_group ID');
        }
        if (node['multiSelect'] != null && node['multiSelect'] is! bool) {
          throw const FormatException('Invalid option_group multiSelect');
        }
        if (node['command'] != null) {
          text('command', maximum: 128);
        }
        final options = node['options'];
        if (options is! List || options.isEmpty || options.length > 50) {
          throw const FormatException('Invalid extension option_group options');
        }
        for (final opt in options) {
          if (opt is! Map) {
            throw const FormatException('Invalid extension option item');
          }
          final optId = opt['id'];
          final optLabel = opt['label'];
          if (optId is! String ||
              optId.isEmpty ||
              optId.length > 64 ||
              optLabel is! String ||
              optLabel.isEmpty ||
              optLabel.length > 256) {
            throw const FormatException('Invalid extension option item fields');
          }
        }
      case 'row':
      case 'card':
      case 'column':
        final children = node['children'];
        if (children is! List || children.length > 100) {
          throw const FormatException('Invalid extension children');
        }
        for (final child in children) {
          if (child is! Map<String, dynamic>) {
            throw const FormatException('Invalid extension child');
          }
          visit(child, depth + 1);
        }
      case 'divider':
        break;
      case 'progress':
        final value = node['value'];
        if (value is! num || !value.isFinite || value < 0 || value > 1) {
          throw const FormatException('Invalid extension progress');
        }
      case 'table':
        final headers = node['headers'];
        final rows = node['rows'];
        if (headers is! List || headers.isEmpty || headers.length > 32) {
          throw const FormatException('Invalid extension table headers');
        }
        for (final h in headers) {
          if (_isSealedHandleMap(h)) continue;
          if (h is! String || h.length > 256) {
            throw const FormatException('Invalid extension table header');
          }
        }
        if (rows is! List || rows.length > 200) {
          throw const FormatException('Invalid extension table rows');
        }
        for (final row in rows) {
          if (row is! List || row.length > 32) {
            throw const FormatException('Invalid extension table row');
          }
          for (final cell in row) {
            if (_isSealedHandleMap(cell)) continue;
            if (cell is! String &&
                cell is! num &&
                cell is! bool &&
                cell != null) {
              throw const FormatException('Invalid extension table cell');
            }
          }
        }
      default:
        throw const FormatException('Unsupported extension view type');
    }
  }

  visit(view, 0);
}

class VibeView extends StatelessWidget {
  const VibeView({
    super.key,
    required this.value,
    required this.onCommand,
    this.onInput,
    this.depth = 0,
    this.autoSubmitTimeoutSeconds,
    this.resolveSealed,
    this.adapter,
  });
  final Map<String, dynamic> value;
  final void Function(String, Map<String, dynamic>) onCommand;
  final void Function(String, String)? onInput;
  final int depth;
  final int? autoSubmitTimeoutSeconds;
  final String? Function(Object? handle)? resolveSealed;
  final VibeWidgetAdapter? adapter;

  VibeWidgetAdapter _effectiveAdapter(BuildContext context) {
    return adapter ??
        VibeWidgetAdapterScope.maybeOf(context) ??
        const VibeWidgetAdapter.material();
  }

  Color _accentColor(BuildContext context) {
    final scope = VibeViewToneScope.maybeOf(context);
    if (scope != null) return scope.accent;
    if (_effectiveAdapter(context).usesCupertino) {
      return CupertinoColors.activeBlue.resolveFrom(context);
    }
    return Theme.of(context).colorScheme.primary;
  }

  Color _mutedColor(BuildContext context) {
    final scope = VibeViewToneScope.maybeOf(context);
    if (scope != null) return scope.mutedText;
    if (_effectiveAdapter(context).usesCupertino) {
      return CupertinoColors.secondaryLabel.resolveFrom(context);
    }
    return Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.72) ??
        Colors.grey;
  }

  Color? _toneColor(BuildContext context, Object? toneRaw) {
    final tone = toneRaw is String ? toneRaw : null;
    if (tone == null || tone == 'default') return null;
    final scope = VibeViewToneScope.maybeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tone) {
      case 'ok':
        return scope?.ok ??
            (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A));
      case 'warn':
        return scope?.warn ??
            (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
      case 'danger':
        return scope?.danger ??
            (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626));
      default:
        return null;
    }
  }

  Color _borderColor(BuildContext context) {
    final scope = VibeViewToneScope.maybeOf(context);
    if (scope != null) return scope.border;
    if (_effectiveAdapter(context).usesCupertino) {
      return CupertinoColors.separator.resolveFrom(context);
    }
    return Theme.of(context).dividerColor.withValues(alpha: 0.35);
  }

  Color _surfaceColor(BuildContext context) {
    final scope = VibeViewToneScope.maybeOf(context);
    if (scope != null) return scope.surface;
    if (_effectiveAdapter(context).usesCupertino) {
      return CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      );
    }
    return Theme.of(context).colorScheme.surface;
  }

  double _radius(BuildContext context) {
    return VibeViewToneScope.maybeOf(context)?.radius ?? 10;
  }

  String _resolvePlainString(Object? raw) {
    if (_isSealedHandleMap(raw)) {
      final resolved = resolveSealed?.call(raw);
      return (resolved != null && resolved.isNotEmpty) ? resolved : '';
    }
    if (raw == null) return '';
    final str = raw.toString();
    return str.length > 64000 ? str.substring(0, 64000) : str;
  }

  Widget _buildValueWidget(
    BuildContext context,
    Object? raw, {
    required VibeWidgetAdapter effectiveAdapter,
    TextStyle? style,
    bool selectable = false,
    bool ellipsis = false,
  }) {
    if (_isSealedHandleMap(raw)) {
      final resolved = resolveSealed?.call(raw);
      if (resolved == null || resolved.isEmpty) {
        return const SizedBox.shrink();
      }
      if (effectiveAdapter.sealedTextBuilder != null) {
        return effectiveAdapter.sealedTextBuilder!(context, resolved, style);
      }
      final accent = _accentColor(context);
      final sealedStyle = (style ?? const TextStyle()).copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: accent.withValues(alpha: 0.8),
        decorationThickness: 1.5,
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 13, color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              resolved,
              style: sealedStyle,
              maxLines: ellipsis ? 1 : null,
              overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
            ),
          ),
        ],
      );
    }

    final text = _resolvePlainString(raw);
    if (selectable && !effectiveAdapter.usesCupertino) {
      return SelectableText(text, style: style);
    }
    return Text(
      text,
      style: style,
      maxLines: ellipsis ? 1 : null,
      overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
    );
  }

  Color? _parseHexColor(Object? raw) {
    if (raw is! String || !_hexColorRe.hasMatch(raw)) return null;
    final hex = raw.substring(1);
    final rgb = int.tryParse(hex, radix: 16);
    if (rgb == null) return null;
    return Color(0xFF000000 | rgb);
  }

  @override
  Widget build(BuildContext context) {
    if (depth > 16) throw const FormatException('Extension view is too deep');
    final node = depth == 0 ? normalizeVibeViewInput(value) : value;
    final effectiveAdapter = _effectiveAdapter(context);
    final usesCupertino = effectiveAdapter.usesCupertino;

    switch (node['type']) {
      case 'heading':
        final toneColor = _toneColor(context, node['tone']);
        final child = _buildValueWidget(
          context,
          node['text'],
          effectiveAdapter: effectiveAdapter,
          selectable: !_isSealedHandleMap(node['text']),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: toneColor,
          ),
        );
        if (effectiveAdapter.headingBuilder != null) {
          return effectiveAdapter.headingBuilder!(
            context,
            node,
            child,
            toneColor,
          );
        }
        return child;
      case 'text':
        final toneColor = _toneColor(context, node['tone']);
        final child = _buildValueWidget(
          context,
          node['text'],
          effectiveAdapter: effectiveAdapter,
          selectable: !_isSealedHandleMap(node['text']),
          style: TextStyle(
            fontWeight: (node['bold'] == true || node['strong'] == true)
                ? FontWeight.bold
                : null,
            fontStyle: node['italic'] == true ? FontStyle.italic : null,
            fontFamily: (node['code'] == true || node['mono'] == true)
                ? 'monospace'
                : null,
            color: toneColor,
          ),
        );
        if (effectiveAdapter.textBuilder != null) {
          return effectiveAdapter.textBuilder!(context, node, child, toneColor);
        }
        return child;
      case 'badge':
        final badgeColor =
            _toneColor(context, node['tone']) ?? _accentColor(context);
        final inner = _buildValueWidget(
          context,
          node['text'],
          effectiveAdapter: effectiveAdapter,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: badgeColor,
          ),
        );
        if (effectiveAdapter.badgeBuilder != null) {
          return effectiveAdapter.badgeBuilder!(
            context,
            node,
            inner,
            badgeColor,
          );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: usesCupertino
                  ? null
                  : Border.all(color: badgeColor.withValues(alpha: 0.45)),
            ),
            child: inner,
          ),
        );
      case 'stat':
        final statTone = _toneColor(context, node['tone']);
        final valueWidget = _buildValueWidget(
          context,
          node['value'],
          effectiveAdapter: effectiveAdapter,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            color: statTone,
          ),
        );
        final labelWidget = _buildValueWidget(
          context,
          node['label'],
          effectiveAdapter: effectiveAdapter,
          style: TextStyle(
            fontSize: 11.5,
            color: _mutedColor(context),
          ),
        );
        if (effectiveAdapter.statBuilder != null) {
          return effectiveAdapter.statBuilder!(
            context,
            node,
            valueWidget,
            labelWidget,
            statTone,
          );
        }
        final border = _borderColor(context);
        final surface = _surfaceColor(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(
              (_radius(context) - 2).clamp(4, 16),
            ),
            border: Border.all(
              color: border,
              width: usesCupertino ? 0.7 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              valueWidget,
              const SizedBox(height: 2),
              labelWidget,
            ],
          ),
        );
      case 'bar':
        final rawVal = (node['value'] as num?)?.toDouble() ?? 0;
        final rawMax = (node['max'] as num?)?.toDouble() ?? 1;
        final safeMax = rawMax > 0 ? rawMax : 1.0;
        final ratio = (rawVal / safeMax).clamp(0.0, 1.0);
        final fillColor =
            _toneColor(context, node['tone']) ?? _accentColor(context);
        final swatchColor = _parseHexColor(node['swatch']);
        final labelWidget = _buildValueWidget(
          context,
          node['label'],
          effectiveAdapter: effectiveAdapter,
          ellipsis: true,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        );
        final captionWidget = node['caption'] != null
            ? _buildValueWidget(
                context,
                node['caption'],
                effectiveAdapter: effectiveAdapter,
                style: TextStyle(
                  fontSize: 11.5,
                  color: _mutedColor(context),
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              )
            : null;
        if (effectiveAdapter.barBuilder != null) {
          return effectiveAdapter.barBuilder!(
            context,
            node,
            labelWidget,
            captionWidget,
            ratio,
            fillColor,
            swatchColor,
          );
        }
        final trackColor = _borderColor(context).withValues(alpha: 0.65);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (swatchColor != null) ...<Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: swatchColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(child: labelWidget),
                if (captionWidget != null) ...<Widget>[
                  const SizedBox(width: 8),
                  captionWidget,
                ],
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: usesCupertino ? 6 : 8,
                color: trackColor,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: ratio,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'sparkline':
        final rawPoints = (node['values'] as List?) ?? const <Object?>[];
        final points = <double>[
          for (final p in rawPoints)
            if (p is num && p.isFinite) p.toDouble(),
        ];
        final strokeColor =
            _toneColor(context, node['tone']) ?? _accentColor(context);
        if (effectiveAdapter.sparklineBuilder != null) {
          return effectiveAdapter.sparklineBuilder!(
            context,
            node,
            points,
            strokeColor,
          );
        }
        return SizedBox(
          height: 28,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(points: points, color: strokeColor),
          ),
        );
      case 'row':
      case 'card':
      case 'column':
        final children = (node['children'] as List).take(100);
        final widgets = <Widget>[
          for (final child in children)
            VibeView(
              value: Map<String, dynamic>.from(child as Map),
              onCommand: onCommand,
              onInput: onInput,
              depth: depth + 1,
              autoSubmitTimeoutSeconds: autoSubmitTimeoutSeconds,
              resolveSealed: resolveSealed,
              adapter: adapter,
            ),
        ];
        if (node['type'] == 'row') {
          return Wrap(spacing: 10, runSpacing: 8, children: widgets);
        }
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < widgets.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 8),
              widgets[i],
            ],
          ],
        );
        if (node['type'] == 'card') {
          if (effectiveAdapter.cardBuilder != null) {
            return effectiveAdapter.cardBuilder!(context, node, column);
          }
          if (usesCupertino) {
            return VibeWidgetAdapter.buildCupertinoCard(context, column);
          }
          return Card(
            child: Padding(padding: const EdgeInsets.all(14), child: column),
          );
        }
        return column;
      case 'divider':
        if (usesCupertino) {
          return Container(
            height: 0.5,
            color: CupertinoColors.separator.resolveFrom(context),
          );
        }
        return const Divider();
      case 'progress':
        final pVal = (node['value'] as num).toDouble().clamp(0.0, 1.0);
        if (usesCupertino) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 6,
              color: CupertinoColors.systemFill.resolveFrom(context),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pVal,
                heightFactor: 1,
                child: Container(color: _accentColor(context)),
              ),
            ),
          );
        }
        return LinearProgressIndicator(value: pVal);
      case 'action':
      case 'button':
        final cmd = node['command'] as String;
        final rawTitle = node['title'] ?? node['text'];
        final title = _resolvePlainString(rawTitle);
        final rawArgs = node['arguments'] ?? node['args'];
        final args = Map<String, dynamic>.from(rawArgs as Map? ?? {});
        final btnTone = _toneColor(context, node['tone']);
        void onPressed() => onCommand(cmd, args);
        if (effectiveAdapter.buttonBuilder != null) {
          return effectiveAdapter.buttonBuilder!(
            context,
            node,
            title,
            cmd,
            args,
            onPressed,
            btnTone,
          );
        }
        if (usesCupertino) {
          return VibeWidgetAdapter.buildCupertinoButton(
            context: context,
            title: title,
            onPressed: onPressed,
            toneColor: btnTone,
            filled: node['type'] == 'action' && cmd == 'approval.approve',
          );
        }
        if (node['type'] == 'action') {
          if (cmd == 'approval.approve') {
            return FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.check, size: 16),
              label: Text(title),
            );
          }
          if (cmd == 'approval.yolo') {
            return OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.bolt, size: 16),
              label: Text(title),
            );
          }
          if (cmd == 'approval.deny') {
            return OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.close, size: 16),
              label: Text(title),
            );
          }
        }
        return OutlinedButton(
          style: btnTone != null
              ? OutlinedButton.styleFrom(
                  foregroundColor: btnTone,
                  side: BorderSide(color: btnTone.withValues(alpha: 0.55)),
                  backgroundColor: btnTone.withValues(alpha: 0.08),
                )
              : null,
          onPressed: onPressed,
          child: Text(title),
        );
      case 'input':
        final inputId = node['id'] as String;
        final inputLabel = node['label'] as String;
        final isSecret = node['secret'] == true;
        final isMultiline = node['multiline'] == true;
        void handleInputChanged(String text) => onInput?.call(inputId, text);
        if (effectiveAdapter.inputBuilder != null) {
          return effectiveAdapter.inputBuilder!(
            context,
            node,
            inputId,
            inputLabel,
            isSecret,
            isMultiline,
            handleInputChanged,
          );
        }
        if (usesCupertino) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (inputLabel.isNotEmpty) ...<Widget>[
                Text(
                  inputLabel,
                  style: TextStyle(fontSize: 12.5, color: _mutedColor(context)),
                ),
                const SizedBox(height: 4),
              ],
              CupertinoTextField(
                key: ValueKey(inputId),
                placeholder: inputLabel,
                obscureText: isSecret,
                maxLines: isSecret ? 1 : (isMultiline ? 5 : 1),
                onChanged: handleInputChanged,
              ),
            ],
          );
        }
        return TextField(
          key: ValueKey(inputId),
          obscureText: isSecret,
          maxLines: isSecret ? 1 : (isMultiline ? 5 : 1),
          onChanged: handleInputChanged,
          decoration: InputDecoration(labelText: inputLabel),
        );
      case 'checkbox':
        return _VibeCheckboxField(
          id: node['id'] as String,
          label: node['label'] as String,
          initialChecked: node['checked'] == true,
          command: node['command'] as String?,
          onInput: onInput,
          onCommand: onCommand,
          node: node,
          adapter: effectiveAdapter,
        );
      case 'option_group':
        final rawTimeout = node['autoSubmitTimeoutSeconds'];
        final nodeTimeout = rawTimeout is int ? rawTimeout : null;
        return _VibeOptionGroupField(
          id: node['id'] as String,
          label: node['label'] as String?,
          multiSelect: node['multiSelect'] == true,
          options: (node['options'] as List)
              .take(50)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false),
          command: node['command'] as String?,
          onInput: onInput,
          onCommand: onCommand,
          autoSubmitTimeoutSeconds: autoSubmitTimeoutSeconds ?? nodeTimeout,
          node: node,
          adapter: effectiveAdapter,
        );
      case 'table':
        final headers = (node['headers'] as List)
            .take(32)
            .toList(growable: false);
        final rows = (node['rows'] as List).take(200);
        final headerWidgets = <Widget>[
          for (final h in headers)
            _buildValueWidget(
              context,
              h,
              effectiveAdapter: effectiveAdapter,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
        ];
        final rowWidgets = <List<Widget>>[
          for (final row in rows)
            if (row is List)
              <Widget>[
                for (var i = 0; i < headers.length; i++)
                  i < row.length
                      ? _buildValueWidget(
                          context,
                          row[i],
                          effectiveAdapter: effectiveAdapter,
                          selectable: !_isSealedHandleMap(row[i]),
                        )
                      : const Text(''),
              ],
        ];
        if (effectiveAdapter.tableBuilder != null) {
          return effectiveAdapter.tableBuilder!(
            context,
            node,
            headerWidgets,
            rowWidgets,
          );
        }
        if (usesCupertino) {
          final sepColor = CupertinoColors.separator.resolveFrom(context);
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: sepColor, width: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                border: TableBorder.symmetric(
                  inside: BorderSide(color: sepColor, width: 0.5),
                ),
                children: <TableRow>[
                  TableRow(
                    decoration: BoxDecoration(
                      color: CupertinoColors.tertiarySystemFill.resolveFrom(
                        context,
                      ),
                    ),
                    children: <Widget>[
                      for (final hw in headerWidgets)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: hw,
                        ),
                    ],
                  ),
                  for (final rw in rowWidgets)
                    TableRow(
                      children: <Widget>[
                        for (final cell in rw)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: cell,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 48,
            columnSpacing: 18,
            horizontalMargin: 12,
            columns: <DataColumn>[
              for (final hw in headerWidgets) DataColumn(label: hw),
            ],
            rows: <DataRow>[
              for (final rw in rowWidgets)
                DataRow(
                  cells: <DataCell>[
                    for (final cell in rw) DataCell(cell),
                  ],
                ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    var minVal = points[0];
    var maxVal = points[0];
    for (var i = 1; i < points.length; i++) {
      if (points[i] < minVal) minVal = points[i];
      if (points[i] > maxVal) maxVal = points[i];
    }
    final span = maxVal - minVal;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final normalized = span == 0 ? 0.5 : (points[i] - minVal) / span;
      final y = size.height - 3 - normalized * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (color != oldDelegate.color || points.length != oldDelegate.points.length) {
      return true;
    }
    for (var i = 0; i < points.length; i++) {
      if (points[i] != oldDelegate.points[i]) return true;
    }
    return false;
  }
}

class _VibeCheckboxField extends StatefulWidget {
  const _VibeCheckboxField({
    required this.id,
    required this.label,
    required this.initialChecked,
    this.command,
    this.onInput,
    required this.onCommand,
    required this.node,
    required this.adapter,
  });

  final String id;
  final String label;
  final bool initialChecked;
  final String? command;
  final void Function(String, String)? onInput;
  final void Function(String, Map<String, dynamic>) onCommand;
  final Map<String, dynamic> node;
  final VibeWidgetAdapter adapter;

  @override
  State<_VibeCheckboxField> createState() => _VibeCheckboxFieldState();
}

class _VibeCheckboxFieldState extends State<_VibeCheckboxField> {
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _checked = widget.initialChecked;
  }

  @override
  void didUpdateWidget(covariant _VibeCheckboxField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChecked != widget.initialChecked) {
      _checked = widget.initialChecked;
    }
  }

  void _setChecked(bool checked) {
    setState(() => _checked = checked);
    widget.onInput?.call(widget.id, checked ? 'true' : 'false');
    if (widget.command != null && widget.command!.isNotEmpty) {
      widget.onCommand(widget.command!, <String, dynamic>{
        'id': widget.id,
        'label': widget.label,
        'checked': checked,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adapter.checkboxBuilder != null) {
      return widget.adapter.checkboxBuilder!(
        context,
        widget.node,
        widget.id,
        widget.label,
        _checked,
        _setChecked,
      );
    }
    if (widget.adapter.usesCupertino) {
      return Row(
        key: ValueKey('vibe-checkbox-${widget.id}'),
        children: <Widget>[
          CupertinoSwitch(
            value: _checked,
            onChanged: _setChecked,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.label)),
        ],
      );
    }
    return CheckboxListTile(
      key: ValueKey('vibe-checkbox-${widget.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(widget.label),
      value: _checked,
      onChanged: (next) => _setChecked(next ?? false),
    );
  }
}

class _VibeOptionGroupField extends StatefulWidget {
  const _VibeOptionGroupField({
    required this.id,
    this.label,
    required this.multiSelect,
    required this.options,
    this.command,
    this.onInput,
    required this.onCommand,
    this.autoSubmitTimeoutSeconds,
    required this.node,
    required this.adapter,
  });

  final String id;
  final String? label;
  final bool multiSelect;
  final List<Map<String, dynamic>> options;
  final String? command;
  final void Function(String, String)? onInput;
  final void Function(String, Map<String, dynamic>) onCommand;
  final int? autoSubmitTimeoutSeconds;
  final Map<String, dynamic> node;
  final VibeWidgetAdapter adapter;

  @override
  State<_VibeOptionGroupField> createState() => _VibeOptionGroupFieldState();
}

class _VibeOptionGroupFieldState extends State<_VibeOptionGroupField> {
  late Set<String> _selectedIds;
  Timer? _countdownTimer;
  int? _remainingSeconds;
  bool _timerCancelled = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{
      for (final opt in widget.options)
        if (opt['checked'] == true || opt['selected'] == true)
          opt['id'].toString(),
    };
    _configureCountdownTimer();
  }

  @override
  void didUpdateWidget(covariant _VibeOptionGroupField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoSubmitTimeoutSeconds != widget.autoSubmitTimeoutSeconds ||
        oldWidget.id != widget.id) {
      if (oldWidget.id != widget.id) {
        _timerCancelled = false;
        _remainingSeconds = null;
      }
      _configureCountdownTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _configureCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    final timeout = widget.autoSubmitTimeoutSeconds;
    if (!widget.multiSelect ||
        widget.command == null ||
        widget.command!.isEmpty ||
        timeout == null ||
        timeout <= 0 ||
        _timerCancelled) {
      _remainingSeconds = null;
      return;
    }
    _remainingSeconds ??= timeout.clamp(1, 600);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = _remainingSeconds ?? 0;
      if (current <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        if (_selectedIds.isNotEmpty &&
            widget.command != null &&
            widget.command!.isNotEmpty) {
          widget.onCommand(widget.command!, <String, dynamic>{
            'id': widget.id,
            'selected': _selectedIds.toList(growable: false),
            'values': _selectedValues(),
          });
        }
      } else {
        setState(() => _remainingSeconds = current - 1);
      }
    });
  }

  List<String> _selectedValues() {
    final values = <String>[];
    for (final opt in widget.options) {
      final optId = opt['id'].toString();
      if (_selectedIds.contains(optId)) {
        final val = opt['value']?.toString();
        values.add(val != null && val.isNotEmpty ? val : optId);
      }
    }
    return values;
  }

  void _toggleOption(String optId) {
    setState(() {
      if (widget.multiSelect) {
        if (!_selectedIds.remove(optId)) {
          _selectedIds.add(optId);
        }
      } else {
        _selectedIds = <String>{optId};
      }
    });
    final values = _selectedValues();
    widget.onInput?.call(widget.id, values.join(','));
    if (!widget.multiSelect &&
        widget.command != null &&
        widget.command!.isNotEmpty) {
      widget.onCommand(widget.command!, <String, dynamic>{
        'id': widget.id,
        'selected': _selectedIds.toList(growable: false),
        'values': values,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adapter.optionGroupBuilder != null) {
      return widget.adapter.optionGroupBuilder!(
        context,
        widget.node,
        widget.id,
        widget.label,
        widget.multiSelect,
        widget.options,
        Set<String>.unmodifiable(_selectedIds),
        _toggleOption,
      );
    }

    if (widget.adapter.usesCupertino) {
      if (!widget.multiSelect &&
          widget.options.length >= 2 &&
          widget.options.length <= 5) {
        final segChildren = <String, Widget>{
          for (final opt in widget.options)
            opt['id'].toString(): Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                opt['label'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        };
        final firstSel = _selectedIds.isNotEmpty &&
                segChildren.containsKey(_selectedIds.first)
            ? _selectedIds.first
            : null;
        return Column(
          key: ValueKey('vibe-option-group-${widget.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.label != null && widget.label!.trim().isNotEmpty) ...<Widget>[
              Text(
                widget.label!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 8),
            ],
            CupertinoSlidingSegmentedControl<String>(
              groupValue: firstSel,
              children: segChildren,
              onValueChanged: (next) {
                if (next != null) _toggleOption(next);
              },
            ),
          ],
        );
      }

      return Column(
        key: ValueKey('vibe-option-group-${widget.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.label != null && widget.label!.trim().isNotEmpty) ...<Widget>[
            Text(
              widget.label!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final opt in widget.options)
                () {
                  final optId = opt['id'].toString();
                  final optLabel = opt['label'].toString();
                  final selected = _selectedIds.contains(optId);
                  return VibeWidgetAdapter.buildCupertinoButton(
                    context: context,
                    title: optLabel,
                    filled: selected,
                    onPressed: () => _toggleOption(optId),
                  );
                }(),
            ],
          ),
          if (widget.multiSelect &&
              widget.command != null &&
              widget.command!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton.filled(
                key: ValueKey('vibe-option-submit-${widget.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () {
                        _countdownTimer?.cancel();
                        widget.onCommand(
                          widget.command!,
                          <String, dynamic>{
                            'id': widget.id,
                            'selected': _selectedIds.toList(growable: false),
                            'values': _selectedValues(),
                          },
                        );
                      },
                child: Text(
                  _remainingSeconds != null
                      ? 'Submit Selected (${_selectedIds.length}) · ${_remainingSeconds}s'
                      : 'Submit Selected (${_selectedIds.length})',
                ),
              ),
            ),
          ],
        ],
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.14);
    final selectedBg = colorScheme.primary.withValues(
      alpha: isDark ? 0.16 : 0.10,
    );
    final unselectedBg = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.black.withValues(alpha: 0.02);
    final allSelected =
        widget.options.isNotEmpty &&
        _selectedIds.length == widget.options.length;

    return Column(
      key: ValueKey('vibe-option-group-${widget.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if ((widget.label != null && widget.label!.trim().isNotEmpty) ||
            widget.multiSelect) ...<Widget>[
          Row(
            children: <Widget>[
              if (widget.label != null && widget.label!.trim().isNotEmpty)
                Expanded(
                  child: Text(
                    widget.label!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (widget.multiSelect && widget.options.isNotEmpty) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '${_selectedIds.length}/${widget.options.length} selected',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      if (allSelected) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds = <String>{
                          for (final opt in widget.options)
                            opt['id'].toString(),
                        };
                      }
                    });
                    widget.onInput?.call(
                      widget.id,
                      _selectedValues().join(','),
                    );
                  },
                  child: Text(
                    allSelected ? 'Clear' : 'Select all',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: unselectedBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < widget.options.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: borderColor),
                () {
                  final opt = widget.options[i];
                  final optId = opt['id'].toString();
                  final optLabel = opt['label'].toString();
                  final optDesc =
                      (opt['description'] ?? opt['subtitle'] ?? '')
                          .toString()
                          .trim();
                  final selected = _selectedIds.contains(optId);
                  return Material(
                    color: selected ? selectedBg : Colors.transparent,
                    child: InkWell(
                      key: ValueKey('vibe-option-${widget.id}-$optId'),
                      onTap: () => _toggleOption(optId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            SizedBox(
                              width: 14,
                              child: Text(
                                selected ? '›' : ' ',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}.',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                            Icon(
                              widget.multiSelect
                                  ? (selected
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded)
                                  : (selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked),
                              size: 19,
                              color: selected
                                  ? colorScheme.primary
                                  : theme.textTheme.bodyMedium?.color
                                      ?.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    optLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (optDesc.isNotEmpty &&
                                      optDesc != 'null') ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      optDesc,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: theme
                                            .textTheme.bodyMedium?.color
                                            ?.withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
              ],
            ],
          ),
        ),
        if (widget.multiSelect &&
            widget.command != null &&
            widget.command!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              Text(
                'Click rows to toggle · Confirm selection to continue',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.textTheme.bodyMedium?.color?.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (_remainingSeconds != null)
                    Container(
                      key: ValueKey('vibe-option-countdown-${widget.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.65),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Auto-approving in ${_remainingSeconds}s',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            key: ValueKey(
                              'vibe-option-cancel-timer-${widget.id}',
                            ),
                            onTap: () {
                              _countdownTimer?.cancel();
                              setState(() {
                                _timerCancelled = true;
                                _remainingSeconds = null;
                              });
                            },
                            child: const Icon(
                              Icons.pause_circle_outline,
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  FilledButton.tonalIcon(
                    key: ValueKey('vibe-option-submit-${widget.id}'),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () {
                            _countdownTimer?.cancel();
                            widget.onCommand(
                              widget.command!,
                              <String, dynamic>{
                                'id': widget.id,
                                'selected':
                                    _selectedIds.toList(growable: false),
                                'values': _selectedValues(),
                              },
                            );
                          },
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      _remainingSeconds != null
                          ? 'Submit Selected (${_selectedIds.length}) · ${_remainingSeconds}s'
                          : 'Submit Selected (${_selectedIds.length})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}
