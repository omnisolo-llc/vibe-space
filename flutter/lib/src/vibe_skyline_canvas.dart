import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart'
    show isValidMiniProgramHandlerName, kMaxVibeCanvasCommands, vibeDeepEquals;

import 'view.dart' show VibeViewToneScope;

int? _hexNibble(int cu) {
  if (cu >= 48 && cu <= 57) return cu - 48;
  if (cu >= 65 && cu <= 70) return cu - 55;
  if (cu >= 97 && cu <= 102) return cu - 87;
  return null;
}

Color? _parseHexColorFast(String s) {
  final len = s.length;
  if (len == 4) {
    final r = _hexNibble(s.codeUnitAt(1));
    final g = _hexNibble(s.codeUnitAt(2));
    final b = _hexNibble(s.codeUnitAt(3));
    if (r == null || g == null || b == null) return null;
    return Color.fromARGB(255, (r << 4) | r, (g << 4) | g, (b << 4) | b);
  }
  if (len == 7 || len == 9) {
    var argb = len == 7 ? 0xFF : 0;
    for (var i = 1; i < len; i++) {
      final nib = _hexNibble(s.codeUnitAt(i));
      if (nib == null) return null;
      argb = (argb << 4) | nib;
    }
    return Color(argb);
  }
  return null;
}

/// Resolves a hex color (`#RGB`, `#RRGGBB`, `#AARRGGBB`) or semantic token
/// (`accent`, `ok`, `warn`, `danger`, `surface`, `border`, `text`, `muted`).
Color? resolveVibeSkylineColor(
  BuildContext context,
  Object? raw, {
  String? fallbackTone,
}) {
  final scope = VibeViewToneScope.maybeOf(context);
  final cs = Theme.of(context).colorScheme;
  if (raw is String && raw.trim().isNotEmpty) {
    final s = raw.trim();
    if (s.startsWith('#')) {
      final c = _parseHexColorFast(s);
      if (c != null) return c;
    }
    return switch (s) {
      'accent' => scope?.accent ?? cs.primary,
      'ok' => scope?.ok ?? Colors.green,
      'warn' => scope?.warn ?? Colors.orange,
      'danger' => scope?.danger ?? cs.error,
      'surface' || 'card' => scope?.surface ?? cs.surfaceContainerLow,
      'border' => scope?.border ?? cs.outlineVariant,
      'text' => scope?.text ?? cs.onSurface,
      'muted' => scope?.mutedText ?? cs.onSurfaceVariant,
      'transparent' => Colors.transparent,
      _ => null,
    };
  }
  return switch (fallbackTone) {
    'ok' => scope?.ok ?? Colors.green,
    'warn' => scope?.warn ?? Colors.orange,
    'danger' => scope?.danger ?? cs.error,
    'default' => scope?.accent ?? cs.primary,
    _ => null,
  };
}

/// Native Skia/Impeller 2D vector draw-list widget (`type: 'canvas'`), capped at
/// [kMaxVibeCanvasCommands] (`<= 2,000`) commands per frame with zero WebViews.
class VibeSkylineCanvas extends StatelessWidget {
  const VibeSkylineCanvas({
    super.key,
    required this.width,
    required this.height,
    required this.commands,
    this.tone,
    this.semanticsLabel,
    this.resolveSealed,
    this.onTap,
  });

  final double width;
  final double height;
  final List<Map<String, dynamic>> commands;
  final String? tone;
  final String? semanticsLabel;
  final String? Function(Object? handle)? resolveSealed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scope = VibeViewToneScope.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final palette = VibeSkylinePalette(
      accent: scope?.accent ?? cs.primary,
      ok: scope?.ok ?? Colors.green,
      warn: scope?.warn ?? Colors.orange,
      danger: scope?.danger ?? cs.error,
      surface: scope?.surface ?? cs.surfaceContainerLow,
      border: scope?.border ?? cs.outlineVariant,
      text: scope?.text ?? cs.onSurface,
      muted: scope?.mutedText ?? cs.onSurfaceVariant,
    );
    final defaultColor = palette.toneColor(tone ?? 'default') ?? palette.accent;

    Widget painted = RepaintBoundary(
      child: SizedBox(
        width: width.clamp(16.0, 2048.0),
        height: height.clamp(16.0, 2048.0),
        child: CustomPaint(
          painter: VibeSkylineCanvasPainter(
            logicalWidth: width.clamp(16.0, 2048.0),
            logicalHeight: height.clamp(16.0, 2048.0),
            commands: commands.length <= kMaxVibeCanvasCommands
                ? commands
                : commands.sublist(0, kMaxVibeCanvasCommands),
            defaultColor: defaultColor,
            palette: palette,
            resolveSealed: resolveSealed,
          ),
        ),
      ),
    );

    if (onTap != null) {
      painted = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: painted,
        ),
      );
    }
    if (semanticsLabel != null && semanticsLabel!.isNotEmpty) {
      painted = Semantics(
        label: semanticsLabel,
        button: onTap != null,
        child: painted,
      );
    }
    return painted;
  }
}

@immutable
class VibeSkylinePalette {
  const VibeSkylinePalette({
    required this.accent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
  });

  final Color accent;
  final Color ok;
  final Color warn;
  final Color danger;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;

  Color? toneColor(String? fallbackTone) => switch (fallbackTone) {
        'ok' => ok,
        'warn' => warn,
        'danger' => danger,
        'default' => accent,
        _ => null,
      };

  Color? parseColor(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final s = raw.trim();
    if (s.startsWith('#')) {
      final c = _parseHexColorFast(s);
      if (c != null) return c;
    }
    return switch (s) {
      'accent' => accent,
      'ok' => ok,
      'warn' => warn,
      'danger' => danger,
      'surface' || 'card' => surface,
      'border' => border,
      'text' => text,
      'muted' => muted,
      'transparent' => Colors.transparent,
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeSkylinePalette &&
          other.accent == accent &&
          other.ok == ok &&
          other.warn == warn &&
          other.danger == danger &&
          other.surface == surface &&
          other.border == border &&
          other.text == text &&
          other.muted == muted;

  @override
  int get hashCode =>
      Object.hash(accent, ok, warn, danger, surface, border, text, muted);
}

/// `CustomPainter` executing bounded Skyline 2D draw commands on Skia/Impeller.
class VibeSkylineCanvasPainter extends CustomPainter {
  const VibeSkylineCanvasPainter({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.commands,
    required this.defaultColor,
    required this.palette,
    this.resolveSealed,
  });

  final double logicalWidth;
  final double logicalHeight;
  final List<Map<String, dynamic>> commands;
  final Color defaultColor;
  final VibeSkylinePalette palette;
  final String? Function(Object? handle)? resolveSealed;

  static double _num(Object? v, [double fallback = 0.0]) =>
      v is num && v.isFinite ? v.toDouble() : fallback;

  ui.Shader? _buildShader(Object? rawGrad, Rect bounds) {
    if (rawGrad is! Map) return null;
    final rawColors = rawGrad['colors'];
    if (rawColors is! List || rawColors.length < 2) return null;
    final colors = <Color>[];
    for (final item in rawColors) {
      final c = palette.parseColor(item);
      if (c != null) colors.add(c);
    }
    if (colors.length < 2) return null;
    double bx = 0.0, by = 0.0, ex = 0.0, ey = 1.0;
    if (rawGrad['begin'] is List && (rawGrad['begin'] as List).length >= 2) {
      final b = rawGrad['begin'] as List;
      bx = _num(b[0], 0.0);
      by = _num(b[1], 0.0);
    }
    if (rawGrad['end'] is List && (rawGrad['end'] as List).length >= 2) {
      final e = rawGrad['end'] as List;
      ex = _num(e[0], 0.0);
      ey = _num(e[1], 1.0);
    }
    return ui.Gradient.linear(
      Offset(bounds.left + bounds.width * bx, bounds.top + bounds.height * by),
      Offset(bounds.left + bounds.width * ex, bounds.top + bounds.height * ey),
      colors,
    );
  }

  Color? _cmdFill(Map<String, dynamic> cmd) =>
      palette.parseColor(cmd['fill'] ?? cmd['color'] ?? cmd['tone']);

  Color? _cmdStroke(Map<String, dynamic> cmd) =>
      palette.parseColor(cmd['stroke']);

  String _resolveText(Object? raw) {
    if (raw is Map && raw.length == 1 && raw['sealed'] is String) {
      return resolveSealed?.call(raw) ?? '';
    }
    return raw?.toString() ?? '';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || commands.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / logicalWidth, size.height / logicalHeight);

    final fullBounds = Rect.fromLTWH(0, 0, logicalWidth, logicalHeight);
    final limit = math.min(commands.length, kMaxVibeCanvasCommands);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()..style = PaintingStyle.stroke;

    for (var i = 0; i < limit; i++) {
      final cmd = commands[i];
      final op = (cmd['op'] ?? cmd['type'])?.toString();
      switch (op) {
        case 'clear':
          final shader = _buildShader(cmd['linearGradient'], fullBounds);
          final fill = _cmdFill(cmd) ?? palette.surface;
          if (shader != null) {
            fillPaint.shader = shader;
          } else {
            fillPaint
              ..shader = null
              ..color = fill;
          }
          canvas.drawRect(fullBounds, fillPaint);

        case 'rect':
        case 'rrect':
          final rect = Rect.fromLTWH(
            _num(cmd['x']),
            _num(cmd['y']),
            _num(cmd['w'] ?? cmd['width'], logicalWidth),
            _num(cmd['h'] ?? cmd['height'], logicalHeight),
          );
          final rad = _num(cmd['radius'] ?? cmd['r']);
          final shader = _buildShader(cmd['linearGradient'], rect);
          final fill = _cmdFill(cmd);
          if (shader != null || fill != null) {
            if (shader != null) {
              fillPaint.shader = shader;
            } else {
              fillPaint
                ..shader = null
                ..color = fill!;
            }
            if (rad > 0 || op == 'rrect') {
              canvas.drawRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(rad)),
                fillPaint,
              );
            } else {
              canvas.drawRect(rect, fillPaint);
            }
          }
          final stroke = _cmdStroke(cmd);
          if (stroke != null) {
            strokePaint
              ..shader = null
              ..color = stroke
              ..strokeWidth = _num(cmd['strokeWidth'], 1.0)
              ..strokeCap = StrokeCap.butt
              ..strokeJoin = StrokeJoin.miter;
            if (rad > 0 || op == 'rrect') {
              canvas.drawRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(rad)),
                strokePaint,
              );
            } else {
              canvas.drawRect(rect, strokePaint);
            }
          }

        case 'circle':
          final center = Offset(
            _num(cmd['cx'] ?? cmd['x']),
            _num(cmd['cy'] ?? cmd['y']),
          );
          final r = _num(cmd['r'] ?? cmd['radius'], 4.0);
          final fill = _cmdFill(cmd);
          if (fill != null) {
            fillPaint
              ..shader = null
              ..color = fill;
            canvas.drawCircle(center, r, fillPaint);
          }
          final stroke = _cmdStroke(cmd);
          if (stroke != null) {
            strokePaint
              ..shader = null
              ..color = stroke
              ..strokeWidth = _num(cmd['strokeWidth'], 1.2)
              ..strokeCap = StrokeCap.butt
              ..strokeJoin = StrokeJoin.miter;
            canvas.drawCircle(center, r, strokePaint);
          }

        case 'arc':
          final center = Offset(
            _num(cmd['cx'] ?? cmd['x']),
            _num(cmd['cy'] ?? cmd['y']),
          );
          final r = _num(cmd['r'] ?? cmd['radius'], 12.0);
          final rect = Rect.fromCircle(center: center, radius: r);
          final start = _num(cmd['startAngle']);
          final sweep = _num(cmd['sweepAngle'], math.pi);
          final useCenter = cmd['useCenter'] == true;
          final stroke = _cmdStroke(cmd) ?? _cmdFill(cmd) ?? defaultColor;
          final isFilled = cmd['fill'] != null;
          final arcPaint = isFilled ? fillPaint : strokePaint;
          arcPaint
            ..shader = null
            ..color = stroke
            ..strokeWidth = _num(cmd['strokeWidth'], 2.0)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.miter;
          canvas.drawArc(rect, start, sweep, useCenter, arcPaint);

        case 'line':
          strokePaint
            ..shader = null
            ..color = _cmdStroke(cmd) ?? _cmdFill(cmd) ?? defaultColor
            ..strokeWidth = _num(cmd['strokeWidth'], 1.5)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.miter;
          canvas.drawLine(
            Offset(_num(cmd['x1']), _num(cmd['y1'])),
            Offset(_num(cmd['x2']), _num(cmd['y2'])),
            strokePaint,
          );

        case 'path':
        case 'polygon':
          final pts = cmd['points'];
          if (pts is! List || pts.length < 2) continue;
          final path = Path();
          var started = false;
          for (final pt in pts) {
            if (pt is List && pt.length >= 2) {
              final x = _num(pt[0]), y = _num(pt[1]);
              if (!started) {
                path.moveTo(x, y);
                started = true;
              } else {
                path.lineTo(x, y);
              }
            }
          }
          if (!started) continue;
          if (op == 'polygon' || cmd['closed'] == true) path.close();
          final shader = _buildShader(cmd['linearGradient'], fullBounds);
          final fill = cmd['fill'] != null
              ? palette.parseColor(cmd['fill'])
              : (op == 'polygon' ? _cmdFill(cmd) : null);
          if (shader != null || fill != null) {
            if (shader != null) {
              fillPaint.shader = shader;
            } else {
              fillPaint
                ..shader = null
                ..color = fill!;
            }
            canvas.drawPath(path, fillPaint);
          }
          final stroke = _cmdStroke(cmd) ??
              (op == 'path' && fill == null && shader == null
                  ? (_cmdFill(cmd) ?? defaultColor)
                  : null);
          if (stroke != null) {
            strokePaint
              ..shader = null
              ..color = stroke
              ..strokeWidth = _num(cmd['strokeWidth'], 1.75)
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;
            canvas.drawPath(path, strokePaint);
          }

        case 'bars':
          final rawVals = cmd['values'];
          if (rawVals is! List || rawVals.isEmpty) continue;
          var numCount = 0;
          var maxCandidate = double.negativeInfinity;
          for (final v in rawVals) {
            if (v is num && v.isFinite) {
              numCount++;
              final d = v.toDouble();
              if (d > maxCandidate) maxCandidate = d;
            }
          }
          if (numCount == 0) continue;
          final bx = _num(cmd['x'], 0.0);
          final by = _num(cmd['y'], 0.0);
          final bw = _num(cmd['w'] ?? cmd['width'], logicalWidth - bx);
          final bh = _num(cmd['h'] ?? cmd['height'], logicalHeight - by);
          final minV = cmd['min'] is num ? _num(cmd['min']) : 0.0;
          final maxV = cmd['max'] is num
              ? _num(cmd['max'], 1.0)
              : (maxCandidate > minV ? maxCandidate : minV + 1.0);
          final span = (maxV - minV) <= 0 ? 1.0 : (maxV - minV);
          final gap = _num(cmd['gap'], 2.0);
          final rad = _num(cmd['radius'], 2.0);
          final barW = math.max(
            1.0,
            (bw - gap * (numCount - 1)) / numCount,
          );
          final bounds = Rect.fromLTWH(bx, by, bw, bh);
          final shader = _buildShader(cmd['linearGradient'], bounds);
          final fill = _cmdFill(cmd) ?? defaultColor;
          if (shader != null) {
            fillPaint.shader = shader;
          } else {
            fillPaint
              ..shader = null
              ..color = fill;
          }
          var j = 0;
          for (final v in rawVals) {
            if (v is! num || !v.isFinite) continue;
            final ratio = ((v.toDouble() - minV) / span).clamp(0.0, 1.0);
            final barH = math.max(1.5, ratio * bh);
            final rRect = RRect.fromRectAndRadius(
              Rect.fromLTWH(
                bx + j * (barW + gap),
                by + (bh - barH),
                barW,
                barH,
              ),
              Radius.circular(rad),
            );
            canvas.drawRRect(rRect, fillPaint);
            j++;
          }

        case 'text':
          final txt = _resolveText(cmd['text']);
          if (txt.isEmpty) continue;
          final fwRaw = cmd['fontWeight']?.toString().toLowerCase();
          final fw = (fwRaw == 'bold' || fwRaw == '700' || fwRaw == '600')
              ? FontWeight.w700
              : FontWeight.w500;
          final tp = TextPainter(
            text: TextSpan(
              text: txt,
              style: TextStyle(
                color: _cmdFill(cmd) ?? palette.text,
                fontSize: _num(cmd['fontSize'], 10.5).clamp(7.0, 48.0),
                fontWeight: fw,
                fontFeatures: const <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout(maxWidth: logicalWidth);
          try {
            var tx = _num(cmd['x']);
            final align = cmd['align']?.toString();
            if (align == 'right' || align == 'end') {
              tx -= tp.width;
            } else if (align == 'center') {
              tx -= tp.width / 2;
            }
            tp.paint(canvas, Offset(tx, _num(cmd['y'])));
          } finally {
            tp.dispose();
          }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VibeSkylineCanvasPainter oldDelegate) {
    return logicalWidth != oldDelegate.logicalWidth ||
        logicalHeight != oldDelegate.logicalHeight ||
        defaultColor != oldDelegate.defaultColor ||
        palette != oldDelegate.palette ||
        !vibeDeepEquals(commands, oldDelegate.commands);
  }
}

/// Wraps a rendered `VibeView` widget with scoped `WXSS`-style visual/layout
/// tokens (`style`) and non-button `bindtap` event dispatch.
Widget applyVibeSkylineNodeStyle(
  BuildContext context,
  Widget child,
  Map<String, dynamic> node, {
  void Function(String command, Map<String, dynamic> args)? onCommand,
}) {
  Widget out = child;
  final rawStyle = node['style'];
  if (rawStyle is Map) {
    double? n(String k) =>
        rawStyle[k] is num ? (rawStyle[k] as num).toDouble() : null;
    final padAll = n('padding');
    final padH = n('paddingHorizontal');
    final padV = n('paddingVertical');
    final padding = (padAll != null || padH != null || padV != null)
        ? EdgeInsets.symmetric(
            horizontal: padH ?? padAll ?? 0.0,
            vertical: padV ?? padAll ?? 0.0,
          )
        : null;
    final bg = resolveVibeSkylineColor(context, rawStyle['backgroundColor']);
    final borderCol = resolveVibeSkylineColor(context, rawStyle['borderColor']);
    final radius = n('borderRadius');
    final borderW = n('borderWidth') ?? (borderCol != null ? 1.0 : 0.0);
    final hasBox = padding != null ||
        bg != null ||
        borderCol != null ||
        radius != null ||
        n('width') != null ||
        n('height') != null;
    if (hasBox) {
      out = Container(
        width: n('width'),
        height: n('height'),
        constraints: (n('minHeight') != null || n('maxWidth') != null)
            ? BoxConstraints(
                minHeight: n('minHeight') ?? 0.0,
                maxWidth: n('maxWidth') ?? double.infinity,
              )
            : null,
        padding: padding,
        decoration: (bg != null || borderCol != null || radius != null)
            ? BoxDecoration(
                color: bg,
                borderRadius:
                    radius != null ? BorderRadius.circular(radius) : null,
                border: borderCol != null
                    ? Border.all(color: borderCol, width: borderW)
                    : null,
              )
            : null,
        child: out,
      );
    }
    final opacity = n('opacity');
    if (opacity != null && opacity < 1.0) {
      out = Opacity(opacity: opacity.clamp(0.0, 1.0), child: out);
    }
  }

  final type = node['type']?.toString();
  final bindTap = node['bindtap']?.toString().trim();
  if (bindTap != null &&
      isValidMiniProgramHandlerName(bindTap) &&
      onCommand != null &&
      type != 'button' &&
      type != 'action' &&
      type != 'canvas') {
    out = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCommand('vibe:tap:$bindTap', <String, dynamic>{
          '__vibeEvent': true,
          'type': 'tap',
          'handler': bindTap,
          if (node['id'] != null) 'id': node['id'],
          if (node['dataset'] is Map)
            'dataset': Map<String, dynamic>.from(node['dataset'] as Map),
        }),
        child: out,
      ),
    );
  }
  return out;
}
