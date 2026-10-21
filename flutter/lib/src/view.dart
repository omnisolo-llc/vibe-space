import 'dart:async';

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
    this.autoSubmitTimeoutSeconds,
  });
  final Map<String, dynamic> value;
  final void Function(String, Map<String, dynamic>) onCommand;
  final void Function(String, String)? onInput;
  final int depth;
  final int? autoSubmitTimeoutSeconds;
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
              autoSubmitTimeoutSeconds: autoSubmitTimeoutSeconds,
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
        final cmd = value['command'] as String;
        final title = value['title'] as String;
        final args = Map<String, dynamic>.from(value['arguments'] as Map? ?? {});
        if (cmd == 'approval.approve') {
          return FilledButton.tonalIcon(
            onPressed: () => onCommand(cmd, args),
            icon: const Icon(Icons.check, size: 16),
            label: Text(title),
          );
        }
        if (cmd == 'approval.yolo') {
          return OutlinedButton.icon(
            onPressed: () => onCommand(cmd, args),
            icon: const Icon(Icons.bolt, size: 16),
            label: Text(title),
          );
        }
        if (cmd == 'approval.deny') {
          return OutlinedButton.icon(
            onPressed: () => onCommand(cmd, args),
            icon: const Icon(Icons.close, size: 16),
            label: Text(title),
          );
        }
        return OutlinedButton(
          onPressed: () => onCommand(cmd, args),
          child: Text(title),
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
        final rawTimeout = value['autoSubmitTimeoutSeconds'];
        final nodeTimeout = rawTimeout is int ? rawTimeout : null;
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
          autoSubmitTimeoutSeconds: autoSubmitTimeoutSeconds ?? nodeTimeout,
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
    this.autoSubmitTimeoutSeconds,
  });

  final String id;
  final String? label;
  final bool multiSelect;
  final List<Map<String, dynamic>> options;
  final String? command;
  final void Function(String, String)? onInput;
  final void Function(String, Map<String, dynamic>) onCommand;
  final int? autoSubmitTimeoutSeconds;

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
