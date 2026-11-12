import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  group('VibeView Phase 4 nodes & sealed handles', () {
    test('validateVibeView accepts stat, bar, sparkline, button and tones', () {
      expect(
        () => validateVibeView(<String, dynamic>{
          'type': 'column',
          'children': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'stat',
              'label': 'Disk peak',
              'value': '84%',
              'caption': '/var',
              'tone': 'warn',
            },
            <String, dynamic>{
              'type': 'bar',
              'label': 'Root',
              'value': 84,
              'max': 100,
              'caption': '84 / 100 GB',
              'swatch': '#f59e0b',
              'tone': 'warn',
            },
            <String, dynamic>{
              'type': 'sparkline',
              'label': 'Load 1m',
              'values': <double>[0.2, 0.5, 0.8, 0.4],
              'tone': 'ok',
            },
            <String, dynamic>{
              'type': 'button',
              'title': 'Refresh now',
              'command': 'refresh_now',
              'tone': 'default',
            },
          ],
        }),
        returnsNormally,
      );

      expect(
        () => validateVibeView(<String, dynamic>{
          'type': 'sparkline',
          'values': <double>[0.5],
        }),
        throwsFormatException,
      );

      expect(
        () => validateVibeView(<String, dynamic>{
          'type': 'stat',
          'label': 'Bad tone',
          'value': '1',
          'tone': 'purple',
        }),
        throwsFormatException,
      );
    });

    testWidgets(
      'renders stat, bar, sparkline, button and resolves vs hides forged sealed handles',
      (WidgetTester tester) async {
        String? clickedCommand;

        final host = VibeProtocolHost(
          id: 'test-host',
          name: 'TestHost',
          capabilities: <VibeCapability>[
            VibeCapability(
              name: 'servers',
              title: 'Servers',
              fields: const <String, String>{
                'host': 'sealed',
                'region': 'public',
              },
              read: () => const <Map<String, Object?>>[],
            ),
          ],
        );
        final validHandle = host.seal('prod-api-01').toJson();
        final forgedHandle = <String, dynamic>{'sealed': 'h_deadbeefcafebabe'};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeViewToneScope(
                accent: const Color(0xFF38BDF8),
                ok: const Color(0xFF22C55E),
                warn: const Color(0xFFF59E0B),
                danger: const Color(0xFFEF4444),
                border: const Color(0xFF263042),
                surface: const Color(0xFF141A24),
                text: const Color(0xFFF1F5F9),
                mutedText: const Color(0xFF94A3B8),
                radius: 12,
                child: SingleChildScrollView(
                  child: VibeView(
                    resolveSealed: host.resolveSealed,
                    onCommand: (cmd, _) => clickedCommand = cmd,
                    value: <String, dynamic>{
                      'type': 'column',
                      'children': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'type': 'stat',
                          'label': 'Host',
                          'value': validHandle,
                          'caption': 'Sealed label',
                          'tone': 'ok',
                        },
                        <String, dynamic>{
                          'type': 'text',
                          'text': forgedHandle,
                        },
                        <String, dynamic>{
                          'type': 'bar',
                          'label': 'Usage',
                          'value': 62,
                          'max': 100,
                          'caption': '62%',
                          'swatch': '#22c55e',
                        },
                        <String, dynamic>{
                          'type': 'sparkline',
                          'label': 'Trend',
                          'values': <double>[1, 3, 2, 5, 4],
                          'tone': 'ok',
                        },
                        <String, dynamic>{
                          'type': 'button',
                          'title': 'Ping',
                          'command': 'ping_host',
                        },
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('prod-api-01'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(find.textContaining('h_deadbeefcafebabe'), findsNothing);
        expect(find.text('Usage'), findsOneWidget);
        expect(find.text('62%'), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));

        await tester.tap(find.text('Ping'));
        await tester.pump();
        expect(clickedCommand, equals('ping_host'));
        host.dispose();
      },
    );
  });

  group('VibeSpacePanel & VibeEmbedCard', () {
    VibeSpec makeDiskVibe({int version = 1, double threshold = 0.8}) {
      return VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        wish: 'Show disk usage and highlight volumes above 80%',
        version: version,
        needs: const <String>['telemetry.disk'],
        source: jsonEncode(<String, Object?>{
          'kind': 'disk_watch',
          'threshold': threshold,
          'warn': 0.6,
          'heading': 'Disk usage',
        }),
      );
    }

    ({
      VibeProtocolHost host,
      void Function(VibeSourceStatus) setDiskStatus,
      List<VibeWishPreset> wishes,
    }) createTestHost({
      Map<String, Object?> Function(VibeSpec, Map<String, Object?>)?
          customRunner,
    }) {
      var diskStatus = const VibeSourceStatus.live();
      final storage = InMemoryVibeStorage();

      final host = VibeProtocolHost(
        id: 'demo-panel-host',
        name: 'DemoHost',
        storage: storage,
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'telemetry.disk',
            title: 'Disk usage',
            fields: const <String, String>{
              'mount': 'public',
              'usedFraction': 'public',
              'sizeGb': 'public',
              'server': 'sealed',
            },
            sealedNote: 'Host names stay sealed.',
            sealedCannot: 'Read hostnames in plain text',
            status: () => diskStatus,
            read: () => const <Map<String, Object?>>[
              <String, Object?>{
                'mount': '/var',
                'usedFraction': 0.86,
                'sizeGb': 100,
                'server': 'web-prod-04',
              },
              <String, Object?>{
                'mount': '/home',
                'usedFraction': 0.42,
                'sizeGb': 200,
                'server': 'web-prod-04',
              },
            ],
            sample: const <Map<String, Object?>>[
              <String, Object?>{
                'mount': '/sample',
                'usedFraction': 0.55,
                'sizeGb': 80,
                'server': 'sample-host',
              },
            ],
          ),
        ],
        notOffered: const <String>['SSH keys', 'Raw command output'],
        customRunner: customRunner,
      );

      final wishes = <VibeWishPreset>[
        VibeWishPreset(
          text: 'Show disk usage and highlight volumes above 80%',
          vibe: makeDiskVibe(),
        ),
        VibeWishPreset(
          text: 'Only highlight volumes above 90%',
          remixOf: 'disk-watch',
          vibe: makeDiskVibe(version: 2, threshold: 0.9),
        ),
      ];

      return (
        host: host,
        setDiskStatus: (next) {
          diskStatus = next;
          host.notifySourceChange();
        },
        wishes: wishes,
      );
    }

    testWidgets(
      'wish install, three-dots menu lifecycle (Edit/Restore, Rename, Inspect, Pause/Resume, Delete/Undo), and Offer dialog',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final env = createTestHost(
          customRunner: (vibe, input) {
            final data = input['data'] as Map<String, Object?>? ??
                const <String, Object?>{};
            final rows = data['telemetry.disk'] as List<Object?>? ??
                const <Object?>[];
            final first = rows.isNotEmpty
                ? rows.first as Map<String, Object?>
                : const <String, Object?>{};
            final hostVal = first['server'];
            final mount = first['mount']?.toString() ?? '/';
            final pct = ((first['usedFraction'] as num?)?.toDouble() ?? 0) * 100;

            return <String, Object?>{
              'state': input['state'],
              'view': <String, Object?>{
                'type': 'column',
                'children': <Map<String, Object?>>[
                  <String, Object?>{
                    'type': 'stat',
                    'label': 'Host',
                    'value': hostVal,
                  },
                  <String, Object?>{
                    'type': 'bar',
                    'label': mount,
                    'value': pct,
                    'max': 100,
                    'caption': '${pct.round()}%',
                  },
                ],
              },
            };
          },
        );
        addTearDown(env.host.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: VibeSpacePanel(
                  host: env.host,
                  wishes: env.wishes,
                ),
              ),
            ),
          ),
        );

        expect(find.text('Nothing here yet. Make a wish.'), findsOneWidget);

        // 1. Open Offer dialog and verify Offered / Not offered.
        await tester.tap(find.text('What DemoHost offers'));
        await tester.pumpAndSettle();
        expect(find.text('telemetry.disk'), findsAtLeastNWidgets(1));
        expect(find.text('SEALED'), findsAtLeastNWidgets(1));
        expect(find.textContaining('SSH keys'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();

        // 2. Tap wish chip -> preview + permission label + custom Title & Note -> Allow and add.
        await tester.tap(
          find.text('Show disk usage and highlight volumes above 80%'),
        );
        await tester.pumpAndSettle();

        expect(find.text('PREVIEW ON SAMPLE DATA'), findsOneWidget);
        expect(find.text('READS'), findsOneWidget);
        expect(find.text('SHOWS'), findsOneWidget);
        expect(find.text('CANNOT'), findsOneWidget);

        final titleField = find.widgetWithText(TextField, 'Title');
        await tester.enterText(titleField, 'Prod Disks');
        final noteField = find.widgetWithText(TextField, 'Note');
        await tester.enterText(noteField, 'Check /var');
        await tester.pump();

        await tester.tap(find.widgetWithText(FilledButton, 'Allow and add'));
        await tester.pumpAndSettle();

        final installed = env.host.installed();
        expect(installed, hasLength(1));
        final rec = installed.first;
        expect(rec.title, equals('Prod Disks'));
        expect(rec.note, equals('Check /var'));
        expect(find.byKey(Key('vs-card-${rec.instanceId}')), findsOneWidget);
        expect(find.text('web-prod-04'), findsAtLeastNWidgets(1));

        // 3. Inspect via ⋯ menu -> verify sealed JSON highlight + read ledger + Hide.
        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Inspect'));
        await tester.pumpAndSettle();

        expect(find.text('WHAT THE VIBE RECEIVED'), findsOneWidget);
        expect(find.text('WHAT IT DID'), findsOneWidget);
        expect(find.textContaining('Read Disk usage'), findsOneWidget);
        expect(find.textContaining('"sealed": "h_'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Hide'));
        await tester.pumpAndSettle();
        expect(find.text('WHAT THE VIBE RECEIVED'), findsNothing);

        // 4. Pause & Resume via ⋯ menu.
        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pause'));
        await tester.pumpAndSettle();
        expect(find.text('Paused \u2014 live updates stopped.'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
        await tester.pumpAndSettle();
        expect(find.text('Paused \u2014 live updates stopped.'), findsNothing);

        // 5. Rename via ⋯ menu.
        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        final renameInput = find.byKey(Key('vs-rename-input-${rec.instanceId}'));
        expect(renameInput, findsOneWidget);
        await tester.enterText(renameInput, 'Renamed Disks');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(env.host.installed().first.title, equals('Renamed Disks'));

        // 6. Edit… via ⋯ menu -> wish remix -> Save v2 -> Edit… -> Restore v1.
        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit\u2026'));
        await tester.pumpAndSettle();
        expect(find.text('Edit Renamed Disks'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Adjust threshold, count, or minutes\u2026',
          ),
          'Only highlight volumes above 90%',
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Preview change'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
        await tester.pumpAndSettle();

        expect(env.host.installed().first.vibe.version, equals(2));
        expect(env.host.installed().first.history, hasLength(1));

        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit\u2026'));
        await tester.pumpAndSettle();
        expect(find.text('VERSION HISTORY'), findsOneWidget);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
        await tester.pumpAndSettle();

        expect(env.host.installed().first.vibe.version, equals(1));

        // 7. Delete + Undo banner.
        await tester.tap(find.byKey(Key('vs-more-${rec.instanceId}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(env.host.installed(), isEmpty);
        expect(find.byKey(const Key('vs-undo-banner')), findsOneWidget);
        await tester.tap(find.byKey(const Key('vs-undo-delete')));
        await tester.pumpAndSettle();

        expect(env.host.installed(), hasLength(1));
        expect(find.byKey(Key('vs-card-${rec.instanceId}')), findsOneWidget);
      },
    );

    testWidgets(
      'source offline stale banner, sample fallback, and automatic live recovery',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final env = createTestHost();
        addTearDown(env.host.dispose);
        final rec = env.host.install(makeDiskVibe());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: VibeSpacePanel(
                  host: env.host,
                  wishes: env.wishes,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('/var'), findsOneWidget);
        expect(
          find.byKey(Key('vs-source-banner-${rec.instanceId}')),
          findsNothing,
        );

        // Source goes offline -> stale banner appears and view body dims (opacity 0.58).
        env.setDiskStatus(
          const VibeSourceStatus.offline('Collector disconnected'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('vs-source-banner-${rec.instanceId}')),
          findsOneWidget,
        );
        expect(find.textContaining('Collector disconnected'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Opacity && (w.opacity - 0.58).abs() < 0.01,
          ),
          findsOneWidget,
        );

        // Preview sample switches to sample data and shows Return to live.
        await tester.tap(find.widgetWithText(OutlinedButton, 'Preview sample'));
        await tester.pumpAndSettle();
        expect(find.textContaining('/sample'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Return to live'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(OutlinedButton, 'Return to live'));
        await tester.pumpAndSettle();

        // Source comes back online -> notifySourceChange triggers automatic recovery.
        env.setDiskStatus(const VibeSourceStatus.live());
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('vs-source-banner-${rec.instanceId}')),
          findsNothing,
        );
        expect(find.textContaining('/var'), findsOneWidget);
      },
    );

    testWidgets('VibeEmbedCard renders agent box and pins into Vibe Space', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final env = createTestHost();
      addTearDown(env.host.dispose);
      var pinnedCallbacks = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VibeEmbedCard(
                host: env.host,
                vibe: makeDiskVibe(),
                defaultTitle: 'Alert Threshold',
                caption: 'Checking host volumes',
                onPinned: () => pinnedCallbacks++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Made by the agent for this answer'), findsOneWidget);
      expect(find.text('Temporary'), findsOneWidget);
      expect(find.textContaining('Reads: Disk usage'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Inspect'));
      await tester.pumpAndSettle();
      expect(find.text('WHAT THE VIBE RECEIVED'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Hide'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Pin to Vibe Space'));
      await tester.pumpAndSettle();
      expect(find.text('READS'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Allow and add'));
      await tester.pumpAndSettle();

      expect(pinnedCallbacks, equals(1));
      expect(find.text('Pinned'), findsOneWidget);
      expect(env.host.installed(), hasLength(1));
      expect(env.host.installed().first.origin, equals('agent'));
      expect(env.host.installed().first.title, equals('Alert Threshold'));
    });
  });
}
