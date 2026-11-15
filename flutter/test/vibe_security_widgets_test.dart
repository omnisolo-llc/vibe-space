import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_space_flutter/vibe_space_flutter.dart';

void main() {
  group('Skyline widget security under malicious inputs', () {
    test(
      'validateVibeView blocks constructor/prototype handlers, unsafe canvas colors, bad SVG paths, NaN geometry, and depth bombs',
      () {
        for (final badView in <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'button',
            'text': 'Click',
            'command': 'noop',
            'bindtap': 'constructor',
          },
          <String, dynamic>{
            'type': 'text',
            'text': 'Hi',
            'catchtap': '__proto__',
          },
          <String, dynamic>{
            'type': 'input',
            'id': 'f1',
            'label': 'Name',
            'bindinput': 'toString',
          },
          <String, dynamic>{
            'type': 'checkbox',
            'id': 'c1',
            'label': 'Ok',
            'bindchange': 'valueOf',
          },
          <String, dynamic>{
            'type': 'canvas',
            'width': 120,
            'height': 40,
            'commands': <Map<String, dynamic>>[
              <String, dynamic>{
                'op': 'rect',
                'x': 0,
                'y': 0,
                'w': 20,
                'h': 20,
                'fill': 'url(https://evil.example/#p)',
              },
            ],
          },
          <String, dynamic>{
            'type': 'canvas',
            'width': 120,
            'height': 40,
            'commands': <Map<String, dynamic>>[
              <String, dynamic>{
                'op': 'clear',
                'linearGradient': <String, dynamic>{
                  'colors': <String>['expression(1)', '#ffffff'],
                },
              },
            ],
          },
          <String, dynamic>{
            'type': 'canvas',
            'width': 120,
            'height': 40,
            'commands': <Map<String, dynamic>>[
              <String, dynamic>{
                'op': 'path',
                'd': 'M0 0"><script>alert(1)</script>',
              },
            ],
          },
          <String, dynamic>{
            'type': 'canvas',
            'width': 120,
            'height': 40,
            'commands': <Map<String, dynamic>>[
              <String, dynamic>{'op': 'rect', 'x': double.nan},
            ],
          },
        ]) {
          expect(
            () => validateVibeView(badView),
            throwsFormatException,
            reason: 'validateVibeView should reject: $badView',
          );
        }

        // Depth > 16 rejected.
        Map<String, dynamic> deep = <String, dynamic>{
          'type': 'text',
          'text': 'bottom',
        };
        for (var i = 0; i < 18; i++) {
          deep = <String, dynamic>{
            'type': 'column',
            'children': <Map<String, dynamic>>[deep],
          };
        }
        expect(() => validateVibeView(deep), throwsFormatException);
      },
    );

    testWidgets(
      'VibeView and applyVibeSkylineNodeStyle ignore blocked constructor/__proto__/toString handlers on tap and input',
      (tester) async {
        final dispatched = <(String, Map<String, dynamic>)>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeView(
                value: <String, dynamic>{
                  'type': 'column',
                  'children': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'type': 'canvas',
                      'width': 140,
                      'height': 36,
                      'bindtap': 'constructor',
                      'commands': <Map<String, dynamic>>[
                        <String, dynamic>{'op': 'clear', 'fill': '#0F172A'},
                      ],
                    },
                    <String, dynamic>{
                      'type': 'text',
                      'text': 'Styled Prototype Tap',
                      'bindtap': '__proto__',
                    },
                    <String, dynamic>{
                      'type': 'input',
                      'id': 'safe_in',
                      'label': 'Blocked Input',
                      'bindinput': 'toString',
                    },
                  ],
                },
                onCommand: (cmd, args) => dispatched.add((cmd, args)),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(VibeSkylineCanvas));
        await tester.tap(find.text('Styled Prototype Tap'));
        await tester.enterText(find.byType(TextField), 'attacker');
        await tester.pump();

        expect(dispatched, isEmpty);
      },
    );

    testWidgets(
      'VibeView & VibeSkylineCanvas isolate forged sealed handles, XSS payloads, and malformed draw lists safely',
      (tester) async {
        const forgedHandle = <String, String>{'sealed': 'h_forged00000001'};
        const validHandle = <String, String>{'sealed': 'h_valid00000002'};
        String? resolver(Object? raw) {
          if (raw is Map && raw['sealed'] == 'h_valid00000002') {
            return 'prod-west-db';
          }
          return null;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeView(
                resolveSealed: resolver,
                onCommand: (_, __) {},
                value: <String, dynamic>{
                  'type': 'column',
                  'children': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'type': 'heading',
                      'text': '<script>alert(1)</script>',
                    },
                    <String, dynamic>{
                      'type': 'stat',
                      'label': 'Legit',
                      'value': validHandle,
                    },
                    <String, dynamic>{
                      'type': 'stat',
                      'label': 'Forged',
                      'value': forgedHandle,
                    },
                    <String, dynamic>{
                      'type': 'canvas',
                      'width': 180,
                      'height': 48,
                      'commands': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'op': 'rect',
                          'x': 0,
                          'y': 0,
                          'w': 40,
                          'h': 20,
                          'fill': 'url(https://evil.example/#x)',
                        },
                        <String, dynamic>{
                          'op': 'text',
                          'text': forgedHandle,
                          'x': 4,
                          'y': 4,
                        },
                        <String, dynamic>{
                          'op': 'bars',
                          'values': <Object?>[double.nan, 'bad', 10, 20],
                        },
                      ],
                    },
                  ],
                },
              ),
            ),
          ),
        );

        // XSS payload is rendered only as harmless literal text (never evaluated).
        expect(find.text('<script>alert(1)</script>'), findsOneWidget);
        // Valid handle resolves cleanly; forged handle never leaks raw handle ID.
        expect(find.text('prod-west-db'), findsOneWidget);
        expect(find.textContaining('h_forged00000001'), findsNothing);
        expect(find.byType(VibeSkylineCanvas), findsOneWidget);
      },
    );

    testWidgets(
      'VibeMiniProgramView enforces fail-closed security while updating interactively on valid events',
      (tester) async {
        final def = VibeMiniProgramDefinition.fromSource('''
          defineVibeSnippet({
            data: { count: 1, banner: 'ok' },
            template: {
              type: 'column',
              style: {
                padding: 8,
                position: 'fixed',
                backgroundImage: 'url(https://evil.example/a.png)'
              },
              children: [
                { type: 'stat', label: 'Count', value: '{{count}}' },
                { type: 'button', text: 'Inc', bindtap: 'inc' }
              ]
            },
            methods: {
              inc() {
                this.setData({ count: this.data.count + 1 });
              }
            }
          })
        ''');

        final session = VibeMiniProgramSession(definition: def)..load();
        final observedEvents = <VibeMiniProgramEvent>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeMiniProgramView(
                session: session,
                onEvent: observedEvents.add,
              ),
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);
        await tester.tap(find.text('Inc'));
        await tester.pump();
        expect(find.text('2'), findsOneWidget);
        expect(observedEvents.length, 1);
        expect(observedEvents.single.handler, 'inc');
        expect(
          session.dispatchEvent(
            const VibeMiniProgramEvent(type: 'tap', handler: 'constructor'),
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'VibeTriggeredViewDeck and VibeRuntimeBody reject and isolate malicious untrusted snippets without crashing host tree',
      (tester) async {
        final host = VibeProtocolHost(
          id: 'widget-sec-host',
          name: 'Widget Sec Host',
          capabilities: const <VibeCapability>[],
        );
        final controller = VibeConditionalController(host: host);
        addTearDown(() {
          controller.dispose();
          host.dispose();
        });

        final evilEntry = VibeConditionalEntry(
          id: 'evil.snippet',
          title: 'Untrusted Evil Card',
          trusted: false,
          runtime: VibeRuntimeKind.miniProgram,
          condition: VibeTriggerCondition.fromJson(
            const <String, Object?>{'program': 'vim'},
          ),
          source:
              'defineVibeSnippet({ onLoad() { window.location = "https://evil.example"; } })',
        );

        expect(() => controller.upsert(evilEntry), throwsFormatException);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VibeRuntimeBody(
                entry: evilEntry,
                triggerContext: const VibeTriggerContext(program: 'vim'),
                theme: VibeSpaceThemeData.dark(),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('forbids'), findsOneWidget);
      },
    );
  });
}
