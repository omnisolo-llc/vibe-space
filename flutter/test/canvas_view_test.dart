import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  testWidgets(
    'VibeCanvasView renders vibe_ui and emits VibeCanvasActionEvent on action tap',
    (tester) async {
      VibeCanvasActionEvent? emittedAction;
      VibeCanvasLayout? selectedLayout;
      var closed = false;

      final viewJson = jsonEncode(<String, dynamic>{
        'type': 'card',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'heading', 'text': 'Deploy Control'},
          <String, dynamic>{
            'type': 'action',
            'title': 'Promote Release',
            'command': 'promote',
            'arguments': <String, dynamic>{'track': 'production'},
          },
        ],
      });

      final payload = VibeCanvasPayload(
        canvasId: 'canvas-ui-1',
        taskId: 'task-ui-1',
        title: 'Release Dashboard',
        format: VibeCanvasFormat.vibeUi,
        content: viewJson,
        layout: VibeCanvasLayout.splitRight,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VibeCanvasView(
              payload: payload,
              onAction: (event) => emittedAction = event,
              onLayoutChanged: (layout) => selectedLayout = layout,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('vibe-canvas-view-canvas-ui-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vibe-canvas-title')), findsOneWidget);
      expect(find.text('Release Dashboard'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vibe-canvas-format-badge')),
        findsOneWidget,
      );
      expect(find.text('Vibe Declarative UI'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vibe-canvas-vibe-ui-body')),
        findsOneWidget,
      );

      await tester.tap(find.text('Promote Release'));
      await tester.pump();

      expect(emittedAction, isNotNull);
      expect(emittedAction!.canvasId, 'canvas-ui-1');
      expect(emittedAction!.taskId, 'task-ui-1');
      expect(emittedAction!.actionName, 'promote');
      expect(emittedAction!.arguments['track'], 'production');

      await tester.tap(find.byKey(const ValueKey('vibe-canvas-layout-toggle')));
      await tester.pump();
      expect(selectedLayout, VibeCanvasLayout.tab);

      await tester.tap(find.byKey(const ValueKey('vibe-canvas-close-button')));
      await tester.pump();
      expect(closed, isTrue);
    },
  );

  testWidgets('VibeCanvasView renders markdown fallback when no builder provided',
      (tester) async {
    const payload = VibeCanvasPayload(
      canvasId: 'canvas-md-1',
      title: 'Architecture Doc',
      format: VibeCanvasFormat.markdown,
      content: '# System Overview\n\n- Edge gateway\n- Worker pool\n\n```mermaid\ngraph TD\n  A-->B\n```',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VibeCanvasView(payload: payload),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('vibe-canvas-markdown-fallback')),
      findsOneWidget,
    );
    expect(find.text('System Overview'), findsOneWidget);
    expect(find.text('Edge gateway'), findsOneWidget);
    expect(find.text('MERMAID'), findsOneWidget);
    expect(find.textContaining('A-->B'), findsOneWidget);
  });

  testWidgets('VibeCanvasView renders html and wasm fallback with byte size',
      (tester) async {
    final wasmBase64 = base64Encode(<int>[0, 97, 115, 109, 1, 0, 0, 0]);
    final payload = VibeCanvasPayload(
      canvasId: 'canvas-wasm-1',
      title: 'Wasm Visualizer',
      format: VibeCanvasFormat.wasm,
      content: '<canvas id="stage"></canvas>',
      wasmBase64: wasmBase64,
      jsGlue: 'window.initStage();',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VibeCanvasView(payload: payload),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('vibe-canvas-web-fallback')),
      findsOneWidget,
    );
    expect(find.text('Sandboxed Wasm Mini-App Preview'), findsOneWidget);
    expect(find.text('Wasm binary: 8 bytes'), findsOneWidget);
    expect(find.text('<canvas id="stage"></canvas>'), findsOneWidget);
  });

  testWidgets('VibeCanvasView displays error card for invalid vibe_ui JSON',
      (tester) async {
    const payload = VibeCanvasPayload(
      canvasId: 'canvas-bad-1',
      title: 'Broken UI',
      format: VibeCanvasFormat.vibeUi,
      content: '{"type": "script_tag_not_allowed"}',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VibeCanvasView(payload: payload),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('vibe-canvas-vibe-ui-error')),
      findsOneWidget,
    );
    expect(find.text('Invalid Vibe UI Schema'), findsOneWidget);
  });
}
