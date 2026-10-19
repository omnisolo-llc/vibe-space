import 'dart:convert';

import 'package:test/test.dart';
import 'package:vibe_space/vibe_space.dart';

void main() {
  test('VibeCanvasPayload parses JSON, encodes JSON, and decodes VibeView UI', () {
    final viewMap = <String, dynamic>{
      'type': 'card',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'heading', 'text': 'Cluster Status'},
      ],
    };
    final payload = VibeCanvasPayload.fromJson(<String, dynamic>{
      'canvas_id': 'canvas-42',
      'task_id': 'task-99',
      'title': 'Deployment Report',
      'format': 'vibe_ui',
      'content': viewMap,
      'layout': 'modal',
      'updated_at_iso': '2026-10-19T00:00:00Z',
    });

    expect(payload.canvasId, 'canvas-42');
    expect(payload.taskId, 'task-99');
    expect(payload.title, 'Deployment Report');
    expect(payload.format, VibeCanvasFormat.vibeUi);
    expect(payload.layout, VibeCanvasLayout.modal);
    expect(payload.updatedAtIso, '2026-10-19T00:00:00Z');
    expect(payload.tryDecodeVibeUi()?['type'], 'card');

    final json = payload.toJson();
    expect(json['canvasId'], 'canvas-42');
    expect(json['taskId'], 'task-99');
    expect(json['format'], 'vibe_ui');
    expect(json['layout'], 'modal');

    final roundTrip = VibeCanvasPayload.fromJson(
      json.map((key, value) => MapEntry(key, value)),
    );
    expect(roundTrip.canvasId, 'canvas-42');
    expect(roundTrip.format, VibeCanvasFormat.vibeUi);
    expect(roundTrip.tryDecodeVibeUi()?['type'], 'card');

    final markdownPayload = payload.copyWith(
      format: VibeCanvasFormat.markdown,
      content: '# Hello',
    );
    expect(markdownPayload.tryDecodeVibeUi(), isNull);
  });

  test('createVibeCanvasHostApi enforces api:vibe.canvas grant and schema', () async {
    VibeCanvasPayload? renderedPayload;
    String? renderedPluginId;

    final registry = VibeHostRegistry()
      ..register(
        createVibeCanvasHostApi(
          onRender: (payload, context) {
            renderedPayload = payload;
            renderedPluginId = context.pluginId;
            return true;
          },
        ),
      );

    expect(registry.supports('api:vibe.canvas'), isTrue);

    JsonMap makeEffect(Map<String, dynamic> input) => <String, dynamic>{
          'id': 'render-1',
          'method': 'host.call',
          'capability': 'api:vibe.canvas',
          'arguments': <String, dynamic>{
            'api': 'vibe.canvas',
            'version': 1,
            'input': input,
          },
        };

    VibeCallContext makeContext() => VibeCallContext(
          pluginId: 'plugin-demo',
          revision: 'r1',
          assertCurrent: () async {},
        );

    // Denied when api:vibe.canvas grant is missing.
    await expectLater(
      registry.call(
        makeEffect(<String, dynamic>{
          'title': 'Title',
          'format': 'markdown',
          'content': '# Hi',
        }),
        const <String>{},
        makeContext(),
        approve: (_) async => true,
      ),
      throwsStateError,
    );
    expect(renderedPayload, isNull);

    // Schema rejects invalid format enum.
    await expectLater(
      registry.call(
        makeEffect(<String, dynamic>{
          'title': 'Title',
          'format': 'unsupported_format',
          'content': '# Hi',
        }),
        const <String>{'api:vibe.canvas'},
        makeContext(),
        approve: (_) async => true,
      ),
      throwsFormatException,
    );

    // Valid call renders payload and returns structured output.
    final wasmBytes = base64Encode(<int>[0, 97, 115, 109, 1, 0, 0, 0]);
    final output = await registry.call(
      makeEffect(<String, dynamic>{
        'canvasId': 'wasm-canvas-1',
        'title': 'Wasm Chart',
        'format': 'wasm',
        'content': '<div id="app"></div>',
        'wasmBase64': wasmBytes,
        'jsGlue': 'console.log("boot");',
        'layout': 'split_right',
      }),
      const <String>{'api:vibe.canvas'},
      makeContext(),
      approve: (_) async => true,
    ) as JsonMap;

    expect(output['rendered'], isTrue);
    expect(output['canvasId'], 'wasm-canvas-1');
    expect(renderedPluginId, 'plugin-demo');
    expect(renderedPayload, isNotNull);
    expect(renderedPayload!.canvasId, 'wasm-canvas-1');
    expect(renderedPayload!.taskId, 'plugin-demo');
    expect(renderedPayload!.format, VibeCanvasFormat.wasm);
    expect(renderedPayload!.wasmBase64, wasmBytes);
    expect(renderedPayload!.jsGlue, 'console.log("boot");');
    expect(renderedPayload!.layout, VibeCanvasLayout.splitRight);
    expect(renderedPayload!.updatedAtIso, isNotEmpty);
  });
}
