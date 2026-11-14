import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  group('VibeWidgetAdapter & external UI dialects', () {
    testWidgets(
      'VibeWidgetAdapter.cupertino renders Cupertino widgets in pure CupertinoApp and isolates forged sealed handles',
      (WidgetTester tester) async {
        String? lastCmd;
        final inputs = <String, String>{};

        final host = VibeProtocolHost(
          id: 'ios-host',
          name: 'Example iOS',
          capabilities: <VibeCapability>[
            VibeCapability(
              name: 'servers',
              title: 'Servers',
              fields: const <String, String>{'name': 'sealed'},
              read: () => const <Map<String, Object?>>[],
            ),
          ],
        );
        addTearDown(host.dispose);

        final realHandle = host.seal('edge-tokyo-01').toJson();
        final forgedHandle = <String, dynamic>{'sealed': 'h_forged_00000001'};

        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: VibeView(
                    adapter: const VibeWidgetAdapter.cupertino(),
                    resolveSealed: host.resolveSealed,
                    onCommand: (cmd, _) => lastCmd = cmd,
                    onInput: (id, val) => inputs[id] = val,
                    value: <String, dynamic>{
                      'type': 'card',
                      'children': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'type': 'heading',
                          'text': realHandle,
                        },
                        <String, dynamic>{
                          'type': 'text',
                          'text': forgedHandle,
                        },
                        <String, dynamic>{
                          'type': 'badge',
                          'text': 'iOS Healthy',
                          'tone': 'ok',
                        },
                        <String, dynamic>{
                          'type': 'bar',
                          'label': 'CPU',
                          'value': 45,
                          'max': 100,
                          'caption': '45%',
                        },
                        <String, dynamic>{
                          'type': 'input',
                          'id': 'note',
                          'label': 'Quick note',
                        },
                        <String, dynamic>{
                          'type': 'checkbox',
                          'id': 'alerts',
                          'label': 'Enable alerts',
                          'checked': false,
                          'command': 'toggle_alerts',
                        },
                        <String, dynamic>{
                          'type': 'option_group',
                          'id': 'window',
                          'label': 'Window',
                          'multiSelect': false,
                          'command': 'set_window',
                          'options': <Map<String, dynamic>>[
                            <String, dynamic>{
                              'id': '1h',
                              'label': '1h',
                              'selected': true,
                            },
                            <String, dynamic>{
                              'id': '24h',
                              'label': '24h',
                            },
                          ],
                        },
                        <String, dynamic>{
                          'type': 'table',
                          'headers': <String>['Metric', 'Value'],
                          'rows': <List<Object?>>[
                            <Object?>['Node', realHandle],
                          ],
                        },
                        <String, dynamic>{
                          'type': 'button',
                          'title': 'Sync now',
                          'command': 'sync_now',
                        },
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('edge-tokyo-01'), findsNWidgets(2));
        expect(find.textContaining('h_forged_00000001'), findsNothing);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(find.byType(CupertinoSwitch), findsOneWidget);
        expect(
          find.byType(CupertinoSlidingSegmentedControl<String>),
          findsOneWidget,
        );
        expect(find.byType(CupertinoButton), findsAtLeastNWidgets(1));

        await tester.enterText(find.byType(CupertinoTextField), 'all green');
        expect(inputs['note'], equals('all green'));

        await tester.tap(find.byType(CupertinoSwitch));
        await tester.pump();
        expect(inputs['alerts'], equals('true'));
        expect(lastCmd, equals('toggle_alerts'));

        await tester.tap(find.text('24h'));
        await tester.pump();
        expect(lastCmd, equals('set_window'));

        await tester.tap(find.widgetWithText(CupertinoButton, 'Sync now'));
        await tester.pump();
        expect(lastCmd, equals('sync_now'));
      },
    );

    testWidgets(
      'VibeWidgetAdapterScope with VibeWidgetAdapter.custom overrides node builders while keeping forged handles empty',
      (WidgetTester tester) async {
        final host = VibeProtocolHost(
          id: 'custom-host',
          name: 'CustomHost',
          capabilities: <VibeCapability>[
            VibeCapability(
              name: 'nodes',
              title: 'Nodes',
              fields: const <String, String>{'host': 'sealed'},
              read: () => const <Map<String, Object?>>[],
            ),
          ],
        );
        addTearDown(host.dispose);

        final realHandle = host.seal('custom-node-9').toJson();
        final forgedHandle = <String, dynamic>{'sealed': 'h_forged_custom'};
        var clicked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeWidgetAdapterScope(
                adapter: VibeWidgetAdapter.custom(
                  sealedTextBuilder: (context, resolved, style) => Text(
                    'LOCKED:$resolved',
                    key: const ValueKey('custom-sealed'),
                  ),
                  buttonBuilder: (ctx, node, title, cmd, args, onPressed, _) =>
                      ElevatedButton(
                    key: const ValueKey('custom-btn'),
                    onPressed: onPressed,
                    child: Text('CUSTOM:$title'),
                  ),
                ),
                child: VibeView(
                  resolveSealed: host.resolveSealed,
                  onCommand: (_, __) => clicked = true,
                  value: <String, dynamic>{
                    'type': 'column',
                    'children': <Map<String, dynamic>>[
                      <String, dynamic>{'type': 'text', 'text': realHandle},
                      <String, dynamic>{'type': 'text', 'text': forgedHandle},
                      <String, dynamic>{
                        'type': 'button',
                        'title': 'Go',
                        'command': 'go',
                      },
                    ],
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.byKey(const ValueKey('custom-sealed')), findsOneWidget);
        expect(find.text('LOCKED:custom-node-9'), findsOneWidget);
        expect(find.textContaining('h_forged_custom'), findsNothing);
        expect(find.byKey(const ValueKey('custom-btn')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('custom-btn')));
        await tester.pump();
        expect(clicked, isTrue);
      },
    );

    testWidgets(
      'VibeView and VibeCanvasView adapt A2UI and AdaptiveCard payloads automatically',
      (WidgetTester tester) async {
        String? capturedCmd;

        final a2uiPayload = <String, dynamic>{
          'surfaceUpdate': <String, dynamic>{
            'surfaceId': 'main',
            'components': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'root',
                'component': <String, dynamic>{
                  'Column': <String, dynamic>{
                    'children': <String, dynamic>{
                      'explicitList': <String>['hdr', 'btn'],
                    },
                  },
                },
              },
              <String, dynamic>{
                'id': 'hdr',
                'component': <String, dynamic>{
                  'Heading': <String, dynamic>{'text': 'A2UI Cluster Status'},
                },
              },
              <String, dynamic>{
                'id': 'btn',
                'component': <String, dynamic>{
                  'Button': <String, dynamic>{
                    'text': 'Inspect Cluster',
                    'action': <String, dynamic>{'name': 'inspect_cluster'},
                  },
                },
              },
            ],
          },
        };

        final adaptiveCard = <String, dynamic>{
          'type': 'AdaptiveCard',
          'version': '1.5',
          'body': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'TextBlock',
              'text': 'Adaptive Deploy Summary',
              'size': 'Large',
            },
            <String, dynamic>{
              'type': 'FactSet',
              'facts': <Map<String, dynamic>>[
                <String, dynamic>{'title': 'Region', 'value': 'us-west-2'},
              ],
            },
          ],
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'Action.Submit',
              'title': 'Acknowledge',
              'data': <String, dynamic>{'command': 'ack_deploy'},
            },
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  VibeView(
                    value: a2uiPayload,
                    onCommand: (cmd, _) => capturedCmd = cmd,
                  ),
                  Expanded(
                    child: VibeCanvasView(
                      payload: VibeCanvasPayload(
                        canvasId: 'ac-1',
                        title: 'Deploy Card',
                        format: VibeCanvasFormat.vibeUi,
                        content: jsonEncode(adaptiveCard),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('A2UI Cluster Status'), findsOneWidget);
        await tester.tap(find.text('Inspect Cluster'));
        await tester.pump();
        expect(capturedCmd, equals('inspect_cluster'));

        expect(find.text('Adaptive Deploy Summary'), findsOneWidget);
        expect(find.textContaining('us-west-2'), findsOneWidget);
        expect(find.text('Acknowledge'), findsOneWidget);
      },
    );

    testWidgets(
      'VibeSpacePanel and VibeEmbedCard support Chinese (zh) and RTL Arabic (ar) locales',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final host = VibeProtocolHost(
          id: 'i18n-host',
          name: 'Example Host',
          capabilities: <VibeCapability>[
            VibeCapability(
              name: 'telemetry.disk',
              title: 'Disk usage',
              fields: const <String, String>{'mount': 'public'},
              read: () => const <Map<String, Object?>>[
                <String, Object?>{'mount': '/', 'usedFraction': 0.5, 'sizeGb': 100},
              ],
            ),
          ],
        );
        addTearDown(host.dispose);

        final zhStrings = VibeStrings.forLocale('zh');
        final arStrings = VibeStrings.forLocale('ar');
        expect(arStrings.isRtl, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    VibeSpacePanel(
                      host: host,
                      locale: 'zh',
                    ),
                    const SizedBox(height: 12),
                    VibeEmbedCard(
                      host: host,
                      vibe: kPortableFocusTimerVibe,
                      locale: 'ar',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(zhStrings.sendLabel), findsOneWidget);
        expect(find.text(zhStrings.emptyInstalled), findsOneWidget);

        expect(find.text(arStrings.madeByAgent), findsOneWidget);
        expect(find.text(arStrings.pinToVibeSpace), findsOneWidget);
        final embedDir = tester.widget<Directionality>(
          find
              .descendant(
                of: find.byType(VibeEmbedCard),
                matching: find.byType(Directionality),
              )
              .first,
        );
        expect(embedDir.textDirection, equals(TextDirection.rtl));
      },
    );
  });
}
