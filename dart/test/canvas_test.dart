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

  test('isReadOnlyCanvasMcpTool and isReadOnlyCanvasShellCommand enforce strict read-only policy', () {
    // Legacy aliases
    expect(isReadOnlyCanvasMcpTool('mcp.server.metrics'), isTrue);
    expect(isReadOnlyCanvasMcpTool('mcp.server.network_bandwidth'), isTrue);
    expect(isReadOnlyCanvasMcpTool('mcp.server.processes'), isTrue);
    expect(isReadOnlyCanvasMcpTool('mcp.ssh.exec_readonly'), isTrue);
    expect(isReadOnlyCanvasMcpTool('client.canvas.read_metrics'), isTrue);
    expect(isReadOnlyCanvasMcpTool('server.telemetry.snapshot'), isTrue);
    expect(isReadOnlyCanvasMcpTool('server.process.inspect'), isTrue);

    // Canonical MCP tools
    expect(isReadOnlyCanvasMcpTool('host_process_list'), isTrue);
    expect(isReadOnlyCanvasMcpTool('runner_info'), isTrue);
    expect(isReadOnlyCanvasMcpTool('runner_ping'), isTrue);
    expect(isReadOnlyCanvasMcpTool('runner_usage'), isTrue);
    expect(isReadOnlyCanvasMcpTool('server.network.sockets'), isTrue);
    expect(isReadOnlyCanvasMcpTool('ssh_resource'), isTrue);
    expect(isReadOnlyCanvasMcpTool('read_files'), isTrue);
    expect(isReadOnlyCanvasMcpTool('git_status'), isTrue);
    expect(isReadOnlyCanvasMcpTool('observe_jobs'), isTrue);

    // Mutating / unlisted tools are rejected
    expect(isReadOnlyCanvasMcpTool('server.containers.prune_images'), isFalse);
    expect(isReadOnlyCanvasMcpTool('write_project_file'), isFalse);
    expect(isReadOnlyCanvasMcpTool('apply_text_edits'), isFalse);
    expect(isReadOnlyCanvasMcpTool('run_shell'), isFalse);
    expect(isReadOnlyCanvasMcpTool('host_process_terminate'), isFalse);
    expect(isReadOnlyCanvasMcpTool('client.canvas.render'), isFalse);

    expect(isReadOnlyCanvasShellCommand('LC_ALL=C cat /proc/net/dev'), isTrue);
    expect(
      isReadOnlyCanvasShellCommand(
        'LC_ALL=C ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%cpu,-%mem | head -n 6',
      ),
      isTrue,
    );
    expect(isReadOnlyCanvasShellCommand('rm -rf /tmp/foo'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /proc/meminfo > /tmp/out'), isFalse);
    expect(isReadOnlyCanvasShellCommand('sudo systemctl restart nginx'), isFalse);
    expect(isReadOnlyCanvasShellCommand('kill -9 1024'), isFalse);
  });

  test('VibeMcpToolCatalog resolves canonical names, tags, and conditional exposure', () {
    final catalog = VibeMcpToolCatalog.instance;

    // Canonical resolution from aliases
    expect(catalog.resolveCanonicalName('mcp.server.metrics'), 'runner_info');
    expect(catalog.resolveCanonicalName('server.telemetry.snapshot'), 'runner_info');
    expect(catalog.resolveCanonicalName('client.canvas.read_metrics'), 'runner_info');
    expect(catalog.resolveCanonicalName('mcp.server.network_bandwidth'), 'server.network.sockets');
    expect(catalog.resolveCanonicalName('mcp.server.processes'), 'host_process_list');
    expect(catalog.resolveCanonicalName('server.process.inspect'), 'host_process_list');
    expect(catalog.resolveCanonicalName('mcp.ssh.exec_readonly'), 'ssh_resource');
    expect(catalog.resolveCanonicalName('vibe.canvas'), 'client.canvas.render');

    // Selection condition filtering
    final telemetryCondition = VibeMcpSelectionCondition.canvasReadOnly(
      anyTags: const <VibeMcpToolTag>{
        VibeMcpToolTag.telemetry,
        VibeMcpToolTag.processInspect,
        VibeMcpToolTag.networkInspect,
        VibeMcpToolTag.sshReadOnly,
      },
    );
    final selectedNames =
        catalog.selectTools(telemetryCondition).map((t) => t.name).toSet();
    expect(
      selectedNames,
      containsAll(<String>{
        'host_process_list',
        'runner_info',
        'runner_ping',
        'runner_usage',
        'server.network.sockets',
        'ssh_resource',
      }),
    );
    expect(selectedNames, isNot(contains('write_project_file')));
    expect(selectedNames, isNot(contains('run_shell')));
    expect(selectedNames, isNot(contains('host_process_terminate')));

    // Without active SSH session, tools requiring SSH are filtered out
    final noSshCondition = VibeMcpSelectionCondition.canvasReadOnly(
      hasActiveSshSession: false,
      anyTags: const <VibeMcpToolTag>{
        VibeMcpToolTag.networkInspect,
        VibeMcpToolTag.sshReadOnly,
      },
    );
    final noSshNames =
        catalog.selectTools(noSshCondition).map((t) => t.name).toSet();
    expect(noSshNames, isNot(contains('server.network.sockets')));
    expect(noSshNames, isNot(contains('ssh_resource')));

    // LLM prompt formatting includes canonical names and aliases
    final prompt = catalog.buildLlmContextPrompt(telemetryCondition);
    expect(prompt, contains('`runner_info`'));
    expect(prompt, contains('`host_process_list`'));
    expect(prompt, contains('`server.network.sockets`'));
    expect(prompt, contains('`ssh_resource`'));
  });

  test('VibeMcpToolDescriptor.fromCatalogJson and fromProjectToolCatalogJson parse canonical catalog', () {
    final descriptor = VibeMcpToolDescriptor.fromCatalogJson(<String, dynamic>{
      'name': 'read_files',
      'scope': 'project:read',
      'mutates': false,
      'description': 'Read UTF-8 files with full-file SHA-256 revisions.',
      'location': 'runner',
      'input_schema': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'project_id': <String, dynamic>{'type': 'string'},
        },
      },
    });
    expect(descriptor.name, 'read_files');
    expect(descriptor.isReadOnly, isTrue);
    expect(descriptor.requiresProjectContext, isTrue);
    expect(descriptor.category, VibeMcpToolCategory.project);
    expect(descriptor.tags, contains(VibeMcpToolTag.filesystemRead));
    expect(descriptor.tags, contains(VibeMcpToolTag.compactDiscovery));
    expect(descriptor.surfaces, contains(VibeMcpExposureSurface.canvasReadOnly));

    final mutatingDescriptor = VibeMcpToolDescriptor.fromCatalogJson(<String, dynamic>{
      'name': 'write_project_file',
      'scope': 'project:write',
      'mutates': true,
      'description': 'Write file.',
      'location': 'runner',
    });
    expect(mutatingDescriptor.isReadOnly, isFalse);
    expect(
      mutatingDescriptor.surfaces,
      isNot(contains(VibeMcpExposureSurface.canvasReadOnly)),
    );
    expect(
      VibeMcpSelectionCondition.canvasReadOnly().allows(mutatingDescriptor),
      isFalse,
    );
  });
}
