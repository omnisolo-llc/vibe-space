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
    // Empty default catalog rejects unlisted tools
    expect(isReadOnlyCanvasMcpTool('telemetry.snapshot'), isFalse);
    expect(isReadOnlyCanvasMcpTool('workspace.write'), isFalse);

    // Host-injected catalog and allowedTools allow only registered read-only tools
    final customCatalog = VibeMcpToolCatalog(
      tools: <VibeMcpToolDescriptor>[
        VibeMcpToolDescriptor(
          name: 'telemetry.snapshot',
          scope: 'telemetry:read',
          mutates: false,
          category: VibeMcpToolCategory.telemetry,
          description: 'Read host CPU/RAM telemetry.',
          aliases: const <String>{'client.canvas.read_metrics'},
        ),
        VibeMcpToolDescriptor(
          name: 'workspace.write',
          scope: 'workspace:write',
          mutates: true,
          category: VibeMcpToolCategory.edit,
          description: 'Write workspace file.',
        ),
      ],
    );
    expect(
      isReadOnlyCanvasMcpTool('telemetry.snapshot', catalog: customCatalog),
      isTrue,
    );
    expect(
      isReadOnlyCanvasMcpTool(
        'client.canvas.read_metrics',
        catalog: customCatalog,
      ),
      isTrue,
    );
    expect(
      isReadOnlyCanvasMcpTool('workspace.write', catalog: customCatalog),
      isFalse,
    );
    expect(
      isReadOnlyCanvasMcpTool(
        'custom.readonly',
        catalog: customCatalog,
        allowedTools: const <String>{'custom.readonly'},
      ),
      isTrue,
    );
    // Registered mutating tool cannot be bypassed via allowedTools
    expect(
      isReadOnlyCanvasMcpTool(
        'workspace.write',
        catalog: customCatalog,
        allowedTools: const <String>{'workspace.write'},
      ),
      isFalse,
    );

    expect(isReadOnlyCanvasShellCommand('LC_ALL=C cat /proc/net/dev'), isTrue);
    expect(isReadOnlyCanvasShellCommand('LANG=C uptime'), isTrue);
    expect(
      isReadOnlyCanvasShellCommand(
        'LC_ALL=C ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%cpu,-%mem | head -n 6',
      ),
      isTrue,
    );
    expect(
      isReadOnlyCanvasShellCommand(
        'df -h | grep /dev | sort -k5 | uniq -c | wc -l',
      ),
      isTrue,
    );
    expect(isReadOnlyCanvasShellCommand('rm -rf /tmp/foo'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /proc/meminfo > /tmp/out'), isFalse);
    expect(isReadOnlyCanvasShellCommand('sudo systemctl restart nginx'), isFalse);
    expect(isReadOnlyCanvasShellCommand('kill -9 1024'), isFalse);

    // Regression tests for allowlist bypasses
    expect(isReadOnlyCanvasShellCommand('python3 -c "print(1)"'), isFalse);
    expect(isReadOnlyCanvasShellCommand("perl -e 'print 1'"), isFalse);
    expect(isReadOnlyCanvasShellCommand('find /tmp -delete'), isFalse);
    expect(isReadOnlyCanvasShellCommand('sed -i s/a/b/ /tmp/file'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.ssh/id_rsa'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.ssh/id_ed25519'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.aws/credentials'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /app/.env'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /etc/shadow'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /etc/sudoers'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ps | awk "{print \$1}"'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ls | xargs rm'), isFalse);
    expect(isReadOnlyCanvasShellCommand('curl https://example.com'), isFalse);
    expect(isReadOnlyCanvasShellCommand('wget https://example.com'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ls; id'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ls && id'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ls || id'), isFalse);
    expect(isReadOnlyCanvasShellCommand('echo `whoami`'), isFalse);
    expect(isReadOnlyCanvasShellCommand('echo \x00'), isFalse);

    // Case-sensitive short flag regressions
    expect(isReadOnlyCanvasShellCommand('dmesg -D'), isFalse);
    expect(isReadOnlyCanvasShellCommand('dmesg -C'), isFalse);
    expect(isReadOnlyCanvasShellCommand('dmesg -E'), isFalse);
    expect(isReadOnlyCanvasShellCommand('dmesg -F /tmp/x'), isFalse);
    expect(isReadOnlyCanvasShellCommand('dmesg -c'), isFalse);
    expect(isReadOnlyCanvasShellCommand('dmesg -T'), isTrue);
    expect(isReadOnlyCanvasShellCommand('sort -T /tmp'), isFalse);
    expect(isReadOnlyCanvasShellCommand('sort -t:'), isTrue);
    expect(isReadOnlyCanvasShellCommand('tail -F /var/log/syslog'), isFalse);
    expect(isReadOnlyCanvasShellCommand('grep -F foo'), isTrue);
    expect(isReadOnlyCanvasShellCommand('grep -f /tmp/patterns'), isFalse);

    // Extended sensitive-path and kubectl secret checks
    expect(isReadOnlyCanvasShellCommand('cat /proc/self/environ'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /proc/42/environ'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.bash_history'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.zsh_history'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.python_history'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.pgpass'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.my.cnf'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.vault-token'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat ~/.config/gh/hosts.yml'), isFalse);
    expect(
      isReadOnlyCanvasShellCommand('cat ~/.config/gcloud/application_default.json'),
      isFalse,
    );
    expect(isReadOnlyCanvasShellCommand('ls ~/.azure'), isFalse);
    expect(isReadOnlyCanvasShellCommand('ls ~/.terraform.d'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /app/credentials'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /app/credentials.json'), isFalse);
    expect(isReadOnlyCanvasShellCommand('kubectl get secret'), isFalse);
    expect(isReadOnlyCanvasShellCommand('kubectl get secrets -n prod'), isFalse);
    expect(
      isReadOnlyCanvasShellCommand('kubectl describe secret/api-key'),
      isFalse,
    );
    expect(isReadOnlyCanvasShellCommand('kubectl get pods,secrets'), isFalse);
    expect(isReadOnlyCanvasShellCommand('kubectl get pods'), isTrue);
    expect(isReadOnlyCanvasShellCommand('docker ps'), isTrue);
    expect(isReadOnlyCanvasShellCommand('docker inspect x'), isFalse);
    expect(isReadOnlyCanvasShellCommand('cat /proc/meminfo'), isTrue);
  });

  test('VibeMcpToolCatalog resolves canonical names, tags, and conditional exposure', () {
    final catalog = VibeMcpToolCatalog(
      tools: <VibeMcpToolDescriptor>[
        VibeMcpToolDescriptor(
          name: 'telemetry.snapshot',
          scope: 'telemetry:read',
          mutates: false,
          category: VibeMcpToolCategory.telemetry,
          description: 'Read host metrics.',
          aliases: const <String>{'host.metrics', 'client.canvas.read_metrics'},
        ),
        VibeMcpToolDescriptor(
          name: 'process.inspect',
          scope: 'telemetry:read',
          mutates: false,
          category: VibeMcpToolCategory.telemetry,
          tags: <VibeMcpToolTag>{
            VibeMcpToolTag.readOnly,
            VibeMcpToolTag.processInspect,
            VibeMcpToolTag.telemetry,
          },
          description: 'Inspect running processes.',
          aliases: const <String>{'host.processes'},
        ),
        VibeMcpToolDescriptor(
          name: 'network.sockets',
          scope: 'network:read',
          mutates: false,
          category: VibeMcpToolCategory.telemetry,
          requiredContext: const <String>{'remote_session'},
          tags: <VibeMcpToolTag>{
            VibeMcpToolTag.readOnly,
            VibeMcpToolTag.networkInspect,
            VibeMcpToolTag.telemetry,
          },
          description: 'Inspect open network sockets.',
        ),
        VibeMcpToolDescriptor(
          name: 'workspace.write',
          scope: 'workspace:write',
          mutates: true,
          category: VibeMcpToolCategory.edit,
          requiresProjectContext: true,
          description: 'Write workspace file.',
        ),
        VibeMcpToolDescriptor(
          name: 'client.canvas.render',
          scope: 'ui:write',
          mutates: true,
          location: VibeMcpExecutionLocation.client,
          category: VibeMcpToolCategory.clientUi,
          description: 'Render Vibe Canvas.',
          aliases: const <String>{'vibe.canvas'},
        ),
      ],
    );

    // Canonical resolution from aliases
    expect(catalog.resolveCanonicalName('host.metrics'), 'telemetry.snapshot');
    expect(
      catalog.resolveCanonicalName('client.canvas.read_metrics'),
      'telemetry.snapshot',
    );
    expect(catalog.resolveCanonicalName('host.processes'), 'process.inspect');
    expect(catalog.resolveCanonicalName('vibe.canvas'), 'client.canvas.render');

    // Selection condition filtering
    final telemetryCondition = VibeMcpSelectionCondition.canvasReadOnly(
      activeContext: const <String>{'remote_session'},
      anyTags: <VibeMcpToolTag>{
        VibeMcpToolTag.telemetry,
        VibeMcpToolTag.processInspect,
        VibeMcpToolTag.networkInspect,
      },
    );
    final selectedNames =
        catalog.selectTools(telemetryCondition).map((t) => t.name).toSet();
    expect(
      selectedNames,
      containsAll(<String>{
        'telemetry.snapshot',
        'process.inspect',
        'network.sockets',
      }),
    );
    expect(selectedNames, isNot(contains('workspace.write')));
    expect(selectedNames, isNot(contains('client.canvas.render')));

    // Without required context, context-gated tools are filtered out
    final noSessionCondition = VibeMcpSelectionCondition.canvasReadOnly(
      activeContext: const <String>{},
      anyTags: <VibeMcpToolTag>{
        VibeMcpToolTag.telemetry,
        VibeMcpToolTag.networkInspect,
      },
    );
    final noSessionNames =
        catalog.selectTools(noSessionCondition).map((t) => t.name).toSet();
    expect(noSessionNames, contains('telemetry.snapshot'));
    expect(noSessionNames, isNot(contains('network.sockets')));

    // LLM prompt formatting includes canonical names and aliases
    final prompt = catalog.buildLlmContextPrompt(telemetryCondition);
    expect(prompt, contains('`telemetry.snapshot`'));
    expect(prompt, contains('`process.inspect`'));
    expect(prompt, contains('`network.sockets`'));
  });

  test('VibeMcpToolDescriptor.fromCatalogJson and VibeMcpToolCatalog.fromCatalogJson support custom host hooks', () {
    const customCategory = VibeMcpToolCategory('notes', 'Notes');
    const customTag = VibeMcpToolTag('notes_read');
    final catalog = VibeMcpToolCatalog.fromCatalogJson(
      jsonEncode(<String, dynamic>{
        'tools': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'notes.list',
            'scope': 'notes:read',
            'mutates': false,
            'description': 'List notes in workspace.',
            'location': 'host',
            'required_context': <String>['project'],
            'aliases': <String>['list_notes'],
          },
          <String, dynamic>{
            'name': 'notes.write',
            'scope': 'notes:write',
            'mutates': true,
            'description': 'Write note.',
            'location': 'host',
          },
        ],
      }),
      classifyCategory: (name) =>
          name.startsWith('notes.') ? customCategory : VibeMcpToolCategory.runtime,
      deriveTags: ({required name, required scope, required mutates}) =>
          <VibeMcpToolTag>{
        if (mutates) VibeMcpToolTag.mutating else VibeMcpToolTag.readOnly,
        if (!mutates && name.startsWith('notes.')) customTag,
      },
      deriveSurfaces: ({
        required name,
        required mutates,
        required category,
        required tags,
      }) =>
          <VibeMcpExposureSurface>{
        VibeMcpExposureSurface.externalAssistant,
        if (!mutates && tags.contains(customTag))
          VibeMcpExposureSurface.canvasReadOnly,
      },
    );

    final readTool = catalog.find('list_notes')!;
    expect(readTool.name, 'notes.list');
    expect(readTool.isReadOnly, isTrue);
    expect(readTool.requiresProjectContext, isTrue);
    expect(readTool.category, customCategory);
    expect(readTool.tags, contains(customTag));
    expect(readTool.surfaces, contains(VibeMcpExposureSurface.canvasReadOnly));
    expect(
      VibeMcpSelectionCondition.canvasReadOnly(
        activeContext: const <String>{'project'},
      ).allows(readTool),
      isTrue,
    );
    expect(
      VibeMcpSelectionCondition.canvasReadOnly().allows(readTool),
      isFalse,
    );

    final writeTool = catalog.find('notes.write')!;
    expect(writeTool.isReadOnly, isFalse);
    expect(
      writeTool.surfaces,
      isNot(contains(VibeMcpExposureSurface.canvasReadOnly)),
    );
    expect(
      VibeMcpSelectionCondition.canvasReadOnly().allows(writeTool),
      isFalse,
    );
  });
}
