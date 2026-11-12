import 'dart:convert';

import 'package:test/test.dart';
import 'package:vibe_space/vibe_space.dart';

void main() {
  group('VibeUiCompatibilityAdapter', () {
    test('normalizes canonical VibeView and preserves sealed handles', () {
      final raw = <String, Object?>{
        'type': 'column',
        'children': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'heading',
            'text': <String, Object?>{'sealed': 'h_server_1'},
          },
          <String, Object?>{
            'type': 'bar',
            'label': <String, Object?>{'sealed': 'h_mount_1'},
            'value': 0.85,
            'max': 1,
            'tone': 'danger',
          },
          <String, Object?>{
            'type': 'button',
            'text': 'Inspect',
            'command': 'inspect',
            'args': <String, Object?>{'url': 'javascript:alert(1)', 'target': 1},
          },
        ],
      };

      final adapted = VibeUiCompatibilityAdapter.adapt(raw);
      expect(adapted['type'], 'column');
      final children = adapted['children'] as List;
      expect(children, hasLength(3));
      expect((children[0] as Map)['text'], <String, Object?>{'sealed': 'h_server_1'});
      expect((children[1] as Map)['label'], <String, Object?>{'sealed': 'h_mount_1'});
      expect((children[1] as Map)['max'], 1);
      final buttonArgs = (children[2] as Map)['args'] as Map;
      expect(buttonArgs.containsKey('url'), isFalse);
      expect(buttonArgs['target'], 1);
    });

    test('adapts A2UI surfaceUpdate adjacency list while preserving sealed handles', () {
      final a2ui = <String, Object?>{
        'beginRendering': <String, Object?>{'root': 'root_col'},
        'surfaceUpdate': <String, Object?>{
          'surfaceId': 'main',
          'components': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'root_col',
              'component': <String, Object?>{
                'Column': <String, Object?>{
                  'children': <String, Object?>{
                    'explicitList': <String>['hdr', 'stat_cpu', 'btn_go'],
                  },
                },
              },
            },
            <String, Object?>{
              'id': 'hdr',
              'component': <String, Object?>{
                'Text': <String, Object?>{
                  'text': <String, Object?>{
                    'literalString': <String, Object?>{'sealed': 'h_host_a'},
                  },
                  'usageHint': 'h2',
                },
              },
            },
            <String, Object?>{
              'id': 'stat_cpu',
              'component': <String, Object?>{
                'Stat': <String, Object?>{
                  'label': <String, Object?>{'literalString': 'CPU'},
                  'value': <String, Object?>{'literalString': '42%'},
                  'tone': 'ok',
                },
              },
            },
            <String, Object?>{
              'id': 'btn_go',
              'component': <String, Object?>{
                'Button': <String, Object?>{
                  'label': <String, Object?>{'literalString': 'Refresh'},
                  'action': <String, Object?>{
                    'name': 'refresh',
                    'context': <String, Object?>{'scope': 'all'},
                  },
                },
              },
            },
          ],
        },
      };

      final adapted = VibeUiCompatibilityAdapter.adapt(a2ui);
      expect(adapted['type'], 'column');
      final children = adapted['children'] as List<Map<String, Object?>>;
      expect(children, hasLength(3));
      expect(children[0]['type'], 'heading');
      expect(children[0]['text'], <String, Object?>{'sealed': 'h_host_a'});
      expect(children[1]['type'], 'stat');
      expect(children[1]['value'], '42%');
      expect(children[2]['type'], 'button');
      expect(children[2]['command'], 'refresh');
    });

    test('adapts AdaptiveCard with Container, FactSet, Input, and Actions safely', () {
      final card = <String, Object?>{
        'type': 'AdaptiveCard',
        'version': '1.5',
        'body': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'TextBlock',
            'text': 'Cluster Summary',
            'size': 'Large',
            'weight': 'Bolder',
          },
          <String, Object?>{
            'type': 'FactSet',
            'facts': <Map<String, Object?>>[
              <String, Object?>{
                'title': 'Host',
                'value': <String, Object?>{'sealed': 'h_secret_host'},
              },
              <String, Object?>{'title': 'Status', 'value': 'Healthy'},
            ],
          },
          <String, Object?>{
            'type': 'Input.Text',
            'id': 'note',
            'label': 'Operator note',
          },
        ],
        'actions': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'Action.Submit',
            'title': 'Save',
            'data': <String, Object?>{'command': 'save-note'},
          },
          <String, Object?>{
            'type': 'Action.OpenUrl',
            'title': 'Bad Link',
            'url': 'javascript:alert(1)',
          },
        ],
      };

      final adapted = VibeUiCompatibilityAdapter.adapt(card);
      expect(adapted['type'], 'column');
      final children = adapted['children'] as List<Map<String, Object?>>;
      expect(children.first['type'], 'heading');
      expect(children.first['text'], 'Cluster Summary');
      final factTable = children[1];
      expect(factTable['type'], 'table');
      final rows = factTable['rows'] as List;
      expect((rows[0] as List)[1], <String, Object?>{'sealed': 'h_secret_host'});
      expect(children[2]['type'], 'input');
      final actionRow = children.last;
      expect(actionRow['type'], 'row');
      final buttons = actionRow['children'] as List<Map<String, Object?>>;
      expect(buttons, hasLength(1)); // javascript: Action.OpenUrl was dropped
      expect(buttons.first['command'], 'save-note');
    });

    test('adapts Markdown strings and strips <script> tags', () {
      const md = '''
# Disk Health
<script>alert("xss")</script>

| Node | Used |
| --- | --- |
| web-1 | 84% |

---
All checks done.
''';
      final adapted = VibeUiCompatibilityAdapter.adapt(md);
      expect(adapted['type'], 'column');
      final encoded = jsonEncode(adapted);
      expect(encoded.contains('<script>'), isFalse);
      expect(encoded.contains('alert("xss")'), isFalse);
      final children = adapted['children'] as List<Map<String, Object?>>;
      expect(children.any((n) => n['type'] == 'heading' && n['text'] == 'Disk Health'), isTrue);
      expect(children.any((n) => n['type'] == 'table'), isTrue);
      expect(children.any((n) => n['type'] == 'divider'), isTrue);
    });

    test('enforces depth <= 16 and nodes <= 1024 limits', () {
      var deep = <String, Object?>{'type': 'text', 'text': 'leaf'};
      for (var i = 0; i < 18; i++) {
        deep = <String, Object?>{
          'type': 'column',
          'children': <Map<String, Object?>>[deep],
        };
      }
      expect(() => VibeUiCompatibilityAdapter.adapt(deep), throwsFormatException);
      expect(VibeUiCompatibilityAdapter.tryAdapt(deep), isNull);

      final huge = <String, Object?>{
        'type': 'column',
        'children': <Map<String, Object?>>[
          for (var i = 0; i < 12; i++)
            <String, Object?>{
              'type': 'column',
              'children': <Map<String, Object?>>[
                for (var j = 0; j < 90; j++)
                  <String, Object?>{'type': 'text', 'text': 'x'},
              ],
            },
        ],
      };
      expect(() => VibeUiCompatibilityAdapter.adapt(huge), throwsFormatException);
    });
  });

  group('VibeSandboxEvaluator automatic compatibility normalization', () {
    test('normalizes external A2UI / AdaptiveCard views inside VibeProtocolHost', () async {
      final host = VibeProtocolHost(
        id: 'compat-host',
        name: 'Compat Host',
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'ops.hosts',
            title: 'Hosts',
            fields: const <String, String>{'host': 'sealed'},
            read: () => <Map<String, Object?>>[
              <String, Object?>{'host': 'prod-db-01'},
            ],
          ),
        ],
        customRunner: (vibe, input) {
          final rows = (input['data'] as Map)['ops.hosts'] as List;
          final handle = (rows.first as Map)['host'];
          return <String, Object?>{
            'state': null,
            'view': <String, Object?>{
              'type': 'AdaptiveCard',
              'version': '1.5',
              'body': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'TextBlock',
                  'text': handle,
                  'size': 'Large',
                },
              ],
            },
          };
        },
      );

      final vibe = VibeSpec(
        id: 'adaptive-host-card',
        name: 'Adaptive Host',
        version: 1,
        needs: const <String>['ops.hosts'],
        source: '{"kind":"static_view","view":{"type":"text","text":"fallback"}}',
      );
      final run = host.mount(vibe);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final view = run.view;
      expect(view, isNotNull);
      expect(view!['type'], 'column');
      final children = view['children'] as List;
      final first = children.first as Map;
      expect(first['type'], 'heading');
      final handle = (first['text'] as Map)['sealed'] as String;
      expect(host.resolveSealed(handle), 'prod-db-01');
      expect(host.resolveSealed('forged-handle'), isNull);
      host.dispose();
    });
  });

  group('resolveVibeViewTree & Renderers', () {
    test('resolves sealed handles, blanks forged handles, renders Terminal + Markdown', () {
      final view = <String, Object?>{
        'type': 'column',
        'children': <Map<String, Object?>>[
          <String, Object?>{'type': 'heading', 'text': 'Telemetry'},
          <String, Object?>{
            'type': 'bar',
            'label': <String, Object?>{'sealed': 'h_good'},
            'value': 0.75,
            'max': 1.0,
            'tone': 'warn',
          },
          <String, Object?>{
            'type': 'text',
            'text': <String, Object?>{'sealed': 'h_forged'},
          },
          <String, Object?>{
            'type': 'sparkline',
            'values': <double>[0.1, 0.4, 0.9],
            'tone': 'ok',
          },
          <String, Object?>{
            'type': 'table',
            'headers': <String>['Node', 'CPU'],
            'rows': <List<Object?>>[
              <Object?>[
                <String, Object?>{'sealed': 'h_good'},
                '75%',
              ],
            ],
          },
        ],
      };

      String? resolve(Object? handle) {
        final parsed = VibeSealedHandle.tryParse(handle);
        final key = parsed?.sealed ?? handle?.toString();
        return key == 'h_good' ? 'db-east-1' : null;
      }

      final ir = resolveVibeViewTree(view, resolveSealed: resolve);
      expect(ir.type, 'column');
      expect(ir.children[1].label, 'db-east-1');
      expect(ir.children[1].sealedResolved, isTrue);
      expect(ir.children[2].text, '');
      expect(ir.children[2].sealedResolved, isFalse);

      final term = VibeTerminalRenderer.render(view, resolveSealed: resolve, ansi: false);
      expect(term, contains('Telemetry'));
      expect(term, contains('🔒 db-east-1'));
      expect(term, contains('█'));
      expect(term, contains('░'));
      expect(term, contains('▁'));

      final termAnsi = VibeTerminalRenderer.render(view, resolveSealed: resolve, ansi: true);
      expect(termAnsi, contains('\x1b['));

      final md = VibeMarkdownRenderer.render(view, resolveSealed: resolve);
      expect(md, contains('## Telemetry'));
      expect(md, contains('🔒 db-east-1'));
      expect(md, contains('| Node | CPU |'));
    });
  });

  group('VibeStrings i18n & RTL', () {
    test('supports all 8 locales with RTL on Arabic and custom overrides', () {
      const locales = <String>['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de', 'ar'];
      for (final loc in locales) {
        final s = VibeStrings.forLocale('$loc-XX');
        expect(s.locale, loc);
        expect(s.isRtl, loc == 'ar');
        expect(s.sendLabel, isNotEmpty);
        expect(s.format(s.revertLabel, const {'version': '3'}), contains('3'));
      }

      final custom = VibeStrings.forLocale(
        'zh-CN',
        overrides: const <String, String>{'sendLabel': '立即发送'},
      );
      expect(custom.locale, 'zh');
      expect(custom.sendLabel, '立即发送');
    });
  });

  group('Multilingual Wish Compiler/Remixer & UTF-8 Share Codec', () {
    test('compiles and remixes Chinese, Spanish, and Arabic wishes', () {
      final host = VibeProtocolHost(
        id: 'i18n-host',
        name: 'Host',
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'telemetry.disk',
            title: 'Disk',
            fields: const <String, String>{
              'server': 'sealed',
              'mount': 'public',
              'usedFraction': 'public',
              'sizeGb': 'public',
            },
            read: () => const <Map<String, Object?>>[
              <String, Object?>{'server': 's1', 'mount': '/', 'usedFraction': 0.91, 'sizeGb': 100},
            ],
          ),
        ],
      );

      final zhDisk = VibeWishCompiler.compile('磁盘 阈值 90%', host);
      expect(zhDisk, isNotNull);
      expect(zhDisk!.needs, contains('telemetry.disk'));
      expect(jsonDecode(zhDisk.source)['threshold'], closeTo(0.9, 0.001));

      final zhTimer = VibeWishCompiler.compile('10分钟 专注', host);
      expect(zhTimer, isNotNull);
      expect(zhTimer!.id, 'focus-timer');
      expect(zhTimer.source, contains('DURATION_MIN = 10'));

      final esRemix = VibeWishRemixer.apply(zhDisk, 'solo los peores 3 al 75%');
      expect(esRemix.ok, isTrue);
      final esDecoded = jsonDecode(esRemix.vibe!.source) as Map;
      expect(esDecoded['limit'], 3);
      expect(esDecoded['threshold'], closeTo(0.75, 0.001));

      final arTimer = VibeWishCompiler.compile('مؤقت 15 دقيقة', host);
      expect(arTimer, isNotNull);
      expect(arTimer!.source, contains('DURATION_MIN = 15'));

      host.dispose();
    });

    test('round-trips CJK and emoji through VibeShareCodec and host records', () {
      final vibe = VibeSpec(
        id: 'cjk-emoji',
        name: '磁盘监控 🚀',
        wish: '显示最差 3 个服务器 🎉',
        version: 1,
        source: '{"kind":"static_view","view":{"type":"text","text":"正常 ✅"}}',
      );
      final token = VibeShareCodec.encode(vibe);
      final decoded = VibeShareCodec.decode(token);
      expect(decoded.name, '磁盘监控 🚀');
      expect(decoded.wish, '显示最差 3 个服务器 🎉');

      final host = VibeProtocolHost(
        id: 'utf8-host',
        name: 'Host',
        capabilities: const <VibeCapability>[],
      );
      final emojiTitle = List<String>.filled(130, '🚀').join();
      final rec = host.install(vibe, title: emojiTitle);
      expect(rec.title.runes.length, kMaxVibeTitleLength);
      host.dispose();
    });
  });
}
