import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vibe_space/vibe_space.dart' show kMaxVibeCanvasCommands;

import 'view.dart' show VibeViewToneScope;

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
      final hex = s.substring(1);
      if (hex.length == 3) {
        final r = hex[0] * 2, g = hex[1] * 2, b = hex[2] * 2;
        final v = int.tryParse('FF$r$g$b', radix: 16);
        if (v != null) return Color(v);
      } else if (hex.length == 6) {
        final v = int.tryParse('FF$hex', radix: 16);
        if (v != null) return Color(v);
      } else if (hex.length == 8) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return Color(v);
      }
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
    final defaultColor = resolveVibeSkylineColor(
          context,
          null,
          fallbackTone: tone ?? 'default',
        ) ??
        palette.accent;

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

  Color? parseColor(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final s = raw.trim();
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 3) {
        final v = int.tryParse('FF${hex[0] * 2}${hex[1] * 2}${hex[2] * 2}',
            radix: 16);
        if (v != null) return Color(v);
      } else if (hex.length == 6) {
        final v = int.tryParse('FF$hex', radix: 16);
        if (v != null) return Color(v);
      } else if (hex.length == 8) {
        final v = int.tryParse(hex, radix: 16);
        if (v != null) return Color(v);
      }
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

    for (var i = 0; i < limit; i++) {
      final cmd = commands[i];
      final op = (cmd['op'] ?? cmd['type'])?.toString();
      switch (op) {
        case 'clear':
          final shader = _buildShader(cmd['linearGradient'], fullBounds);
          final fill = _cmdFill(cmd) ?? palette.surface;
          final p = Paint()..style = PaintingStyle.fill;
          if (shader != null) {
            p.shader = shader;
          } else {
            p.color = fill;
          }
          canvas.drawRect(fullBounds, p);

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
            final p = Paint()..style = PaintingStyle.fill;
            if (shader != null) {
              p.shader = shader;
            } else {
              p.color = fill!;
            }
            if (rad > 0 || op == 'rrect') {
              canvas.drawRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(rad)),
                p,
              );
            } else {
              canvas.drawRect(rect, p);
            }
          }
          final stroke = _cmdStroke(cmd);
          if (stroke != null) {
            final sp = Paint()
              ..style = PaintingStyle.stroke
              ..color = stroke
              ..strokeWidth = _num(cmd['strokeWidth'], 1.0);
            if (rad > 0 || op == 'rrect') {
              canvas.drawRRect(
                RRect.fromRectAndRadius(rect, Radius.circular(rad)),
                sp,
              );
            } else {
              canvas.drawRect(rect, sp);
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
            canvas.drawCircle(center, r, Paint()..color = fill);
          }
          final stroke = _cmdStroke(cmd);
          if (stroke != null) {
            canvas.drawCircle(
              center,
              r,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = stroke
                ..strokeWidth = _num(cmd['strokeWidth'], 1.2),
            );
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
          final p = Paint()
            ..color = stroke
            ..style =
                cmd['fill'] != null ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = _num(cmd['strokeWidth'], 2.0)
            ..strokeCap = StrokeCap.round;
          canvas.drawArc(rect, start, sweep, useCenter, p);

        case 'line':
          final p = Paint()
            ..style = PaintingStyle.stroke
            ..color = _cmdStroke(cmd) ?? _cmdFill(cmd) ?? defaultColor
            ..strokeWidth = _num(cmd['strokeWidth'], 1.5)
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            Offset(_num(cmd['x1']), _num(cmd['y1'])),
            Offset(_num(cmd['x2']), _num(cmd['y2'])),
            p,
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
            final fp = Paint()..style = PaintingStyle.fill;
            if (shader != null) {
              fp.shader = shader;
            } else {
              fp.color = fill!;
            }
            canvas.drawPath(path, fp);
          }
          final stroke = _cmdStroke(cmd) ??
              (op == 'path' && fill == null && shader == null
                  ? (_cmdFill(cmd) ?? defaultColor)
                  : null);
          if (stroke != null) {
            canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = stroke
                ..strokeWidth = _num(cmd['strokeWidth'], 1.75)
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
          }

        case 'bars':
          final rawVals = cmd['values'];
          if (rawVals is! List || rawVals.isEmpty) continue;
          final vals = <double>[
            for (final v in rawVals)
              if (v is num && v.isFinite) v.toDouble(),
          ];
          if (vals.isEmpty) continue;
          final bx = _num(cmd['x'], 0.0);
          final by = _num(cmd['y'], 0.0);
          final bw = _num(cmd['w'] ?? cmd['width'], logicalWidth - bx);
          final bh = _num(cmd['h'] ?? cmd['height'], logicalHeight - by);
          final minV = cmd['min'] is num ? _num(cmd['min']) : 0.0;
          final maxCandidate = vals.reduce(math.max);
          final maxV = cmd['max'] is num
              ? _num(cmd['max'], 1.0)
              : (maxCandidate > minV ? maxCandidate : minV + 1.0);
          final span = (maxV - minV) <= 0 ? 1.0 : (maxV - minV);
          final gap = _num(cmd['gap'], 2.0);
          final rad = _num(cmd['radius'], 2.0);
          final barW = math.max(
            1.0,
            (bw - gap * (vals.length - 1)) / vals.length,
          );
          final bounds = Rect.fromLTWH(bx, by, bw, bh);
          final shader = _buildShader(cmd['linearGradient'], bounds);
          final fill = _cmdFill(cmd) ?? defaultColor;
          final p = Paint()..style = PaintingStyle.fill;
          if (shader != null) {
            p.shader = shader;
          } else {
            p.color = fill;
          }
          for (var j = 0; j < vals.length; j++) {
            final ratio = ((vals[j] - minV) / span).clamp(0.0, 1.0);
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
            canvas.drawRRect(rRect, p);
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
          var tx = _num(cmd['x']);
          final align = cmd['align']?.toString();
          if (align == 'right' || align == 'end') {
            tx -= tp.width;
          } else if (align == 'center') {
            tx -= tp.width / 2;
          }
          tp.paint(canvas, Offset(tx, _num(cmd['y'])));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VibeSkylineCanvasPainter oldDelegate) {
    return logicalWidth != oldDelegate.logicalWidth ||
        logicalHeight != oldDelegate.logicalHeight ||
        defaultColor != oldDelegate.defaultColor ||
        !identical(commands, oldDelegate.commands);
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
  final bindTap = node['bindtap']?.toString();
  if (bindTap != null &&
      bindTap.isNotEmpty &&
      onCommand != null &&
      type != 'button' &&
      type != 'action' &&
      type != 'canvas') {
    out = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCommand('mp:tap:$bindTap', <String, dynamic>{
          '__mpEvent': true,
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
