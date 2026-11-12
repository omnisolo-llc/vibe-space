import { launchChromium, loadPlaywright, startDemoServer } from './server.mjs';

function assert(cond, msg) {
  if (!cond) {
    throw new Error(msg);
  }
}

async function main() {
  const { chromium } = await loadPlaywright();

  const blankHtml = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>SafeHostTitle</title>
  <script src="/kit/vibekit.js"></script>
</head>
<body>
  <div id="stage"></div>
  <script>
    window.__pwnedMessages = [];
    window.__alertCalls = [];
    window.__hostPageErrors = [];
    window.addEventListener('error', function(e) { window.__hostPageErrors.push(e.message || 'error'); });
    window.addEventListener('unhandledrejection', function(e) { window.__hostPageErrors.push(String(e.reason || 'rejection')); });
    window.alert = function(msg) { window.__alertCalls.push(String(msg)); };
    window.addEventListener('message', function(ev) {
      if (typeof ev.data === 'string' && ev.data.includes('pwned')) {
        window.__pwnedMessages.push(ev.data);
      } else if (ev.data && typeof ev.data === 'object' && JSON.stringify(ev.data).includes('pwned')) {
        window.__pwnedMessages.push(JSON.stringify(ev.data));
      }
    });
  </script>
</body>
</html>`;

  const uiHtml = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>SafeUIHostTitle</title>
  <link rel="stylesheet" href="/kit/vibespace.css">
  <script src="/kit/vibekit.js"></script>
  <script src="/kit/vibespace.js"></script>
</head>
<body><div id="vs"></div></body>
</html>`;

  const server = await startDemoServer({
    '/__hostile.html': {
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: blankHtml,
    },
    '/__hostile_ui.html': {
      status: 200,
      contentType: 'text/html; charset=utf-8',
      body: uiHtml,
    },
  });

  const browser = await launchChromium(chromium);
  const results = [];

  function record(id, name, pass, detail = '') {
    results.push({ id, name, pass, detail });
    const tag = pass ? 'PASS' : 'FAIL';
    console.log(`[${tag}] ${id}: ${name}${detail ? ' — ' + detail : ''}`);
  }

  try {
    const context = await browser.newContext();
    const page = await context.newPage();

    const pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));

    await page.goto(`${server.baseUrl}/__hostile.html`, { waitUntil: 'networkidle' });

    // Verify VibeKit exists and set host secrets in storage, cookie, indexedDB
    await page.evaluate(async () => {
      localStorage.setItem('host_secret', 'ls_secret_value');
      sessionStorage.setItem('host_secret', 'ss_secret_value');
      document.cookie = 'host_cookie=cookie_secret_value; path=/';

      await new Promise((resolve) => {
        const req = indexedDB.open('host_secret_db', 1);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains('secrets')) {
            db.createObjectStore('secrets');
          }
        };
        req.onsuccess = () => {
          const tx = req.result.transaction('secrets', 'readwrite');
          tx.objectStore('secrets').put('idb_secret_value', 'k1');
          tx.oncomplete = () => {
            req.result.close();
            resolve();
          };
          tx.onerror = () => resolve();
        };
        req.onerror = () => resolve();
      });

      window.__host = window.VibeKit.createHost({
        id: 'hostile-test-host',
        name: 'HostileTestHost',
        capabilities: [
          {
            name: 'secrets.servers',
            title: 'Server list',
            fields: { name: 'sealed', load: 'public' },
            sealedNote: 'server names stay sealed',
            sealedCannot: 'See server names',
            read: () => [
              { name: 'top-secret-db-01.internal', load: 0.91 },
              { name: 'classified-auth-02.internal', load: 0.42 },
            ],
            sample: [
              { name: 'sample-secret-a', load: 0.5 },
            ],
          },
        ],
        notOffered: ['Use the internet'],
      });
      // Populate handle table in localStorage
      window.__sealedOne = window.__host.seal('top-secret-db-01.internal');
      window.__sealedTwo = window.__host.seal('classified-auth-02.internal');
    });

    async function mountVibe(id, vibeSpec, waitMs = 800) {
      return await page.evaluate(async ({ id, vibeSpec, waitMs }) => {
        const stage = document.getElementById('stage');
        const box = document.createElement('div');
        box.id = 'box-' + id;
        stage.appendChild(box);
        let updates = 0;
        const run = window.__host.mount(vibeSpec, box, {
          data: 'live',
          onUpdate: () => { updates += 1; },
        });
        window.__runs = window.__runs || {};
        window.__runs[id] = run;

        const deadline = Date.now() + waitMs;
        while (Date.now() < deadline) {
          if (box.children.length > 0 || (run.ledger && run.ledger().lastError)) {
            // give a brief moment for any async settle
            await new Promise((r) => setTimeout(r, 150));
            break;
          }
          await new Promise((r) => setTimeout(r, 40));
        }

        return {
          html: box.innerHTML,
          text: box.textContent,
          hasErrorNode: !!box.querySelector('.vk-error'),
          ledger: run.ledger(),
          inspect: run.inspect(),
          updates,
          title: document.title,
        };
      }, { id, vibeSpec, waitMs });
    }

    async function stopRun(id) {
      await page.evaluate((id) => {
        if (window.__runs && window.__runs[id]) {
          window.__runs[id].stop();
        }
      }, id);
    }

    // a. Network exfiltration attempts: fetch, Image, sendBeacon
    try {
      server.clearLeaks();
      const absLeak = `${server.baseUrl}/leak`;
      const vibeA = {
        id: 'hostile-a-net',
        name: 'Hostile Network',
        wish: 'leak data',
        version: 1,
        needs: ['secrets.servers'],
        source: `(function invoke(input) {
          var notes = [];
          try {
            if (typeof fetch === 'function') {
              Promise.resolve(fetch(${JSON.stringify(absLeak + '?via=fetch-abs')})).catch(function () {});
              Promise.resolve(fetch('/leak?via=fetch-rel')).catch(function () {});
              notes.push('fetch-called');
            } else { notes.push('no-fetch'); }
          } catch (e) { notes.push('fetch-err:' + e.name); }
          try {
            if (typeof Image === 'function') {
              var im = new Image();
              im.src = ${JSON.stringify(absLeak + '?via=img-abs')};
              var im2 = new Image();
              im2.src = '/leak?via=img-rel';
              notes.push('img-called');
            } else { notes.push('no-img'); }
          } catch (e) { notes.push('img-err:' + e.name); }
          try {
            if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
              var b1 = navigator.sendBeacon(${JSON.stringify(absLeak + '?via=beacon-abs')}, 'leak');
              var b2 = navigator.sendBeacon('/leak?via=beacon-rel', 'leak');
              notes.push('beacon:' + b1 + ',' + b2);
            } else { notes.push('no-beacon'); }
          } catch (e) { notes.push('beacon-err:' + e.name); }
          try {
            if (typeof XMLHttpRequest === 'function') {
              var x = new XMLHttpRequest();
              x.open('GET', ${JSON.stringify(absLeak + '?via=xhr-abs')}, true);
              x.send();
              notes.push('xhr-called');
            } else { notes.push('no-xhr'); }
          } catch (e) { notes.push('xhr-err:' + e.name); }
          try {
            var fnSelf = Function('return this')();
            if (fnSelf) {
              var proto = Object.getPrototypeOf(fnSelf);
              if (proto && typeof proto.fetch === 'function') {
                Promise.resolve(proto.fetch.call(fnSelf, ${JSON.stringify(absLeak + '?via=proto-fetch')})).catch(function () {});
                notes.push('proto-fetch-called');
              }
            }
          } catch (e) { notes.push('proto-fetch-err:' + e.name); }
          return { state: null, view: { type: 'text', text: notes.join('|') } };
        })`,
      };
      const resA = await mountVibe('a', vibeA, 1500);
      await new Promise((r) => setTimeout(r, 500));
      await stopRun('a');
      assert(server.leaks.length === 0, `Server recorded ${server.leaks.length} leak requests: ${JSON.stringify(server.leaks)}`);
      record('a', 'Network isolation (fetch, Image, sendBeacon, XHR)', true, `leaks=0, outcome=${resA.text || resA.ledger.lastError}`);
    } catch (err) {
      record('a', 'Network isolation (fetch, Image, sendBeacon, XHR)', false, err.message);
    }

    // b. Reading parent.document, top.location or window.frameElement
    try {
      const vibeB = {
        id: 'hostile-b-dom',
        name: 'Hostile DOM Escape',
        wish: 'read parent',
        version: 1,
        needs: [],
        source: `(function invoke(input) {
          var out = {};
          try { out.parentDoc = (typeof parent !== 'undefined' && parent && parent.document) ? String(parent.document.title) : 'blocked-or-undef'; }
          catch (e) { out.parentDoc = 'threw:' + e.name; }
          try { if (typeof parent !== 'undefined' && parent && parent.document) parent.document.title = 'PWNED'; }
          catch (e) { out.parentWrite = 'threw:' + e.name; }
          try { out.topLoc = (typeof top !== 'undefined' && top && top.location) ? String(top.location.href) : 'blocked-or-undef'; }
          catch (e) { out.topLoc = 'threw:' + e.name; }
          try { out.frameEl = (typeof window !== 'undefined' && window.frameElement) ? String(window.frameElement.tagName) : 'null-or-undef'; }
          catch (e) { out.frameEl = 'threw:' + e.name; }
          return { state: null, view: { type: 'text', text: JSON.stringify(out) } };
        })`,
      };
      const resB = await mountVibe('b', vibeB, 1500);
      await stopRun('b');
      assert(resB.title === 'SafeHostTitle', `Page title changed to "${resB.title}"`);
      if (!resB.hasErrorNode && resB.text) {
        const parsed = JSON.parse(resB.text);
        assert(parsed.parentDoc === 'blocked-or-undef' || parsed.parentDoc.startsWith('threw:'), `parent.document leaked: ${parsed.parentDoc}`);
        assert(parsed.topLoc === 'blocked-or-undef' || parsed.topLoc.startsWith('threw:'), `top.location leaked: ${parsed.topLoc}`);
        assert(parsed.frameEl === 'null-or-undef' || parsed.frameEl.startsWith('threw:'), `frameElement leaked: ${parsed.frameEl}`);
      }
      record('b', 'DOM isolation (parent.document, top.location, frameElement)', true, `title=${resB.title}, info=${resB.text || resB.ledger.lastError}`);
    } catch (err) {
      record('b', 'DOM isolation (parent.document, top.location, frameElement)', false, err.message);
    }

    // c. Storage and cookies
    try {
      const vibeC = {
        id: 'hostile-c-storage',
        name: 'Hostile Storage',
        wish: 'read storage',
        version: 1,
        needs: [],
        source: `(function invoke(input) {
          var out = {};
          try { out.ls = typeof localStorage === 'undefined' ? 'undef' : JSON.stringify({ len: localStorage.length, secret: localStorage.getItem('host_secret'), handles: localStorage.getItem('vibekit:hostile-test-host:handles') }); }
          catch (e) { out.ls = 'threw:' + e.name; }
          try { out.ss = typeof sessionStorage === 'undefined' ? 'undef' : JSON.stringify({ len: sessionStorage.length, secret: sessionStorage.getItem('host_secret') }); }
          catch (e) { out.ss = 'threw:' + e.name; }
          try { out.cookie = typeof document === 'undefined' ? 'undef' : String(document.cookie); }
          catch (e) { out.cookie = 'threw:' + e.name; }
          try {
            if (typeof indexedDB === 'undefined') { out.idb = 'undef'; }
            else {
              var req = indexedDB.open('host_secret_db', 1);
              out.idb = 'opened-request';
            }
          } catch (e) { out.idb = 'threw:' + e.name; }
          return { state: null, view: { type: 'text', text: JSON.stringify(out) } };
        })`,
      };
      const resC = await mountVibe('c', vibeC, 1500);
      await stopRun('c');
      assert(!resC.text.includes('ls_secret_value'), 'localStorage secret leaked');
      assert(!resC.text.includes('ss_secret_value'), 'sessionStorage secret leaked');
      assert(!resC.text.includes('cookie_secret_value'), 'cookie secret leaked');
      assert(!resC.text.includes('top-secret-db-01.internal'), 'handle table secret leaked');
      if (!resC.hasErrorNode && resC.text) {
        const parsed = JSON.parse(resC.text);
        assert(parsed.ls === 'undef' || parsed.ls.startsWith('threw:') || parsed.ls === '{"len":0,"secret":null,"handles":null}', `localStorage accessible: ${parsed.ls}`);
        assert(parsed.ss === 'undef' || parsed.ss.startsWith('threw:') || parsed.ss === '{"len":0,"secret":null}', `sessionStorage accessible: ${parsed.ss}`);
        assert(parsed.cookie === 'undef' || parsed.cookie.startsWith('threw:') || parsed.cookie === '', `cookie accessible: ${parsed.cookie}`);
        assert(parsed.idb === 'undef' || parsed.idb.startsWith('threw:'), `indexedDB accessible: ${parsed.idb}`);
      }
      record('c', 'Storage/cookie isolation (localStorage, sessionStorage, indexedDB, cookie)', true, `info=${resC.text || resC.ledger.lastError}`);
    } catch (err) {
      record('c', 'Storage/cookie isolation (localStorage, sessionStorage, indexedDB, cookie)', false, err.message);
    }

    // d. Endless loop while (true) {}
    try {
      const loopRes = await page.evaluate(async () => {
        const stage = document.getElementById('stage');
        const box = document.createElement('div');
        box.id = 'box-d';
        stage.appendChild(box);

        const ticks = [];
        const iv = setInterval(() => ticks.push(Date.now()), 50);
        const start = Date.now();
        let timerFiredMs = null;
        setTimeout(() => { timerFiredMs = Date.now() - start; }, 100);

        const vibeD = {
          id: 'hostile-d-loop',
          name: 'Endless Loop',
          wish: 'hang forever',
          version: 1,
          needs: [],
          source: '(function invoke(input) { while (true) {} })',
        };
        const run = window.__host.mount(vibeD, box, { data: 'live' });

        let errAppearedAt = null;
        while (Date.now() - start < 3500) {
          if (box.querySelector('.vk-error') && run.ledger().lastError) {
            errAppearedAt = Date.now() - start;
            break;
          }
          await new Promise((r) => setTimeout(r, 50));
        }

        clearInterval(iv);
        let maxGap = 0;
        for (let i = 1; i < ticks.length; i++) {
          maxGap = Math.max(maxGap, ticks[i] - ticks[i - 1]);
        }
        run.stop();
        return {
          timerFiredMs,
          ticksCount: ticks.length,
          maxGap,
          errAppearedAt,
          hasErrorNode: !!box.querySelector('.vk-error'),
          lastError: run.ledger().lastError,
        };
      });
      assert(loopRes.timerFiredMs !== null && loopRes.timerFiredMs < 3000, `Page timer did not fire within 3s (timerFiredMs=${loopRes.timerFiredMs})`);
      assert(loopRes.hasErrorNode, 'No .vk-error element rendered after timeout');
      assert(!!loopRes.lastError, 'ledger.lastError not recorded after timeout');
      record('d', 'Infinite loop termination & page responsiveness', true, `timerFired=${loopRes.timerFiredMs}ms, errAt=${loopRes.errAppearedAt}ms, maxGap=${loopRes.maxGap}ms`);
    } catch (err) {
      record('d', 'Infinite loop termination & page responsiveness', false, err.message);
    }

    // e. Output larger than 64 kB
    try {
      const vibeE = {
        id: 'hostile-e-oversize',
        name: 'Oversize Output',
        wish: 'huge output',
        version: 1,
        needs: [],
        source: `(function invoke(input) {
          return { state: null, view: { type: 'text', text: 'Z'.repeat(70000) } };
        })`,
      };
      const resE = await mountVibe('e', vibeE, 1500);
      const renderedPayload = await page.evaluate(() => {
        const box = document.getElementById('box-e');
        return {
          nonErrorNodes: box.querySelectorAll('.vk-text, .vk-column, .vk-heading, .vk-card').length,
          hasBigZ: box.textContent.includes('ZZZZZZZZZZ'),
        };
      });
      await stopRun('e');
      assert(resE.hasErrorNode, 'Oversized output did not render .vk-error');
      assert(!!resE.ledger.lastError, 'Oversized output did not set ledger.lastError');
      assert(renderedPayload.nonErrorNodes === 0 && !renderedPayload.hasBigZ, 'Oversized output still rendered non-error content');
      record('e', 'Output > 64 kB rejected safely', true, `lastError=${resE.ledger.lastError}`);
    } catch (err) {
      record('e', 'Output > 64 kB rejected safely', false, err.message);
    }

    // f. Script tag breakout
    try {
      const vibeF1 = {
        id: 'hostile-f1-breakout',
        name: 'Script Breakout String',
        wish: 'break out',
        version: 1,
        needs: [],
        source: '(function invoke(input) { var x = "</script><script>parent.postMessage(\\"pwned\\",\\"*\\")</script>"; return { state: null, view: { type: "text", text: "f1-safe" } }; })',
      };
      const vibeF2 = {
        id: 'hostile-f2-breakout',
        name: 'Script Breakout Raw',
        wish: 'break out raw',
        version: 1,
        needs: [],
        source: 'function invoke(input) { </script><script>parent.postMessage("pwned","*")</script> return { state: null, view: { type: "text", text: "f2-bad" } }; }',
      };
      const resF1 = await mountVibe('f1', vibeF1, 1500);
      const resF2 = await mountVibe('f2', vibeF2, 1500);
      await new Promise((r) => setTimeout(r, 300));
      await stopRun('f1');
      await stopRun('f2');
      const pwned = await page.evaluate(() => window.__pwnedMessages);
      assert(pwned.length === 0, `Received pwned postMessage: ${JSON.stringify(pwned)}`);
      assert(resF2.hasErrorNode || !resF2.text.includes('f2-bad'), 'Invalid breakout source rendered unexpectedly');
      record('f', 'Script tag breakout prevention', true, `pwnedMessages=0, f1=${resF1.text || resF1.ledger.lastError}, f2Err=${resF2.hasErrorNode}`);
    } catch (err) {
      record('f', 'Script tag breakout prevention', false, err.message);
    }

    // g. XSS markup in view text
    try {
      const xss = '<img src=x onerror=alert(1)>';
      const vibeG = {
        id: 'hostile-g-xss',
        name: 'Markup Injection',
        wish: 'inject html',
        version: 1,
        needs: [],
        source: `(function invoke(input) {
          var p = ${JSON.stringify(xss)};
          return {
            state: null,
            view: {
              type: 'column',
              children: [
                { type: 'heading', text: p },
                { type: 'text', text: p },
                { type: 'badge', text: '<svg onload=alert(1)>' },
                { type: 'bar', label: p, value: 0.5, caption: '<b>bold</b>' },
                { type: 'table', headers: ['<i>H</i>'], rows: [[p]] }
              ]
            }
          };
        })`,
      };
      const resG = await mountVibe('g', vibeG, 1500);
      const domCheck = await page.evaluate(() => {
        const box = document.getElementById('box-g');
        return {
          badElements: box.querySelectorAll('img, svg, b, i, script, iframe').length,
          alerts: window.__alertCalls.length,
        };
      });
      await stopRun('g');
      assert(!resG.hasErrorNode, `Valid text node errored: ${resG.ledger.lastError}`);
      assert(domCheck.badElements === 0, `Created ${domCheck.badElements} injected HTML elements`);
      assert(domCheck.alerts === 0, `alert() was called ${domCheck.alerts} times`);
      assert(resG.text.includes(xss), `Literal text "${xss}" missing from output: ${resG.text}`);
      record('g', 'HTML/XSS markup rendered as literal text', true, `badElements=0, alerts=0`);
    } catch (err) {
      record('g', 'HTML/XSS markup rendered as literal text', false, err.message);
    }

    // h. Fake / prototype sealed handles
    try {
      const vibeH = {
        id: 'hostile-h-fake-handle',
        name: 'Fake Handle',
        wish: 'forge handle',
        version: 1,
        needs: ['secrets.servers'],
        source: `(function invoke(input) {
          return {
            state: null,
            view: {
              type: 'column',
              children: [
                { type: 'text', text: { sealed: 'h_fake' } },
                { type: 'bar', label: { sealed: 'h_fake_999' }, value: 0.5, caption: { sealed: 'toString' } },
                { type: 'table', headers: [''], rows: [[{ sealed: 'constructor' }], [{ sealed: '__proto__' }]] }
              ]
            }
          };
        })`,
      };
      const resH = await mountVibe('h', vibeH, 1500);
      const directRender = await page.evaluate(() => {
        const tmp = document.createElement('div');
        window.VibeKit.renderView(
          { type: 'text', text: { sealed: 'h_fake' } },
          tmp,
          { resolve: (h) => window.__host && null }
        );
        return tmp.textContent;
      });
      await stopRun('h');
      assert(!resH.hasErrorNode, `Vibe H errored: ${resH.ledger.lastError}`);
      assert(!resH.text.includes('top-secret-db-01.internal'), 'Real secret 1 leaked via fake handle');
      assert(!resH.text.includes('classified-auth-02.internal'), 'Real secret 2 leaked via fake handle');
      assert(!resH.text.includes('h_fake'), 'Raw handle string h_fake rendered');
      assert(!resH.text.includes('undefined') && !resH.text.includes('[object Object]') && !resH.text.includes('function'), `Unexpected leaked text in fake handle view: "${resH.text}"`);
      assert(resH.text.trim() === '', `Fake handles rendered non-empty text: "${resH.text}"`);
      assert(directRender === '', `Direct renderView rendered "${directRender}"`);
      record('h', 'Fake/unknown sealed handles render nothing', true, `renderedText="${resH.text}"`);
    } catch (err) {
      record('h', 'Fake/unknown sealed handles render nothing', false, err.message);
    }

    // i. Input never contains real sealed field value
    try {
      const vibeI = {
        id: 'hostile-i-inspect-input',
        name: 'Input Leak Check',
        wish: 'stringify input',
        version: 1,
        needs: ['secrets.servers'],
        source: `(function invoke(input) {
          return { state: null, view: { type: 'text', text: JSON.stringify(input) } };
        })`,
      };
      const resI = await mountVibe('i', vibeI, 1500);
      const sealCheck = await page.evaluate(() => ({
        h1: window.__host.seal('top-secret-db-01.internal'),
        h2: window.__host.seal('classified-auth-02.internal'),
      }));
      await stopRun('i');
      assert(!resI.hasErrorNode, `Vibe I errored: ${resI.ledger.lastError}`);
      assert(!resI.text.includes('top-secret-db-01.internal'), 'Real sealed value 1 found in vibe input JSON!');
      assert(!resI.text.includes('classified-auth-02.internal'), 'Real sealed value 2 found in vibe input JSON!');
      const parsedInput = JSON.parse(resI.text);
      const rows = parsedInput.data && parsedInput.data['secrets.servers'];
      assert(Array.isArray(rows) && rows.length === 2, 'Expected 2 rows in input.data["secrets.servers"]');
      assert(rows[0].name && typeof rows[0].name.sealed === 'string' && rows[0].name.sealed === sealCheck.h1.sealed, 'Sealed handle mismatch for row 0');
      assert(rows[1].name && typeof rows[1].name.sealed === 'string' && rows[1].name.sealed === sealCheck.h2.sealed, 'Sealed handle mismatch for row 1');
      assert(rows[0].load === 0.91, 'Public field load was altered');
      assert(!JSON.stringify(resI.inspect.input).includes('top-secret-db-01.internal'), 'run.inspect().input exposed real value');
      record('i', 'Sealed values never enter sandbox input', true, `handles=${rows[0].name.sealed}, ${rows[1].name.sealed}`);
    } catch (err) {
      record('i', 'Sealed values never enter sandbox input', false, err.message);
    }

    // j. Global escape location.href / location.assign (j1 normal, j2 no-Worker fail-closed)
    try {
      server.clearLeaks();
      const absLeak = `${server.baseUrl}/leak`;
      const vibeJ1 = {
        id: 'hostile-j1-loc',
        name: 'Hostile Location Escape',
        wish: 'navigate to leak',
        version: 1,
        needs: ['secrets.servers'],
        source: `(function invoke(input) {
          var notes = [];
          try {
            var g = Function('return this')();
            try {
              g.location.href = ${JSON.stringify(absLeak + '?via=j1-href&d=')} + encodeURIComponent(JSON.stringify(input.data));
              notes.push('href-set');
            } catch (e) { notes.push('href-err:' + e.name); }
            try {
              g.location.assign(${JSON.stringify(absLeak + '?via=j1-assign')});
              notes.push('assign-called');
            } catch (e) { notes.push('assign-err:' + e.name); }
          } catch (e) { notes.push('fn-err:' + e.name); }
          return { state: null, view: { type: 'text', text: notes.join('|') } };
        })`,
      };
      const resJ1 = await mountVibe('j1', vibeJ1, 1500);
      await new Promise((r) => setTimeout(r, 500));
      await stopRun('j1');
      assert(server.leaks.length === 0, `j1 leaked ${server.leaks.length} requests: ${JSON.stringify(server.leaks)}`);

      // j2: Browser context where Worker is unavailable inside sub-frames -> must fail closed
      const noWorkerCtx = await browser.newContext();
      try {
        await noWorkerCtx.addInitScript(() => {
          if (window.parent !== window) {
            try { delete window.Worker; } catch (_) {}
            try { Object.defineProperty(window, 'Worker', { value: undefined, writable: true, configurable: true }); }
            catch (_) { window.Worker = undefined; }
          }
        });
        const nwPage = await noWorkerCtx.newPage();
        await nwPage.goto(`${server.baseUrl}/__hostile.html`, { waitUntil: 'networkidle' });
        const resJ2 = await nwPage.evaluate(async (leakBase) => {
          const host = window.VibeKit.createHost({
            id: 'hostile-nw-host',
            name: 'NoWorkerHost',
            capabilities: [
              {
                name: 'secrets.servers',
                title: 'Server list',
                fields: { name: 'sealed', load: 'public' },
                read: () => [{ name: 'top-secret-db-01.internal', load: 0.91 }],
                sample: [{ name: 'sample-a', load: 0.5 }],
              },
            ],
            notOffered: ['Use the internet'],
          });
          const box = document.createElement('div');
          document.getElementById('stage').appendChild(box);
          const vibe = {
            id: 'hostile-j2-noworker',
            name: 'NoWorker Probe',
            wish: 'leak without worker',
            version: 1,
            needs: ['secrets.servers'],
            source: `(function invoke(input) {
              try {
                Function('return this')().location.href = ${JSON.stringify(leakBase + '?via=j2-noworker&d=')} + encodeURIComponent(JSON.stringify(input.data));
              } catch (e) {}
              return { state: null, view: { type: 'text', text: 'ran-without-worker' } };
            })`,
          };
          const run = host.mount(vibe, box, { data: 'live' });
          const deadline = Date.now() + 6000;
          while (Date.now() < deadline) {
            if (box.querySelector('.vk-error') || box.textContent.includes('ran-without-worker')) {
              await new Promise((r) => setTimeout(r, 200));
              break;
            }
            await new Promise((r) => setTimeout(r, 50));
          }
          const out = {
            hasErrorNode: !!box.querySelector('.vk-error'),
            text: box.textContent,
            ledger: run.ledger(),
          };
          run.stop();
          return out;
        }, absLeak);
        await nwPage.close();
        assert(server.leaks.length === 0, `j2 (no Worker) leaked ${server.leaks.length} requests: ${JSON.stringify(server.leaks)}`);
        assert(!resJ2.text.includes('ran-without-worker'), 'j2 vibe ran in iframe fallback instead of failing closed');
        assert(resJ2.hasErrorNode, `j2 did not render .vk-error (text=${resJ2.text})`);
        assert(!!resJ2.ledger.lastError, 'j2 did not record ledger.lastError');
        record('j', 'Location escape & fail-closed without Worker (j1, j2)', true, `j1=${resJ1.text || resJ1.ledger.lastError}, j2Err="${resJ2.ledger.lastError}"`);
      } finally {
        await noWorkerCtx.close();
      }
    } catch (err) {
      record('j', 'Location escape & fail-closed without Worker (j1, j2)', false, err.message);
    }

    // k. Round-2 management & code-edit hostile paths (XSS title/note, sandbox isolation, updateRecord hostile code)
    try {
      server.clearLeaks();
      const absLeak = `${server.baseUrl}/leak`;
      const xssTitle = '<img src=x onerror=alert(1)>SecretTitleMeta';
      const xssNote = '<script>parent.postMessage("pwned","*")</script>SecretNoteMeta';

      const kInspect = await page.evaluate(async ({ xssTitle, xssNote }) => {
        const hostK = window.VibeKit.createHost({
          id: 'hostile-k-host',
          name: 'HostileKHost',
          capabilities: [
            {
              name: 'secrets.servers',
              title: 'Server list',
              fields: { name: 'sealed', load: 'public' },
              read: () => [{ name: 'top-secret-db-01.internal', load: 0.91 }],
              sample: [{ name: 'sample-a', load: 0.5 }],
            },
          ],
          notOffered: ['Use the internet'],
        });
        window.__hostK = hostK;

        const baseVibe = {
          id: 'hostile-k-vibe',
          name: 'K Test Vibe',
          wish: 'check input',
          version: 1,
          needs: ['secrets.servers'],
          source: '(function invoke(input) { return { state: null, view: { type: "text", text: JSON.stringify(input) } }; })',
        };
        const rec = hostK.install(baseVibe, { origin: 'yours', title: xssTitle, note: xssNote });
        window.__recK = rec;

        const encoded = window.VibeKit.share.encode(rec.vibe);
        const decoded = window.VibeKit.share.decode(encoded);

        // Verify updateRecord rejects unauthorized capability escalation
        let escalationRejected = false;
        try {
          hostK.updateRecord(rec.instanceId, {
            vibe: { ...rec.vibe, version: 2, needs: ['secrets.servers', 'forbidden.cap'] },
          });
        } catch (e) {
          escalationRejected = true;
        }

        const box = document.createElement('div');
        box.id = 'box-k1';
        document.getElementById('stage').appendChild(box);
        const run = hostK.mount(rec.vibe, box, { data: 'live' });
        const deadline = Date.now() + 2000;
        while (Date.now() < deadline) {
          if (box.children.length > 0 || run.ledger().lastError) {
            await new Promise((r) => setTimeout(r, 100));
            break;
          }
          await new Promise((r) => setTimeout(r, 40));
        }
        const text = box.textContent;
        const inspect = run.inspect();
        run.stop();
        return {
          rec,
          encoded,
          decodedKeys: Object.keys(decoded),
          escalationRejected,
          text,
          inspectInputStr: JSON.stringify(inspect.input),
        };
      }, { xssTitle, xssNote });

      assert(!kInspect.encoded.includes('SecretTitleMeta') && !kInspect.encoded.includes('SecretNoteMeta'), 'share.encode leaked record title/note');
      assert(!kInspect.decodedKeys.includes('title') && !kInspect.decodedKeys.includes('note'), 'share.decode included title/note');
      assert(!kInspect.text.includes('SecretTitleMeta') && !kInspect.text.includes('SecretNoteMeta'), 'sandbox input leaked record title/note into vibe');
      assert(!kInspect.inspectInputStr.includes('SecretTitleMeta') && !kInspect.inspectInputStr.includes('SecretNoteMeta'), 'run.inspect().input contained title/note');
      assert(kInspect.escalationRejected, 'updateRecord did not reject undeclared capability');

      // Test hostile edited code via updateRecord: (1) while(true){}, (2) fetch + location.href leak
      const kEdited = await page.evaluate(async (absLeak) => {
        const hostK = window.__hostK;
        const rec = window.__recK;

        const updatedLoop = hostK.updateRecord(rec.instanceId, {
          title: '<img src=x onerror=alert(1)>EditedLoopTitle',
          note: '<svg onload=alert(1)>EditedNote',
          vibe: {
            ...rec.vibe,
            version: 2,
            source: '(function invoke(input) { while (true) {} })',
          },
        });

        const boxLoop = document.createElement('div');
        boxLoop.id = 'box-k-loop';
        document.getElementById('stage').appendChild(boxLoop);
        const start = Date.now();
        let timerFiredMs = null;
        setTimeout(() => { timerFiredMs = Date.now() - start; }, 100);

        const runLoop = hostK.mount(updatedLoop.vibe, boxLoop, { data: 'live' });
        while (Date.now() - start < 6000) {
          if (boxLoop.querySelector('.vk-error') && runLoop.ledger().lastError) break;
          await new Promise((r) => setTimeout(r, 50));
        }
        const loopErr = !!boxLoop.querySelector('.vk-error');
        const loopLastErr = runLoop.ledger().lastError;
        runLoop.stop();

        const updatedLeak = hostK.updateRecord(rec.instanceId, {
          vibe: {
            ...rec.vibe,
            version: 3,
            source: `(function invoke(input) {
              try { Promise.resolve(fetch(${JSON.stringify(absLeak + '?via=k-edit-fetch')})).catch(function(){}); } catch (e) {}
              try { Function('return this')().location.href = ${JSON.stringify(absLeak + '?via=k-edit-loc')}; } catch (e) {}
              return { state: null, view: { type: 'text', text: 'edited-leak-checked' } };
            })`,
          },
        });
        const boxLeak = document.createElement('div');
        boxLeak.id = 'box-k-leak';
        document.getElementById('stage').appendChild(boxLeak);
        const runLeak = hostK.mount(updatedLeak.vibe, boxLeak, { data: 'live' });
        const d2 = Date.now() + 2000;
        while (Date.now() < d2) {
          if (boxLeak.children.length > 0 || runLeak.ledger().lastError) {
            await new Promise((r) => setTimeout(r, 200));
            break;
          }
          await new Promise((r) => setTimeout(r, 40));
        }
        const leakText = boxLeak.textContent;
        runLeak.stop();

        return { timerFiredMs, loopErr, loopLastErr, leakText };
      }, absLeak);

      await new Promise((r) => setTimeout(r, 300));
      assert(kEdited.timerFiredMs !== null && kEdited.timerFiredMs < 3000, `Page froze on edited while(true): ${kEdited.timerFiredMs}`);
      assert(kEdited.loopErr && !!kEdited.loopLastErr, 'Edited while(true) did not produce .vk-error and lastError');
      assert(server.leaks.length === 0, `Edited vibe leaked ${server.leaks.length} requests: ${JSON.stringify(server.leaks)}`);

      // Test VibeSpace UI renders XSS title/note safely as textContent (zero DOM injection / alert)
      const uiPage = await context.newPage();
      try {
        await uiPage.goto(`${server.baseUrl}/__hostile_ui.html`, { waitUntil: 'networkidle' });
        const uiRes = await uiPage.evaluate(async ({ xssTitle, xssNote }) => {
          window.__xssAlerts = 0;
          window.alert = () => { window.__xssAlerts += 1; };
          const h = window.VibeKit.createHost({
            id: 'hostile-k-ui',
            name: 'UIHost',
            capabilities: [],
            notOffered: [],
          });
          h.install({
            id: 'k-ui-vibe',
            name: 'Safe Name',
            wish: 'hi',
            version: 1,
            needs: [],
            source: '(function invoke() { return { state: null, view: { type: "text", text: "ok" } }; })',
          }, { origin: 'yours', title: xssTitle, note: xssNote });
          window.VibeSpace.mountPanel(h, document.getElementById('vs'), { wishes: [], gallery: [], shareTargets: [] });
          await new Promise((r) => setTimeout(r, 200));
          const root = document.getElementById('vs');
          const titleEl = root.querySelector('[data-vs="vibe-title"]');
          const noteEl = root.querySelector('[data-vs="vibe-note"]');
          return {
            badElements: root.querySelectorAll('img, script, iframe').length +
              (titleEl ? titleEl.querySelectorAll('img, script, svg, iframe').length : 0) +
              (noteEl ? noteEl.querySelectorAll('img, script, svg, iframe').length : 0),
            alerts: window.__xssAlerts,
            text: root.textContent,
          };
        }, { xssTitle, xssNote });
        assert(uiRes.badElements === 0, `VibeSpace created ${uiRes.badElements} injected elements from XSS title/note`);
        assert(uiRes.alerts === 0, `VibeSpace XSS title/note fired alert ${uiRes.alerts} times`);
        assert(uiRes.text.includes('<img src=x onerror=alert(1)>'), 'VibeSpace did not render XSS title as literal text');
      } finally {
        await uiPage.close();
      }

      const pwnedAfterK = await page.evaluate(() => window.__pwnedMessages);
      assert(pwnedAfterK.length === 0, `Case k caused pwned postMessage: ${JSON.stringify(pwnedAfterK)}`);
      record('k', 'Management/edit paths: title/note isolation, XSS escaping, hostile edited source', true, `loopErr=${kEdited.loopErr}, leaks=0, escalationRejected=true`);
    } catch (err) {
      record('k', 'Management/edit paths: title/note isolation, XSS escaping, hostile edited source', false, err.message);
    }

    // Check no uncaught host page errors escaped
    try {
      const hostErrs = await page.evaluate(() => window.__hostPageErrors);
      assert(hostErrs.length === 0, `Host window errors: ${hostErrs.join('; ')}`);
      assert(pageErrors.length === 0, `Uncaught page/worker errors: ${pageErrors.join('; ')}`);
      record('pageerrors', 'No uncaught host page exceptions', true, '0 pageerrors');
    } catch (err) {
      record('pageerrors', 'No uncaught host page exceptions', false, err.message);
    }

    const failed = results.filter((r) => !r.pass);
    console.log(`\nSummary: ${results.length - failed.length}/${results.length} passed.`);
    if (failed.length > 0) {
      process.exitCode = 1;
    }
  } finally {
    await browser.close();
    await server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
