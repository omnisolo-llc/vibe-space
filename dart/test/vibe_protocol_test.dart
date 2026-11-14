import 'dart:convert';

import 'package:test/test.dart';
import 'package:vibe_space/vibe_space.dart';

void main() {
  group('VibeSealedHandle & seal table', () {
    test('seals deterministically per host, persists, and rejects forged handles', () {
      final storage = InMemoryVibeStorage();
      final hostA1 = VibeProtocolHost(
        id: 'example-host',
        name: 'Example Host',
        capabilities: const <VibeCapability>[],
        storage: storage,
      );
      final hostA2 = VibeProtocolHost(
        id: 'example-host',
        name: 'Example Host',
        capabilities: const <VibeCapability>[],
        storage: storage,
      );
      final hostB = VibeProtocolHost(
        id: 'moments',
        name: 'Moments',
        capabilities: const <VibeCapability>[],
        storage: storage,
      );

      final h1 = hostA1.seal('db-1.prod.internal');
      final h2 = hostA2.seal('db-1.prod.internal');
      final hb = hostB.seal('db-1.prod.internal');

      expect(h1.sealed, matches(RegExp(r'^h_[0-9a-f]{16}$')));
      expect(h1, equals(h2));
      expect(h1.sealed, isNot(equals(hb.sealed)));
      expect(hostA1.resolveSealed(h1), 'db-1.prod.internal');
      expect(hostA2.resolveSealed({'sealed': h1.sealed}), 'db-1.prod.internal');

      // Forged, malformed, or cross-host handles must never resolve.
      expect(hostA1.resolveSealed(const VibeSealedHandle('h_fake')), isNull);
      expect(hostA1.resolveSealed({'sealed': 'h_fake'}), isNull);
      expect(hostA1.resolveSealed(hb), isNull);
      expect(VibeSealedHandle.tryParse({'sealed': 'h_abc', 'extra': 1}), isNull);
      expect(VibeSealedHandle.tryParse({'sealed': ''}), isNull);
      expect(VibeSealedHandle.tryParse(const {'sealed': 'h_abc'}), equals(const VibeSealedHandle('h_abc')));
    });
  });

  group('VibeSpec, labels, and VibeShareCodec', () {
    test('generates deduplicated Reads / Shows / Cannot labels', () {
      final host = VibeProtocolHost(
        id: 'example-host',
        name: 'Example Host',
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'telemetry.disk',
            title: 'Disk usage of your servers',
            fields: const {'server': 'sealed', 'usedFraction': 'public'},
            sealedNote: 'server names stay sealed',
            sealedCannot: 'See server names or addresses',
            read: () => const <Map<String, Object?>>[],
          ),
          VibeCapability(
            name: 'telemetry.load',
            title: 'CPU and memory of your servers',
            fields: const {'server': 'sealed', 'cpu': 'public'},
            sealedNote: 'server names stay sealed',
            sealedCannot: 'See server names or addresses',
            read: () => const <Map<String, Object?>>[],
          ),
        ],
        notOffered: const ['Run commands', 'Use the internet'],
      );

      final combined = VibeSpec(
        id: 'combined',
        name: 'Combined',
        version: 1,
        needs: const ['telemetry.disk', 'telemetry.load'],
        source: '{"kind":"disk_watch"}',
      );
      final lbl = host.label(combined);
      expect(lbl.reads, <String>[
        'Disk usage of your servers (server names stay sealed)',
        'CPU and memory of your servers (server names stay sealed)',
      ]);
      expect(lbl.shows, <String>['Only inside its own box']);
      expect(lbl.cannot, <String>[
        'See server names or addresses',
        'Run commands',
        'Use the internet',
        'Change anything in Example Host',
      ]);

      final portableLbl = host.label(kPortableFocusTimerVibe);
      expect(portableLbl.reads, <String>['Nothing from Example Host']);
      expect(portableLbl.shows, <String>['Only inside its own box']);
      expect(portableLbl.cannot, <String>[
        'Run commands',
        'Use the internet',
        'Change anything in Example Host',
      ]);
    });

    test('VibeShareCodec strips title/note/args and decodes raw token or URL', () {
      final spec = VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        wish: 'Show disk usage',
        version: 2,
        needs: const ['telemetry.disk'],
        refreshMs: 2000,
        source: 'function invoke(input) { return { state: null, view: { type: "text", text: "ok" } }; }',
      );

      final token = VibeShareCodec.encode(spec);
      expect(token.contains('='), isFalse);
      expect(VibeShareCodec.decode(token), equals(spec));
      expect(VibeShareCodec.decode('#vibe=$token'), equals(spec));
      expect(
        VibeShareCodec.decode('https://example.com/demo/index.html#vibe=$token&extra=1'),
        equals(spec),
      );

      // Stripping extra host-only fields in fromJson
      final parsedFromDirty = VibeSpec.fromJson(<String, Object?>{
        ...spec.toJson(),
        'title': 'Secret Host Title',
        'note': 'Secret Host Note',
        'args': {'server': 'db-1'},
      });
      expect(parsedFromDirty, equals(spec));
      expect(VibeShareCodec.decode(token).toJson().containsKey('title'), isFalse);

      expect(() => VibeShareCodec.decode('not valid!'), throwsFormatException);
      expect(
        () => VibeSpec.fromJson({
          'id': 'BAD ID',
          'name': 'Bad',
          'version': 1,
          'needs': const <String>[],
          'source': 'function invoke(){}',
        }),
        throwsFormatException,
      );
    });
  });

  group('VibeProtocolHost lifecycle store', () {
    VibeProtocolHost makeHost(VibeStorageAdapter storage, {bool includeDisk = true}) {
      return VibeProtocolHost(
        id: 'example-host',
        name: 'Example Host',
        storage: storage,
        capabilities: <VibeCapability>[
          if (includeDisk)
            VibeCapability(
              name: 'telemetry.disk',
              title: 'Disk usage',
              fields: const {'server': 'sealed', 'usedFraction': 'public'},
              read: () => const <Map<String, Object?>>[],
            ),
          VibeCapability(
            name: 'telemetry.load',
            title: 'CPU and memory',
            fields: const {'server': 'sealed', 'cpu': 'public'},
            read: () => const <Map<String, Object?>>[],
          ),
        ],
      );
    }

    test('supports multi-instance args, custom title/note, history/revert, reorder, and uninstall/restore', () {
      final storage = InMemoryVibeStorage();
      final host = makeHost(storage);
      var changes = 0;
      final unsub = host.onChange(() => changes++);

      final loadSpec = const VibeSpec(
        id: 'server-load',
        name: 'CPU and memory',
        version: 1,
        needs: ['telemetry.load'],
        source: '{"kind":"server_load"}',
      );
      final hDb1 = host.seal('db-1');
      final hWeb1 = host.seal('web-1');

      final rDb1 = host.install(
        loadSpec,
        origin: 'agent',
        args: {'server': hDb1.toJson()},
        title: 'CPU · db-1',
        note: 'Primary database',
      );
      final rWeb1 = host.install(
        loadSpec,
        origin: 'agent',
        args: {'server': hWeb1.toJson()},
        title: 'CPU · web-1',
      );
      expect(rDb1.instanceId, isNot(equals(rWeb1.instanceId)));
      expect(host.installed().length, 2);

      // Re-installing same id + same args updates in place and keeps custom title/note
      final rDb1v2 = host.install(
        loadSpec.copyWith(version: 2),
        origin: 'agent',
        args: {'server': hDb1.toJson()},
      );
      expect(rDb1v2.instanceId, equals(rDb1.instanceId));
      expect(rDb1v2.title, 'CPU · db-1');
      expect(rDb1v2.note, 'Primary database');
      expect(rDb1v2.history.length, 1);
      expect(rDb1v2.history.first.vibe.version, 1);

      // Capability escalation rejected by updateRecord
      expect(
        () => host.updateRecord(
          rDb1.instanceId,
          vibe: loadSpec.copyWith(
            version: 3,
            needs: const ['telemetry.load', 'secrets.vault'],
          ),
        ),
        throwsStateError,
      );

      // History capped at 10 entries + revertRecord
      final diskSpec = const VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        version: 1,
        needs: ['telemetry.disk'],
        source: '{"kind":"disk_watch"}',
      );
      final rDisk = host.install(diskSpec, title: 'Prod Disks');
      for (var v = 2; v <= 13; v++) {
        host.updateRecord(
          rDisk.instanceId,
          vibe: diskSpec.copyWith(version: v),
        );
      }
      final latestDisk =
          host.installed().firstWhere((r) => r.instanceId == rDisk.instanceId);
      expect(latestDisk.vibe.version, 13);
      expect(latestDisk.history.length, 10);
      expect(latestDisk.history.first.vibe.version, 12);

      final reverted = host.revertRecord(rDisk.instanceId, 0);
      expect(reverted.vibe.version, 12);
      expect(reverted.history.first.vibe.version, 13);

      // Pin to top stays ahead of unpinned across reorder
      host.updateRecord(rWeb1.instanceId, pinned: true);
      var ordered = host.reorder([rDisk.instanceId, rDb1.instanceId, rWeb1.instanceId]);
      expect(ordered[0].instanceId, rWeb1.instanceId);
      expect(ordered[1].instanceId, rDisk.instanceId);
      expect(ordered[2].instanceId, rDb1.instanceId);

      // Uninstall returns snapshot; restoreRecord brings it back intact
      final removed = host.uninstall(rDisk.instanceId);
      expect(removed, isNotNull);
      expect(host.installed().any((r) => r.instanceId == rDisk.instanceId), isFalse);
      host.restoreRecord(removed!, 1);
      final restoredList = host.installed();
      expect(restoredList[1].instanceId, rDisk.instanceId);
      expect(restoredList[1].history.length, 10);

      // Persisted records survive even if a capability disappears on reload!
      final hostReloaded = makeHost(storage, includeDisk: false);
      expect(
        hostReloaded.installed().any((r) => r.instanceId == rDisk.instanceId),
        isTrue,
      );

      unsub();
      final countBefore = changes;
      host.uninstall(rWeb1.instanceId);
      expect(changes, countBefore);
    });
  });

  group('VibeRunController, sealed isolation & graceful source health', () {
    test('seals data, omits host title/note, enforces 64 kB & errors, and recovers from offline/revoked', () async {
      var diskStatus = const VibeSourceStatus.live();
      var throwOnRead = false;
      var diskRows = <Map<String, Object?>>[
        {'server': 'db-1.prod.internal', 'mount': '/', 'usedFraction': 0.85, 'sizeGb': 200},
        {'server': 'web-1.prod.internal', 'mount': '/', 'usedFraction': 0.92, 'sizeGb': 100},
      ];

      final host = VibeProtocolHost(
        id: 'ops',
        name: 'Example Host',
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'telemetry.disk',
            title: 'Disk usage',
            fields: const {
              'server': 'sealed',
              'mount': 'public',
              'usedFraction': 'public',
              'sizeGb': 'public',
            },
            status: () => diskStatus,
            read: () {
              if (throwOnRead) throw StateError('Host pipe broken');
              return diskRows;
            },
            sample: const <Map<String, Object?>>[
              {'server': 'sample-a', 'mount': '/', 'usedFraction': 0.5, 'sizeGb': 100},
            ],
          ),
        ],
      );

      final diskSpec = const VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        version: 1,
        needs: ['telemetry.disk'],
        source: '{"kind":"disk_watch","threshold":0.8}',
      );
      host.install(diskSpec, title: 'My Secret Title', note: 'My Secret Note');

      final run = host.mount(diskSpec, dataMode: 'live');
      expect(run.health().state, VibeSourceMode.live);
      expect(run.health().isStale, isFalse);
      expect(run.lastError, isNull);
      expect(run.view, isNotNull);

      final insp = run.inspect();
      final inputJson = jsonEncode(insp.input);
      expect(inputJson.contains('db-1.prod.internal'), isFalse);
      expect(inputJson.contains('My Secret Title'), isFalse);
      expect(inputJson.contains('My Secret Note'), isFalse);
      expect(inputJson.contains('"sealed"'), isTrue);
      expect(insp.ledger.reads['telemetry.disk'], 1);

      // Go offline -> stale view preserved, lastError stays null
      diskStatus = const VibeSourceStatus.offline('Host telemetry feed disconnected');
      host.notifySourceChange();
      expect(run.health().state, VibeSourceMode.offline);
      expect(run.health().isStale, isTrue);
      expect(run.lastError, isNull);
      expect(run.unavailableReason, isNull);
      expect(run.view, isNotNull);

      // Sample fallback -> usingSampleFallback = true
      await run.setDataMode('sample');
      expect(run.health().state, VibeSourceMode.sample);
      expect(run.health().usingSampleFallback, isTrue);
      expect(run.view.toString().contains('sample-a'), isFalse); // sealed!

      // Return to live while still offline -> clears sample view, shows unavailableReason
      await run.setDataMode('live');
      expect(run.health().state, VibeSourceMode.offline);
      expect(run.view, isNull);
      expect(run.unavailableReason, contains('Host telemetry feed disconnected'));
      expect(run.lastError, isNull);

      // Source returns -> auto-recovers via notifySourceChange
      diskStatus = const VibeSourceStatus.live();
      host.notifySourceChange();
      expect(run.health().state, VibeSourceMode.live);
      expect(run.health().isStale, isFalse);
      expect(run.view, isNotNull);
      expect(run.unavailableReason, isNull);

      // Throwing read() also preserves stale view gracefully
      throwOnRead = true;
      await run.retry();
      expect(run.health().state, VibeSourceMode.offline);
      expect(run.health().isStale, isTrue);
      expect(run.lastError, isNull);
      run.stop();

      // Missing capability when mounted directly -> unavailableReason, not lastError
      final missingRun = host.mount(
        const VibeSpec(
          id: 'bad-cap',
          name: 'Bad Cap',
          version: 1,
          needs: ['unknown.cap'],
          source: '{"kind":"disk_watch"}',
        ),
      );
      expect(missingRun.health().state, VibeSourceMode.missing);
      expect(missingRun.unavailableReason, isNotNull);
      expect(missingRun.lastError, isNull);
      missingRun.stop();

      // Hostile infinite loop & >64 kB output record lastError cleanly
      final loopRun = host.mount(
        const VibeSpec(
          id: 'loop',
          name: 'Loop',
          version: 1,
          needs: [],
          source: 'function invoke(input) { while (true) {} }',
        ),
      );
      expect(loopRun.lastError, isNotNull);
      expect(loopRun.view, isNull);
      loopRun.stop();

      final hugeHost = VibeProtocolHost(
        id: 'huge',
        name: 'Huge',
        capabilities: const <VibeCapability>[],
        customRunner: (_, __) => <String, Object?>{
          'state': null,
          'view': <String, Object?>{
            'type': 'text',
            'text': 'Z' * 70000,
          },
        },
      );
      final hugeRun = hugeHost.mount(kPortableFocusTimerVibe);
      expect(hugeRun.lastError, contains('64 kB'));
      expect(hugeRun.view, isNull);
      hugeRun.stop();
    });

    test('built-in focus timer, server-load offline target, and wish remix/compiler work', () async {
      var serversOnline = true;
      final host = VibeProtocolHost(
        id: 'ops2',
        name: 'Example Host',
        capabilities: <VibeCapability>[
          VibeCapability(
            name: 'telemetry.disk',
            title: 'Disk usage',
            fields: const {'server': 'sealed', 'mount': 'public', 'usedFraction': 'public', 'sizeGb': 'public'},
            read: () => const <Map<String, Object?>>[
              {'server': 'db-1', 'mount': '/', 'usedFraction': 0.83, 'sizeGb': 200},
              {'server': 'web-1', 'mount': '/', 'usedFraction': 0.91, 'sizeGb': 100},
            ],
          ),
          VibeCapability(
            name: 'telemetry.load',
            title: 'CPU and memory',
            fields: const {'server': 'sealed', 'cpu': 'public', 'mem': 'public', 'cpuHistory': 'public', 'memHistory': 'public'},
            read: () {
              if (!serversOnline) {
                return const <Map<String, Object?>>[
                  {'server': 'web-1', 'cpu': 0.32, 'mem': 0.41, 'cpuHistory': [0.3, 0.32], 'memHistory': [0.4, 0.41]},
                ];
              }
              return const <Map<String, Object?>>[
                {'server': 'db-1', 'cpu': 0.91, 'mem': 0.62, 'cpuHistory': [0.88, 0.91], 'memHistory': [0.61, 0.62]},
                {'server': 'web-1', 'cpu': 0.32, 'mem': 0.41, 'cpuHistory': [0.3, 0.32], 'memHistory': [0.4, 0.41]},
              ];
            },
          ),
        ],
      );

      // Focus timer commands
      final timerRun = host.mount(kPortableFocusTimerVibe);
      expect(jsonEncode(timerRun.view), contains('Start'));
      await timerRun.dispatch('start');
      expect(jsonEncode(timerRun.view), contains('Pause'));
      await timerRun.dispatch('pause');
      expect(jsonEncode(timerRun.view), contains('Resume'));
      await timerRun.dispatch('reset');
      expect(jsonEncode(timerRun.view), contains('Start'));
      timerRun.stop();

      // Server-load offline target preserves last reading + clear-target / restore-target
      final hDb1 = host.seal('db-1');
      final loadVibe = VibeWishCompiler.compile('Why is db-1 slow?', host)!;
      final loadRun = host.mount(loadVibe, args: {'server': hDb1.toJson()});
      expect(jsonEncode(loadRun.view), contains('91%'));
      serversOnline = false;
      host.notifySourceChange();
      expect(jsonEncode(loadRun.view), contains('Target server offline'));
      expect(jsonEncode(loadRun.view), contains('91%'));
      await loadRun.dispatch('clear-target');
      expect(jsonEncode(loadRun.view), contains('Back to target server'));
      await loadRun.dispatch('restore-target');
      expect(jsonEncode(loadRun.view), contains('Target server offline'));
      loadRun.stop();

      // Wish remixer preserves WARN_LEVEL=0.6 while updating threshold & count
      const jsDisk = '''function invoke(input) {
  var THRESHOLD = 0.8;
  var WARN_LEVEL = 0.6;
  var TOP_LIMIT = 10;
  return { state: null, view: { type: 'heading', text: 'Disk usage' } };
}''';
      final diskBase = const VibeSpec(
        id: 'disk-watch',
        name: 'Disk Watch',
        version: 1,
        needs: ['telemetry.disk'],
        source: jsDisk,
      );
      final remixed = VibeWishRemixer.apply(diskBase, 'Make it red above 75% and show worst 2');
      expect(remixed.ok, isTrue);
      expect(remixed.vibe!.version, 2);
      expect(remixed.vibe!.source, contains('THRESHOLD = 0.75'));
      expect(remixed.vibe!.source, contains('WARN_LEVEL = 0.6'));
      expect(remixed.vibe!.source, contains('TOP_LIMIT = 2'));

      final compiledDisk = VibeWishCompiler.compile('Show disk usage above 85% worst 1', host);
      expect(compiledDisk, isNotNull);
      final diskRun = host.mount(compiledDisk!);
      expect(jsonEncode(diskRun.view), contains('above 85%'));
      diskRun.stop();
    });
  });
}
