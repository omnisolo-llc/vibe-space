import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  testWidgets(
    'VibeTriggeredViewDeck dynamically activates, hydrates, pins, and dismisses conditional Vibe views',
    (tester) async {
      final host = VibeProtocolHost(
        id: 'deck-host',
        name: 'Deck Host',
        capabilities: const <VibeCapability>[],
      );
      final controller = VibeConditionalController(host: host);
      addTearDown(() {
        controller.dispose();
        host.dispose();
      });

      controller.registerPresets(<VibeConditionalEntry>[
        VibeConditionalEntry(
          id: 'vibe.preset.agy',
          title: 'AGY Session',
          isPreset: true,
          priority: 100,
          condition: VibeTriggerCondition.fromJson(<String, Object?>{
            'program': 'agy',
          }),
          canvas: const VibeCanvasPayload(
            canvasId: 'agy-card',
            title: 'AGY',
            format: VibeCanvasFormat.vibeUi,
            content:
                '{"type":"column","children":[{"type":"stat","label":"Active Model","value":"{{activeModel}}"},{"type":"sparkline","values":[22,38,54,61]}]}',
          ),
        ),
      ]);

      controller.upsert(
        VibeConditionalEntry(
          id: 'custom.nvim-helper',
          title: 'Neovim Tips',
          priority: 50,
          condition: VibeTriggerCondition.fromJson(<String, Object?>{
            'program': 'nvim',
          }),
          canvas: const VibeCanvasPayload(
            canvasId: 'nvim-md',
            title: 'Editing in {{cwd}}',
            format: VibeCanvasFormat.markdown,
            content: 'Editing inside **{{cwd}}**',
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VibeTriggeredViewDeck(controller: controller),
          ),
        ),
      );

      // Initially idle -> empty
      expect(find.text('AGY Session'), findsNothing);
      expect(find.text('Neovim Tips'), findsNothing);

      // Enter agy session -> AGY card appears with hydrated {{activeModel}}
      controller.updateContext(
        const VibeTriggerContext(
          program: 'agy',
          cwd: '/repo',
          context: <String, Object?>{'activeModel': 'Gemini Pro'},
        ),
      );
      await tester.pump();

      expect(find.text('AGY Session'), findsOneWidget);
      expect(find.text('Preset'), findsOneWidget);
      expect(find.text('Gemini Pro'), findsOneWidget);
      expect(find.text('Neovim Tips'), findsNothing);

      // Switch program to nvim -> AGY hides, Neovim Tips appears with hydrated cwd
      controller.updateContext(
        const VibeTriggerContext(program: 'nvim', cwd: '/repo/app'),
      );
      await tester.pump();

      expect(find.text('AGY Session'), findsNothing);
      expect(find.text('Neovim Tips'), findsOneWidget);
      expect(find.textContaining('/repo/app'), findsOneWidget);

      // Pin Neovim Tips -> stays visible even when switching back to zsh
      await tester.tap(
        find.byKey(
            const ValueKey<String>('vibe-conditional-pin-custom.nvim-helper')),
      );
      await tester.pump();

      controller.updateContext(
        const VibeTriggerContext(program: 'zsh', cwd: '/repo/app'),
      );
      await tester.pump();
      expect(find.text('Neovim Tips'), findsOneWidget);

      // Unpin -> disappears in zsh
      await tester.tap(
        find.byKey(
            const ValueKey<String>('vibe-conditional-pin-custom.nvim-helper')),
      );
      await tester.pump();
      expect(find.text('Neovim Tips'), findsNothing);

      // Re-enter agy, click Dismiss -> suppressed until agy exits and re-enters
      controller.updateContext(const VibeTriggerContext(program: 'agy'));
      await tester.pump();
      expect(find.text('AGY Session'), findsOneWidget);

      await tester.tap(
        find.byKey(
            const ValueKey<String>('vibe-conditional-dismiss-vibe.preset.agy')),
      );
      await tester.pump();
      expect(find.text('AGY Session'), findsNothing);

      controller.updateContext(const VibeTriggerContext(program: 'zsh'));
      await tester.pump();
      controller.updateContext(const VibeTriggerContext(program: 'agy'));
      await tester.pump();
      expect(find.text('AGY Session'), findsOneWidget);
    },
  );

  testWidgets(
      'VibeTriggeredViewDeck supports tabbed layout and VibeSpec mounting',
      (tester) async {
    final host = VibeProtocolHost(
      id: 'tab-host',
      name: 'Tab Host',
      capabilities: const <VibeCapability>[],
    );
    final controller = VibeConditionalController(host: host);
    addTearDown(() {
      controller.dispose();
      host.dispose();
    });

    controller.upsert(
      VibeConditionalEntry(
        id: 'timer-vibe',
        title: 'Focus Timer',
        priority: 20,
        condition: VibeTriggerCondition.fromJson(<String, Object?>{
          'surface': 'terminal',
        }),
        vibe: kPortableFocusTimerVibe,
      ),
    );
    controller.upsert(
      VibeConditionalEntry(
        id: 'second-view',
        title: 'Docker Quick Card',
        priority: 10,
        condition: VibeTriggerCondition.fromJson(<String, Object?>{
          'surface': 'terminal',
        }),
        view: const <String, Object?>{
          'type': 'badge',
          'text': '3 containers healthy',
          'tone': 'ok',
        },
      ),
    );

    controller.updateContext(const VibeTriggerContext(surface: 'terminal'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VibeTriggeredViewDeck(
            controller: controller,
            layout: VibeTriggeredDeckLayout.tabbed,
          ),
        ),
      ),
    );
    await tester.pump();

    // First tab (Focus Timer) is active by default
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('3 containers healthy'), findsNothing);

    // Switch to second tab
    await tester.tap(
      find.byKey(const ValueKey<String>('vibe-triggered-tab-second-view')),
    );
    await tester.pump();
    expect(find.text('3 containers healthy'), findsOneWidget);
  });

  testWidgets(
    'VibeTriggeredViewDeck renders WeChat Mini Program VXML + VibeSkylineCanvas with live stream & bindtap',
    (tester) async {
      var liveTps = 62.5;
      final host = VibeProtocolHost(
        id: 'mp-host',
        name: 'MP Host',
        capabilities: const <VibeCapability>[],
      );
      host.registerStreamCapability(
        VibeCapability(
          name: 'terminal.agy',
          title: 'AGY Telemetry',
          fields: const <String, String>{'tps': 'public', 'series': 'public'},
          sample: const <Map<String, Object?>>[
            <String, Object?>{
              'tps': 50.0,
              'series': <double>[20, 35, 50],
            },
          ],
          read: () => <Map<String, Object?>>[
            <String, Object?>{
              'tps': liveTps,
              'series': <double>[24, 48, liveTps],
            },
          ],
        ),
      );
      final controller = VibeConditionalController(host: host);
      addTearDown(() {
        controller.dispose();
        host.dispose();
      });

      controller.upsert(
        VibeConditionalEntry.fromJson(<String, Object?>{
          'id': 'custom.agy-skyline',
          'name': 'AGY Skyline Histogram',
          'when': <String, Object?>{'program': 'agy'},
          'needs': <String>['terminal.agy'],
          'runtime': 'miniprogram',
          'trusted': true,
          'source': '''
            defineMiniProgram({
              data: {
                tps: 0,
                series: [10, 20, 30],
                boosted: false
              },
              template: {
                type: 'column',
                children: [
                  { type: 'stat', label: 'Live TPS', value: '{{tps}} tok/s', tone: 'ok' },
                  {
                    type: 'canvas',
                    width: 240,
                    height: 52,
                    bindtap: 'onCanvasTap',
                    'data-tag': 'tps-bars',
                    commands: [
                      { op: 'clear', fill: '#0F172A' },
                      { op: 'bars', values: '{{series}}', fill: '#38BDF8', radius: 2 },
                      { op: 'text', text: 'TPS', x: 6, y: 6, fill: '#E2E8F0' }
                    ]
                  },
                  { if: '{{boosted}}', type: 'badge', text: 'Chart Inspector Open', tone: 'ok' }
                ]
              },
              onDataUpdate(hostData) {
                const rows = hostData['terminal.agy'];
                if (rows && rows[0]) {
                  this.setData({
                    tps: rows[0].tps,
                    series: rows[0].series
                  });
                }
              },
              methods: {
                onCanvasTap(ev) {
                  this.setData({ boosted: ev.target.dataset.tag === 'tps-bars' });
                }
              }
            })
          ''',
        }),
      );

      controller.updateContext(const VibeTriggerContext(program: 'agy'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VibeTriggeredViewDeck(controller: controller),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('62.5 tok/s'), findsOneWidget);
      expect(find.byType(VibeSkylineCanvas), findsOneWidget);
      expect(find.text('Chart Inspector Open'), findsNothing);

      // Push live capability update -> Mini Program updates in place via setData
      liveTps = 96.4;
      host.notifySourceChange();
      await tester.pump();
      expect(find.text('96.4 tok/s'), findsOneWidget);

      // Tap native Skyline canvas -> dispatches mp:tap:onCanvasTap -> setData({ boosted: true })
      await tester.tap(find.byType(VibeSkylineCanvas));
      await tester.pump();
      expect(find.text('Chart Inspector Open'), findsOneWidget);
    },
  );
}
