import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibe_space/vibe_space.dart';

import 'view.dart';

/// Builder hook allowing a host app to render rich Markdown & Mermaid diagrams.
typedef VibeCanvasMarkdownBuilder = Widget Function(
  BuildContext context,
  VibeCanvasPayload payload,
);

/// Builder hook allowing a host app to render sandboxed HTML & Wasm viewports.
typedef VibeCanvasWebViewportBuilder = Widget Function(
  BuildContext context,
  VibeCanvasPayload payload,
  ValueChanged<VibeCanvasActionEvent>? onAction,
);

/// Interactive Vibe Canvas widget supporting `markdown`, `vibe_ui`, `html`, and
/// `wasm` formats with zero external package dependencies.
class VibeCanvasView extends StatefulWidget {
  const VibeCanvasView({
    super.key,
    required this.payload,
    this.onClose,
    this.onLayoutChanged,
    this.onAction,
    this.markdownBuilder,
    this.webViewportBuilder,
    this.autoSubmitTimeoutSeconds,
  });

  final VibeCanvasPayload payload;
  final VoidCallback? onClose;
  final ValueChanged<VibeCanvasLayout>? onLayoutChanged;
  final ValueChanged<VibeCanvasActionEvent>? onAction;
  final VibeCanvasMarkdownBuilder? markdownBuilder;
  final VibeCanvasWebViewportBuilder? webViewportBuilder;
  final int? autoSubmitTimeoutSeconds;

  @override
  State<VibeCanvasView> createState() => _VibeCanvasViewState();
}

class _VibeCanvasViewState extends State<VibeCanvasView> {
  bool _copied = false;

  VibeCanvasLayout _nextLayout(VibeCanvasLayout current) {
    const layouts = VibeCanvasLayout.values;
    final idx = layouts.indexOf(current);
    return layouts[(idx + 1) % layouts.length];
  }

  Future<void> _copySource() async {
    await Clipboard.setData(ClipboardData(text: widget.payload.content));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = widget.payload;
    return Container(
      key: ValueKey('vibe-canvas-view-${payload.canvasId}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context, payload),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(context, payload),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VibeCanvasPayload payload) {
    final theme = Theme.of(context);
    final nextLayout = _nextLayout(payload.layout);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(
            _iconForFormat(payload.format),
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              payload.title,
              key: const ValueKey('vibe-canvas-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Container(
                key: const ValueKey('vibe-canvas-format-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  payload.format.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            key: const ValueKey('vibe-canvas-layout-toggle'),
            tooltip:
                'Layout: ${payload.layout.label} (switch to ${nextLayout.label})',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(_iconForLayout(payload.layout), size: 18),
            onPressed: widget.onLayoutChanged == null
                ? null
                : () => widget.onLayoutChanged!(nextLayout),
          ),
          IconButton(
            key: const ValueKey('vibe-canvas-copy-button'),
            tooltip: _copied ? 'Copied!' : 'Copy canvas source',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 18,
            ),
            onPressed: _copySource,
          ),
          IconButton(
            key: const ValueKey('vibe-canvas-close-button'),
            tooltip: 'Close canvas',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, VibeCanvasPayload payload) {
    switch (payload.format) {
      case VibeCanvasFormat.vibeUi:
        return _buildVibeUiBody(context, payload);
      case VibeCanvasFormat.markdown:
        if (widget.markdownBuilder != null) {
          return widget.markdownBuilder!(context, payload);
        }
        return _buildMarkdownFallback(context, payload);
      case VibeCanvasFormat.html:
      case VibeCanvasFormat.wasm:
        if (widget.webViewportBuilder != null) {
          return widget.webViewportBuilder!(context, payload, widget.onAction);
        }
        return _buildWebFallback(context, payload);
    }
  }

  Widget _buildVibeUiBody(BuildContext context, VibeCanvasPayload payload) {
    final decoded = payload.tryDecodeVibeUi();
    if (decoded == null) {
      return _buildErrorCard(
        context,
        title: 'Invalid Vibe UI JSON',
        message: 'Canvas content is not a valid JSON object.',
      );
    }
    try {
      validateVibeView(decoded);
    } on FormatException catch (error) {
      return _buildErrorCard(
        context,
        title: 'Invalid Vibe UI Schema',
        message: error.message,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('vibe-canvas-vibe-ui-body'),
      padding: const EdgeInsets.all(16),
      child: VibeView(
        value: decoded,
        autoSubmitTimeoutSeconds: widget.autoSubmitTimeoutSeconds,
        onCommand: (command, args) {
          widget.onAction?.call(
            VibeCanvasActionEvent(
              canvasId: payload.canvasId,
              taskId: payload.taskId,
              actionName: command,
              arguments: Map<String, Object?>.from(args),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarkdownFallback(
    BuildContext context,
    VibeCanvasPayload payload,
  ) {
    final theme = Theme.of(context);
    final blocks = _parseMarkdownBlocks(payload.content);
    return SingleChildScrollView(
      key: const ValueKey('vibe-canvas-markdown-fallback'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < blocks.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 10),
            _buildMarkdownBlockWidget(context, theme, blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkdownBlockWidget(
    BuildContext context,
    ThemeData theme,
    _MarkdownBlock block,
  ) {
    switch (block.kind) {
      case _MarkdownBlockKind.heading:
        final fontSize = switch (block.headingLevel) {
          1 => 22.0,
          2 => 18.0,
          _ => 16.0,
        };
        return SelectableText(
          block.text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        );
      case _MarkdownBlockKind.code:
        final badge = block.language.isEmpty
            ? 'CODE'
            : block.language.toUpperCase();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                badge,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                block.text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      case _MarkdownBlockKind.bulletList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in block.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('• '),
                    Expanded(child: SelectableText(item)),
                  ],
                ),
              ),
          ],
        );
      case _MarkdownBlockKind.paragraph:
        return SelectableText(
          block.text,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        );
      case _MarkdownBlockKind.table:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 48,
            columnSpacing: 18,
            horizontalMargin: 12,
            columns: <DataColumn>[
              for (final h in block.tableHeaders)
                DataColumn(
                  label: Text(
                    h,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
            rows: <DataRow>[
              for (final row in block.tableRows)
                DataRow(
                  cells: <DataCell>[
                    for (var i = 0; i < block.tableHeaders.length; i++)
                      DataCell(
                        SelectableText(i < row.length ? row[i] : ''),
                      ),
                  ],
                ),
            ],
          ),
        );
    }
  }

  Widget _buildWebFallback(BuildContext context, VibeCanvasPayload payload) {
    final theme = Theme.of(context);
    final wasmBytes = _decodeWasmByteSize(payload.wasmBase64);
    final isWasm = payload.format == VibeCanvasFormat.wasm;
    return SingleChildScrollView(
      key: const ValueKey('vibe-canvas-web-fallback'),
      padding: const EdgeInsets.all(16),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isWasm ? Icons.memory_outlined : Icons.html_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWasm
                          ? 'Sandboxed Wasm Mini-App Preview'
                          : 'Sandboxed HTML Preview',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (wasmBytes != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Wasm binary: $wasmBytes bytes',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (payload.jsGlue != null &&
                  payload.jsGlue!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'JS glue attached (${payload.jsGlue!.length} chars)',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  payload.content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          key: const ValueKey('vibe-canvas-vibe-ui-error'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconForFormat(VibeCanvasFormat format) => switch (format) {
        VibeCanvasFormat.markdown => Icons.article_outlined,
        VibeCanvasFormat.vibeUi => Icons.widgets_outlined,
        VibeCanvasFormat.html => Icons.web_outlined,
        VibeCanvasFormat.wasm => Icons.memory_outlined,
      };

  static IconData _iconForLayout(VibeCanvasLayout layout) => switch (layout) {
        VibeCanvasLayout.splitRight => Icons.vertical_split_outlined,
        VibeCanvasLayout.tab => Icons.tab_outlined,
        VibeCanvasLayout.modal => Icons.branding_watermark_outlined,
      };

  static int? _decodeWasmByteSize(String? rawBase64) {
    final trimmed = rawBase64?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      return base64Decode(trimmed).length;
    } on Object {
      return (trimmed.length * 3) ~/ 4;
    }
  }
}

enum _MarkdownBlockKind { heading, code, bulletList, paragraph, table }

class _MarkdownBlock {
  const _MarkdownBlock({
    required this.kind,
    this.text = '',
    this.headingLevel = 1,
    this.language = '',
    this.items = const <String>[],
    this.tableHeaders = const <String>[],
    this.tableRows = const <List<String>>[],
  });

  final _MarkdownBlockKind kind;
  final String text;
  final int headingLevel;
  final String language;
  final List<String> items;
  final List<String> tableHeaders;
  final List<List<String>> tableRows;
}

List<String> _splitMarkdownTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed.split('|').map((c) => c.trim()).toList(growable: false);
}

bool _isMarkdownTableSeparator(String line) {
  final cells = _splitMarkdownTableRow(line);
  if (cells.isEmpty) return false;
  return cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c));
}

List<_MarkdownBlock> _parseMarkdownBlocks(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MarkdownBlock>[];
  var inFence = false;
  var fenceLanguage = '';
  final fenceLines = <String>[];
  final paragraphLines = <String>[];
  final bulletItems = <String>[];
  final tableLines = <String>[];

  void flushParagraph() {
    if (paragraphLines.isEmpty) return;
    blocks.add(
      _MarkdownBlock(
        kind: _MarkdownBlockKind.paragraph,
        text: paragraphLines.join('\n').trim(),
      ),
    );
    paragraphLines.clear();
  }

  void flushBullets() {
    if (bulletItems.isEmpty) return;
    blocks.add(
      _MarkdownBlock(
        kind: _MarkdownBlockKind.bulletList,
        items: List<String>.unmodifiable(bulletItems),
      ),
    );
    bulletItems.clear();
  }

  void flushTable() {
    if (tableLines.isEmpty) return;
    if (tableLines.length >= 2 && _isMarkdownTableSeparator(tableLines[1])) {
      final headers = _splitMarkdownTableRow(tableLines[0]);
      final rows = <List<String>>[
        for (var i = 2; i < tableLines.length; i++)
          _splitMarkdownTableRow(tableLines[i]),
      ];
      blocks.add(
        _MarkdownBlock(
          kind: _MarkdownBlockKind.table,
          tableHeaders: headers,
          tableRows: rows,
        ),
      );
    } else {
      paragraphLines.addAll(tableLines);
      flushParagraph();
    }
    tableLines.clear();
  }

  for (final line in lines) {
    final trimmed = line.trim();
    if (inFence) {
      if (trimmed.startsWith('```')) {
        blocks.add(
          _MarkdownBlock(
            kind: _MarkdownBlockKind.code,
            language: fenceLanguage,
            text: fenceLines.join('\n'),
          ),
        );
        fenceLines.clear();
        fenceLanguage = '';
        inFence = false;
      } else {
        fenceLines.add(line);
      }
      continue;
    }

    if (trimmed.startsWith('```')) {
      flushTable();
      flushParagraph();
      flushBullets();
      inFence = true;
      fenceLanguage = trimmed.substring(3).trim();
      continue;
    }

    if (trimmed.isEmpty) {
      flushTable();
      flushParagraph();
      flushBullets();
      continue;
    }

    if (trimmed.contains('|') &&
        (trimmed.startsWith('|') || trimmed.endsWith('|'))) {
      flushParagraph();
      flushBullets();
      tableLines.add(trimmed);
      continue;
    }
    flushTable();

    final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (headingMatch != null) {
      flushParagraph();
      flushBullets();
      blocks.add(
        _MarkdownBlock(
          kind: _MarkdownBlockKind.heading,
          headingLevel: headingMatch.group(1)!.length,
          text: headingMatch.group(2)!.trim(),
        ),
      );
      continue;
    }

    final bulletMatch = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
    if (bulletMatch != null) {
      flushParagraph();
      bulletItems.add(bulletMatch.group(1)!.trim());
      continue;
    }

    flushBullets();
    paragraphLines.add(line);
  }

  if (inFence && fenceLines.isNotEmpty) {
    blocks.add(
      _MarkdownBlock(
        kind: _MarkdownBlockKind.code,
        language: fenceLanguage,
        text: fenceLines.join('\n'),
      ),
    );
  }
  flushTable();
  flushParagraph();
  flushBullets();

  if (blocks.isEmpty && markdown.trim().isNotEmpty) {
    blocks.add(
      _MarkdownBlock(
        kind: _MarkdownBlockKind.paragraph,
        text: markdown.trim(),
      ),
    );
  }
  return blocks;
}
