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
      default:
        return const SizedBox.shrink();
    }
  }
}
