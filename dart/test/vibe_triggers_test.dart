import 'package:test/test.dart';
import 'package:vibe_space/vibe_space.dart';

void main() {
  group('VibeTriggerMatcher & VibeTriggerCondition', () {
    test(
        'evaluates exact, glob, regex, contains, prefix, suffix, exists, and oneOf',
        () {
      final cond = VibeTriggerCondition.fromJson(<String, Object?>{
        'program': <Object?>['agy', 'docker*'],
        'command': <String, Object?>{'contains': '--model'},
        'surface': 'terminal',
        'windowTitle': <String, Object?>{
          'prefix': 'AGY',
          'caseSensitive': false
        },
        'cwd': '*/leapterm*',
        'env': <String, Object?>{
          'TMUX': <String, Object?>{'exists': true},
        },
        'context': <String, Object?>{
          'inTmux': true,
          'gitRepo': true,
          'portOpen': '3000',
          'branch': <String, Object?>{'regex': r'^swarm/[a-z-]+$'},
          'logFile': <String, Object?>{'suffix': '.jsonl'},
        },
        'not': <String, Object?>{
          'window': 'prod-bastion',
        },
      });

      final matchingCtx = VibeTriggerContext.fromJson(<String, Object?>{
        'program': '/home/kevin/.local/bin/agy',
        'command': 'agy --model gemini-pro',
        'surface': 'terminal',
        'window': 'dev-pane-1',
        'windowTitle': 'agy · session',
        'cwd': '/workspace/leapterm/app',
        'env': <String, Object?>{'TMUX': '/tmp/tmux-1000/default,123,0'},
        'context': <String, Object?>{
          'inTmux': true,
          'gitRepo': true,
          'ports': <String>['3000', '8080'],
          'branch': 'swarm/vibe-triggers',
          'logFile': 'transcript.jsonl',
        },
      });

      expect(cond.matches(matchingCtx), isTrue);
      expect(
        VibeTriggerEvaluator.matchesJson(cond.toJson(), matchingCtx.toJson()),
        isTrue,
      );
      expect(cond.describe(), contains('program'));

      // Negated window blocks match
      expect(
        cond.matches(matchingCtx.copyWith(window: 'prod-bastion')),
        isFalse,
      );
      // Missing port blocks match
      expect(
        cond.matches(
          matchingCtx.copyWith(
            context: <String, Object?>{
              ...matchingCtx.context,
              'ports': <String>['9090'],
            },
          ),
        ),
        isFalse,
      );
    });

    test('supports boolean combinators all, any, not, and always', () {
      final cond = VibeTriggerCondition.allOf(<VibeTriggerCondition>[
        VibeTriggerCondition.anyOf(<VibeTriggerCondition>[
          VibeTriggerCondition.fromJson(<String, Object?>{'program': 'nvim'}),
          VibeTriggerCondition.fromJson(<String, Object?>{'program': 'hx'}),
        ]),
        VibeTriggerCondition.notCondition(
          VibeTriggerCondition.fromJson(<String, Object?>{'cwd': '/etc*'}),
        ),
      ]);

      expect(
        cond.matches(
          const VibeTriggerContext(program: 'nvim', cwd: '/home/dev/repo'),
        ),
        isTrue,
      );
      expect(
        cond.matches(
          const VibeTriggerContext(program: 'hx', cwd: '/etc/nginx'),
        ),
        isFalse,
      );
      expect(
        const VibeTriggerCondition.never().matches(
          const VibeTriggerContext(program: 'nvim'),
        ),
        isFalse,
      );
      expect(
        const VibeTriggerCondition.always().matches(const VibeTriggerContext()),
        isTrue,
      );
    });

    test(
        'round-trips when condition on VibeSpec, VibeShareCodec, and VibeCanvasPayload',
        () {
      final trigger = VibeTriggerCondition.fromJson(<String, Object?>{
        'program': 'kubectl',
        'context': <String, Object?>{'inTmux': true},
      });
      final spec = kPortableFocusTimerVibe.copyWith(when: trigger);
      final encoded = VibeShareCodec.encode(spec);
      final decoded = VibeShareCodec.decode(encoded);
      expect(decoded.when, equals(trigger));
      expect(decoded, equals(spec));

      final canvas = VibeCanvasPayload(
        canvasId: 'k8s-card',
        title: 'K8s Pods',
        format: VibeCanvasFormat.vibeUi,
        content: '{"type":"text","text":"Pods"}',
        when: trigger,
      );
      final roundTripCanvas = VibeCanvasPayload.fromJson(canvas.toJson());
      expect(roundTripCanvas.when, equals(trigger));
    });
  });

  group('VibeTriggerEvaluator & VibeConditionalRegistry', () {
    test(
        'tracks newlyTriggered, deactivated, hysteresis holdMs, and dismissal episodes',
        () {
      final evaluator = VibeTriggerEvaluator();
      final entries = <VibeConditionalEntry>[
        VibeConditionalEntry(
          id: 'agy',
          title: 'AGY Quota',
          condition: VibeTriggerCondition.fromJson(<String, Object?>{
            'program': 'agy',
          }),
          holdMs: 1500,
          priority: 20,
        ),
        VibeConditionalEntry(
          id: 'docker',
          title: 'Docker Containers',
          condition: VibeTriggerCondition.fromJson(<String, Object?>{
            'program': 'docker*',
          }),
          priority: 10,
        ),
      ];

      var res = evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'agy'),
        nowMs: 1000,
      );
      expect(res.activeIds, <String>['agy']);
      expect(res.newlyTriggeredIds, <String>['agy']);
      expect(res.changed, isTrue);

      // Transient subshell at 1800ms (< 1500ms hold) keeps 'agy' active via hysteresis
      res = evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'git'),
        nowMs: 1800,
      );
      expect(res.activeIds, <String>['agy']);
      expect(res.heldIds, <String>['agy']);
      expect(res.changed, isFalse);

      // At 2600ms (>= 1500ms after last match at 1000ms), 'agy' deactivates
      res = evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'docker-compose'),
        nowMs: 2600,
      );
      expect(res.activeIds, <String>['docker']);
      expect(res.newlyTriggeredIds, <String>['docker']);
      expect(res.deactivatedIds, <String>['agy']);

      // Dismiss 'docker' during current episode -> suppressed until condition resets
      evaluator.dismiss('docker');
      res = evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'docker'),
        nowMs: 2700,
      );
      expect(res.activeIds, isEmpty);
      expect(res.dismissedIds, <String>['docker']);

      // Leaving docker clears episode dismissal so returning triggers again
      evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'zsh'),
        nowMs: 2800,
      );
      res = evaluator.evaluate(
        entries,
        const VibeTriggerContext(program: 'docker'),
        nowMs: 2900,
      );
      expect(res.activeIds, <String>['docker']);
    });

    test(
        'preserves preset user overrides across registerPresets, hydratePresetPayloads, and storage',
        () {
      final storage = InMemoryVibeStorage();
      final host = VibeProtocolHost(
        id: 'test-host',
        name: 'Test Host',
        storage: storage,
        capabilities: const <VibeCapability>[],
      );
      final registry = VibeConditionalRegistry(host: host, storage: storage);

      final agyPreset = VibeConditionalEntry(
        id: 'vibe.preset.agy',
        title: 'AGY Models',
        isPreset: true,
        priority: 100,
        condition: VibeTriggerCondition.fromJson(<String, Object?>{
          'program': 'agy',
        }),
        canvas: const VibeCanvasPayload(
          canvasId: 'agy-canvas',
          title: 'AGY',
          format: VibeCanvasFormat.vibeUi,
          content: '{"type":"stat","label":"TPS","value":"42"}',
        ),
      );
      final gitPreset = VibeConditionalEntry(
        id: 'vibe.preset.git',
        title: 'Git Repo',
        isPreset: true,
        priority: 50,
        condition: VibeTriggerCondition.fromJson(<String, Object?>{
          'context': <String, Object?>{'gitRepo': true},
        }),
      );

      registry.registerPresets(<VibeConditionalEntry>[agyPreset, gitPreset]);

      // User disables gitPreset and adds a custom Vibe view
      registry.setEnabled('vibe.preset.git', false);
      registry.upsert(
        VibeConditionalEntry(
          id: 'custom.branch-banner',
          title: 'Branch {{gitBranch}}',
          condition: VibeTriggerCondition.fromJson(<String, Object?>{
            'cwd': '/repo*',
          }),
          canvas: const VibeCanvasPayload(
            canvasId: 'custom-md',
            title: 'On {{gitBranch}}',
            format: VibeCanvasFormat.markdown,
            content: 'Working in `{{cwd}}` on **{{gitBranch}}**',
          ),
        ),
      );

      // Live telemetry updates agyPreset payload without touching custom entries or overrides
      registry.hydratePresetPayloads(<String, Object?>{
        'vibe.preset.agy': const VibeCanvasPayload(
          canvasId: 'agy-canvas',
          title: 'AGY Live',
          format: VibeCanvasFormat.vibeUi,
          content: '{"type":"stat","label":"TPS","value":"88"}',
        ),
      });

      final eval = registry.updateContextFromJson(<String, Object?>{
        'program': 'agy',
        'cwd': '/repo/app',
        'context': <String, Object?>{
          'gitRepo': true,
          'gitBranch': 'main',
        },
      });

      expect(
        eval.activeIds,
        <String>['vibe.preset.agy', 'custom.branch-banner'],
      );
      expect(
        registry.activeEntries.first.canvas!.content,
        contains('"88"'),
      );
      final hydratedMd = eval.activeEntries[1].hydratedCanvas(eval.context)!;
      expect(hydratedMd.title, 'On main');
      expect(hydratedMd.content, 'Working in `/repo/app` on **main**');

      // Reloading from storage retains custom view and disabled gitPreset override
      final reloaded = VibeConditionalRegistry(host: host, storage: storage);
      reloaded.registerPresets(<VibeConditionalEntry>[agyPreset, gitPreset]);
      reloaded.updateContext(eval.context);
      expect(
        reloaded.activeEntries.map((e) => e.id).toList(),
        <String>['vibe.preset.agy', 'custom.branch-banner'],
      );

      reloaded.dispose();
      registry.dispose();
      host.dispose();
    });
  });

  group('WeChat Mini Program Dual-Layer & Skyline VXML / Canvas', () {
    test(
        'parses air-gapped defineMiniProgram, enforces sandbox caps, and compiles VXML + canvas',
        () {
      expect(
        () => validateMiniProgramSource(
          'defineMiniProgram({ onLoad() { fetch("https://evil.example"); } })',
        ),
        throwsFormatException,
      );
      expect(
        () => validateMiniProgramSource(
          'defineMiniProgram({ onLoad() { window.alert(1); } })',
        ),
        throwsFormatException,
      );

      final def = VibeMiniProgramDefinition.fromSource('''
        defineMiniProgram({
          data: {
            mode: 'compact',
            tps: 48.5,
            series: [18, 42, 76, 91],
            showHistogram: true
          },
          template: {
            type: 'column',
            children: [
              { type: 'stat', label: 'Throughput', value: '{{tps}} tok/s', tone: 'ok' },
              {
                if: '{{showHistogram}}',
                type: 'canvas',
                width: 260,
                height: 56,
                bindtap: 'toggleChart',
                'data-panel': 'histogram',
                commands: [
                  { op: 'clear', fill: '#0F172A' },
                  { op: 'bars', values: '{{series}}', fill: '#38BDF8', radius: 3 }
                ]
              },
              {
                for: 'point in series',
                type: 'badge',
                text: 'pt={{point}}'
              }
            ]
          },
          onDataUpdate(hostData) {
            if (hostData['terminal.agy']) {
              this.setData({
                tps: hostData['terminal.agy'].tps,
                'series[3]': hostData['terminal.agy'].tps
              });
            }
          },
          methods: {
            toggleChart(ev) {
              this.setData({
                mode: ev.target.dataset.panel,
                showHistogram: !this.data.showHistogram
              });
            }
          }
        })
      ''');

      final session = VibeMiniProgramSession(definition: def);
      session.load(
        hostData: <String, Object?>{
          'terminal.agy': <String, Object?>{'tps': 94.2},
        },
        context: const VibeTriggerContext(program: 'agy'),
      );

      var view = session.buildView()!;
      final kids = view['children'] as List<Object?>;
      expect((kids[0] as Map)['value'], '94.2 tok/s');
      expect((kids[1] as Map)['type'], 'canvas');
      final canvasCmds = (kids[1] as Map)['commands'] as List<Object?>;
      expect((canvasCmds[1] as Map)['values'], <Object?>[18, 42, 76, 94.2]);
      expect(kids.length, 6); // stat + canvas + 4 badges

      // Dispatch bindtap event -> hides canvas via setData
      final tapEvent = VibeMiniProgramEvent.tryFromCommand(
        'mp:tap:toggleChart',
        <String, Object?>{
          '__mpEvent': true,
          'type': 'tap',
          'handler': 'toggleChart',
          'dataset': <String, Object?>{'panel': 'expanded'},
        },
      )!;
      expect(session.dispatchEvent(tapEvent), isTrue);
      expect(session.data['mode'], 'expanded');
      view = session.buildView()!;
      expect(
        (view['children'] as List).where((n) => (n as Map)['type'] == 'canvas'),
        isEmpty,
      );

      // > 64 KiB setData diff rejected
      expect(
        () => applyVibeSetData(
          const <String, Object?>{},
          <String, Object?>{'payload': 'x' * 70000},
        ),
        throwsFormatException,
      );

      // > 30/s setData rate limit rejected
      final rateSession = VibeMiniProgramSession(
        definition: const VibeMiniProgramDefinition(
          initialData: <String, Object?>{'n': 0},
        ),
      );
      for (var i = 0; i < kMaxVibeSetDataRatePerSec; i++) {
        rateSession.setData(<String, Object?>{'n': i}, nowMs: 1000);
      }
      expect(
        () => rateSession.setData(<String, Object?>{'n': 99}, nowMs: 1200),
        throwsStateError,
      );

      // > 2,000 canvas commands rejected by adapter
      final overLimit = List<Map<String, Object?>>.generate(
        kMaxVibeCanvasCommands + 1,
        (i) => <String, Object?>{'op': 'rect', 'x': i, 'y': 0, 'w': 1, 'h': 1},
      );
      expect(
        () => VibeUiCompatibilityAdapter.adapt(<String, Object?>{
          'type': 'canvas',
          'width': 260,
          'height': 56,
          'commands': overLimit,
        }),
        throwsFormatException,
      );
    });
  });
}
