import {test} from 'node:test';
import assert from 'node:assert/strict';
import {
  validateManifest,
  validateTriggerCondition,
  evaluateTriggerCondition,
  hydrateVibeTemplate,
  createTriggerEvaluator,
  adaptExternalUi,
  validateMiniProgramSource,
  applySetData,
  compileTemplate,
  createMiniProgramSession
} from '../sdk/typescript/index.mjs';

test('evaluateTriggerCondition supports combinators, globs, regex, cwd, env, and context', () => {
  const cond = {
    all: [
      {program: ['agy', 'docker*']},
      {cwd: '*/example-project*'},
      {context: {inTmux: true, portOpen: '3000'}},
    ],
    not: {windowTitle: {regex: 'production', caseSensitive: false}},
  };
  assert.equal(evaluateTriggerCondition(cond, {
    program: '/usr/local/bin/agy',
    command: 'agy chat',
    windowTitle: 'dev-shell',
    cwd: '/workspace/example-project/app',
    context: {inTmux: true, ports: ['3000', '5173']},
  }), true);

  assert.equal(evaluateTriggerCondition(cond, {
    program: 'docker-compose',
    windowTitle: 'PRODUCTION-SSH',
    cwd: '/workspace/example-project',
    context: {inTmux: true, ports: ['3000']},
  }), false);
});

test('createTriggerEvaluator handles hysteresis holdMs, pinning, and episode dismissal', () => {
  const ev = createTriggerEvaluator();
  const entries = [
    {id: 'agy-card', title: 'AGY', when: {program: 'agy'}, holdMs: 2000, priority: 10},
    {id: 'git-card', title: 'Git', when: {context: {gitRepo: true}}, priority: 5},
  ];

  let res = ev.evaluate(entries, {program: 'agy', context: {gitRepo: true}}, 1000);
  assert.deepEqual(res.activeIds, ['agy-card', 'git-card']);
  assert.deepEqual(res.newlyTriggeredIds, ['agy-card', 'git-card']);

  // Brief dip in program within 2000ms hold window keeps agy-card held
  res = ev.evaluate(entries, {program: 'sh', context: {gitRepo: true}}, 2200);
  assert.deepEqual(res.activeIds, ['agy-card', 'git-card']);
  assert.deepEqual(res.heldIds, ['agy-card']);

  // After hold expires, agy-card deactivates
  res = ev.evaluate(entries, {program: 'sh', context: {gitRepo: true}}, 3500);
  assert.deepEqual(res.activeIds, ['git-card']);
  assert.deepEqual(res.deactivatedIds, ['agy-card']);

  // Dismiss git-card for current episode; resets once condition goes false then true
  ev.dismiss('git-card');
  res = ev.evaluate(entries, {program: 'sh', context: {gitRepo: true}}, 3600);
  assert.deepEqual(res.activeIds, []);
  res = ev.evaluate(entries, {program: 'sh', context: {gitRepo: false}}, 3700);
  res = ev.evaluate(entries, {program: 'sh', context: {gitRepo: true}}, 3800);
  assert.deepEqual(res.activeIds, ['git-card']);
});

test('validateManifest validates contribution when triggers and hydrateVibeTemplate escapes', () => {
  const base = {
    id: 'cond-demo',
    version: 1,
    api_version: 1,
    name: 'Conditional Demo',
    license: 'MIT',
    capabilities: ['terminal_read'],
    network_origins: [],
    module_sha256: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    contributions: [{
      id: 'agy-chip',
      slot: 'terminal_action',
      title: 'AGY',
      command: 'open',
      when: {program: 'agy', env: {TMUX: {exists: true}}},
    }],
  };
  assert.throws(() => validateManifest(base));
  assert.equal(
    validateManifest({...base, capabilities: ['api:host.ui']}).contributions[0].when.program,
    'agy'
  );
  assert.equal(
    validateManifest(base, {capabilities: ['terminal_read']}).contributions[0].when.program,
    'agy'
  );
  assert.throws(() => validateTriggerCondition({program: {regex: '[unclosed'}}));
  assert.equal(
    hydrateVibeTemplate('Branch: {{gitBranch}}', {context: {gitBranch: 'feat/<x>'}}, {escapeHtml: true}),
    'Branch: feat/&lt;x&gt;'
  );
});

test('WeChat Mini Program dual-layer session, setData path patching, VXML template, and canvas limits', () => {
  assert.throws(() => validateMiniProgramSource('defineMiniProgram({ onLoad() { fetch("https://evil.example"); } })'));
  assert.throws(() => validateMiniProgramSource('defineMiniProgram({ onLoad() { window.location = "x"; } })'));
  assert.equal(validateMiniProgramSource('defineMiniProgram({ data: { count: 1 } })'), true);

  // Path-based setData + prototype pollution & 64 KiB cap
  const next = applySetData({ meta: { tps: 10 }, bars: [12, 24] }, { 'meta.tps': 94.2, 'bars[1]': 88 });
  assert.equal(next.meta.tps, 94.2);
  assert.deepEqual(next.bars, [12, 88]);
  assert.throws(() => applySetData({}, { '__proto__.polluted': true }));
  assert.throws(() => applySetData({}, { huge: 'x'.repeat(70000) }));

  // MiniProgram lifecycle + VXML compilation + canvas + bindtap round-trip
  const session = createMiniProgramSession({
    data: { mode: 'live', tps: 42.5, history: [20, 45, 78], showChart: true, hostLabel: { sealed: 'h_host1' } },
    template: {
      type: 'column',
      children: [
        { type: 'stat', label: '{{hostLabel}}', value: '{{tps}} tok/s', tone: 'ok' },
        {
          if: '{{showChart}}',
          type: 'canvas',
          width: 240,
          height: 48,
          bindtap: 'onToggleMode',
          'data-source': 'agy',
          commands: [
            { op: 'clear', fill: '#0F172A' },
            { op: 'bars', values: '{{history}}', fill: '#38BDF8' }
          ]
        },
        { for: 'v in history', type: 'badge', text: 'sample={{v}}' }
      ]
    },
    onDataUpdate(hostData) {
      if (typeof hostData.tps === 'number') this.setData({ tps: hostData.tps });
    },
    methods: {
      onToggleMode(ev) {
        this.setData({ mode: ev.target?.dataset?.source || 'tapped', tps: 99.1 });
      }
    }
  });

  session.load({ tps: 64.0 }, { program: 'agy' });
  let view = session.buildView();
  assert.equal(view.children[0].label.sealed, 'h_host1');
  assert.equal(view.children[0].value, '64 tok/s');
  assert.equal(view.children[1].type, 'canvas');
  assert.deepEqual(view.children[1].commands[1].values, [20, 45, 78]);
  assert.equal(view.children.length, 5);

  session.dispatchEvent({ type: 'tap', handler: 'onToggleMode', target: { dataset: { source: 'skyline' } } });
  assert.equal(session.data.mode, 'skyline');
  view = session.buildView();
  assert.equal(view.children[0].value, '99.1 tok/s');

  // > 2,000 canvas commands rejected
  const tooMany = Array.from({ length: 2001 }, (_, i) => ({ op: 'rect', x: i, y: 0, w: 1, h: 1 }));
  assert.throws(() => adaptExternalUi({ type: 'canvas', width: 240, height: 48, commands: tooMany }));

  // > 30/s setData rate limit rejected
  const fastSession = createMiniProgramSession({ data: { n: 0 }, template: { type: 'text', text: '{{n}}' } });
  for (let i = 0; i < 30; i++) fastSession.setData({ n: i }, 5000);
  assert.throws(() => fastSession.setData({ n: 31 }, 5100));
});
