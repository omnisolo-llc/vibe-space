import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibe_space/vibe_space.dart';

import 'view.dart';

/// Theme palette for [VibeSpacePanel] and [VibeEmbedCard].
@immutable
class VibeSpaceThemeData {
  const VibeSpaceThemeData({
    required this.background,
    required this.surface,
    required this.cardBackground,
    required this.border,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.ok,
    required this.warn,
    required this.danger,
    this.radius = 10,
  });

  final Color background;
  final Color surface;
  final Color cardBackground;
  final Color border;
  final Color text;
  final Color mutedText;
  final Color accent;
  final Color ok;
  final Color warn;
  final Color danger;
  final double radius;

  factory VibeSpaceThemeData.dark() {
    return const VibeSpaceThemeData(
      background: Color(0xFF0D131F),
      surface: Color(0xFF151F32),
      cardBackground: Color(0xFF0D131F),
      border: Color(0xFF24324D),
      text: Color(0xFFE6EDF7),
      mutedText: Color(0xFF8FA3BF),
      accent: Color(0xFF38BDF8),
      ok: Color(0xFF4ADE80),
      warn: Color(0xFFFBBF24),
      danger: Color(0xFFF87171),
      radius: 10,
    );
  }

  factory VibeSpaceThemeData.light() {
    return const VibeSpaceThemeData(
      background: Color(0xFFFAF7F5),
      surface: Color(0xFFFFFFFF),
      cardBackground: Color(0xFFFAF7F5),
      border: Color(0xFFECE6E1),
      text: Color(0xFF1F1A17),
      mutedText: Color(0xFF7A6F68),
      accent: Color(0xFF7C3AED),
      ok: Color(0xFF16A34A),
      warn: Color(0xFFD97706),
      danger: Color(0xFFDC2626),
      radius: 14,
    );
  }

  factory VibeSpaceThemeData.fromTheme(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? VibeSpaceThemeData.dark() : VibeSpaceThemeData.light();
    final scheme = theme.colorScheme;
    return VibeSpaceThemeData(
      background: scheme.surfaceContainerLowest,
      surface: scheme.surface,
      cardBackground: scheme.surfaceContainerLow,
      border: theme.dividerColor.withValues(alpha: 0.35),
      text: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      accent: scheme.primary,
      ok: base.ok,
      warn: base.warn,
      danger: scheme.error,
      radius: base.radius,
    );
  }
}

VibeSpaceThemeData _resolveVibeTheme(
  BuildContext context,
  VibeSpaceThemeData? explicit,
) {
  return explicit ?? VibeSpaceThemeData.fromTheme(Theme.of(context));
}

Widget _wrapToneScope(VibeSpaceThemeData t, Widget child) {
  return VibeViewToneScope(
    accent: t.accent,
    ok: t.ok,
    warn: t.warn,
    danger: t.danger,
    border: t.border,
    surface: t.surface,
    text: t.text,
    mutedText: t.mutedText,
    radius: t.radius,
    child: child,
  );
}

String _originBadgeLabel(String origin) {
  switch (origin) {
    case 'shared':
      return 'Shared';
    case 'gallery':
      return 'Gallery';
    case 'agent':
      return 'From the agent';
    default:
      return 'Yours';
  }
}

String _originSourceLine(String origin) {
  switch (origin) {
    case 'shared':
      return 'Shared with you by link.';
    case 'gallery':
      return 'From the gallery.';
    case 'agent':
      return 'Made by the agent.';
    default:
      return 'Made from your wish.';
  }
}

bool _sameNeeds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final sa = List<String>.from(a)..sort();
  final sb = List<String>.from(b)..sort();
  for (var i = 0; i < sa.length; i++) {
    if (sa[i] != sb[i]) return false;
  }
  return true;
}

VibeInstalledRecord? _findMatchingRecord(
  VibeProtocolHost host,
  String vibeId,
  Map<String, Object?>? args,
) {
  final argsKey = jsonEncode(args);
  for (final r in host.installed()) {
    if (r.vibe.id == vibeId && jsonEncode(r.args) == argsKey) {
      return r;
    }
  }
  return null;
}

Future<void> showVibeOfferDialog(
  BuildContext context,
  VibeProtocolHost host, {
  VibeSpaceThemeData? theme,
}) {
  final t = _resolveVibeTheme(context, theme);
  final manifest = host.manifest();
  final caps = (manifest['capabilities'] as List?) ?? const <Object?>[];
  final notOffered = (manifest['notOffered'] as List?) ?? const <Object?>[];
  final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      title: Text(
        'What ${host.name} offers',
        style: TextStyle(color: t.text, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'OFFERED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.mutedText,
                ),
              ),
              const SizedBox(height: 8),
              for (final rawCap in caps)
                if (rawCap is Map) ...<Widget>[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.cardBackground,
                      borderRadius: BorderRadius.circular(t.radius),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              (rawCap['title'] ?? rawCap['name'] ?? '').toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                            Text(
                              (rawCap['name'] ?? '').toString(),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: t.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (rawCap['fields'] is Map)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              for (final entry in (rawCap['fields'] as Map).entries)
                                _FieldModeChip(
                                  fieldName: entry.key.toString(),
                                  mode: entry.value.toString(),
                                  theme: t,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              const SizedBox(height: 8),
              Text(
                'NOT OFFERED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.mutedText,
                ),
              ),
              const SizedBox(height: 6),
              for (final item in notOffered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${item.toString()}',
                    style: TextStyle(fontSize: 13, color: t.text),
                  ),
                ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Manifest (what an AI reads)',
                  style: TextStyle(fontSize: 13, color: t.mutedText),
                ),
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.cardBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.border),
                    ),
                    child: SelectableText(
                      manifestJson,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: t.text,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _FieldModeChip extends StatelessWidget {
  const _FieldModeChip({
    required this.fieldName,
    required this.mode,
    required this.theme,
  });

  final String fieldName;
  final String mode;
  final VibeSpaceThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isSealed = mode == 'sealed';
    final badgeColor = isSealed ? theme.accent : theme.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            fieldName,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: theme.text,
            ),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isSealed ? 'SEALED' : 'PUBLIC',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionLabelCard extends StatefulWidget {
  const _PermissionLabelCard({
    required this.host,
    required this.vibe,
    required this.origin,
    required this.theme,
    this.args,
    this.defaultTitle,
    required this.onAllow,
    required this.onCancel,
  });

  final VibeProtocolHost host;
  final VibeSpec vibe;
  final String origin;
  final VibeSpaceThemeData theme;
  final Map<String, Object?>? args;
  final String? defaultTitle;
  final void Function(String title, String note) onAllow;
  final VoidCallback onCancel;

  @override
  State<_PermissionLabelCard> createState() => _PermissionLabelCardState();
}

class _PermissionLabelCardState extends State<_PermissionLabelCard> {
  late TextEditingController _titleCtrl;
  late TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    final existing = _findMatchingRecord(
      widget.host,
      widget.vibe.id,
      widget.args,
    );
    _titleCtrl = TextEditingController(
      text: widget.defaultTitle ?? existing?.title ?? widget.vibe.name,
    );
    _noteCtrl = TextEditingController(
      text: existing?.note ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _PermissionLabelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vibe.id != widget.vibe.id ||
        oldWidget.defaultTitle != widget.defaultTitle) {
      final existing = _findMatchingRecord(
        widget.host,
        widget.vibe.id,
        widget.args,
      );
      _titleCtrl.text =
          widget.defaultTitle ?? existing?.title ?? widget.vibe.name;
      _noteCtrl.text = existing?.note ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final existing = _findMatchingRecord(
      widget.host,
      widget.vibe.id,
      widget.args,
    );
    final isSamePermUpdate =
        existing != null && _sameNeeds(existing.vibe.needs, widget.vibe.needs);
    final label = widget.host.label(widget.vibe);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.vibe.name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _originSourceLine(widget.origin),
            style: TextStyle(fontSize: 12.5, color: t.mutedText),
          ),
          if (isSamePermUpdate) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.ok.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.ok.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Version ${widget.vibe.version}. No new permissions.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.ok,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: t.border),
          _LabelRow(title: 'Reads', items: label.reads, accentColor: t.accent, theme: t),
          Divider(height: 1, color: t.border),
          _LabelRow(title: 'Shows', items: label.shows, accentColor: t.mutedText, theme: t),
          Divider(height: 1, color: t.border),
          _LabelRow(title: 'Cannot', items: label.cannot, accentColor: t.mutedText, theme: t),
          Divider(height: 1, color: t.border),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Optional note (e.g. why you pinned this)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                ),
                onPressed: () {
                  final cleanTitle = _titleCtrl.text.trim();
                  widget.onAllow(
                    cleanTitle.isNotEmpty ? cleanTitle : widget.vibe.name,
                    _noteCtrl.text.trim(),
                  );
                },
                child: Text(isSamePermUpdate ? 'Update' : 'Allow and add'),
              ),
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.title,
    required this.items,
    required this.accentColor,
    required this.theme,
  });

  final String title;
  final List<String> items;
  final Color accentColor;
  final VibeSpaceThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 62,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: accentColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      items.length > 1 ? '• $item' : item,
                      style: TextStyle(fontSize: 12.5, color: theme.text),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectPane extends StatefulWidget {
  const _InspectPane({
    required this.host,
    required this.vibe,
    required this.run,
    required this.theme,
    this.onHide,
  });

  final VibeProtocolHost host;
  final VibeSpec vibe;
  final VibeRunController? run;
  final VibeSpaceThemeData theme;
  final VoidCallback? onHide;

  @override
  State<_InspectPane> createState() => _InspectPaneState();
}

class _InspectPaneState extends State<_InspectPane> {
  VoidCallback? _unsub;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant _InspectPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run != widget.run) {
      _unsub?.call();
      _attach();
    }
  }

  void _attach() {
    _unsub = widget.run?.onUpdate(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  List<TextSpan> _highlightSealedJson(String jsonText, VibeSpaceThemeData t) {
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11.5,
      color: t.text,
      height: 1.45,
    );
    final sealedStyle = baseStyle.copyWith(
      color: t.accent,
      backgroundColor: t.accent.withValues(alpha: 0.16),
      fontWeight: FontWeight.w600,
    );
    final regex = RegExp(r'\{\s*"sealed":\s*"[^"]*"\s*\}');
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in regex.allMatches(jsonText)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: jsonText.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      final collapsed = match.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
      spans.add(TextSpan(text: collapsed, style: sealedStyle));
      lastEnd = match.end;
    }
    if (lastEnd < jsonText.length) {
      spans.add(TextSpan(text: jsonText.substring(lastEnd), style: baseStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final run = widget.run;
    final capTitles = <String, String>{
      for (final cap in widget.host.capabilities) cap.name: cap.title,
    };

    if (run == null) {
      return Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        child: Text(
          'Paused — resume to inspect live runs.',
          style: TextStyle(fontSize: 12, color: t.mutedText),
        ),
      );
    }

    final snap = run.inspect();
    final inputData = snap.input['data'] ?? const <String, Object?>{};
    final rawJson = const JsonEncoder.withIndent('  ').convert(inputData);
    final collapsedJson = rawJson.replaceAllMapped(
      RegExp(r'\{\s*\n\s*("sealed":\s*"(?:[^"\\]|\\.)*")\s*\n\s*\}'),
      (m) => '{ ${m.group(1)} }',
    );
    final led = snap.ledger;

    final capNames = <String>[
      ...widget.vibe.needs,
      for (final k in led.reads.keys)
        if (!widget.vibe.needs.contains(k)) k,
    ];

    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'WHAT THE VIBE RECEIVED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: t.mutedText,
                  ),
                ),
              ),
              if (widget.onHide != null)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: widget.onHide,
                  child: const Text('Hide'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(
                TextSpan(children: _highlightSealedJson(collapsedJson, t)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'WHAT IT DID',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: t.mutedText,
            ),
          ),
          const SizedBox(height: 4),
          if (capNames.isEmpty)
            Text(
              '• Read nothing from ${widget.host.name}',
              style: TextStyle(fontSize: 12, color: t.text),
            )
          else
            for (final name in capNames)
              Text(
                '• Read ${capTitles[name] ?? name} ${led.reads[name] ?? 0} '
                '${(led.reads[name] ?? 0) == 1 ? 'time' : 'times'}',
                style: TextStyle(fontSize: 12, color: t.text),
              ),
          Text(
            led.sent == 0
                ? '• Sent nothing'
                : '• Sent ${led.sent} ${led.sent == 1 ? 'time' : 'times'}',
            style: TextStyle(fontSize: 12, color: t.text),
          ),
          Text(
            led.changed == 0
                ? '• Changed nothing'
                : '• Changed ${led.changed} ${led.changed == 1 ? 'time' : 'times'}',
            style: TextStyle(fontSize: 12, color: t.text),
          ),
          if (led.lastError != null)
            Text(
              '• Error: ${led.lastError}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.danger,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Values marked sealed are handles. ${widget.host.name} draws the real value. The vibe never sees it.',
            style: TextStyle(fontSize: 11.5, color: t.mutedText),
          ),
        ],
      ),
    );
  }
}

/// Dedicated Vibe Space panel widget providing full wish authoring,
/// permission labels, card lifecycle (`⋯` menu), live inspection, editing,
/// history restore, share/import, portable gallery, and graceful source banners.
class VibeSpacePanel extends StatefulWidget {
  const VibeSpacePanel({
    super.key,
    required this.host,
    this.wishes = const <VibeWishPreset>[],
    this.gallery = const <VibeSpec>[kPortableFocusTimerVibe],
    this.theme,
    this.headerTrailing,
    this.onShare,
  });

  final VibeProtocolHost host;
  final List<VibeWishPreset> wishes;
  final List<VibeSpec> gallery;
  final VibeSpaceThemeData? theme;
  final Widget? headerTrailing;
  final void Function(String encodedShareToken, VibeSpec vibe)? onShare;

  @override
  State<VibeSpacePanel> createState() => _VibeSpacePanelState();
}

class _VibeSpacePanelState extends State<VibeSpacePanel> {
  final TextEditingController _wishCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  VoidCallback? _hostUnsub;

  VibeSpec? _draftVibe;
  String _draftOrigin = 'yours';
  String? _draftWishText;
  VibeRunController? _draftPreviewRun;
  VoidCallback? _draftPreviewUnsub;
  bool _showCode = false;
  bool _wishProminentNote = false;

  String? _blockedSharedName;
  List<String> _blockedMissing = const <String>[];

  VibeInstalledRecord? _deletedSnapshot;
  int _deletedIndex = 0;
  Timer? _undoTimer;

  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _hostUnsub = widget.host.onChange(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant VibeSpacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _hostUnsub?.call();
      _hostUnsub = widget.host.onChange(() {
        if (mounted) setState(() {});
      });
      _clearDraft();
    }
  }

  @override
  void dispose() {
    _hostUnsub?.call();
    _clearDraft();
    _undoTimer?.cancel();
    _wishCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _clearDraft() {
    _draftPreviewUnsub?.call();
    _draftPreviewUnsub = null;
    _draftPreviewRun?.stop();
    _draftPreviewRun = null;
    _draftVibe = null;
    _draftWishText = null;
    _showCode = false;
    _blockedSharedName = null;
    _blockedMissing = const <String>[];
  }

  void _startPreviewDraft(
    VibeSpec vibe, {
    required String origin,
    String? wishText,
  }) {
    _clearDraft();
    final check = widget.host.check(vibe);
    if (!check.ok) {
      setState(() {
        _blockedSharedName = vibe.name;
        _blockedMissing = check.missing;
      });
      return;
    }

    VibeRunController? run;
    if (origin == 'yours') {
      run = widget.host.mount(vibe, dataMode: 'sample');
      _draftPreviewUnsub = run.onUpdate(() {
        if (mounted) setState(() {});
      });
    }

    setState(() {
      _draftVibe = vibe;
      _draftOrigin = origin;
      _draftWishText = wishText ?? vibe.wish;
      _draftPreviewRun = run;
      _wishProminentNote = false;
    });
  }

  void _submitWish(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) {
      setState(() => _wishProminentNote = true);
      return;
    }
    final compiled = VibeWishCompiler.compile(
      text,
      widget.host,
      presets: widget.wishes,
    );
    if (compiled == null) {
      setState(() => _wishProminentNote = true);
      return;
    }
    _wishCtrl.text = text;
    _startPreviewDraft(compiled, origin: 'yours', wishText: text);
  }

  List<VibeWishPreset> _visibleWishes() {
    final byId = <String, VibeInstalledRecord>{
      for (final rec in widget.host.installed()) rec.vibe.id: rec,
    };
    return <VibeWishPreset>[
      for (final w in widget.wishes)
        if (w.remixOf == null ||
            (byId[w.remixOf] != null &&
                byId[w.remixOf]!.vibe.version < w.vibe.version))
          w,
    ];
  }

  void _deleteWithUndo(VibeInstalledRecord record, int index) {
    _undoTimer?.cancel();
    final removed = widget.host.uninstall(record.instanceId);
    if (removed == null) return;
    setState(() {
      _deletedSnapshot = removed;
      _deletedIndex = index;
    });
    _undoTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() => _deletedSnapshot = null);
      }
    });
  }

  Future<void> _openImportDialog(VibeSpaceThemeData t) async {
    final ctrl = TextEditingController();
    String? errorMsg;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: t.surface,
          title: Text('Import vibe link', style: TextStyle(color: t.text)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Share link or #vibe=... token',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMsg != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(errorMsg!, style: TextStyle(color: t.danger, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final vibe = VibeShareCodec.decode(ctrl.text.trim());
                  Navigator.of(ctx).pop();
                  _startPreviewDraft(vibe, origin: 'shared');
                } catch (err) {
                  setDialogState(() {
                    errorMsg = 'Could not decode link: $err';
                  });
                }
              },
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _openShareDialog(
    VibeSpec vibe,
    VibeSpaceThemeData t,
  ) async {
    final token = VibeShareCodec.encode(vibe);
    if (widget.onShare != null) {
      widget.onShare!(token, vibe);
      return;
    }
    final link = '#vibe=$token';
    var copied = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: t.surface,
          title: Text('Share ${vibe.name}', style: TextStyle(color: t.text)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SelectableText(
                  link,
                  maxLines: 3,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Grants do not travel. Whoever opens the link sees the label and decides.',
                  style: TextStyle(fontSize: 12.5, color: t.mutedText),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                setDialogState(() => copied = true);
              },
              child: Text(copied ? 'Copied' : 'Copy link'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditDialog(
    VibeInstalledRecord record,
    VibeSpaceThemeData t,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditVibeDialog(
        host: widget.host,
        record: record,
        wishes: widget.wishes,
        theme: t,
      ),
    );
  }

  void _moveWithinGroup(VibeInstalledRecord record, int delta) {
    final all = widget.host.installed();
    final group = <String>[
      for (final r in all)
        if (r.pinned == record.pinned) r.instanceId,
    ];
    final idx = group.indexOf(record.instanceId);
    final swapIdx = idx + delta;
    if (idx < 0 || swapIdx < 0 || swapIdx >= group.length) return;
    final tmp = group[idx];
    group[idx] = group[swapIdx];
    group[swapIdx] = tmp;

    final pinnedIds = record.pinned
        ? group
        : <String>[for (final r in all) if (r.pinned) r.instanceId];
    final unpinnedIds = !record.pinned
        ? group
        : <String>[for (final r in all) if (!r.pinned) r.instanceId];
    widget.host.reorder(<String>[...pinnedIds, ...unpinnedIds]);
  }

  @override
  Widget build(BuildContext context) {
    final t = _resolveVibeTheme(context, widget.theme);
    final records = widget.host.installed();
    if (records.length < 2 && _filterQuery.isNotEmpty) {
      _filterQuery = '';
      _filterCtrl.clear();
    }
    final query = _filterQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? records
        : records.where((r) {
            final hay =
                '${r.title} ${r.note} ${r.vibe.name} ${r.vibe.id} ${r.vibe.wish}'
                    .toLowerCase();
            return hay.contains(query);
          }).toList(growable: false);

    final pinnedList = <VibeInstalledRecord>[
      for (final r in records)
        if (r.pinned) r,
    ];
    final unpinnedList = <VibeInstalledRecord>[
      for (final r in records)
        if (!r.pinned) r,
    ];

    final visibleWishes = _visibleWishes();

    return _wrapToneScope(
      t,
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Top bar
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  Text(
                    'Vibe Space',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      TextButton(
                        onPressed: () =>
                            showVibeOfferDialog(context, widget.host, theme: t),
                        child: Text(
                          'What ${widget.host.name} offers',
                          style: TextStyle(color: t.accent, fontSize: 12.5),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Import link',
                        icon: Icon(Icons.link, size: 18, color: t.mutedText),
                        onPressed: () => _openImportDialog(t),
                      ),
                      if (widget.headerTrailing != null) widget.headerTrailing!,
                    ],
                  ),
                ],
              ),
              Divider(height: 16, color: t.border),

              // Wish box
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('vs-wish-input'),
                      controller: _wishCtrl,
                      onChanged: (_) {
                        if (_wishProminentNote) {
                          setState(() => _wishProminentNote = false);
                        }
                      },
                      onSubmitted: _submitWish,
                      decoration: InputDecoration(
                        hintText: 'I wish ${widget.host.name} would\u2026',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('vs-wish-send'),
                    style: FilledButton.styleFrom(backgroundColor: t.accent),
                    onPressed: () => _submitWish(_wishCtrl.text),
                    child: const Text('Send'),
                  ),
                ],
              ),
              if (visibleWishes.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final wish in visibleWishes)
                      ActionChip(
                        label: Text(
                          wish.text,
                          style: TextStyle(fontSize: 12, color: t.text),
                        ),
                        backgroundColor: t.cardBackground,
                        side: BorderSide(color: t.border),
                        onPressed: () {
                          _wishCtrl.text = wish.text;
                          _startPreviewDraft(
                            wish.vibe,
                            origin: 'yours',
                            wishText: wish.text,
                          );
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: _wishProminentNote
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                    : EdgeInsets.zero,
                decoration: _wishProminentNote
                    ? BoxDecoration(
                        color: t.warn.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.warn.withValues(alpha: 0.5)),
                      )
                    : null,
                child: Text(
                  'Pick a wish or describe what you want to see.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _wishProminentNote ? FontWeight.w600 : FontWeight.w400,
                    color: _wishProminentNote ? t.text : t.mutedText,
                  ),
                ),
              ),

              // Blocked shared vibe card
              if (_blockedSharedName != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.warn.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(t.radius),
                    border: Border.all(color: t.warn.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Shared vibe: $_blockedSharedName',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'It needs ${_blockedMissing.join(', ')}, which ${widget.host.name} does not offer. It cannot run here.',
                        style: TextStyle(fontSize: 12.5, color: t.text),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => setState(_clearDraft),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ),
              ],

              // Draft preview + code + label
              if (_draftVibe != null) ...<Widget>[
                const SizedBox(height: 12),
                if (_draftPreviewRun != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.cardBackground,
                      borderRadius: BorderRadius.circular(t.radius),
                      border: Border.all(color: t.accent.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'PREVIEW ON SAMPLE DATA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: t.mutedText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_draftPreviewRun!.view != null)
                          VibeView(
                            value: _draftPreviewRun!.view!,
                            resolveSealed: widget.host.resolveSealed,
                            onCommand: (cmd, args) =>
                                _draftPreviewRun!.dispatch(cmd, args),
                          )
                        else if (_draftPreviewRun!.lastError != null)
                          Text(
                            _draftPreviewRun!.lastError!,
                            style: TextStyle(color: t.danger, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _showCode = !_showCode),
                      child: Text(_showCode ? 'Hide code' : 'Show code'),
                    ),
                  ),
                  if (_showCode) ...<Widget>[
                    Text(
                      'Your wish: “${_draftWishText ?? _draftVibe!.wish}”',
                      style: TextStyle(fontSize: 12, color: t.mutedText),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.cardBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.border),
                      ),
                      child: SelectableText(
                        _draftVibe!.source,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                _PermissionLabelCard(
                  host: widget.host,
                  vibe: _draftVibe!,
                  origin: _draftOrigin,
                  theme: t,
                  onAllow: (title, note) {
                    widget.host.install(
                      _draftVibe!,
                      origin: _draftOrigin,
                      title: title,
                      note: note,
                    );
                    _wishCtrl.clear();
                    setState(_clearDraft);
                  },
                  onCancel: () => setState(_clearDraft),
                ),
              ],

              const SizedBox(height: 16),

              // Installed header
              Text(
                'INSTALLED \u00b7 ${records.length}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.mutedText,
                ),
              ),
              if (records.length >= 2) ...<Widget>[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('vs-filter-input'),
                  controller: _filterCtrl,
                  onChanged: (v) => setState(() => _filterQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Filter installed vibes\u2026',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (records.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.lock_outline, size: 13, color: t.accent),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Values with a lock are sealed. ${widget.host.name} draws them. The vibe never sees them.',
                        style: TextStyle(fontSize: 12, color: t.mutedText),
                      ),
                    ),
                  ],
                ),
              ],

              // Undo delete banner
              if (_deletedSnapshot != null) ...<Widget>[
                const SizedBox(height: 8),
                Container(
                  key: const Key('vs-undo-banner'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.accent.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Deleted \u201c${_deletedSnapshot!.title}\u201d',
                          style: TextStyle(fontSize: 12.5, color: t.text),
                        ),
                      ),
                      TextButton(
                        key: const Key('vs-undo-delete'),
                        onPressed: () {
                          final snap = _deletedSnapshot;
                          final idx = _deletedIndex;
                          _undoTimer?.cancel();
                          setState(() => _deletedSnapshot = null);
                          if (snap != null) {
                            widget.host.restoreRecord(snap, idx);
                          }
                        },
                        child: const Text('Undo'),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              if (records.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                  decoration: BoxDecoration(
                    color: t.cardBackground,
                    borderRadius: BorderRadius.circular(t.radius),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'Nothing here yet. Make a wish.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: t.mutedText),
                  ),
                )
              else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  decoration: BoxDecoration(
                    color: t.cardBackground,
                    borderRadius: BorderRadius.circular(t.radius),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'No matching vibes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: t.mutedText),
                  ),
                )
              else
                for (final rec in filtered) ...<Widget>[
                  Builder(
                    builder: (context) {
                      final grp = rec.pinned ? pinnedList : unpinnedList;
                      final grpIdx = grp.indexWhere(
                        (x) => x.instanceId == rec.instanceId,
                      );
                      final globalIdx = records.indexWhere(
                        (x) => x.instanceId == rec.instanceId,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _InstalledVibeCard(
                          key: ValueKey<String>(rec.instanceId),
                          host: widget.host,
                          record: rec,
                          theme: t,
                          canMoveUp: grpIdx > 0,
                          canMoveDown: grpIdx >= 0 && grpIdx < grp.length - 1,
                          onEdit: () => _openEditDialog(rec, t),
                          onShare: () => _openShareDialog(rec.vibe, t),
                          onMoveUp: () => _moveWithinGroup(rec, -1),
                          onMoveDown: () => _moveWithinGroup(rec, 1),
                          onDelete: () =>
                              _deleteWithUndo(rec, globalIdx >= 0 ? globalIdx : 0),
                        ),
                      );
                    },
                  ),
                ],

              // Portable vibes gallery
              if (widget.gallery.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  'PORTABLE VIBES',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: t.mutedText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'These need nothing from the app, so they run anywhere.',
                  style: TextStyle(fontSize: 12, color: t.mutedText),
                ),
                const SizedBox(height: 8),
                for (final gv in widget.gallery)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: t.cardBackground,
                      borderRadius: BorderRadius.circular(t.radius),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                gv.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                              if (gv.wish.isNotEmpty)
                                Text(
                                  gv.wish,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.mutedText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () =>
                              _startPreviewDraft(gv, origin: 'gallery'),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InstalledVibeCard extends StatefulWidget {
  const _InstalledVibeCard({
    super.key,
    required this.host,
    required this.record,
    required this.theme,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onShare,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final VibeProtocolHost host;
  final VibeInstalledRecord record;
  final VibeSpaceThemeData theme;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  State<_InstalledVibeCard> createState() => _InstalledVibeCardState();
}

class _InstalledVibeCardState extends State<_InstalledVibeCard> {
  VibeRunController? _run;
  VoidCallback? _runUnsub;
  bool _inspectOpen = false;
  bool _renaming = false;
  final TextEditingController _renameCtrl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _syncRun(null);
    _renameFocus.addListener(() {
      if (!_renameFocus.hasFocus && _renaming) {
        _commitRename();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _InstalledVibeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRun(oldWidget.record);
  }

  void _syncRun(VibeInstalledRecord? prev) {
    final rec = widget.record;
    if (rec.paused) {
      _stopRun();
      return;
    }
    final needsRemount = prev == null ||
        prev.paused ||
        prev.vibe.source != rec.vibe.source ||
        prev.vibe.version != rec.vibe.version ||
        !_sameNeeds(prev.vibe.needs, rec.vibe.needs) ||
        prev.vibe.refreshMs != rec.vibe.refreshMs ||
        jsonEncode(prev.args) != jsonEncode(rec.args);

    if (needsRemount) {
      _stopRun();
      final nextRun = widget.host.mount(
        rec.vibe,
        dataMode: 'live',
        args: rec.args,
      );
      _run = nextRun;
      _runUnsub = nextRun.onUpdate(() {
        if (mounted) setState(() {});
      });
    }
  }

  void _stopRun() {
    _runUnsub?.call();
    _runUnsub = null;
    _run?.stop();
    _run = null;
  }

  @override
  void dispose() {
    _stopRun();
    _renameCtrl.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename() {
    setState(() {
      _renaming = true;
      _renameCtrl.text = widget.record.title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _renameFocus.requestFocus();
        _renameCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _renameCtrl.text.length,
        );
      }
    });
  }

  void _commitRename() {
    if (!_renaming) return;
    final next = _renameCtrl.text.trim();
    setState(() => _renaming = false);
    if (next.isNotEmpty && next != widget.record.title) {
      widget.host.updateRecord(widget.record.instanceId, title: next);
    }
  }

  void _cancelRename() {
    if (!_renaming) return;
    setState(() => _renaming = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final rec = widget.record;
    final health = _run?.health();

    String? stateBadgeText;
    Color stateBadgeColor = t.mutedText;
    if (rec.paused) {
      stateBadgeText = 'Paused';
    } else if (health != null && health.usingSampleFallback) {
      stateBadgeText = 'Sample data';
      stateBadgeColor = t.accent;
    } else if (health != null && health.state == VibeSourceMode.offline) {
      stateBadgeText = 'Source offline';
      stateBadgeColor = t.warn;
    } else if (health != null &&
        (health.state == VibeSourceMode.revoked ||
            health.state == VibeSourceMode.missing)) {
      stateBadgeText = 'Source unavailable';
      stateBadgeColor = t.warn;
    }

    return Container(
      key: Key('vs-card-${rec.instanceId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardBackground,
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Header: collapse + title + three-dots menu
          Row(
            children: <Widget>[
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: rec.collapsed ? 'Expand' : 'Collapse',
                icon: Icon(
                  rec.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: t.mutedText,
                ),
                onPressed: () => widget.host.updateRecord(
                  rec.instanceId,
                  collapsed: !rec.collapsed,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _renaming
                    ? KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (ev) {
                          if (ev.logicalKey == LogicalKeyboardKey.escape) {
                            _cancelRename();
                          }
                        },
                        child: TextField(
                          key: Key('vs-rename-input-${rec.instanceId}'),
                          controller: _renameCtrl,
                          focusNode: _renameFocus,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _commitRename(),
                        ),
                      )
                    : InkWell(
                        onTap: _startRename,
                        child: Text(
                          rec.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                      ),
              ),
              PopupMenuButton<String>(
                key: Key('vs-more-${rec.instanceId}'),
                tooltip: 'Manage vibe',
                icon: Icon(Icons.more_horiz, size: 18, color: t.mutedText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      widget.onEdit();
                    case 'rename':
                      _startRename();
                    case 'inspect':
                      setState(() => _inspectOpen = !_inspectOpen);
                    case 'share':
                      widget.onShare();
                    case 'pause':
                      widget.host.updateRecord(
                        rec.instanceId,
                        paused: !rec.paused,
                      );
                    case 'pin':
                      widget.host.updateRecord(
                        rec.instanceId,
                        pinned: !rec.pinned,
                      );
                    case 'up':
                      widget.onMoveUp();
                    case 'down':
                      widget.onMoveDown();
                    case 'revert':
                      widget.host.revertRecord(rec.instanceId, 0);
                    case 'delete':
                      widget.onDelete();
                  }
                },
                itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit\u2026'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('Rename'),
                  ),
                  PopupMenuItem<String>(
                    value: 'inspect',
                    child: Text(_inspectOpen ? 'Hide inspect' : 'Inspect'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'share',
                    child: Text('Share\u2026'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'pause',
                    child: Text(rec.paused ? 'Resume' : 'Pause'),
                  ),
                  PopupMenuItem<String>(
                    value: 'pin',
                    child: Text(rec.pinned ? 'Unpin' : 'Pin to top'),
                  ),
                  PopupMenuItem<String>(
                    value: 'up',
                    enabled: widget.canMoveUp,
                    child: const Text('Move up'),
                  ),
                  PopupMenuItem<String>(
                    value: 'down',
                    enabled: widget.canMoveDown,
                    child: const Text('Move down'),
                  ),
                  if (rec.history.isNotEmpty)
                    PopupMenuItem<String>(
                      value: 'revert',
                      child: Text('Revert to v${rec.history.first.vibe.version}'),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      'Delete',
                      style: TextStyle(color: t.danger, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (rec.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              rec.note,
              style: TextStyle(fontSize: 12.5, color: t.mutedText),
            ),
          ],

          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              if (rec.pinned) _SmallPill(label: 'Pinned', color: t.accent, theme: t),
              _SmallPill(
                label: _originBadgeLabel(rec.origin),
                color: t.mutedText,
                theme: t,
              ),
              _SmallPill(
                label: rec.history.isNotEmpty
                    ? 'v${rec.vibe.version} \u00b7 ${rec.history.length} prev'
                    : 'v${rec.vibe.version}',
                color: t.mutedText,
                theme: t,
              ),
              if (stateBadgeText != null)
                _SmallPill(
                  label: stateBadgeText,
                  color: stateBadgeColor,
                  theme: t,
                ),
            ],
          ),

          if (!rec.collapsed) ...<Widget>[
            Divider(height: 16, color: t.border),
            if (rec.paused)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.border),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Text(
                      'Paused \u2014 live updates stopped.',
                      style: TextStyle(fontSize: 12.5, color: t.mutedText),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: t.accent),
                      onPressed: () =>
                          widget.host.updateRecord(rec.instanceId, paused: false),
                      child: const Text('Resume'),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              if (health != null &&
                  (health.state != VibeSourceMode.live ||
                      health.usingSampleFallback)) ...<Widget>[
                _SourceHealthBanner(
                  bannerKey: Key('vs-source-banner-${rec.instanceId}'),
                  health: health,
                  theme: t,
                  onRetry: () => _run?.retry(),
                  onUseSample: () => _run?.setDataMode('sample'),
                  onUseLive: () => _run?.setDataMode('live'),
                  onEdit: widget.onEdit,
                ),
                const SizedBox(height: 8),
              ],
              _RunViewBody(
                host: widget.host,
                run: _run,
                theme: t,
              ),
            ],
            if (_inspectOpen) ...<Widget>[
              const SizedBox(height: 10),
              _InspectPane(
                host: widget.host,
                vibe: rec.vibe,
                run: _run,
                theme: t,
                onHide: () => setState(() => _inspectOpen = false),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    required this.label,
    required this.color,
    required this.theme,
  });

  final String label;
  final Color color;
  final VibeSpaceThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SourceHealthBanner extends StatelessWidget {
  const _SourceHealthBanner({
    this.bannerKey,
    required this.health,
    required this.theme,
    required this.onRetry,
    required this.onUseSample,
    required this.onUseLive,
    this.onEdit,
  });

  final Key? bannerKey;
  final VibeRunHealth health;
  final VibeSpaceThemeData theme;
  final VoidCallback onRetry;
  final VoidCallback onUseSample;
  final VoidCallback onUseLive;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    if (health.usingSampleFallback || health.state == VibeSourceMode.sample) {
      return Container(
        key: bannerKey,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Previewing sample data instead of live data.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onUseLive,
              child: const Text('Return to live'),
            ),
          ],
        ),
      );
    }

    var headline = health.state == VibeSourceMode.offline
        ? 'Source offline'
        : (health.state == VibeSourceMode.revoked
            ? 'Source access turned off'
            : 'Source unavailable');
    if (health.isStale) {
      headline += ' \u00b7 Showing last reading';
    }
    final hasSample = health.issues.any((i) => i.hasSample);

    return Container(
      key: bannerKey,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.warn.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.warn.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            headline,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          for (final iss in health.issues) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '${iss.title}: ${iss.reason}',
              style: TextStyle(fontSize: 12, color: t.mutedText),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              if (hasSample)
                OutlinedButton(
                  onPressed: onUseSample,
                  child: const Text('Preview sample'),
                ),
              if (onEdit != null &&
                  (health.state == VibeSourceMode.revoked ||
                      health.state == VibeSourceMode.missing))
                OutlinedButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunViewBody extends StatelessWidget {
  const _RunViewBody({
    required this.host,
    required this.run,
    required this.theme,
  });

  final VibeProtocolHost host;
  final VibeRunController? run;
  final VibeSpaceThemeData theme;

  @override
  Widget build(BuildContext context) {
    final r = run;
    if (r == null) return const SizedBox.shrink();
    final health = r.health();
    if (r.view != null) {
      final viewWidget = VibeView(
        value: Map<String, dynamic>.from(r.view!),
        resolveSealed: host.resolveSealed,
        onCommand: (cmd, args) => r.dispatch(cmd, args),
      );
      if (health.isStale) {
        return Opacity(opacity: 0.58, child: viewWidget);
      }
      return viewWidget;
    }
    if (r.lastError != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.danger.withValues(alpha: 0.5)),
        ),
        child: Text(
          r.lastError!,
          style: TextStyle(fontSize: 12.5, color: theme.danger),
        ),
      );
    }
    if (r.unavailableReason != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.border),
        ),
        child: Text(
          r.unavailableReason!,
          style: TextStyle(fontSize: 12.5, color: theme.mutedText),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _EditVibeDialog extends StatefulWidget {
  const _EditVibeDialog({
    required this.host,
    required this.record,
    required this.wishes,
    required this.theme,
  });

  final VibeProtocolHost host;
  final VibeInstalledRecord record;
  final List<VibeWishPreset> wishes;
  final VibeSpaceThemeData theme;

  @override
  State<_EditVibeDialog> createState() => _EditVibeDialogState();
}

class _EditVibeDialogState extends State<_EditVibeDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _wishCtrl;
  late TextEditingController _refreshCtrl;
  late TextEditingController _sourceCtrl;
  late Set<String> _selectedNeeds;
  late VibeSpec _draftVibe;

  int _tabIndex = 0; // 0 = Remix by wish, 1 = Edit code
  String? _wishError;
  String? _saveError;
  VibeRunController? _previewRun;
  VoidCallback? _previewUnsub;

  @override
  void initState() {
    super.initState();
    final v = widget.record.vibe;
    _draftVibe = v;
    _titleCtrl = TextEditingController(text: widget.record.title);
    _noteCtrl = TextEditingController(text: widget.record.note);
    _wishCtrl = TextEditingController();
    _refreshCtrl = TextEditingController(
      text: v.refreshMs != null ? v.refreshMs.toString() : '',
    );
    _sourceCtrl = TextEditingController(text: v.source);
    _selectedNeeds = Set<String>.from(v.needs);
    _runPreview(v);
  }

  @override
  void dispose() {
    _stopPreview();
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _wishCtrl.dispose();
    _refreshCtrl.dispose();
    _sourceCtrl.dispose();
    super.dispose();
  }

  void _stopPreview() {
    _previewUnsub?.call();
    _previewUnsub = null;
    _previewRun?.stop();
    _previewRun = null;
  }

  void _runPreview(VibeSpec candidate) {
    _stopPreview();
    final check = widget.host.check(candidate);
    if (!check.ok) {
      setState(() {
        _saveError = 'Missing capabilities: ${check.missing.join(', ')}';
      });
      return;
    }
    final status = widget.host.sourceStatus(candidate.needs);
    final mode = status.mode == VibeSourceMode.live ? 'live' : 'sample';
    final run = widget.host.mount(
      candidate,
      dataMode: mode,
      args: widget.record.args,
    );
    _previewRun = run;
    _previewUnsub = run.onUpdate(() {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  VibeSpec _buildCandidateFromInputs() {
    final base = widget.record.vibe;
    final rawRefresh = _refreshCtrl.text.trim();
    final parsedRefresh = rawRefresh.isEmpty ? null : int.tryParse(rawRefresh);
    final nextNeeds = _selectedNeeds.toList(growable: false);
    final nextSource = _sourceCtrl.text;
    final codeChanged = nextSource != base.source ||
        !_sameNeeds(nextNeeds, base.needs) ||
        parsedRefresh != base.refreshMs ||
        _draftVibe.wish != base.wish;
    return base.copyWith(
      wish: _draftVibe.wish,
      version: codeChanged ? base.version + 1 : base.version,
      needs: nextNeeds,
      refreshMs: parsedRefresh,
      clearRefreshMs: parsedRefresh == null,
      source: nextSource,
    );
  }

  void _applyWishRemix(String text) {
    final res = VibeWishRemixer.apply(
      _draftVibe,
      text,
      presets: widget.wishes,
    );
    if (!res.ok || res.vibe == null) {
      setState(() {
        _wishError = res.message ?? 'Could not remix from that wish.';
      });
      return;
    }
    final next = res.vibe!;
    setState(() {
      _wishError = null;
      _saveError = null;
      _draftVibe = next;
      _selectedNeeds = Set<String>.from(next.needs);
      _refreshCtrl.text = next.refreshMs?.toString() ?? '';
      _sourceCtrl.text = next.source;
    });
    _runPreview(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final base = widget.record.vibe;
    final candidate = _buildCandidateFromInputs();
    final addedNeeds = <String>[
      for (final n in candidate.needs)
        if (!base.needs.contains(n)) n,
    ];
    final codeChanged = candidate.version != base.version;
    final history = widget.record.history;

    return AlertDialog(
      backgroundColor: t.surface,
      title: Text(
        'Edit ${widget.record.title}',
        style: TextStyle(color: t.text, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('Remix by wish')),
                  ButtonSegment<int>(value: 1, label: Text('Edit code')),
                ],
                selected: <int>{_tabIndex},
                onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
              ),
              const SizedBox(height: 12),

              if (_tabIndex == 0) ...<Widget>[
                if (base.wish.isNotEmpty) ...<Widget>[
                  Text(
                    'Current wish: \u201c${base.wish}\u201d',
                    style: TextStyle(fontSize: 12, color: t.mutedText),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _wishCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Adjust threshold, count, or minutes\u2026',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: _applyWishRemix,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _applyWishRemix(_wishCtrl.text),
                      child: const Text('Preview change'),
                    ),
                  ],
                ),
                if (_wishError != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(_wishError!, style: TextStyle(fontSize: 12, color: t.warn)),
                ],
              ] else ...<Widget>[
                Text(
                  'CAPABILITIES NEEDED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.mutedText,
                  ),
                ),
                for (final cap in widget.host.capabilities)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(cap.name, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    subtitle: Text(cap.title, style: TextStyle(fontSize: 11.5, color: t.mutedText)),
                    value: _selectedNeeds.contains(cap.name),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedNeeds.add(cap.name);
                        } else {
                          _selectedNeeds.remove(cap.name);
                        }
                      });
                    },
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _refreshCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Refresh (ms, min 500 or blank)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sourceCtrl,
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Source',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => _runPreview(_buildCandidateFromInputs()),
                    child: const Text('Test in sandbox'),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.cardBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'SANDBOX PREVIEW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _RunViewBody(host: widget.host, run: _previewRun, theme: t),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              Text(
                addedNeeds.isNotEmpty
                    ? 'Version ${candidate.version} adds access: ${addedNeeds.join(', ')}'
                    : (codeChanged
                        ? 'Version ${candidate.version}. No new permissions.'
                        : 'No permission changes.'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: addedNeeds.isNotEmpty ? t.warn : t.ok,
                ),
              ),
              if (addedNeeds.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final lbl = widget.host.label(candidate);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _LabelRow(title: 'Reads', items: lbl.reads, accentColor: t.accent, theme: t),
                        _LabelRow(title: 'Shows', items: lbl.shows, accentColor: t.mutedText, theme: t),
                        _LabelRow(title: 'Cannot', items: lbl.cannot, accentColor: t.mutedText, theme: t),
                      ],
                    );
                  },
                ),
              ],
              if (_saveError != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(_saveError!, style: TextStyle(color: t.danger, fontSize: 12.5)),
              ],

              if (history.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Divider(height: 1, color: t.border),
                const SizedBox(height: 8),
                Text(
                  'VERSION HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.mutedText,
                  ),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < history.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'v${history[i].vibe.version} \u2014 ${history[i].vibe.name}',
                            style: TextStyle(fontSize: 12.5, color: t.text),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            widget.host.revertRecord(widget.record.instanceId, i);
                            Navigator.of(context).pop();
                          },
                          child: const Text('Restore'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.accent),
          onPressed: () {
            final cleanTitle = _titleCtrl.text.trim();
            final cleanNote = _noteCtrl.text.trim();
            final next = _buildCandidateFromInputs();
            final hasCodeEdit = next.version != base.version;
            try {
              if (!hasCodeEdit) {
                widget.host.updateRecord(
                  widget.record.instanceId,
                  title: cleanTitle.isNotEmpty ? cleanTitle : base.name,
                  note: cleanNote,
                );
              } else {
                widget.host.updateRecord(
                  widget.record.instanceId,
                  title: cleanTitle.isNotEmpty ? cleanTitle : base.name,
                  note: cleanNote,
                  vibe: next,
                );
              }
              Navigator.of(context).pop();
            } catch (err) {
              setState(() => _saveError = err.toString());
            }
          },
          child: Text(addedNeeds.isNotEmpty ? 'Allow & save' : 'Save changes'),
        ),
      ],
    );
  }
}

/// Temporary vibe box rendered inline inside an agent reply, with Inspect and
/// "Pin to Vibe Space" (which asks permission and installs into [host]).
class VibeEmbedCard extends StatefulWidget {
  const VibeEmbedCard({
    super.key,
    required this.host,
    required this.vibe,
    this.args,
    this.caption,
    this.defaultTitle,
    this.theme,
    this.onPinned,
  });

  final VibeProtocolHost host;
  final VibeSpec vibe;
  final Map<String, Object?>? args;
  final String? caption;
  final String? defaultTitle;
  final VibeSpaceThemeData? theme;
  final VoidCallback? onPinned;

  @override
  State<VibeEmbedCard> createState() => _VibeEmbedCardState();
}

class _VibeEmbedCardState extends State<VibeEmbedCard> {
  VibeRunController? _run;
  VoidCallback? _runUnsub;
  bool _inspectOpen = false;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _mountRun();
  }

  @override
  void didUpdateWidget(covariant VibeEmbedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host ||
        oldWidget.vibe.id != widget.vibe.id ||
        oldWidget.vibe.source != widget.vibe.source ||
        jsonEncode(oldWidget.args) != jsonEncode(widget.args)) {
      _stopRun();
      _pinned = false;
      _mountRun();
    }
  }

  void _mountRun() {
    final run = widget.host.mount(
      widget.vibe,
      dataMode: 'live',
      args: widget.args,
    );
    _run = run;
    _runUnsub = run.onUpdate(() {
      if (mounted) setState(() {});
    });
  }

  void _stopRun() {
    _runUnsub?.call();
    _runUnsub = null;
    _run?.stop();
    _run = null;
  }

  @override
  void dispose() {
    _stopRun();
    super.dispose();
  }

  Future<void> _openPinDialog(VibeSpaceThemeData t) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Pin to Vibe Space', style: TextStyle(color: t.text)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: _PermissionLabelCard(
              host: widget.host,
              vibe: widget.vibe,
              origin: 'agent',
              theme: t,
              args: widget.args,
              defaultTitle: widget.defaultTitle ?? widget.vibe.name,
              onAllow: (title, note) {
                widget.host.install(
                  widget.vibe,
                  origin: 'agent',
                  args: widget.args,
                  title: title,
                  note: note,
                );
                Navigator.of(ctx).pop();
                setState(() => _pinned = true);
                widget.onPinned?.call();
              },
              onCancel: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _resolveVibeTheme(context, widget.theme);
    final label = widget.host.label(widget.vibe);
    final health = _run?.health();

    return _wrapToneScope(
      t,
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Made by the agent for this answer',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    if (widget.caption != null && widget.caption!.isNotEmpty)
                      Text(
                        widget.caption!,
                        style: TextStyle(fontSize: 12, color: t.mutedText),
                      ),
                  ],
                ),
                _SmallPill(
                  label: _pinned ? 'Pinned' : 'Temporary',
                  color: _pinned ? t.ok : t.warn,
                  theme: t,
                ),
              ],
            ),
            Divider(height: 16, color: t.border),
            if (health != null &&
                (health.state != VibeSourceMode.live ||
                    health.usingSampleFallback)) ...<Widget>[
              _SourceHealthBanner(
                health: health,
                theme: t,
                onRetry: () => _run?.retry(),
                onUseSample: () => _run?.setDataMode('sample'),
                onUseLive: () => _run?.setDataMode('live'),
              ),
              const SizedBox(height: 8),
            ],
            _RunViewBody(host: widget.host, run: _run, theme: t),
            Divider(height: 16, color: t.border),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                Text(
                  'Reads: ${label.reads.join(', ')}',
                  style: TextStyle(fontSize: 12, color: t.mutedText),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    TextButton(
                      onPressed: () =>
                          setState(() => _inspectOpen = !_inspectOpen),
                      child: Text(_inspectOpen ? 'Hide inspect' : 'Inspect'),
                    ),
                    if (_pinned)
                      Text(
                        'Pinned to Vibe Space',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.ok,
                        ),
                      )
                    else
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: t.accent),
                        onPressed: () => _openPinDialog(t),
                        child: const Text('Pin to Vibe Space'),
                      ),
                  ],
                ),
              ],
            ),
            if (_inspectOpen) ...<Widget>[
              const SizedBox(height: 8),
              _InspectPane(
                host: widget.host,
                vibe: widget.vibe,
                run: _run,
                theme: t,
                onHide: () => setState(() => _inspectOpen = false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
