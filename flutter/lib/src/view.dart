import 'package:flutter/material.dart';

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

    switch (node['type']) {
      case 'heading':
      case 'badge':
      case 'text':
        text('text');
        for (final key in ['bold', 'italic', 'code']) {
          if (node[key] != null && node[key] is! bool)
            throw const FormatException('Invalid text style');
        }
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
        text('title', maximum: 256);
        text('command', maximum: 128);
        if (node['arguments'] != null && node['arguments'] is! Map) {
          throw const FormatException('Invalid action arguments');
        }
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
  });
  final Map<String, dynamic> value;
  final void Function(String, Map<String, dynamic>) onCommand;
  final void Function(String, String)? onInput;
  final int depth;
  @override
  Widget build(BuildContext context) {
    if (depth > 16) throw const FormatException('Extension view is too deep');
    switch (value['type']) {
      case 'heading':
      case 'badge':
      case 'text':
        return SelectableText(
          (value['text'] as String? ?? '').substring(
            0,
            (value['text'] as String? ?? '').length.clamp(0, 64000),
          ),
          style: TextStyle(
            fontSize: value['type'] == 'heading' ? 22 : null,
            fontWeight: value['bold'] == true || value['type'] == 'heading'
                ? FontWeight.bold
                : null,
            fontStyle: value['italic'] == true ? FontStyle.italic : null,
            fontFamily: value['code'] == true ? 'monospace' : null,
          ),
        );
      case 'row':
      case 'card':
      case 'column':
        final children = (value['children'] as List).take(100);
        final widgets = <Widget>[
          for (final child in children)
            VibeView(
              value: Map<String, dynamic>.from(child as Map),
              onCommand: onCommand,
              onInput: onInput,
              depth: depth + 1,
            ),
        ];
        if (value['type'] == 'row')
          return Wrap(spacing: 12, runSpacing: 8, children: widgets);
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
        if (value['type'] == 'card')
          return Card(
            child: Padding(padding: const EdgeInsets.all(16), child: column),
          );
        return column;
      case 'divider':
        return const Divider();
      case 'progress':
        return LinearProgressIndicator(
          value: (value['value'] as num).toDouble(),
        );
      case 'action':
        return TextButton(
          onPressed: () => onCommand(
            value['command'] as String,
            Map<String, dynamic>.from(value['arguments'] as Map? ?? {}),
          ),
          child: Text(value['title'] as String),
        );
      case 'input':
        return TextField(
          key: ValueKey(value['id']),
          obscureText: value['secret'] == true,
          maxLines: value['secret'] == true
              ? 1
              : value['multiline'] == true
              ? 5
              : 1,
          onChanged: (text) => onInput?.call(value['id'] as String, text),
          decoration: InputDecoration(labelText: value['label'] as String),
        );
      case 'checkbox':
        return _VibeCheckboxField(
          id: value['id'] as String,
          label: value['label'] as String,
          initialChecked: value['checked'] == true,
          command: value['command'] as String?,
          onInput: onInput,
          onCommand: onCommand,
        );
      case 'option_group':
        return _VibeOptionGroupField(
          id: value['id'] as String,
          label: value['label'] as String?,
          multiSelect: value['multiSelect'] == true,
          options: (value['options'] as List)
              .take(50)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false),
          command: value['command'] as String?,
          onInput: onInput,
          onCommand: onCommand,
        );
      case 'table':
        final headers = (value['headers'] as List)
            .take(32)
            .map((h) => h.toString())
            .toList(growable: false);
        final rows = (value['rows'] as List).take(200);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 48,
            columnSpacing: 18,
            horizontalMargin: 12,
            columns: <DataColumn>[
              for (final h in headers)
                DataColumn(
                  label: Text(
                    h,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
            rows: <DataRow>[
              for (final row in rows)
                if (row is List)
                  DataRow(
                    cells: <DataCell>[
                      for (var i = 0; i < headers.length; i++)
                        DataCell(
                          SelectableText(
                            i < row.length ? (row[i]?.toString() ?? '') : '',
                          ),
                        ),
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

class _VibeCheckboxField extends StatefulWidget {
  const _VibeCheckboxField({
    required this.id,
    required this.label,
    required this.initialChecked,
    this.command,
    this.onInput,
    required this.onCommand,
  });

  final String id;
  final String label;
  final bool initialChecked;
  final String? command;
  final void Function(String, String)? onInput;
  final void Function(String, Map<String, dynamic>) onCommand;

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

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: ValueKey('vibe-checkbox-${widget.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(widget.label),
      value: _checked,
      onChanged: (next) {
        final checked = next ?? false;
        setState(() => _checked = checked);
        widget.onInput?.call(widget.id, checked ? 'true' : 'false');
        if (widget.command != null && widget.command!.isNotEmpty) {
          widget.onCommand(widget.command!, <String, dynamic>{
            'id': widget.id,
            'label': widget.label,
            'checked': checked,
          });
        }
      },
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
  });

  final String id;
  final String? label;
  final bool multiSelect;
  final List<Map<String, dynamic>> options;
  final String? command;
  final void Function(String, String)? onInput;
  final void Function(String, Map<String, dynamic>) onCommand;

  @override
  State<_VibeOptionGroupField> createState() => _VibeOptionGroupFieldState();
}

class _VibeOptionGroupFieldState extends State<_VibeOptionGroupField> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{
      for (final opt in widget.options)
        if (opt['checked'] == true || opt['selected'] == true)
          opt['id'].toString(),
    };
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
    final joined = _selectedIds.join(',');
    widget.onInput?.call(widget.id, joined);
    if (!widget.multiSelect &&
        widget.command != null &&
        widget.command!.isNotEmpty) {
      widget.onCommand(widget.command!, <String, dynamic>{
        'id': widget.id,
        'selected': _selectedIds.toList(growable: false),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('vibe-option-group-${widget.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null && widget.label!.trim().isNotEmpty) ...<Widget>[
          Text(
            widget.label!,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            for (final opt in widget.options)
              () {
                final optId = opt['id'].toString();
                final optLabel = opt['label'].toString();
                final selected = _selectedIds.contains(optId);
                return FilterChip(
                  key: ValueKey('vibe-option-${widget.id}-$optId'),
                  label: Text(optLabel),
                  selected: selected,
                  onSelected: (_) => _toggleOption(optId),
                );
              }(),
          ],
        ),
        if (widget.multiSelect &&
            widget.command != null &&
            widget.command!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: ValueKey('vibe-option-submit-${widget.id}'),
            onPressed: _selectedIds.isEmpty
                ? null
                : () => widget.onCommand(widget.command!, <String, dynamic>{
                      'id': widget.id,
                      'selected': _selectedIds.toList(growable: false),
                    }),
            icon: const Icon(Icons.check, size: 16),
            label: Text('Submit Selected (${_selectedIds.length})'),
          ),
        ],
      ],
    );
  }
}
