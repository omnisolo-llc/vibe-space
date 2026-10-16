import 'dart:async';

import 'package:test/test.dart';
import 'package:vibe_space/vibe_space.dart';

JsonMap effect([String name = 'demo.theme']) => {
      'id': 'theme',
      'method': 'host.call',
      'capability': 'api:$name',
      'arguments': {
        'api': name,
        'version': 1,
        'input': {'accent': 'purple'},
      },
    };
VibeHostApi api(
  FutureOr<Object?> Function(JsonMap, VibeCallContext) handler, {
  bool readOnly = false,
}) =>
    VibeHostApi(
      name: 'demo.theme',
      version: 1,
      title: 'Theme',
      description: 'Test appearance hook',
      readOnly: readOnly,
      inputSchema: {
        'type': 'object',
        'properties': {
          'accent': {
            'type': 'string',
            'enum': ['purple'],
          },
        },
        'required': ['accent'],
      },
      outputSchema: {
        'type': 'object',
        'properties': {
          'applied': {'type': 'boolean'},
        },
        'required': ['applied'],
      },
      handler: handler,
    );
VibeCallContext context(Future<void> Function() check) =>
    VibeCallContext(pluginId: 'demo', revision: 'r1', assertCurrent: check);

void main() {
  test('reviewed effect snapshot is deeply immutable', () {
    final original = effect();
    final batch = VibeEffectBatch([original]);
    (original['arguments'] as Map)['input'] = {'accent': 'red'};
    expect(batch.effects.single['arguments']['input']['accent'], 'purple');
    expect(() => batch.effects.clear(), throwsUnsupportedError);
    expect(
      () => batch.effects.single['arguments']['input']['accent'] = 'red',
      throwsUnsupportedError,
    );
    expect(
      () => VibeEffectBatch([
        {...effect(), 'capability': 'terminal_read'},
      ]),
      throwsStateError,
    );
    expect(() => VibeEffectBatch([effect(), effect()]), throwsFormatException);
  });
  test(
    'unregistered APIs, forged grants and missing approval never dispatch',
    () async {
      var calls = 0;
      final registry = VibeHostRegistry()
        ..register(
          api((_, __) {
            calls++;
            return {'applied': true};
          }),
        );
      await expectLater(
        registry.call(effect('unknown'), {'api:unknown'}, context(() async {})),
        throwsUnsupportedError,
      );
      await expectLater(
        registry.call(
          effect(),
          {},
          context(() async {}),
          approve: (_) async => true,
        ),
        throwsStateError,
      );
      await expectLater(
        registry.call(effect(), {'api:demo.theme'}, context(() async {})),
        throwsStateError,
      );
      await expectLater(
        registry.call(
          effect(),
          {'api:demo.theme'},
          context(() async {}),
          approve: (_) async => false,
        ),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );
  test(
    'schema rejects unknown fields before dispatch and bad outputs',
    () async {
      var calls = 0;
      final registry = VibeHostRegistry()
        ..register(
          api((_, __) {
            calls++;
            return {'applied': 'yes'};
          }, readOnly: true),
        );
      final invalid = effect();
      invalid['arguments']['input']['script'] = 'alert(1)';
      await expectLater(
        registry.call(invalid, {'api:demo.theme'}, context(() async {})),
        throwsFormatException,
      );
      expect(calls, 0);
      await expectLater(
        registry.call(effect(), {'api:demo.theme'}, context(() async {})),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );
  test('revocation while review is open prevents handler dispatch', () async {
    var current = true, calls = 0;
    final registry = VibeHostRegistry()
      ..register(
        api((_, __) {
          calls++;
          return {'applied': true};
        }),
      );
    await expectLater(
      registry.call(
        effect(),
        {'api:demo.theme'},
        context(() async {
          if (!current) throw StateError('revoked');
        }),
        approve: (_) async {
          current = false;
          return true;
        },
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
  test('revocation and API replacement reject pending outputs', () async {
    for (final replace in [false, true]) {
      final pending = Completer<Object?>(), started = Completer<void>();
      var current = true;
      final registry = VibeHostRegistry()
        ..register(
          api((_, __) {
            started.complete();
            return pending.future;
          }, readOnly: true),
        );
      final result = registry.call(
        effect(),
        {'api:demo.theme'},
        context(() async {
          if (!current) throw StateError('revoked');
        }),
      );
      final expectation = expectLater(result, throwsStateError);
      await started.future;
      if (replace) {
        registry.unregister('demo.theme');
        registry.register(api((_, __) => {'applied': true}, readOnly: true));
      } else {
        current = false;
      }
      pending.complete({'applied': true});
      await expectation;
    }
  });
  test(
    'API descriptors snapshot schemas and reject unsupported validation',
    () {
      final input = <String, dynamic>{'type': 'object', 'properties': {}};
      final value = VibeHostApi(
        name: 'demo.read',
        version: 1,
        title: 'Read',
        description: 'Read',
        inputSchema: input,
        outputSchema: {'type': 'null'},
        readOnly: true,
        handler: (_, __) => null,
      );
      input['additionalProperties'] = true;
      expect(value.inputSchema.containsKey('additionalProperties'), false);
      expect(
        () => VibeSchema.check({'type': 'string', 'pattern': '.*'}),
        throwsFormatException,
      );
      expect(
        () => VibeSchema.check({'type': 'array', 'maxItems': -1}),
        throwsFormatException,
      );
    },
  );
}
