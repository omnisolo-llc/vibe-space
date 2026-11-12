import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {
  adaptExternalUi,
  resolveViewTree,
  renderWithH,
  renderToTerminal,
  renderToMarkdown,
  renderToHtmlString,
  defineVibeWebComponents,
  getVibeStrings,
  isRtlLocale
} from '../sdk/typescript/index.mjs';

test('adaptExternalUi converts A2UI surfaceUpdate adjacency list while preserving sealed handles', () => {
  const a2ui = {
    surfaceUpdate: {
      surfaceId: 'main',
      root: 'root',
      components: [
        { id: 'root', component: { Column: { children: { explicitList: ['hdr', 'stat1', 'bar1', 'btn1'] } } } },
        { id: 'hdr', component: { Heading: { text: { literalString: 'Cluster health' } } } },
        { id: 'stat1', component: { Metric: { label: { sealed: 'h_srv1' }, value: { literalString: '92%' }, tone: 'danger' } } },
        { id: 'bar1', component: { Bar: { label: { literalString: 'Disk /' }, value: 0.91, max: 1, tone: 'danger', swatch: '#ef4444' } } },
        { id: 'btn1', component: { Button: { text: { literalString: 'Inspect' }, action: { name: 'inspect_srv', context: { id: 'db-1' } } } } }
      ]
    }
  };
  const view = adaptExternalUi(a2ui);
  assert.equal(view.type, 'column');
  assert.equal(view.children[0].type, 'heading');
  assert.equal(view.children[0].text, 'Cluster health');
  assert.equal(view.children[1].type, 'stat');
  assert.deepEqual(view.children[1].label, { sealed: 'h_srv1' });
  assert.equal(view.children[2].type, 'bar');
  assert.equal(view.children[2].swatch, '#ef4444');
  assert.equal(view.children[3].type, 'button');
  assert.equal(view.children[3].command, 'inspect_srv');
});

test('adaptExternalUi converts AdaptiveCard and Markdown into canonical VibeView', () => {
  const card = {
    type: 'AdaptiveCard',
    version: '1.5',
    body: [
      { type: 'TextBlock', text: 'Top fans', size: 'Large', weight: 'Bolder' },
      {
        type: 'FactSet',
        facts: [
          { title: { sealed: 'h_fan1' }, value: '84 likes' },
          { title: { sealed: 'h_forged' }, value: '12 likes' }
        ]
      }
    ],
    actions: [{ type: 'Action.Submit', title: 'Refresh', verb: 'refresh', style: 'positive' }]
  };
  const adaptedCard = adaptExternalUi(card);
  assert.equal(adaptedCard.type, 'column');
  assert.equal(adaptedCard.children[0].type, 'heading');
  assert.equal(adaptedCard.children[1].type, 'table');
  assert.deepEqual(adaptedCard.children[1].rows[0][0], { sealed: 'h_fan1' });
  assert.equal(adaptedCard.children[2].children[0].type, 'button');
  assert.equal(adaptedCard.children[2].children[0].tone, 'ok');

  const md = adaptExternalUi('# Status\n\n- CPU normal\n---\n| Host | Load |\n| --- | --- |\n| api-1 | 42% |');
  assert.equal(md.type, 'column');
  assert.equal(md.children[0].type, 'heading');
  assert.equal(md.children[1].text, '\u2022 CPU normal');
  assert.equal(md.children[2].type, 'divider');
  assert.equal(md.children[3].type, 'table');
  assert.deepEqual(md.children[3].rows[0], ['api-1', '42%']);
});

test('resolveViewTree resolves known sealed handles and strips forged handles to empty', () => {
  const view = {
    type: 'column',
    children: [
      { type: 'text', text: { sealed: 'h_real' } },
      { type: 'text', text: { sealed: 'h_fake' } }
    ]
  };
  const resolved = resolveViewTree(view, {
    resolveSealed: id => (id === 'h_real' ? 'db-1.prod.internal' : null)
  });
  assert.equal(resolved.children[0].text, 'db-1.prod.internal');
  assert.equal(resolved.children[0].sealedResolved, true);
  assert.equal(resolved.children[1].text, '');
  assert.equal(resolved.children[1].sealedResolved, false);
});

test('renderWithH produces React/Vue-compatible VDOM and triggers onCommand', () => {
  const h = (tag, props, ...children) => ({ tag, props: props || {}, children });
  let invoked = null;
  const view = {
    type: 'card',
    children: [
      { type: 'badge', text: { sealed: 'h_srv' }, tone: 'warn' },
      { type: 'button', text: 'Restart', command: 'restart', args: { unit: 'nginx' }, tone: 'danger' }
    ]
  };
  const vdom = renderWithH(h, view, {
    resolveSealed: id => (id === 'h_srv' ? 'web-1' : null),
    onCommand: (cmd, args) => { invoked = { cmd, args }; }
  });
  assert.equal(vdom.tag, 'div');
  assert.equal(vdom.props.className, 'vk-card');
  const badge = vdom.children[0];
  assert.equal(badge.tag, 'span');
  assert.equal(badge.children[0].props.className, 'vk-sealed');
  assert.equal(badge.children[0].children[0], 'web-1');
  const btn = vdom.children[1];
  btn.props.onClick();
  assert.deepEqual(invoked, { cmd: 'restart', args: { unit: 'nginx' } });
});

test('renderToTerminal, renderToMarkdown, and XSS-escaped renderToHtmlString', () => {
  const view = {
    type: 'column',
    children: [
      { type: 'heading', text: '<script>alert(1)</script>' },
      { type: 'bar', label: { sealed: 'h_srv' }, value: 0.85, max: 1, caption: '85%', tone: 'danger' },
      { type: 'sparkline', values: [10, 40, 85] },
      { type: 'text', text: { sealed: 'h_forged' } }
    ]
  };
  const resolveSealed = id => (id === 'h_srv' ? 'db-1' : null);

  const term = renderToTerminal(view, { resolveSealed, ansi: false });
  assert.ok(term.includes('\ud83d\udd12 db-1'));
  assert.ok(term.includes('\u2588'));
  assert.ok(!term.includes('h_forged'));

  const md = renderToMarkdown(view, { resolveSealed });
  assert.ok(md.includes('## <script>alert(1)</script>'));
  assert.ok(md.includes('\ud83d\udd12 db-1'));
  assert.ok(!md.includes('h_forged'));

  const html = renderToHtmlString(view, { resolveSealed });
  assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
  assert.ok(html.includes('<span class="vk-sealed">db-1</span>'));
  assert.ok(!html.includes('h_forged'));
});

test('defineVibeWebComponents registers <vibe-view>, <vibe-embed>, and <vibe-space>', () => {
  const defined = new Map();
  class MockHTMLElement {
    constructor() {
      this.attributes = {};
      this.children = [];
      this.textContent = '';
      this.ownerDocument = {
        createElement: tag => ({ tagName: tag, className: '', textContent: '', children: [], appendChild(c) { this.children.push(c); } }),
        createTextNode: txt => ({ textContent: txt })
      };
    }
    getAttribute(k) { return this.attributes[k] || null; }
    appendChild(c) { this.children.push(c); }
  }
  const env = {
    HTMLElement: MockHTMLElement,
    document: new MockHTMLElement().ownerDocument,
    customElements: {
      get: name => defined.get(name),
      define: (name, cls) => defined.set(name, cls)
    }
  };
  const classes = defineVibeWebComponents(env);
  assert.ok(defined.has('vibe-view'));
  assert.ok(defined.has('vibe-embed'));
  assert.ok(defined.has('vibe-space'));
  const el = new classes.VibeViewElement();
  el.view = { type: 'heading', text: 'Hello WC' };
  assert.equal(el.children[0].textContent, 'Hello WC');
});

test('getVibeStrings and isRtlLocale support all 8 locales and RTL detection', () => {
  for (const loc of ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de', 'ar']) {
    const s = getVibeStrings(loc);
    assert.equal(s.locale, loc);
    assert.ok(typeof s.panelTitle === 'string' && s.panelTitle.length > 0);
    assert.equal(s.rtl, loc === 'ar');
  }
  assert.equal(isRtlLocale('ar-SA'), true);
  assert.equal(isRtlLocale('zh-CN'), false);
  const custom = getVibeStrings('zh', { send: 'Go' });
  assert.equal(custom.send, 'Go');
});

test('demo/kit vibekit.js + vibespace.js UTF-8 share links, adaptUi, and RTL support', () => {
  const store = {};
  const g = {
    window: null,
    globalThis: null,
    crypto: { getRandomValues: arr => crypto.randomFillSync(arr) },
    localStorage: {
      getItem: k => (k in store ? store[k] : null),
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: k => { delete store[k]; }
    },
    TextEncoder, TextDecoder,
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    Date, Math, Object, Array, String, Number, Boolean, JSON, Map, Set, RegExp, Error, TypeError, RangeError, parseInt, parseFloat, isNaN, isFinite, encodeURIComponent, decodeURIComponent, escape, unescape,
    setTimeout: () => 1, clearTimeout: () => {}, setInterval: () => 1, clearInterval: () => {},
    location: { hash: '' }, addEventListener: () => {}, removeEventListener: () => {}
  };
  g.window = g;
  g.globalThis = g;
  vm.createContext(g);
  vm.runInContext(fs.readFileSync(new URL('../demo/kit/vibekit.js', import.meta.url), 'utf8'), g);

  const utf8Vibe = {
    id: 'multilingual-vibe',
    name: '\u78c1\u76d8\u76d1\u63a7 \ud83d\udcca',
    wish: '\u663e\u793a\u6700\u8fd1\u7684\u670d\u52a1\u5668 \u0627\u0644\u062e\u0627\u062f\u0645',
    version: 1,
    needs: [],
    source: 'function invoke(input) { return { state: null, view: { type: "text", text: "\u0645\u0631\u062d\u0628\u0627 \ud83c\udf10" } }; }'
  };
  const encoded = g.VibeKit.share.encode(utf8Vibe);
  const decoded = g.VibeKit.share.decode(encoded);
  assert.equal(decoded.name, utf8Vibe.name);
  assert.equal(decoded.wish, utf8Vibe.wish);

  const adapted = g.VibeKit.adaptUi({ type: 'AdaptiveCard', body: [{ type: 'TextBlock', text: 'From AC' }] });
  assert.equal(adapted.type, 'column');
  assert.equal(adapted.children[0].text, 'From AC');
  assert.equal(g.VibeKit.adapters.isRtlLocale('ar'), true);

  // Verify vibespace.js mounts RTL Arabic panel and default English panel cleanly
  function makeDomNode(tag) {
    const node = {
      tagName: tag.toUpperCase(),
      attributes: {},
      children: [],
      style: {},
      className: '',
      hidden: false,
      firstChild: null,
      textContent: '',
      classList: { add() {}, remove() {}, toggle() {} },
      setAttribute(k, v) { this.attributes[k] = String(v); },
      getAttribute(k) { return this.attributes[k] || null; },
      appendChild(c) {
        c.parentNode = this;
        this.children.push(c);
        this.firstChild = this.children[0] || null;
        return c;
      },
      removeChild(c) {
        const idx = this.children.indexOf(c);
        if (idx >= 0) this.children.splice(idx, 1);
        this.firstChild = this.children[0] || null;
      },
      addEventListener() {}
    };
    return node;
  }
  g.document = {
    createElement: tag => makeDomNode(tag),
    createElementNS: (_ns, tag) => makeDomNode(tag),
    createTextNode: txt => ({ textContent: txt, parentNode: null }),
    addEventListener() {},
    removeEventListener() {},
    body: makeDomNode('body'),
    activeElement: null
  };
  vm.runInContext(fs.readFileSync(new URL('../demo/kit/vibespace.js', import.meta.url), 'utf8'), g);

  const arHost = g.VibeKit.createHost({ id: 'rtl-host', name: 'HostAR', capabilities: [], locale: 'ar' });
  const arTarget = makeDomNode('div');
  const arPanel = g.VibeSpace.mountPanel(arHost, arTarget, { wishes: [], gallery: [] });
  assert.equal(arTarget.children[0].getAttribute('dir'), 'rtl');
  assert.equal(arTarget.children[0].children[0].children[0].textContent, '\u0645\u0633\u0627\u062d\u0629 Vibe');
  arPanel.stop();

  const enHost = g.VibeKit.createHost({ id: 'en-host', name: 'HostEN', capabilities: [] });
  const enTarget = makeDomNode('div');
  const enPanel = g.VibeSpace.mountPanel(enHost, enTarget, { wishes: [], gallery: [] });
  assert.equal(enTarget.children[0].getAttribute('dir'), null);
  assert.equal(enTarget.children[0].children[0].children[0].textContent, 'Vibe Space');
  enPanel.stop();
});
