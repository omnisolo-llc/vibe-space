(function (global) {
  'use strict';

  var MAX_SHARE_BYTES = 32 * 1024;
  var MAX_OUTPUT_BYTES = 64 * 1024;
  var CALL_TIMEOUT_MS = 1000;
  var INIT_TIMEOUT_MS = 5000;
  var WORKER_BOOT_TIMEOUT_MS = 4000;
  var MAX_VIEW_DEPTH = 12;
  var MAX_VIEW_NODES = 400;
  var MAX_TABLE_ROWS = 200;
  var MAX_TABLE_COLS = 30;
  var MAX_TITLE_LEN = 120;
  var MAX_NOTE_LEN = 280;
  var MAX_HISTORY_ENTRIES = 10;
  var PROTOCOL_VERSION = 'vibeprotocol-demo/0';

  var VALID_TONES = new Set(['default', 'ok', 'warn', 'danger']);
  var VALID_ORIGINS = new Set(['yours', 'shared', 'gallery', 'agent']);
  var CONTAINER_TYPES = new Set(['column', 'row', 'card']);
  var ID_RE = /^[a-z0-9-]{1,40}$/;
  var HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;

  var renderStateMap = typeof WeakMap === 'function' ? new WeakMap() : null;

  function isPlainObject(val) {
    if (val === null || typeof val !== 'object' || Array.isArray(val)) return false;
    var proto = Object.getPrototypeOf(val);
    if (proto === null) return true;
    if (Object.getPrototypeOf(proto) !== null) return false;
    return Object.prototype.toString.call(val) === '[object Object]';
  }

  function hasOwn(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key);
  }

  function utf8ByteLength(str) {
    if (typeof TextEncoder !== 'undefined') {
      return new TextEncoder().encode(str).length;
    }
    var bytes = 0;
    for (var i = 0; i < str.length; i++) {
      var code = str.charCodeAt(i);
      if (code <= 0x7f) bytes += 1;
      else if (code <= 0x7ff) bytes += 2;
      else if (code >= 0xd800 && code <= 0xdbff) {
        bytes += 4;
        i += 1;
      } else bytes += 3;
    }
    return bytes;
  }

  function assertJsonSafe(val, seen) {
    if (val === null || typeof val === 'boolean' || typeof val === 'string') return;
    if (typeof val === 'number') {
      if (!Number.isFinite(val)) {
        throw new Error('Value must not contain NaN or Infinity');
      }
      return;
    }
    if (typeof val !== 'object') {
      throw new Error('Value is not JSON-safe (' + typeof val + ')');
    }
    if (!seen) seen = new Set();
    if (seen.has(val)) {
      throw new Error('Value must not contain circular references');
    }
    seen.add(val);
    if (Array.isArray(val)) {
      for (var i = 0; i < val.length; i++) {
        if (val[i] === undefined) {
          throw new Error('Arrays must not contain undefined');
        }
        assertJsonSafe(val[i], seen);
      }
    } else if (isPlainObject(val)) {
      var keys = Object.keys(val);
      for (var k = 0; k < keys.length; k++) {
        var key = keys[k];
        if (val[key] !== undefined) {
          assertJsonSafe(val[key], seen);
        }
      }
    } else {
      throw new Error('Value must contain only plain objects, arrays, and primitives');
    }
    seen.delete(val);
  }

  function jsonClone(val) {
    if (val === undefined) return undefined;
    if (val === null || typeof val !== 'object') return val;
    return JSON.parse(JSON.stringify(val));
  }

  function safeStorageGet(key) {
    try {
      if (typeof localStorage === 'undefined' || !localStorage) return null;
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function safeStorageSet(key, value) {
    try {
      if (typeof localStorage === 'undefined' || !localStorage) return false;
      localStorage.setItem(key, value);
      return true;
    } catch (e) {
      return false;
    }
  }

  function randomHandleId() {
    var bytes = new Uint8Array(8);
    if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
      crypto.getRandomValues(bytes);
    } else {
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = Math.floor(Math.random() * 256);
      }
    }
    var hex = '';
    for (var j = 0; j < bytes.length; j++) {
      var h = bytes[j].toString(16);
      hex += h.length === 1 ? '0' + h : h;
    }
    return 'h_' + hex;
  }

  function randomToken() {
    var bytes = new Uint8Array(12);
    if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
      crypto.getRandomValues(bytes);
    } else {
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = Math.floor(Math.random() * 256);
      }
    }
    var hex = '';
    for (var j = 0; j < bytes.length; j++) {
      var h = bytes[j].toString(16);
      hex += h.length === 1 ? '0' + h : h;
    }
    return hex;
  }

  function randomInstanceId() {
    var bytes = new Uint8Array(8);
    if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
      crypto.getRandomValues(bytes);
    } else {
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = Math.floor(Math.random() * 256);
      }
    }
    var hex = '';
    for (var j = 0; j < bytes.length; j++) {
      var h = bytes[j].toString(16);
      hex += h.length === 1 ? '0' + h : h;
    }
    return 'inst_' + hex;
  }

  function canonicalJsonString(val) {
    if (val === undefined || val === null) return 'null';
    if (typeof val !== 'object') return JSON.stringify(val);
    if (Array.isArray(val)) {
      var arrParts = [];
      for (var i = 0; i < val.length; i++) {
        arrParts.push(canonicalJsonString(val[i]));
      }
      return '[' + arrParts.join(',') + ']';
    }
    var keys = Object.keys(val).sort();
    var objParts = [];
    for (var k = 0; k < keys.length; k++) {
      var key = keys[k];
      if (val[key] !== undefined) {
        objParts.push(JSON.stringify(key) + ':' + canonicalJsonString(val[key]));
      }
    }
    return '{' + objParts.join(',') + '}';
  }

  function normalizeTitle(raw, fallback) {
    if (typeof raw !== 'string') return fallback;
    var trimmed = raw.trim();
    if (!trimmed) return fallback;
    return trimmed.slice(0, MAX_TITLE_LEN);
  }

  function normalizeNote(raw) {
    if (typeof raw !== 'string') return '';
    return raw.slice(0, MAX_NOTE_LEN);
  }

  function validateVibe(vibe) {
    if (!isPlainObject(vibe)) {
      throw new Error('Vibe package must be a plain object');
    }
    if (typeof vibe.id !== 'string' || !ID_RE.test(vibe.id)) {
      throw new Error('Vibe id must match ^[a-z0-9-]{1,40}$');
    }
    if (typeof vibe.name !== 'string' || vibe.name.trim().length === 0 || vibe.name.length > 120) {
      throw new Error('Vibe name must be a non-empty string (max 120 chars)');
    }
    if (vibe.wish !== undefined && typeof vibe.wish !== 'string') {
      throw new Error('Vibe wish must be a string when provided');
    }
    if (typeof vibe.version !== 'number' || !Number.isInteger(vibe.version) || vibe.version < 1) {
      throw new Error('Vibe version must be an integer >= 1');
    }
    if (!Array.isArray(vibe.needs)) {
      throw new Error('Vibe needs must be an array of capability names');
    }
    for (var i = 0; i < vibe.needs.length; i++) {
      var cap = vibe.needs[i];
      if (typeof cap !== 'string' || cap.trim().length === 0 || cap.length > 120) {
        throw new Error('Each capability in vibe.needs must be a non-empty string');
      }
    }
    if (vibe.refresh !== undefined && vibe.refresh !== null) {
      if (typeof vibe.refresh !== 'number' || !Number.isFinite(vibe.refresh) || vibe.refresh < 500) {
        throw new Error('Vibe refresh must be a number >= 500 ms');
      }
    }
    if (typeof vibe.source !== 'string' || vibe.source.trim().length === 0) {
      throw new Error('Vibe source must be a non-empty string');
    }
    if (utf8ByteLength(vibe.source) > MAX_OUTPUT_BYTES) {
      throw new Error('Vibe source exceeds 64 kB limit');
    }
    assertJsonSafe(vibe);
    return vibe;
  }

  function canonicalVibeCopy(vibe) {
    validateVibe(vibe);
    var copy = {
      id: vibe.id,
      name: vibe.name,
      wish: vibe.wish !== undefined ? vibe.wish : '',
      version: vibe.version,
      needs: vibe.needs.slice(),
      source: vibe.source
    };
    if (vibe.refresh !== undefined && vibe.refresh !== null) {
      copy.refresh = vibe.refresh;
    }
    return copy;
  }

  function toBase64Url(str) {
    var bytes;
    if (typeof TextEncoder !== 'undefined') {
      bytes = new TextEncoder().encode(str);
    } else {
      var utf8 = unescape(encodeURIComponent(str));
      bytes = new Uint8Array(utf8.length);
      for (var i = 0; i < utf8.length; i++) bytes[i] = utf8.charCodeAt(i);
    }
    var bin = '';
    for (var j = 0; j < bytes.length; j++) {
      bin += String.fromCharCode(bytes[j]);
    }
    var b64;
    if (typeof btoa === 'function') {
      b64 = btoa(bin);
    } else if (typeof Buffer !== 'undefined') {
      b64 = Buffer.from(bytes).toString('base64');
    } else {
      throw new Error('Base64 encoding unavailable');
    }
    return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function fromBase64Url(encoded) {
    if (typeof encoded !== 'string' || encoded.length === 0 || !/^[A-Za-z0-9_-]+$/.test(encoded)) {
      throw new Error('Invalid share link payload');
    }
    if (utf8ByteLength(encoded) > MAX_SHARE_BYTES) {
      throw new Error('Share payload exceeds 32 kB limit');
    }
    var padLen = encoded.length % 4;
    var std = encoded.replace(/-/g, '+').replace(/_/g, '/') + (padLen ? '='.repeat(4 - padLen) : '');
    var bytes;
    if (typeof atob === 'function') {
      var bin = atob(std);
      bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    } else if (typeof Buffer !== 'undefined') {
      bytes = new Uint8Array(Buffer.from(std, 'base64'));
    } else {
      throw new Error('Base64 decoding unavailable');
    }
    if (typeof TextDecoder !== 'undefined') {
      return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    }
    var str = '';
    for (var j = 0; j < bytes.length; j++) str += String.fromCharCode(bytes[j]);
    return decodeURIComponent(escape(str));
  }

  var share = {
    encode: function (vibe) {
      var clean = canonicalVibeCopy(vibe);
      var json = JSON.stringify(clean);
      var encoded = toBase64Url(json);
      if (utf8ByteLength(encoded) > MAX_SHARE_BYTES) {
        throw new Error('Encoded vibe exceeds 32 kB share limit');
      }
      return encoded;
    },
    decode: function (str) {
      var json = fromBase64Url(str);
      var parsed;
      try {
        parsed = JSON.parse(json);
      } catch (e) {
        throw new Error('Share link does not contain valid JSON');
      }
      validateVibe(parsed);
      return canonicalVibeCopy(parsed);
    }
  };

  function isSealedHandle(val) {
    if (!isPlainObject(val)) return false;
    var keys = Object.keys(val);
    return keys.length === 1 && keys[0] === 'sealed' && typeof val.sealed === 'string';
  }

  function callResolver(resolve, handleObj) {
    if (typeof resolve !== 'function') return undefined;
    var res;
    try {
      res = resolve(handleObj);
    } catch (e) {
      res = undefined;
    }
    if (res === undefined) {
      try {
        res = resolve(handleObj.sealed);
      } catch (e2) {
        res = undefined;
      }
    }
    if (typeof res === 'string') return res;
    if (typeof res === 'number' && Number.isFinite(res)) return String(res);
    return undefined;
  }

  function setSlotContent(el, val, resolve) {
    if (isSealedHandle(val)) {
      var resolved = callResolver(resolve, val);
      if (resolved === undefined) {
        if (el.childNodes.length > 0) el.textContent = '';
        return;
      }
      if (
        el.childNodes.length === 1 &&
        el.firstChild &&
        el.firstChild.nodeType === 1 &&
        el.firstChild.classList &&
        el.firstChild.classList.contains('vk-sealed')
      ) {
        if (el.firstChild.textContent !== resolved) {
          el.firstChild.textContent = resolved;
        }
        return;
      }
      var span = el.ownerDocument.createElement('span');
      span.className = 'vk-sealed';
      span.textContent = resolved;
      el.replaceChildren(span);
      return;
    }
    var text = '';
    if (typeof val === 'string') text = val;
    else if (typeof val === 'number' && Number.isFinite(val)) text = String(val);

    if (el.childNodes.length === 0 && text === '') return;
    if (el.childNodes.length === 1 && el.firstChild.nodeType === 3) {
      if (el.firstChild.nodeValue !== text) el.firstChild.nodeValue = text;
      return;
    }
    el.textContent = text;
  }

  function validToneClass(tone) {
    return typeof tone === 'string' && VALID_TONES.has(tone) ? 'vk-tone-' + tone : '';
  }

  function isValidSwatch(swatch) {
    return typeof swatch === 'string' && HEX_COLOR_RE.test(swatch);
  }

  function hasBarCaption(node) {
    return node.caption !== undefined && node.caption !== null;
  }

  function sparklinePoints(values) {
    if (!Array.isArray(values)) return '';
    var nums = [];
    for (var i = 0; i < values.length; i++) {
      if (typeof values[i] === 'number' && Number.isFinite(values[i])) {
        nums.push(values[i]);
      }
    }
    if (nums.length === 0) return '';
    if (nums.length === 1) return '0,14 100,14';
    var min = nums[0];
    var max = nums[0];
    for (var j = 1; j < nums.length; j++) {
      if (nums[j] < min) min = nums[j];
      if (nums[j] > max) max = nums[j];
    }
    var span = max - min;
    var pts = [];
    for (var k = 0; k < nums.length; k++) {
      var x = (k / (nums.length - 1)) * 100;
      var y = span === 0 ? 14 : 25 - ((nums[k] - min) / span) * 22;
      pts.push(x.toFixed(1) + ',' + y.toFixed(1));
    }
    return pts.join(' ');
  }

  function barWidthPercent(value, max) {
    var m = typeof max === 'number' && Number.isFinite(max) && max > 0 ? max : 1;
    var v = typeof value === 'number' && Number.isFinite(value) ? value : 0;
    var pct = Math.max(0, Math.min(100, (v / m) * 100));
    return (Math.round(pct * 100) / 100) + '%';
  }

  function normalizeChildren(children) {
    return Array.isArray(children) ? children : [];
  }

  function canRenderNode(node) {
    if (!isPlainObject(node) || typeof node.type !== 'string') return false;
    return (
      CONTAINER_TYPES.has(node.type) ||
      node.type === 'heading' ||
      node.type === 'text' ||
      node.type === 'badge' ||
      node.type === 'stat' ||
      node.type === 'bar' ||
      node.type === 'sparkline' ||
      node.type === 'table' ||
      node.type === 'divider' ||
      node.type === 'button'
    );
  }

  function sameShape(a, b, depth, budget) {
    if (depth > MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES) return true;
    var aValid = canRenderNode(a);
    var bValid = canRenderNode(b);
    if (!aValid && !bValid) return true;
    if (aValid !== bValid) return false;
    if (a.type !== b.type) return false;
    budget.count += 1;

    if (CONTAINER_TYPES.has(a.type)) {
      var ac = normalizeChildren(a.children);
      var bc = normalizeChildren(b.children);
      if (ac.length !== bc.length) return false;
      for (var i = 0; i < ac.length; i++) {
        if (!sameShape(ac[i], bc[i], depth + 1, budget)) return false;
      }
      return true;
    }
    if (a.type === 'bar') {
      return isValidSwatch(a.swatch) === isValidSwatch(b.swatch) &&
        hasBarCaption(a) === hasBarCaption(b);
    }
    if (a.type === 'table') {
      var ah = Array.isArray(a.headers) ? Math.min(a.headers.length, MAX_TABLE_COLS) : 0;
      var bh = Array.isArray(b.headers) ? Math.min(b.headers.length, MAX_TABLE_COLS) : 0;
      if (ah !== bh) return false;
      var ar = Array.isArray(a.rows) ? Math.min(a.rows.length, MAX_TABLE_ROWS) : 0;
      var br = Array.isArray(b.rows) ? Math.min(b.rows.length, MAX_TABLE_ROWS) : 0;
      if (ar !== br) return false;
      for (var r = 0; r < ar; r++) {
        var rowA = Array.isArray(a.rows[r]) ? Math.min(a.rows[r].length, MAX_TABLE_COLS) : 0;
        var rowB = Array.isArray(b.rows[r]) ? Math.min(b.rows[r].length, MAX_TABLE_COLS) : 0;
        if (rowA !== rowB) return false;
      }
      return true;
    }
    return true;
  }

  function applyClasses(el, baseClass, extras) {
    var cls = baseClass;
    for (var i = 0; i < extras.length; i++) {
      if (extras[i]) cls += ' ' + extras[i];
    }
    if (typeof SVGElement !== 'undefined' && el instanceof SVGElement) {
      if (el.getAttribute('class') !== cls) el.setAttribute('class', cls);
    } else if (el.className !== cls) {
      el.className = cls;
    }
  }

  function buildNodeTree(doc, node, depth, budget, ctx) {
    if (depth > MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES || !canRenderNode(node)) {
      return null;
    }
    budget.count += 1;

    var toneCls = validToneClass(node.tone);
    var el;

    if (CONTAINER_TYPES.has(node.type)) {
      el = doc.createElement('div');
      applyClasses(el, 'vk-' + node.type, []);
      var children = normalizeChildren(node.children);
      var childSlots = [];
      for (var i = 0; i < children.length; i++) {
        if (budget.count >= MAX_VIEW_NODES) break;
        var built = buildNodeTree(doc, children[i], depth + 1, budget, ctx);
        if (built) {
          el.appendChild(built.el);
          childSlots.push(built);
        }
      }
      return { el: el, type: node.type, childSlots: childSlots };
    }

    if (node.type === 'heading') {
      el = doc.createElement('div');
      el.className = 'vk-heading';
      setSlotContent(el, node.text, ctx.resolve);
      return { el: el, type: 'heading' };
    }

    if (node.type === 'text') {
      el = doc.createElement('div');
      applyClasses(el, 'vk-text', [
        toneCls,
        node.strong === true ? 'vk-strong' : '',
        node.mono === true ? 'vk-mono' : ''
      ]);
      setSlotContent(el, node.text, ctx.resolve);
      return { el: el, type: 'text' };
    }

    if (node.type === 'badge') {
      el = doc.createElement('span');
      applyClasses(el, 'vk-badge', [toneCls]);
      setSlotContent(el, node.text, ctx.resolve);
      return { el: el, type: 'badge' };
    }

    if (node.type === 'stat') {
      el = doc.createElement('div');
      applyClasses(el, 'vk-stat', [toneCls]);
      var valEl = doc.createElement('div');
      valEl.className = 'vk-stat-value';
      setSlotContent(valEl, node.value, ctx.resolve);
      var lblEl = doc.createElement('div');
      lblEl.className = 'vk-stat-label';
      setSlotContent(lblEl, node.label, ctx.resolve);
      el.appendChild(valEl);
      el.appendChild(lblEl);
      return { el: el, type: 'stat', valEl: valEl, lblEl: lblEl };
    }

    if (node.type === 'bar') {
      el = doc.createElement('div');
      applyClasses(el, 'vk-bar', [toneCls]);
      var headEl = doc.createElement('div');
      headEl.className = 'vk-bar-head';

      var swatchEl = null;
      if (isValidSwatch(node.swatch)) {
        swatchEl = doc.createElement('span');
        swatchEl.className = 'vk-bar-swatch';
        swatchEl.style.backgroundColor = node.swatch;
        headEl.appendChild(swatchEl);
      }

      var barLabelEl = doc.createElement('span');
      barLabelEl.className = 'vk-bar-label';
      setSlotContent(barLabelEl, node.label, ctx.resolve);
      headEl.appendChild(barLabelEl);

      var captionEl = null;
      if (hasBarCaption(node)) {
        captionEl = doc.createElement('span');
        captionEl.className = 'vk-bar-caption';
        setSlotContent(captionEl, node.caption, ctx.resolve);
        headEl.appendChild(captionEl);
      }

      var trackEl = doc.createElement('div');
      trackEl.className = 'vk-bar-track';
      var fillEl = doc.createElement('div');
      fillEl.className = 'vk-bar-fill';
      fillEl.style.width = barWidthPercent(node.value, node.max);
      trackEl.appendChild(fillEl);

      el.appendChild(headEl);
      el.appendChild(trackEl);
      return {
        el: el,
        type: 'bar',
        swatchEl: swatchEl,
        barLabelEl: barLabelEl,
        captionEl: captionEl,
        fillEl: fillEl
      };
    }

    if (node.type === 'sparkline') {
      var SVG_NS = 'http://www.w3.org/2000/svg';
      el = doc.createElementNS(SVG_NS, 'svg');
      applyClasses(el, 'vk-sparkline', [toneCls]);
      el.setAttribute('viewBox', '0 0 100 28');
      el.setAttribute('preserveAspectRatio', 'none');
      var poly = doc.createElementNS(SVG_NS, 'polyline');
      poly.setAttribute('fill', 'none');
      poly.setAttribute('points', sparklinePoints(node.values));
      el.appendChild(poly);
      return { el: el, type: 'sparkline', poly: poly };
    }

    if (node.type === 'table') {
      el = doc.createElement('table');
      el.className = 'vk-table';
      var thCells = [];
      var headers = Array.isArray(node.headers) ? node.headers : [];
      var hCount = Math.min(headers.length, MAX_TABLE_COLS);
      if (hCount > 0) {
        var thead = doc.createElement('thead');
        var htr = doc.createElement('tr');
        for (var h = 0; h < hCount; h++) {
          var th = doc.createElement('th');
          setSlotContent(th, headers[h], ctx.resolve);
          htr.appendChild(th);
          thCells.push(th);
        }
        thead.appendChild(htr);
        el.appendChild(thead);
      }
      var tdRows = [];
      var rows = Array.isArray(node.rows) ? node.rows : [];
      var rCount = Math.min(rows.length, MAX_TABLE_ROWS);
      var tbody = doc.createElement('tbody');
      for (var r = 0; r < rCount; r++) {
        var tr = doc.createElement('tr');
        var rowData = Array.isArray(rows[r]) ? rows[r] : [];
        var cCount = Math.min(rowData.length, MAX_TABLE_COLS);
        var tdRow = [];
        for (var c = 0; c < cCount; c++) {
          var td = doc.createElement('td');
          setSlotContent(td, rowData[c], ctx.resolve);
          tr.appendChild(td);
          tdRow.push(td);
        }
        tbody.appendChild(tr);
        tdRows.push(tdRow);
      }
      el.appendChild(tbody);
      return { el: el, type: 'table', thCells: thCells, tdRows: tdRows };
    }

    if (node.type === 'divider') {
      el = doc.createElement('hr');
      el.className = 'vk-divider';
      return { el: el, type: 'divider' };
    }

    if (node.type === 'button') {
      el = doc.createElement('button');
      el.type = 'button';
      applyClasses(el, 'vk-button', [toneCls]);
      setSlotContent(el, node.text, ctx.resolve);
      var actionState = {
        command: typeof node.command === 'string' ? node.command : '',
        args: node.args === undefined ? null : jsonClone(node.args)
      };
      el.addEventListener('click', function () {
        if (typeof ctx.onAction === 'function') {
          try {
            ctx.onAction(actionState.command, jsonClone(actionState.args));
          } catch (e) {
            // Never let handler errors escape
          }
        }
      });
      return { el: el, type: 'button', actionState: actionState };
    }

    return null;
  }

  function patchNodeTree(slot, node, depth, budget, ctx) {
    if (!slot || depth > MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES || !canRenderNode(node)) {
      return;
    }
    budget.count += 1;
    var toneCls = validToneClass(node.tone);

    if (CONTAINER_TYPES.has(node.type)) {
      var children = normalizeChildren(node.children);
      for (var i = 0; i < slot.childSlots.length && i < children.length; i++) {
        if (budget.count >= MAX_VIEW_NODES) break;
        patchNodeTree(slot.childSlots[i], children[i], depth + 1, budget, ctx);
      }
      return;
    }

    if (node.type === 'heading') {
      setSlotContent(slot.el, node.text, ctx.resolve);
      return;
    }

    if (node.type === 'text') {
      applyClasses(slot.el, 'vk-text', [
        toneCls,
        node.strong === true ? 'vk-strong' : '',
        node.mono === true ? 'vk-mono' : ''
      ]);
      setSlotContent(slot.el, node.text, ctx.resolve);
      return;
    }

    if (node.type === 'badge') {
      applyClasses(slot.el, 'vk-badge', [toneCls]);
      setSlotContent(slot.el, node.text, ctx.resolve);
      return;
    }

    if (node.type === 'stat') {
      applyClasses(slot.el, 'vk-stat', [toneCls]);
      setSlotContent(slot.valEl, node.value, ctx.resolve);
      setSlotContent(slot.lblEl, node.label, ctx.resolve);
      return;
    }

    if (node.type === 'bar') {
      applyClasses(slot.el, 'vk-bar', [toneCls]);
      if (slot.swatchEl && isValidSwatch(node.swatch)) {
        if (slot.swatchEl.style.backgroundColor !== node.swatch) {
          slot.swatchEl.style.backgroundColor = node.swatch;
        }
      }
      setSlotContent(slot.barLabelEl, node.label, ctx.resolve);
      if (slot.captionEl && hasBarCaption(node)) {
        setSlotContent(slot.captionEl, node.caption, ctx.resolve);
      }
      var nextWidth = barWidthPercent(node.value, node.max);
      if (slot.fillEl.style.width !== nextWidth) {
        slot.fillEl.style.width = nextWidth;
      }
      return;
    }

    if (node.type === 'sparkline') {
      applyClasses(slot.el, 'vk-sparkline', [toneCls]);
      var pts = sparklinePoints(node.values);
      if (slot.poly.getAttribute('points') !== pts) {
        slot.poly.setAttribute('points', pts);
      }
      return;
    }

    if (node.type === 'table') {
      var headers = Array.isArray(node.headers) ? node.headers : [];
      for (var h = 0; h < slot.thCells.length && h < headers.length; h++) {
        setSlotContent(slot.thCells[h], headers[h], ctx.resolve);
      }
      var rows = Array.isArray(node.rows) ? node.rows : [];
      for (var r = 0; r < slot.tdRows.length && r < rows.length; r++) {
        var rowData = Array.isArray(rows[r]) ? rows[r] : [];
        var tdRow = slot.tdRows[r];
        for (var c = 0; c < tdRow.length && c < rowData.length; c++) {
          setSlotContent(tdRow[c], rowData[c], ctx.resolve);
        }
      }
      return;
    }

    if (node.type === 'button') {
      applyClasses(slot.el, 'vk-button', [toneCls]);
      setSlotContent(slot.el, node.text, ctx.resolve);
      slot.actionState.command = typeof node.command === 'string' ? node.command : '';
      slot.actionState.args = node.args === undefined ? null : jsonClone(node.args);
    }
  }

  function clearRenderState(element) {
    if (renderStateMap) renderStateMap.delete(element);
    else delete element.__vkRenderState;
  }

  function getRenderState(element) {
    return renderStateMap ? renderStateMap.get(element) : element.__vkRenderState;
  }

  function setRenderState(element, state) {
    if (renderStateMap) renderStateMap.set(element, state);
    else element.__vkRenderState = state;
  }

  function renderView(view, element, options) {
    if (!element || typeof element.appendChild !== 'function') {
      throw new Error('renderView requires a valid DOM element');
    }
    var opts = options && typeof options === 'object' ? options : {};
    var doc = element.ownerDocument || document;
    var prev = getRenderState(element);

    view = maybeAdaptExternalUi(view);

    var ctx = {
      resolve: typeof opts.resolve === 'function' ? opts.resolve : null,
      onAction: typeof opts.onAction === 'function' ? opts.onAction : (prev ? prev.onAction : null)
    };

    if (!canRenderNode(view)) {
      clearRenderState(element);
      element.textContent = '';
      return;
    }

    if (
      prev &&
      prev.slot &&
      prev.slot.el &&
      prev.slot.el.parentNode === element &&
      sameShape(prev.view, view, 0, { count: 0 })
    ) {
      prev.ctx.resolve = ctx.resolve;
      prev.ctx.onAction = ctx.onAction;
      patchNodeTree(prev.slot, view, 0, { count: 0 }, prev.ctx);
      prev.view = jsonClone(view);
      return;
    }

    var slot = buildNodeTree(doc, view, 0, { count: 0 }, ctx);
    if (!slot) {
      clearRenderState(element);
      element.textContent = '';
      return;
    }

    element.replaceChildren(slot.el);
    setRenderState(element, {
      view: jsonClone(view),
      slot: slot,
      ctx: ctx
    });
  }

  function renderError(element, message) {
    if (!element || typeof element.appendChild !== 'function') return;
    clearRenderState(element);
    if (element.classList) element.classList.remove('vk-view-stale');
    var doc = element.ownerDocument || document;
    var errEl = doc.createElement('div');
    errEl.className = 'vk-error';
    errEl.textContent = String(message || 'Vibe error');
    element.replaceChildren(errEl);
  }

  function renderUnavailable(element, state, issues) {
    if (!element || typeof element.appendChild !== 'function') return;
    clearRenderState(element);
    if (element.classList) element.classList.remove('vk-view-stale');
    var doc = element.ownerDocument || document;
    var box = doc.createElement('div');
    box.className = 'vk-unavailable';
    var titleEl = doc.createElement('div');
    titleEl.className = 'vk-unavailable-title';
    if (state === 'revoked') {
      titleEl.textContent = 'Data access turned off';
    } else if (state === 'missing') {
      titleEl.textContent = 'Capability not offered here';
    } else {
      titleEl.textContent = 'Data source offline';
    }
    box.appendChild(titleEl);
    var reasonParts = [];
    for (var i = 0; i < issues.length; i++) {
      var it = issues[i];
      reasonParts.push((it.title || it.capability) + ': ' + it.reason);
    }
    if (reasonParts.length > 0) {
      var reasonEl = doc.createElement('div');
      reasonEl.className = 'vk-unavailable-reason';
      reasonEl.textContent = reasonParts.join(' \u00b7 ');
      box.appendChild(reasonEl);
    }
    element.replaceChildren(box);
  }

  function buildSandboxSrcdoc() {
    var shadowList = [
      'window', 'self', 'globalThis', 'document', 'location', 'parent', 'top',
      'frames', 'frameElement', 'opener', 'navigator', 'history', 'screen',
      'fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource', 'importScripts',
      'Worker', 'SharedWorker', 'BroadcastChannel', 'caches', 'indexedDB',
      'localStorage', 'sessionStorage', 'cookieStore', 'postMessage',
      'setTimeout', 'setInterval', 'clearTimeout', 'clearInterval',
      'setImmediate', 'queueMicrotask', 'requestAnimationFrame', 'cancelAnimationFrame',
      'Image', 'Audio', 'Option', 'alert', 'confirm', 'prompt', 'open', 'close'
    ];

    var blockedGlobals = [
      'fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource', 'importScripts',
      'Worker', 'SharedWorker', 'BroadcastChannel', 'caches', 'indexedDB',
      'localStorage', 'sessionStorage', 'cookieStore', 'open', 'close',
      'alert', 'confirm', 'prompt', 'Image', 'Audio', 'Option',
      'FileReaderSync', 'XMLHttpRequestEventTarget', 'XMLHttpRequestUpload'
    ];

    var workerScriptLines = [
      '(function () {',
      '  "use strict";',
      '  var _post = self.postMessage.bind(self);',
      '  var _JSON = JSON;',
      '  var _Object = Object;',
      '  var _Array = Array;',
      '  var _Function = Function;',
      '  var _Encoder = typeof TextEncoder !== "undefined" ? new TextEncoder() : null;',
      '  var _blocked = ' + JSON.stringify(blockedGlobals) + ';',
      '  for (var i = 0; i < _blocked.length; i++) {',
      '    var k = _blocked[i];',
      '    try { _Object.defineProperty(self, k, { value: undefined, writable: false, configurable: false }); }',
      '    catch (e) { try { self[k] = undefined; } catch (e2) {} }',
      '  }',
      '  try {',
      '    if (self.navigator && self.navigator.sendBeacon) {',
      '      _Object.defineProperty(self.navigator, "sendBeacon", { value: undefined, writable: false, configurable: false });',
      '    }',
      '  } catch (e) {}',
      '  try { _Object.defineProperty(self, "navigator", { value: undefined, writable: false, configurable: false }); } catch (e) {}',
      '  try { _Object.defineProperty(self, "location", { value: undefined, writable: false, configurable: false }); } catch (e) {}',
      '  var _shadow = ' + JSON.stringify(shadowList) + ';',
      '  var _shadowUndefined = new _Array(_shadow.length);',
      '  var _invokeFn = null;',
      '  function byteLen(s) {',
      '    if (_Encoder) return _Encoder.encode(s).length;',
      '    return s.length * 3;',
      '  }',
      '  function compileVibe(source) {',
      '    var args1 = _shadow.concat(["\\"use strict\\";\\n" + source + "\\nreturn typeof invoke === \\"function\\" ? invoke : null;"]);',
      '    var f1 = _Function.apply(null, args1);',
      '    var fn = f1.apply(undefined, _shadowUndefined);',
      '    if (typeof fn === "function") return fn;',
      '    var args2 = _shadow.concat(["\\"use strict\\"; return (" + source + ");"]);',
      '    var f2 = _Function.apply(null, args2);',
      '    var fn2 = f2.apply(undefined, _shadowUndefined);',
      '    if (typeof fn2 === "function") return fn2;',
      '    throw new Error("Vibe source must define function invoke(input)");',
      '  }',
      '  function validateAndSerialize(out) {',
      '    if (!out || typeof out !== "object" || _Array.isArray(out)) {',
      '      throw new Error("Vibe output must be { state, view }");',
      '    }',
      '    var hasState = _Object.prototype.hasOwnProperty.call(out, "state");',
      '    var hasView = _Object.prototype.hasOwnProperty.call(out, "view");',
      '    var keys = _Object.keys(out);',
      '    if (!hasState || !hasView || keys.length !== 2) {',
      '      throw new Error("Vibe output must have exact keys { state, view }");',
      '    }',
      '    if (!out.view || typeof out.view !== "object" || _Array.isArray(out.view)) {',
      '      throw new Error("Vibe output.view must be an object");',
      '    }',
      '    var normalized = { state: out.state === undefined ? null : out.state, view: out.view };',
      '    var json = _JSON.stringify(normalized);',
      '    if (typeof json !== "string") throw new Error("Vibe output is not JSON-serializable");',
      '    if (byteLen(json) > ' + MAX_OUTPUT_BYTES + ') {',
      '      throw new Error("Vibe output exceeds 64 kB limit");',
      '    }',
      '    return json;',
      '  }',
      '  self.onmessage = function (ev) {',
      '    var msg = ev.data;',
      '    if (!msg || typeof msg !== "object") return;',
      '    if (msg.type === "w-compile") {',
      '      try {',
      '        _invokeFn = compileVibe(msg.source);',
      '        _post({ type: "w-compiled", ok: true });',
      '      } catch (err) {',
      '        _post({ type: "w-compiled", ok: false, error: err && err.message ? err.message : String(err) });',
      '      }',
      '      return;',
      '    }',
      '    if (msg.type === "w-invoke") {',
      '      if (typeof _invokeFn !== "function") {',
      '        _post({ type: "w-result", callId: msg.callId, ok: false, error: "Vibe invoke is not compiled" });',
      '        return;',
      '      }',
      '      try {',
      '        var input = _JSON.parse(msg.inputJson);',
      '        var out = _invokeFn(input);',
      '        var outputJson = validateAndSerialize(out);',
      '        _post({ type: "w-result", callId: msg.callId, ok: true, outputJson: outputJson });',
      '      } catch (err) {',
      '        _post({ type: "w-result", callId: msg.callId, ok: false, error: err && err.message ? err.message : String(err) });',
      '      }',
      '    }',
      '  };',
      '  _post({ type: "w-ready" });',
      '})();'
    ];

    var workerCode = workerScriptLines.join('\n');

    var csp = [
      "default-src 'none'",
      "script-src 'unsafe-inline' 'unsafe-eval' blob:",
      "worker-src blob:",
      "child-src blob:",
      "connect-src 'none'",
      "img-src 'none'",
      "style-src 'none'",
      "font-src 'none'",
      "media-src 'none'",
      "frame-src 'none'",
      "object-src 'none'",
      "base-uri 'none'",
      "form-action 'none'"
    ].join('; ');

    var iframeScriptLines = [
      '(function () {',
      '  "use strict";',
      '  var _parent = window.parent;',
      '  var _postToParent = _parent.postMessage.bind(_parent);',
      '  var _token = null;',
      '  var _worker = null;',
      '  var _blobUrl = null;',
      '  var _bootTimer = null;',
      '  var _stopped = false;',
      '  var WORKER_CODE = ' + JSON.stringify(workerCode) + ';',
      '  var SANDBOX_START_ERROR = "This browser cannot start the vibe sandbox";',
      '  function cleanup() {',
      '    _stopped = true;',
      '    if (_bootTimer) { clearTimeout(_bootTimer); _bootTimer = null; }',
      '    if (_worker) { try { _worker.terminate(); } catch (e) {} _worker = null; }',
      '    if (_blobUrl) { try { URL.revokeObjectURL(_blobUrl); } catch (e) {} _blobUrl = null; }',
      '  }',
      '  function failSandboxStart() {',
      '    if (_stopped) return;',
      '    cleanup();',
      '    _postToParent({ type: "vp-init-error", token: _token, error: SANDBOX_START_ERROR }, "*");',
      '  }',
      '  function initRunner(source) {',
      '    if (typeof Worker !== "function" || typeof Blob !== "function" || typeof URL === "undefined" || typeof URL.createObjectURL !== "function") {',
      '      failSandboxStart();',
      '      return;',
      '    }',
      '    var workerReady = false;',
      '    try {',
      '      var blob = new Blob([WORKER_CODE], { type: "text/javascript" });',
      '      _blobUrl = URL.createObjectURL(blob);',
      '      _worker = new Worker(_blobUrl);',
      '    } catch (err) {',
      '      failSandboxStart();',
      '      return;',
      '    }',
      '    _bootTimer = setTimeout(function () {',
      '      if (!workerReady && !_stopped) failSandboxStart();',
      '    }, ' + WORKER_BOOT_TIMEOUT_MS + ');',
      '    _worker.onerror = function (ev) {',
      '      if (ev && typeof ev.preventDefault === "function") ev.preventDefault();',
      '      if (!workerReady) {',
      '        failSandboxStart();',
      '      } else if (!_stopped) {',
      '        cleanup();',
      '        _postToParent({ type: "vp-init-error", token: _token, error: (ev && ev.message) || "Worker error" }, "*");',
      '      }',
      '    };',
      '    _worker.onmessage = function (ev) {',
      '      if (_stopped) return;',
      '      var m = ev.data;',
      '      if (!m || typeof m !== "object") return;',
      '      if (m.type === "w-ready") {',
      '        workerReady = true;',
      '        if (_bootTimer) { clearTimeout(_bootTimer); _bootTimer = null; }',
      '        _worker.postMessage({ type: "w-compile", source: source });',
      '      } else if (m.type === "w-compiled") {',
      '        if (m.ok) {',
      '          _postToParent({ type: "vp-init-ok", token: _token }, "*");',
      '        } else {',
      '          cleanup();',
      '          _postToParent({ type: "vp-init-error", token: _token, error: m.error || "Compile failed" }, "*");',
      '        }',
      '      } else if (m.type === "w-result") {',
      '        _postToParent({',
      '          type: "vp-result",',
      '          token: _token,',
      '          callId: m.callId,',
      '          ok: Boolean(m.ok),',
      '          outputJson: m.outputJson,',
      '          error: m.error',
      '        }, "*");',
      '      }',
      '    };',
      '  }',
      '  window.addEventListener("pagehide", cleanup);',
      '  window.addEventListener("message", function (ev) {',
      '    if (ev.source !== _parent) return;',
      '    var msg = ev.data;',
      '    if (!msg || typeof msg !== "object") return;',
      '    if (msg.type === "vp-init") {',
      '      _token = msg.token;',
      '      initRunner(msg.source);',
      '      return;',
      '    }',
      '    if (msg.token !== _token) return;',
      '    if (msg.type === "vp-terminate") {',
      '      cleanup();',
      '      return;',
      '    }',
      '    if (msg.type === "vp-invoke") {',
      '      if (_stopped || !_worker) return;',
      '      _worker.postMessage({ type: "w-invoke", callId: msg.callId, inputJson: msg.inputJson });',
      '    }',
      '  });',
      '  _postToParent({ type: "vp-ready" }, "*");',
      '})();'
    ];

    return [
      '<!doctype html>',
      '<html>',
      '<head>',
      '<meta charset="utf-8">',
      '<meta http-equiv="Content-Security-Policy" content="' + csp + '">',
      '</head>',
      '<body>',
      '<script>',
      iframeScriptLines.join('\n'),
      '<' + '/script>',
      '</body>',
      '</html>'
    ].join('');
  }

  var SANDBOX_SRCDOC = buildSandboxSrcdoc();

  function validateOutputPayload(outputJson) {
    if (typeof outputJson !== 'string') {
      throw new Error('Missing output payload');
    }
    if (utf8ByteLength(outputJson) > MAX_OUTPUT_BYTES) {
      throw new Error('Output exceeds 64 kB limit');
    }
    var parsed;
    try {
      parsed = JSON.parse(outputJson);
    } catch (e) {
      throw new Error('Output is not valid JSON');
    }
    if (!isPlainObject(parsed)) {
      throw new Error('Vibe output must be { state, view }');
    }
    var keys = Object.keys(parsed);
    if (!hasOwn(parsed, 'state') || !hasOwn(parsed, 'view') || keys.length !== 2) {
      throw new Error('Vibe output must have exact keys { state, view }');
    }
    if (!isPlainObject(parsed.view)) {
      throw new Error('Vibe output.view must be a plain object');
    }
    return parsed;
  }

  function createHost(config) {
    if (!isPlainObject(config)) {
      throw new Error('Host config must be an object');
    }
    if (typeof config.id !== 'string' || config.id.trim().length === 0) {
      throw new Error('Host config.id must be a non-empty string');
    }
    if (typeof config.name !== 'string' || config.name.trim().length === 0) {
      throw new Error('Host config.name must be a non-empty string');
    }

    var hostId = config.id;
    var hostName = config.name;
    var hostLocale = typeof config.locale === 'string' && config.locale.trim() ? config.locale.trim() : 'en';
    var hostStrings = getVibeStrings(hostLocale, config.strings);
    var capabilities = Array.isArray(config.capabilities) ? config.capabilities.slice() : [];
    var notOffered = Array.isArray(config.notOffered) ? config.notOffered.slice() : [];
    var capByName = new Map();
    for (var i = 0; i < capabilities.length; i++) {
      var cap = capabilities[i];
      if (!cap || typeof cap.name !== 'string' || cap.name.length === 0) {
        throw new Error('Each capability must have a non-empty name');
      }
      capByName.set(cap.name, cap);
    }

    var HANDLES_KEY = 'vibekit:' + hostId + ':handles';
    var INSTALLS_KEY = 'vibekit:' + hostId;

    var keyToHandle = new Map();
    var handleToValue = new Map();
    var entriesCache = [];
    var listeners = new Set();
    var activeRuns = new Set();

    function valueKey(val) {
      if (typeof val === 'string') return 's:' + val;
      return 'j:' + JSON.stringify(val);
    }

    function loadHandles() {
      var raw = safeStorageGet(HANDLES_KEY);
      if (!raw) return;
      try {
        var parsed = JSON.parse(raw);
        if (isPlainObject(parsed) && Array.isArray(parsed.entries)) {
          for (var idx = 0; idx < parsed.entries.length; idx++) {
            var item = parsed.entries[idx];
            if (Array.isArray(item) && item.length === 3 && typeof item[2] === 'string') {
              if (!keyToHandle.has(item[0])) {
                keyToHandle.set(item[0], item[2]);
                handleToValue.set(item[2], item[1]);
                entriesCache.push(item);
              }
            }
          }
        }
      } catch (e) {
        // Ignore corrupted handle storage
      }
    }

    function saveHandles() {
      safeStorageSet(HANDLES_KEY, JSON.stringify({ v: 1, entries: entriesCache }));
    }

    loadHandles();

    function seal(value) {
      assertJsonSafe(value);
      var k = valueKey(value);
      var h = keyToHandle.get(k);
      if (!h) {
        loadHandles();
        h = keyToHandle.get(k);
      }
      if (!h) {
        do {
          h = randomHandleId();
        } while (handleToValue.has(h));
        keyToHandle.set(k, h);
        handleToValue.set(h, jsonClone(value));
        entriesCache.push([k, jsonClone(value), h]);
        saveHandles();
      }
      return { sealed: h };
    }

    function resolveHandle(handleOrId) {
      var id = isPlainObject(handleOrId) && typeof handleOrId.sealed === 'string'
        ? handleOrId.sealed
        : (typeof handleOrId === 'string' ? handleOrId : null);
      if (!id) return undefined;
      if (!handleToValue.has(id)) {
        loadHandles();
      }
      if (!handleToValue.has(id)) return undefined;
      return handleToValue.get(id);
    }

    function sealRows(rawRows, fields) {
      var rowsCopy = Array.isArray(rawRows) ? jsonClone(rawRows) : [];
      var fieldMap = isPlainObject(fields) ? fields : {};
      var sealedFields = [];
      var fKeys = Object.keys(fieldMap);
      for (var fk = 0; fk < fKeys.length; fk++) {
        if (fieldMap[fKeys[fk]] === 'sealed') sealedFields.push(fKeys[fk]);
      }
      if (sealedFields.length === 0) return rowsCopy;
      for (var r = 0; r < rowsCopy.length; r++) {
        var row = rowsCopy[r];
        if (!isPlainObject(row)) continue;
        for (var sf = 0; sf < sealedFields.length; sf++) {
          var fieldName = sealedFields[sf];
          if (hasOwn(row, fieldName) && row[fieldName] !== undefined && row[fieldName] !== null) {
            row[fieldName] = seal(row[fieldName]);
          }
        }
      }
      return rowsCopy;
    }

    function manifest() {
      var capsOut = [];
      for (var i = 0; i < capabilities.length; i++) {
        var c = capabilities[i];
        capsOut.push({
          name: c.name,
          title: c.title || c.name,
          fields: isPlainObject(c.fields) ? jsonClone(c.fields) : {},
          sample: Array.isArray(c.sample) ? jsonClone(c.sample) : []
        });
      }
      return {
        protocol: PROTOCOL_VERSION,
        host: { id: hostId, name: hostName },
        capabilities: capsOut,
        notOffered: notOffered.slice()
      };
    }

    function check(vibe) {
      validateVibe(vibe);
      var missing = [];
      var seen = new Set();
      for (var i = 0; i < vibe.needs.length; i++) {
        var name = vibe.needs[i];
        if (!capByName.has(name) && !seen.has(name)) {
          seen.add(name);
          missing.push(name);
        }
      }
      if (missing.length > 0) {
        return { ok: false, missing: missing };
      }
      return { ok: true };
    }

    function label(vibe) {
      validateVibe(vibe);
      var reads = [];
      var cannot = [];
      var cannotSeen = new Set();

      if (vibe.needs.length === 0) {
        reads.push('Nothing from ' + hostName);
      } else {
        for (var i = 0; i < vibe.needs.length; i++) {
          var capName = vibe.needs[i];
          var cap = capByName.get(capName);
          if (!cap) {
            reads.push('Missing capability: ' + capName);
            continue;
          }
          var title = cap.title || cap.name;
          if (cap.sealedNote) {
            reads.push(title + ' (' + cap.sealedNote + ')');
          } else {
            reads.push(title);
          }
          if (cap.sealedCannot && !cannotSeen.has(cap.sealedCannot)) {
            cannotSeen.add(cap.sealedCannot);
            cannot.push(cap.sealedCannot);
          }
        }
      }

      for (var j = 0; j < notOffered.length; j++) {
        if (!cannotSeen.has(notOffered[j])) {
          cannotSeen.add(notOffered[j]);
          cannot.push(notOffered[j]);
        }
      }
      var finalCannot = 'Change anything in ' + hostName;
      if (!cannotSeen.has(finalCannot)) {
        cannot.push(finalCannot);
      }

      return {
        reads: reads,
        shows: ['Only inside its own box'],
        cannot: cannot
      };
    }

    function aggregateSourceState(issues) {
      var hasMissing = false;
      var hasRevoked = false;
      var hasOffline = false;
      for (var i = 0; i < issues.length; i++) {
        if (issues[i].state === 'missing') hasMissing = true;
        else if (issues[i].state === 'revoked') hasRevoked = true;
        else hasOffline = true;
      }
      if (hasMissing) return 'missing';
      if (hasRevoked) return 'revoked';
      if (hasOffline) return 'offline';
      return 'ok';
    }

    function evaluateCapabilitiesStatus(needs) {
      var issues = [];
      var seen = new Set();
      var list = Array.isArray(needs) ? needs : [];
      for (var i = 0; i < list.length; i++) {
        var capName = list[i];
        if (seen.has(capName)) continue;
        seen.add(capName);
        var cap = capByName.get(capName);
        if (!cap) {
          issues.push({
            capability: capName,
            title: capName,
            state: 'missing',
            reason: hostName + ' does not offer ' + capName,
            hasSample: false
          });
          continue;
        }
        var hasSample = Array.isArray(cap.sample) && cap.sample.length > 0;
        if (typeof cap.status === 'function') {
          try {
            var st = cap.status();
            if (st && st.available === false) {
              var mode = st.mode === 'revoked' ? 'revoked' : 'offline';
              issues.push({
                capability: capName,
                title: cap.title || capName,
                state: mode,
                reason: typeof st.reason === 'string' && st.reason.trim()
                  ? st.reason
                  : (mode === 'revoked' ? 'Access to this data source is turned off' : 'Data source is offline'),
                hasSample: hasSample
              });
            }
          } catch (err) {
            issues.push({
              capability: capName,
              title: cap.title || capName,
              state: 'offline',
              reason: err && err.message ? err.message : String(err),
              hasSample: hasSample
            });
          }
        }
      }
      return {
        state: aggregateSourceState(issues),
        issues: issues
      };
    }

    function sourceStatus(vibe) {
      validateVibe(vibe);
      return jsonClone(evaluateCapabilitiesStatus(vibe.needs));
    }

    function notifySourceChange() {
      var runsSnapshot = Array.from(activeRuns);
      for (var i = 0; i < runsSnapshot.length; i++) {
        try {
          runsSnapshot[i]();
        } catch (e) {
          // Never let run listener failure escape
        }
      }
    }

    function normalizeHistory(rawHistory) {
      if (!Array.isArray(rawHistory)) return [];
      var out = [];
      for (var i = 0; i < rawHistory.length && out.length < MAX_HISTORY_ENTRIES; i++) {
        var h = rawHistory[i];
        if (!isPlainObject(h) || !h.vibe) continue;
        try {
          var cleanV = canonicalVibeCopy(h.vibe);
          out.push({
            vibe: cleanV,
            title: normalizeTitle(h.title, cleanV.name),
            savedAt: typeof h.savedAt === 'number' ? h.savedAt : 0
          });
        } catch (e) {
          // Skip invalid history entry
        }
      }
      return out;
    }

    function normalizeRecordOrders(records) {
      var pinnedList = [];
      var unpinnedList = [];
      for (var i = 0; i < records.length; i++) {
        if (records[i].pinned) pinnedList.push(records[i]);
        else unpinnedList.push(records[i]);
      }
      var ordered = pinnedList.concat(unpinnedList);
      for (var j = 0; j < ordered.length; j++) {
        ordered[j].order = j;
      }
      return ordered;
    }

    function normalizeRecord(rec, fallbackOrder) {
      var cleanVibe = canonicalVibeCopy(rec.vibe);
      var installedAt = typeof rec.installedAt === 'number' ? rec.installedAt : Date.now();
      var updatedAt = typeof rec.updatedAt === 'number' ? rec.updatedAt : installedAt;
      var args = rec.args !== undefined && rec.args !== null ? jsonClone(rec.args) : null;
      if (args !== null) assertJsonSafe(args);
      return {
        instanceId: typeof rec.instanceId === 'string' && rec.instanceId.trim()
          ? rec.instanceId.trim()
          : randomInstanceId(),
        vibe: cleanVibe,
        title: normalizeTitle(rec.title, cleanVibe.name),
        note: normalizeNote(rec.note),
        origin: VALID_ORIGINS.has(rec.origin) ? rec.origin : 'yours',
        args: args,
        pinned: Boolean(rec.pinned),
        paused: Boolean(rec.paused),
        collapsed: Boolean(rec.collapsed),
        order: typeof rec.order === 'number' ? rec.order : fallbackOrder,
        installedAt: installedAt,
        updatedAt: updatedAt,
        history: normalizeHistory(rec.history)
      };
    }

    function loadInstalledRecords() {
      var raw = safeStorageGet(INSTALLS_KEY);
      if (!raw) return [];
      try {
        var parsed = JSON.parse(raw);
        if (!Array.isArray(parsed)) return [];
        var valid = [];
        var migrated = false;
        var seenIds = new Set();
        for (var i = 0; i < parsed.length; i++) {
          var rec = parsed[i];
          if (!isPlainObject(rec) || !rec.vibe) continue;
          try {
            if (
              typeof rec.instanceId !== 'string' ||
              !rec.instanceId.trim() ||
              typeof rec.title !== 'string' ||
              typeof rec.note !== 'string' ||
              !Array.isArray(rec.history) ||
              typeof rec.pinned !== 'boolean' ||
              typeof rec.paused !== 'boolean' ||
              typeof rec.collapsed !== 'boolean'
            ) {
              migrated = true;
            }
            var norm = normalizeRecord(rec, valid.length);
            while (seenIds.has(norm.instanceId)) {
              norm.instanceId = randomInstanceId();
              migrated = true;
            }
            seenIds.add(norm.instanceId);
            valid.push(norm);
          } catch (e) {
            // Skip invalid persisted vibe
          }
        }
        var ordered = normalizeRecordOrders(valid);
        if (migrated) {
          saveInstalledRecords(ordered);
        }
        return ordered;
      } catch (e) {
        return [];
      }
    }

    function saveInstalledRecords(records) {
      safeStorageSet(INSTALLS_KEY, JSON.stringify(records));
    }

    function findRecordIndex(records, idOrInstanceId) {
      if (typeof idOrInstanceId !== 'string' || !idOrInstanceId) return -1;
      for (var i = 0; i < records.length; i++) {
        if (records[i].instanceId === idOrInstanceId) return i;
      }
      for (var j = 0; j < records.length; j++) {
        if (records[j].vibe.id === idOrInstanceId) return j;
      }
      return -1;
    }

    function notifyListeners() {
      var snapshot = installed();
      listeners.forEach(function (fn) {
        try {
          fn(jsonClone(snapshot));
        } catch (e) {
          // Do not let listener exceptions break host
        }
      });
    }

    function vibeChangedForHistory(prevVibe, nextVibe) {
      return (
        prevVibe.version !== nextVibe.version ||
        prevVibe.source !== nextVibe.source ||
        canonicalJsonString(prevVibe.needs) !== canonicalJsonString(nextVibe.needs)
      );
    }

    function insertAtGroupTop(records, record) {
      if (record.pinned) {
        records.unshift(record);
      } else {
        var insertAt = 0;
        while (insertAt < records.length && records[insertAt].pinned) {
          insertAt += 1;
        }
        records.splice(insertAt, 0, record);
      }
    }

    function install(vibe, options) {
      var cleanVibe = canonicalVibeCopy(vibe);
      var capCheck = check(cleanVibe);
      if (!capCheck.ok) {
        throw new Error('Cannot install vibe; missing capabilities: ' + capCheck.missing.join(', '));
      }
      var opts = isPlainObject(options) ? options : {};
      var origin = typeof opts.origin === 'string' && VALID_ORIGINS.has(opts.origin) ? opts.origin : 'yours';
      var args = opts.args !== undefined && opts.args !== null ? jsonClone(opts.args) : null;
      if (args !== null) assertJsonSafe(args);

      var records = loadInstalledRecords();
      var matchIdx = -1;
      if (typeof opts.instanceId === 'string' && opts.instanceId.trim()) {
        var targetInstId = opts.instanceId.trim();
        for (var i = 0; i < records.length; i++) {
          if (records[i].instanceId === targetInstId) {
            matchIdx = i;
            break;
          }
        }
      } else {
        var targetArgsKey = canonicalJsonString(args);
        for (var j = 0; j < records.length; j++) {
          if (
            records[j].vibe.id === cleanVibe.id &&
            canonicalJsonString(records[j].args) === targetArgsKey
          ) {
            matchIdx = j;
            break;
          }
        }
      }

      var now = Date.now();
      var record;
      if (matchIdx >= 0) {
        var prev = records[matchIdx];
        var nextHistory = prev.history.slice();
        if (vibeChangedForHistory(prev.vibe, cleanVibe)) {
          nextHistory.unshift({
            vibe: jsonClone(prev.vibe),
            title: prev.title,
            savedAt: prev.updatedAt || prev.installedAt
          });
          nextHistory = nextHistory.slice(0, MAX_HISTORY_ENTRIES);
        }

        var nextTitle;
        if (opts.title !== undefined) {
          nextTitle = normalizeTitle(opts.title, cleanVibe.name);
        } else if (prev.title === prev.vibe.name) {
          nextTitle = cleanVibe.name;
        } else {
          nextTitle = prev.title;
        }

        var nextNote = opts.note !== undefined ? normalizeNote(opts.note) : prev.note;
        var nextPinned = opts.pinned !== undefined ? Boolean(opts.pinned) : prev.pinned;
        var nextPaused = opts.paused !== undefined ? Boolean(opts.paused) : prev.paused;
        var nextCollapsed = opts.collapsed !== undefined ? Boolean(opts.collapsed) : prev.collapsed;

        record = {
          instanceId: prev.instanceId,
          vibe: cleanVibe,
          title: nextTitle,
          note: nextNote,
          origin: origin,
          args: args,
          pinned: nextPinned,
          paused: nextPaused,
          collapsed: nextCollapsed,
          order: prev.order,
          installedAt: prev.installedAt,
          updatedAt: now,
          history: nextHistory
        };

        if (nextPinned !== prev.pinned) {
          records.splice(matchIdx, 1);
          insertAtGroupTop(records, record);
        } else {
          records[matchIdx] = record;
        }
      } else {
        record = {
          instanceId: typeof opts.instanceId === 'string' && opts.instanceId.trim()
            ? opts.instanceId.trim()
            : randomInstanceId(),
          vibe: cleanVibe,
          title: normalizeTitle(opts.title, cleanVibe.name),
          note: normalizeNote(opts.note),
          origin: origin,
          args: args,
          pinned: Boolean(opts.pinned),
          paused: Boolean(opts.paused),
          collapsed: Boolean(opts.collapsed),
          order: 0,
          installedAt: now,
          updatedAt: now,
          history: []
        };
        insertAtGroupTop(records, record);
      }

      records = normalizeRecordOrders(records);
      saveInstalledRecords(records);
      notifyListeners();
      return jsonClone(record);
    }

    function updateRecord(idOrInstanceId, patch) {
      if (!isPlainObject(patch)) {
        throw new Error('updateRecord patch must be an object');
      }
      var records = loadInstalledRecords();
      var idx = findRecordIndex(records, idOrInstanceId);
      if (idx < 0) {
        throw new Error('Installed vibe record not found: ' + idOrInstanceId);
      }
      var prev = records[idx];
      var next = jsonClone(prev);

      if (hasOwn(patch, 'vibe') && patch.vibe !== undefined) {
        var nextVibe = canonicalVibeCopy(patch.vibe);
        var capCheck = check(nextVibe);
        if (!capCheck.ok) {
          throw new Error('Cannot update vibe; missing capabilities: ' + capCheck.missing.join(', '));
        }
        if (vibeChangedForHistory(prev.vibe, nextVibe)) {
          next.history.unshift({
            vibe: jsonClone(prev.vibe),
            title: prev.title,
            savedAt: prev.updatedAt || prev.installedAt
          });
          next.history = next.history.slice(0, MAX_HISTORY_ENTRIES);
        }
        next.vibe = nextVibe;
        if (!(hasOwn(patch, 'title') && patch.title !== undefined) && prev.title === prev.vibe.name) {
          next.title = nextVibe.name;
        }
      }

      if (hasOwn(patch, 'title') && patch.title !== undefined) {
        next.title = normalizeTitle(patch.title, next.vibe.name);
      }
      if (hasOwn(patch, 'note') && patch.note !== undefined) {
        next.note = normalizeNote(patch.note);
      }
      if (hasOwn(patch, 'args')) {
        var nextArgs = patch.args !== undefined && patch.args !== null ? jsonClone(patch.args) : null;
        if (nextArgs !== null) assertJsonSafe(nextArgs);
        next.args = nextArgs;
      }

      var pinnedChanged = false;
      if (hasOwn(patch, 'pinned') && patch.pinned !== undefined) {
        var nextPinned = Boolean(patch.pinned);
        pinnedChanged = nextPinned !== prev.pinned;
        next.pinned = nextPinned;
      }
      if (hasOwn(patch, 'paused') && patch.paused !== undefined) {
        next.paused = Boolean(patch.paused);
      }
      if (hasOwn(patch, 'collapsed') && patch.collapsed !== undefined) {
        next.collapsed = Boolean(patch.collapsed);
      }

      next.updatedAt = Date.now();

      if (pinnedChanged) {
        records.splice(idx, 1);
        insertAtGroupTop(records, next);
      } else {
        records[idx] = next;
      }

      records = normalizeRecordOrders(records);
      saveInstalledRecords(records);
      notifyListeners();
      return jsonClone(next);
    }

    function revertRecord(idOrInstanceId, historyIndex) {
      var hi = typeof historyIndex === 'number' && Number.isInteger(historyIndex) ? historyIndex : 0;
      var records = loadInstalledRecords();
      var idx = findRecordIndex(records, idOrInstanceId);
      if (idx < 0) {
        throw new Error('Installed vibe record not found: ' + idOrInstanceId);
      }
      var prev = records[idx];
      if (!Array.isArray(prev.history) || hi < 0 || hi >= prev.history.length) {
        throw new Error('History version not found at index ' + hi);
      }
      var entry = prev.history[hi];
      var restoredVibe = canonicalVibeCopy(entry.vibe);
      var capCheck = check(restoredVibe);
      if (!capCheck.ok) {
        throw new Error('Cannot revert vibe; missing capabilities: ' + capCheck.missing.join(', '));
      }

      var nextHistory = prev.history.slice();
      nextHistory.splice(hi, 1);
      nextHistory.unshift({
        vibe: jsonClone(prev.vibe),
        title: prev.title,
        savedAt: prev.updatedAt || prev.installedAt
      });
      nextHistory = nextHistory.slice(0, MAX_HISTORY_ENTRIES);

      var updated = {
        instanceId: prev.instanceId,
        vibe: restoredVibe,
        title: normalizeTitle(entry.title, restoredVibe.name),
        note: prev.note,
        origin: prev.origin,
        args: prev.args,
        pinned: prev.pinned,
        paused: prev.paused,
        collapsed: prev.collapsed,
        order: prev.order,
        installedAt: prev.installedAt,
        updatedAt: Date.now(),
        history: nextHistory
      };

      records[idx] = updated;
      records = normalizeRecordOrders(records);
      saveInstalledRecords(records);
      notifyListeners();
      return jsonClone(updated);
    }

    function reorder(orderedInstanceIds) {
      if (!Array.isArray(orderedInstanceIds)) {
        throw new Error('reorder requires an array of instanceIds');
      }
      var records = loadInstalledRecords();
      var rank = new Map();
      for (var i = 0; i < orderedInstanceIds.length; i++) {
        var id = orderedInstanceIds[i];
        if (typeof id === 'string' && !rank.has(id)) {
          rank.set(id, i);
        }
      }
      var decorated = [];
      for (var j = 0; j < records.length; j++) {
        decorated.push({ rec: records[j], orig: j });
      }
      decorated.sort(function (a, b) {
        if (a.rec.pinned !== b.rec.pinned) {
          return a.rec.pinned ? -1 : 1;
        }
        var hasA = rank.has(a.rec.instanceId);
        var hasB = rank.has(b.rec.instanceId);
        if (hasA && hasB) return rank.get(a.rec.instanceId) - rank.get(b.rec.instanceId);
        if (hasA !== hasB) return hasA ? -1 : 1;
        return a.orig - b.orig;
      });
      var next = [];
      for (var k = 0; k < decorated.length; k++) {
        next.push(decorated[k].rec);
      }
      next = normalizeRecordOrders(next);
      saveInstalledRecords(next);
      notifyListeners();
      return jsonClone(next);
    }

    function uninstall(idOrInstanceId) {
      if (typeof idOrInstanceId !== 'string') return null;
      var records = loadInstalledRecords();
      var idx = findRecordIndex(records, idOrInstanceId);
      if (idx < 0) return null;
      var removed = records.splice(idx, 1)[0];
      records = normalizeRecordOrders(records);
      saveInstalledRecords(records);
      notifyListeners();
      return jsonClone(removed);
    }

    function restoreRecord(recordSnapshot, index) {
      if (!isPlainObject(recordSnapshot) || !recordSnapshot.vibe) {
        throw new Error('restoreRecord requires a valid record snapshot');
      }
      var norm = normalizeRecord(recordSnapshot, 0);
      var records = loadInstalledRecords().filter(function (r) {
        return r.instanceId !== norm.instanceId;
      });
      var pos = typeof index === 'number' && Number.isInteger(index)
        ? Math.max(0, Math.min(records.length, index))
        : 0;
      records.splice(pos, 0, norm);
      records = normalizeRecordOrders(records);
      saveInstalledRecords(records);
      notifyListeners();
      return jsonClone(norm);
    }

    function installed() {
      return jsonClone(loadInstalledRecords());
    }

    function onChange(listener) {
      if (typeof listener !== 'function') {
        throw new Error('onChange requires a listener function');
      }
      listeners.add(listener);
      return function unsubscribe() {
        listeners.delete(listener);
      };
    }

    function mount(vibe, element, options) {
      if (!element || typeof element.appendChild !== 'function') {
        throw new Error('host.mount requires a valid DOM element');
      }
      var opts = isPlainObject(options) ? options : {};
      var dataMode = opts.data === 'sample' ? 'sample' : 'live';
      var mountArgs = opts.args !== undefined ? jsonClone(opts.args) : null;
      var onUpdate = typeof opts.onUpdate === 'function' ? opts.onUpdate : null;

      var ledgerState = {
        reads: {},
        sent: 0,
        changed: 0,
        calls: 0,
        lastError: null
      };
      var sourceHealth = {
        state: dataMode === 'sample' ? 'sample' : 'live',
        issues: [],
        lastGoodAt: null,
        usingSampleFallback: false
      };
      var latestInput = null;
      var latestOutput = null;
      var vibeState = null;
      var stopped = false;
      var initialized = false;
      var hasOpened = false;
      var showingLiveDom = false;
      var inFlight = false;
      var activeCallId = 0;
      var pendingAction = null;
      var pendingDataRefresh = false;
      var callTimeoutId = null;
      var refreshIntervalId = null;
      var iframe = null;
      var messageHandler = null;
      var token = randomToken();

      function syncSourceChange() {
        if (stopped) return;
        if (dataMode === 'live') {
          run.retry();
        } else if (sourceHealth.usingSampleFallback) {
          sourceHealth.issues = evaluateCapabilitiesStatus(cleanVibe.needs).issues;
          safeOnUpdate();
        }
      }

      var run = {
        stop: function () {
          stopRun();
        },
        inspect: function () {
          return {
            input: latestInput === null ? null : jsonClone(latestInput),
            output: latestOutput === null ? null : jsonClone(latestOutput)
          };
        },
        ledger: function () {
          return {
            reads: jsonClone(ledgerState.reads),
            sent: ledgerState.sent,
            changed: ledgerState.changed,
            calls: ledgerState.calls,
            lastError: ledgerState.lastError
          };
        },
        health: function () {
          return {
            state: sourceHealth.state,
            issues: jsonClone(sourceHealth.issues),
            lastGoodAt: sourceHealth.lastGoodAt,
            usingSampleFallback: sourceHealth.usingSampleFallback
          };
        },
        retry: function () {
          if (stopped) return;
          if (!initialized || inFlight) {
            pendingDataRefresh = true;
            return;
          }
          dispatchCall(hasOpened ? 'refresh' : 'open', mountArgs);
        },
        setDataMode: function (mode) {
          if (mode !== 'live' && mode !== 'sample') {
            throw new Error("setDataMode requires 'live' or 'sample'");
          }
          if (stopped) return;
          dataMode = mode;
          sourceHealth.usingSampleFallback = (mode === 'sample');
          if (!initialized || inFlight) {
            pendingDataRefresh = true;
            return;
          }
          dispatchCall(hasOpened ? 'refresh' : 'open', mountArgs);
        }
      };

      function safeOnUpdate() {
        if (!onUpdate) return;
        try {
          onUpdate(run);
        } catch (e) {
          // Never let callback exception escape
        }
      }

      function clearCallTimeout() {
        if (callTimeoutId !== null) {
          clearTimeout(callTimeoutId);
          callTimeoutId = null;
        }
      }

      function cleanupSandbox() {
        clearCallTimeout();
        activeRuns.delete(syncSourceChange);
        if (refreshIntervalId !== null) {
          clearInterval(refreshIntervalId);
          refreshIntervalId = null;
        }
        if (messageHandler && typeof window !== 'undefined') {
          try {
            window.removeEventListener('message', messageHandler);
          } catch (e) {}
          messageHandler = null;
        }
        if (iframe) {
          try {
            if (iframe.contentWindow) {
              iframe.contentWindow.postMessage({ type: 'vp-terminate', token: token }, '*');
            }
          } catch (e) {}
          try {
            if (iframe.parentNode) iframe.parentNode.removeChild(iframe);
          } catch (e) {}
          iframe = null;
        }
      }

      function stopRun() {
        if (stopped) return;
        stopped = true;
        inFlight = false;
        pendingAction = null;
        pendingDataRefresh = false;
        if (element && element.classList) {
          element.classList.remove('vk-view-stale');
        }
        cleanupSandbox();
      }

      function failRun(message, shouldStop) {
        clearCallTimeout();
        inFlight = false;
        showingLiveDom = false;
        ledgerState.lastError = String(message || 'Vibe error');
        latestOutput = null;
        if (shouldStop) {
          stopRun();
        }
        renderError(element, ledgerState.lastError);
        safeOnUpdate();
      }

      function applyUnavailableState(issues) {
        var aggState = aggregateSourceState(issues);
        sourceHealth.state = aggState;
        sourceHealth.issues = jsonClone(issues);
        sourceHealth.usingSampleFallback = false;
        if (sourceHealth.lastGoodAt !== null && showingLiveDom) {
          if (element && element.classList) {
            element.classList.add('vk-view-stale');
          }
        } else {
          showingLiveDom = false;
          renderUnavailable(element, aggState, issues);
        }
      }

      var cleanVibe;
      try {
        cleanVibe = canonicalVibeCopy(vibe);
        if (mountArgs !== null) assertJsonSafe(mountArgs);
      } catch (err) {
        ledgerState.lastError = err && err.message ? err.message : String(err);
        stopped = true;
        renderError(element, ledgerState.lastError);
        safeOnUpdate();
        return run;
      }

      for (var i = 0; i < cleanVibe.needs.length; i++) {
        ledgerState.reads[cleanVibe.needs[i]] = 0;
      }

      if (dataMode === 'live') {
        var initialStatus = evaluateCapabilitiesStatus(cleanVibe.needs);
        if (initialStatus.issues.length > 0) {
          applyUnavailableState(initialStatus.issues);
          Promise.resolve().then(function () {
            if (!stopped) safeOnUpdate();
          });
        }
      }

      function dispatchCall(command, callArgs) {
        if (stopped || !initialized || !iframe || !iframe.contentWindow) return;
        if (inFlight) {
          if (command !== 'open' && command !== 'refresh') {
            pendingAction = { command: command, args: callArgs };
          }
          return;
        }

        var input;
        var capIssues = [];
        var rawByCap = {};

        if (dataMode === 'sample') {
          var sampleStatus = evaluateCapabilitiesStatus(cleanVibe.needs);
          for (var si = 0; si < sampleStatus.issues.length; si++) {
            if (sampleStatus.issues[si].state === 'missing') {
              capIssues.push(sampleStatus.issues[si]);
            }
          }
          if (capIssues.length === 0) {
            for (var sc = 0; sc < cleanVibe.needs.length; sc++) {
              var sCapName = cleanVibe.needs[sc];
              var sCap = capByName.get(sCapName);
              rawByCap[sCapName] = Array.isArray(sCap.sample) ? sCap.sample : [];
            }
          }
        } else {
          var liveStatus = evaluateCapabilitiesStatus(cleanVibe.needs);
          capIssues = liveStatus.issues.slice();
          if (capIssues.length === 0) {
            for (var c = 0; c < cleanVibe.needs.length; c++) {
              var capName = cleanVibe.needs[c];
              if (hasOwn(rawByCap, capName)) continue;
              var cap = capByName.get(capName);
              var hasSample = Array.isArray(cap.sample) && cap.sample.length > 0;
              try {
                var rawRows = cap.read();
                if (!Array.isArray(rawRows)) {
                  if (isPlainObject(rawRows) && rawRows.available === false) {
                    var rMode = rawRows.mode === 'revoked' ? 'revoked' : 'offline';
                    capIssues.push({
                      capability: capName,
                      title: cap.title || capName,
                      state: rMode,
                      reason: typeof rawRows.reason === 'string' && rawRows.reason.trim()
                        ? rawRows.reason
                        : (rMode === 'revoked' ? 'Access to this data source is turned off' : 'Data source is offline'),
                      hasSample: hasSample
                    });
                  } else {
                    capIssues.push({
                      capability: capName,
                      title: cap.title || capName,
                      state: 'offline',
                      reason: 'Source returned unavailable data',
                      hasSample: hasSample
                    });
                  }
                } else {
                  rawByCap[capName] = rawRows;
                }
              } catch (err) {
                capIssues.push({
                  capability: capName,
                  title: cap.title || capName,
                  state: 'offline',
                  reason: err && err.message ? err.message : String(err),
                  hasSample: hasSample
                });
              }
            }
          }
        }

        if (capIssues.length > 0) {
          applyUnavailableState(capIssues);
          safeOnUpdate();
          return;
        }

        try {
          var data = {};
          for (var dc = 0; dc < cleanVibe.needs.length; dc++) {
            var dCapName = cleanVibe.needs[dc];
            var dCap = capByName.get(dCapName);
            ledgerState.reads[dCapName] = (ledgerState.reads[dCapName] || 0) + 1;
            data[dCapName] = sealRows(rawByCap[dCapName], dCap.fields);
          }
          ledgerState.calls += 1;

          input = {
            command: String(command),
            args: callArgs === undefined ? null : jsonClone(callArgs),
            state: vibeState === undefined ? null : jsonClone(vibeState),
            data: data,
            host: { id: hostId, name: hostName },
            now: Date.now()
          };
          latestInput = jsonClone(input);
        } catch (err) {
          failRun('Failed to read host data: ' + (err && err.message ? err.message : String(err)), true);
          return;
        }

        inFlight = true;
        activeCallId += 1;
        var thisCallId = activeCallId;
        var callDataMode = dataMode;

        clearCallTimeout();
        callTimeoutId = setTimeout(function () {
          try {
            if (stopped || activeCallId !== thisCallId) return;
            failRun('Vibe timed out after 1000 ms', true);
          } catch (e) {
            // Never escape timer
          }
        }, CALL_TIMEOUT_MS);

        try {
          iframe.contentWindow.postMessage({
            type: 'vp-invoke',
            token: token,
            callId: thisCallId,
            inputJson: JSON.stringify(input),
            dataMode: callDataMode
          }, '*');
        } catch (err) {
          failRun('Sandbox communication failed: ' + (err && err.message ? err.message : String(err)), true);
        }
      }

      function handleAction(command, args) {
        if (stopped) return;
        dispatchCall(command, args);
      }

      function startInitTimeout() {
        clearCallTimeout();
        callTimeoutId = setTimeout(function () {
          try {
            if (stopped || initialized) return;
            failRun('Vibe startup timed out', true);
          } catch (e) {
            // Never escape timer
          }
        }, INIT_TIMEOUT_MS);
      }

      if (typeof document === 'undefined' || typeof window === 'undefined') {
        failRun('Browser DOM is required to mount vibes', true);
        return run;
      }

      activeRuns.add(syncSourceChange);

      iframe = document.createElement('iframe');
      iframe.setAttribute('sandbox', 'allow-scripts');
      iframe.setAttribute('aria-hidden', 'true');
      iframe.style.display = 'none';
      iframe.style.width = '0';
      iframe.style.height = '0';
      iframe.style.border = '0';
      iframe.srcdoc = SANDBOX_SRCDOC;

      messageHandler = function (ev) {
        try {
          if (stopped || !iframe || !iframe.contentWindow) return;
          if (ev.source !== iframe.contentWindow) return;
          var msg = ev.data;
          if (!msg || typeof msg !== 'object') return;

          if (msg.type === 'vp-ready') {
            if (initialized) return;
            iframe.contentWindow.postMessage({
              type: 'vp-init',
              token: token,
              source: cleanVibe.source
            }, '*');
            return;
          }

          if (msg.token !== token) return;

          if (msg.type === 'vp-init-error') {
            failRun(msg.error || 'Vibe compilation error', true);
            return;
          }

          if (msg.type === 'vp-init-ok') {
            if (initialized) return;
            initialized = true;
            clearCallTimeout();
            pendingDataRefresh = false;
            dispatchCall('open', mountArgs);
            if (!stopped && cleanVibe.refresh) {
              refreshIntervalId = setInterval(function () {
                try {
                  if (!stopped && initialized) {
                    dispatchCall(hasOpened ? 'refresh' : 'open', mountArgs);
                  }
                } catch (e) {
                  // Never escape interval
                }
              }, cleanVibe.refresh);
            }
            return;
          }

          if (msg.type === 'vp-result') {
            if (msg.callId !== activeCallId) return;
            clearCallTimeout();
            inFlight = false;

            if (!msg.ok) {
              failRun(msg.error || 'Vibe execution failed', false);
              return;
            }

            var output;
            try {
              output = validateOutputPayload(msg.outputJson);
              output.view = maybeAdaptExternalUi(output.view);
            } catch (err) {
              failRun(err && err.message ? err.message : String(err), false);
              return;
            }

            vibeState = output.state;
            latestOutput = jsonClone(output);
            ledgerState.lastError = null;
            hasOpened = true;

            try {
              if (element && element.classList) {
                element.classList.remove('vk-view-stale');
              }
              renderView(output.view, element, {
                resolve: resolveHandle,
                onAction: handleAction
              });
            } catch (err) {
              failRun('Render failed: ' + (err && err.message ? err.message : String(err)), false);
              return;
            }

            if (dataMode === 'live') {
              showingLiveDom = true;
              sourceHealth.state = 'live';
              sourceHealth.issues = [];
              sourceHealth.lastGoodAt = Date.now();
              sourceHealth.usingSampleFallback = false;
            } else {
              showingLiveDom = false;
              sourceHealth.state = 'sample';
              sourceHealth.issues = sourceHealth.usingSampleFallback
                ? evaluateCapabilitiesStatus(cleanVibe.needs).issues
                : [];
            }

            safeOnUpdate();

            if (!stopped && pendingAction) {
              var next = pendingAction;
              pendingAction = null;
              dispatchCall(next.command, next.args);
            } else if (!stopped && pendingDataRefresh) {
              pendingDataRefresh = false;
              dispatchCall(hasOpened ? 'refresh' : 'open', mountArgs);
            }
          }
        } catch (err) {
          failRun('Unexpected sandbox error: ' + (err && err.message ? err.message : String(err)), true);
        }
      };

      window.addEventListener('message', messageHandler);
      startInitTimeout();

      var container = document.body || document.documentElement;
      if (!container) {
        failRun('No document container available for sandbox', true);
        return run;
      }
      container.appendChild(iframe);
      return run;
    }

    return {
      id: hostId,
      name: hostName,
      locale: hostLocale,
      strings: hostStrings,
      manifest: manifest,
      seal: seal,
      check: check,
      label: label,
      sourceStatus: sourceStatus,
      notifySourceChange: notifySourceChange,
      install: install,
      updateRecord: updateRecord,
      revertRecord: revertRecord,
      reorder: reorder,
      uninstall: uninstall,
      restoreRecord: restoreRecord,
      installed: installed,
      onChange: onChange,
      mount: mount
    };
  }

  var DEMO_LOCALE_PACKS = {
    en: {
      locale: 'en',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: 'What {host} offers',
      wishPlaceholder: 'I wish {host} would\u2026',
      send: 'Send',
      wishNote: 'The AI is scripted in this demo. Pick a wish.',
      installed: 'Installed',
      filterPlaceholder: 'Filter installed vibes\u2026',
      emptyInstalled: 'Nothing here yet. Make a wish.',
      sealedLegend: 'Values with a lock are sealed. {host} draws them. The vibe never sees them.',
      portableVibes: 'Portable vibes',
      portableSub: 'These need nothing from the app, so they run anywhere.',
      reads: 'Reads',
      shows: 'Shows',
      cannot: 'Cannot',
      onlyInsideBox: 'Only inside its own box',
      changeNothing: 'Change anything in {host}',
      nothingFromHost: 'Nothing from {host}',
      allowAndAdd: 'Allow and add',
      update: 'Update',
      cancel: 'Cancel',
      noNewPermissions: 'Version {version}. No new permissions.',
      inspect: 'Inspect',
      hideInspect: 'Hide inspect',
      share: 'Share',
      edit: 'Edit',
      rename: 'Rename',
      pause: 'Pause',
      resume: 'Resume',
      pinToTop: 'Pin to top',
      unpin: 'Unpin',
      moveUp: 'Move up',
      moveDown: 'Move down',
      revert: 'Revert',
      deleteLabel: 'Delete',
      undo: 'Undo',
      temporary: 'Temporary',
      pinned: 'Pinned',
      pinToVibeSpace: 'Pin to Vibe Space',
      pinnedToVibeSpace: 'Pinned to Vibe Space',
      madeByAgent: 'Made by the agent for this answer',
      retry: 'Retry',
      previewSample: 'Preview sample',
      returnToLive: 'Return to live',
      sourceOffline: 'Source offline',
      sourceRevoked: 'Source access turned off',
      sourceMissing: 'Source unavailable'
    },
    zh: {
      locale: 'zh',
      rtl: false,
      panelTitle: 'Vibe \u7a7a\u95f4',
      whatOffers: '{host} \u63d0\u4f9b\u7684\u80fd\u529b',
      wishPlaceholder: '\u6211\u5e0c\u671b {host} \u80fd\u591f\u2026',
      send: '\u53d1\u9001',
      wishNote: '\u6b64\u6f14\u793a\u4e2d AI \u4e3a\u9884\u8bbe\u811a\u672c\uff0c\u8bf7\u9009\u62e9\u4e00\u4e2a\u613f\u671b\u3002',
      installed: '\u5df2\u5b89\u88c5',
      filterPlaceholder: '\u7b5b\u9009\u5df2\u5b89\u88c5\u7684 vibe\u2026',
      emptyInstalled: '\u6682\u65e0\u5185\u5bb9\uff0c\u8bd5\u8bd5\u5199\u4e0b\u4e00\u4e2a\u613f\u671b\u3002',
      sealedLegend: '\u5e26\u9501\u7684\u503c\u5df2\u5c01\u88c5\uff0c\u7531 {host} \u7ed8\u5236\uff0cvibe \u65e0\u6cd5\u770b\u5230\u3002',
      portableVibes: '\u4fbf\u643a vibe',
      portableSub: '\u4e0d\u4f9d\u8d56\u5e94\u7528\u6570\u636e\uff0c\u53ef\u5728\u4efb\u610f\u5bbf\u4e3b\u4e2d\u8fd0\u884c\u3002',
      reads: '\u8bfb\u53d6',
      shows: '\u663e\u793a',
      cannot: '\u7981\u6b62',
      onlyInsideBox: '\u4ec5\u5728\u5176\u81ea\u8eab\u5bb9\u5668\u5185',
      changeNothing: '\u4fee\u6539 {host} \u4e2d\u7684\u4efb\u4f55\u5185\u5bb9',
      nothingFromHost: '\u4e0d\u8bfb\u53d6 {host} \u7684\u4efb\u4f55\u6570\u636e',
      allowAndAdd: '\u5141\u8bb8\u5e76\u6dfb\u52a0',
      update: '\u66f4\u65b0',
      cancel: '\u53d6\u6d88',
      noNewPermissions: '\u7248\u672c {version}\uff0c\u65e0\u65b0\u589e\u6743\u9650\u3002',
      inspect: '\u68c0\u67e5',
      hideInspect: '\u9690\u85cf\u68c0\u67e5',
      share: '\u5206\u4eab',
      edit: '\u7f16\u8f91',
      rename: '\u91cd\u547d\u540d',
      pause: '\u6682\u505c',
      resume: '\u6062\u590d',
      pinToTop: '\u7f6e\u9876',
      unpin: '\u53d6\u6d88\u7f6e\u9876',
      moveUp: '\u4e0a\u79fb',
      moveDown: '\u4e0b\u79fb',
      revert: '\u8fd8\u539f',
      deleteLabel: '\u5220\u9664',
      undo: '\u64a4\u9500',
      temporary: '\u4e34\u65f6',
      pinned: '\u5df2\u56fa\u5b9a',
      pinToVibeSpace: '\u56fa\u5b9a\u5230 Vibe \u7a7a\u95f4',
      pinnedToVibeSpace: '\u5df2\u56fa\u5b9a\u5230 Vibe \u7a7a\u95f4',
      madeByAgent: '\u7531\u667a\u80fd\u4f53\u4e3a\u6b64\u56de\u590d\u751f\u6210',
      retry: '\u91cd\u8bd5',
      previewSample: '\u9884\u89c8\u793a\u4f8b',
      returnToLive: '\u8fd4\u56de\u5b9e\u65f6\u6570\u636e',
      sourceOffline: '\u6570\u636e\u6e90\u79bb\u7ebf',
      sourceRevoked: '\u6570\u636e\u8bbf\u95ee\u5df2\u5173\u95ed',
      sourceMissing: '\u6570\u636e\u6e90\u4e0d\u53ef\u7528'
    },
    ja: {
      locale: 'ja',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: '{host} \u304c\u63d0\u4f9b\u3059\u308b\u6a5f\u80fd',
      wishPlaceholder: '{host} \u306b\u304a\u9858\u3044\u3059\u308b\u2026',
      send: '\u9001\u4fe1',
      wishNote: '\u3053\u306e\u30c7\u30e2\u306e AI \u306f\u30b9\u30af\u30ea\u30d7\u30c8\u5316\u3055\u308c\u3066\u3044\u307e\u3059\u3002',
      installed: '\u30a4\u30f3\u30b9\u30c8\u30fc\u30eb\u6e08\u307f',
      filterPlaceholder: 'vibe \u3092\u7d5e\u308a\u8fbc\u3080\u2026',
      emptyInstalled: '\u307e\u3060\u3042\u308a\u307e\u305b\u3093\u3002',
      sealedLegend: '\u9375\u4ed8\u304d\u306e\u5024\u306f\u5c01\u5370\u3055\u308c\u3001{host} \u304c\u63cf\u753b\u3057\u307e\u3059\u3002',
      portableVibes: '\u30dd\u30fc\u30bf\u30d6\u30eb vibe',
      portableSub: '\u30a2\u30d7\u30ea\u306e\u30c7\u30fc\u30bf\u4e0d\u8981\u3067\u52d5\u4f5c\u3057\u307e\u3059\u3002',
      reads: '\u8aad\u307f\u53d6\u308a',
      shows: '\u8868\u793a',
      cannot: '\u4e0d\u53ef',
      onlyInsideBox: '\u3053\u306e\u30dc\u30c3\u30af\u30b9\u5185\u306e\u307f',
      changeNothing: '{host} \u306e\u5909\u66f4',
      nothingFromHost: '{host} \u304b\u3089\u306f\u4f55\u3082\u8aad\u307f\u53d6\u308a\u307e\u305b\u3093',
      allowAndAdd: '\u8a31\u53ef\u3057\u3066\u8ffd\u52a0',
      update: '\u66f4\u65b0',
      cancel: '\u30ad\u30e3\u30f3\u30bb\u30eb',
      noNewPermissions: '\u30d0\u30fc\u30b8\u30e7\u30f3 {version}\u3002\u65b0\u3057\u3044\u6a29\u9650\u306f\u3042\u308a\u307e\u305b\u3093\u3002',
      inspect: '\u691c\u67fb',
      hideInspect: '\u691c\u67fb\u3092\u96a0\u3059',
      share: '\u5171\u6709',
      edit: '\u7de8\u96c6',
      rename: '\u540d\u524d\u3092\u5909\u66f4',
      pause: '\u4e00\u6642\u505c\u6b62',
      resume: '\u518d\u958b',
      pinToTop: '\u5148\u982d\u306b\u56fa\u5b9a',
      unpin: '\u56fa\u5b9a\u89e3\u9664',
      moveUp: '\u4e0a\u3078',
      moveDown: '\u4e0b\u3078',
      revert: '\u5143\u306b\u623b\u3059',
      deleteLabel: '\u524a\u9664',
      undo: '\u5143\u306b\u623b\u3059',
      temporary: '\u4e00\u6642\u7684',
      pinned: '\u56fa\u5b9a\u6e08\u307f',
      pinToVibeSpace: 'Vibe Space \u306b\u56fa\u5b9a',
      pinnedToVibeSpace: 'Vibe Space \u306b\u56fa\u5b9a\u3057\u307e\u3057\u305f',
      madeByAgent: '\u3053\u306e\u56de\u7b54\u7528\u306b\u30a8\u30fc\u30b8\u30a7\u30f3\u30c8\u304c\u4f5c\u6210',
      retry: '\u518d\u8a66\u884c',
      previewSample: '\u30b5\u30f3\u30d7\u30eb\u3092\u8868\u793a',
      returnToLive: '\u30e9\u30a4\u30d6\u306b\u623b\u3059',
      sourceOffline: '\u30bd\u30fc\u30b9\u304c\u30aa\u30d5\u30e9\u30a4\u30f3',
      sourceRevoked: '\u30a2\u30af\u30bb\u30b9\u304c\u7121\u52b9\u3067\u3059',
      sourceMissing: '\u30bd\u30fc\u30b9\u304c\u5229\u7528\u3067\u304d\u307e\u305b\u3093'
    },
    ko: {
      locale: 'ko',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: '{host} \uc81c\uacf5 \uae30\ub2a5',
      wishPlaceholder: '{host}\uc5d0\uac8c \uc6d0\ud558\ub294 \uae30\ub2a5\u2026',
      send: '\uc804\uc1a1',
      wishNote: '\uc774 \ub370\ubaa8\uc758 AI\ub294 \uc2a4\ud06c\ub9bd\ud2b8\ub85c \ub3d9\uc791\ud569\ub2c8\ub2e4.',
      installed: '\uc124\uce58\ub428',
      filterPlaceholder: '\uc124\uce58\ub41c vibe \uac80\uc0c9\u2026',
      emptyInstalled: '\uc544\uc9c1 \uc5c6\uc2b5\ub2c8\ub2e4.',
      sealedLegend: '\uc790\ubb3c\uc1e0 \uac12\uc740 \ubd09\uc778\ub418\uc5b4 {host}\uac00 \uadf8\ub9bd\ub2c8\ub2e4.',
      portableVibes: '\ud3ec\ud130\ube14 vibe',
      portableSub: '\uc571 \ub370\uc774\ud130 \uc5c6\uc774 \uc2e4\ud589\ub429\ub2c8\ub2e4.',
      reads: '\uc77d\uae30',
      shows: '\ud45c\uc2dc',
      cannot: '\ubd88\uac00',
      onlyInsideBox: '\uc790\uccb4 \uc0c1\uc790 \ub0b4\ubd80\ub9cc',
      changeNothing: '{host} \ub0b4\uc6a9 \ubcc0\uacbd',
      nothingFromHost: '{host}\uc5d0\uc11c \uc77d\uc9c0 \uc54a\uc74c',
      allowAndAdd: '\ud5c8\uc6a9 \ubc0f \ucd94\uac00',
      update: '\uc5c5\ub370\uc774\ud2b8',
      cancel: '\ucde8\uc18c',
      noNewPermissions: '\ubc84\uc804 {version}. \uc0c8 \uad8c\ud55c \uc5c6\uc74c.',
      inspect: '\uac80\uc0ac',
      hideInspect: '\uac80\uc0ac \uc228\uae30\uae30',
      share: '\uacf5\uc720',
      edit: '\ud3b8\uc9d1',
      rename: '\uc774\ub984 \ubcc0\uacbd',
      pause: '\uc77c\uc2dc\uc911\uc9c0',
      resume: '\uc7ac\uac1c',
      pinToTop: '\uc0c1\ub2e8 \uace0\uc815',
      unpin: '\uace0\uc815 \ud574\uc81c',
      moveUp: '\uc704\ub85c',
      moveDown: '\uc544\ub798\ub85c',
      revert: '\ub418\ub3cc\ub9ac\uae30',
      deleteLabel: '\uc0ad\uc81c',
      undo: '\uc2e4\ud589 \ucde8\uc18c',
      temporary: '\uc784\uc2dc',
      pinned: '\uace0\uc815\ub428',
      pinToVibeSpace: 'Vibe Space\uc5d0 \uace0\uc815',
      pinnedToVibeSpace: 'Vibe Space\uc5d0 \uace0\uc815\ub428',
      madeByAgent: '\uc5d0\uc774\uc804\ud2b8\uac00 \uc0dd\uc131',
      retry: '\uc7ac\uc2dc\ub3c4',
      previewSample: '\uc0d8\ud50c \ubbf8\ub9ac\ubcf4\uae30',
      returnToLive: '\uc2e4\uc2dc\uac04\uc73c\ub85c \ub3cc\uc544\uac00\uae30',
      sourceOffline: '\uc18c\uc2a4 \uc624\ud504\ub77c\uc778',
      sourceRevoked: '\uc18c\uc2a4 \uc811\uadfc \uaebc\uc9d0',
      sourceMissing: '\uc18c\uc2a4 \uc0ac\uc6a9 \ubd88\uac00'
    },
    es: {
      locale: 'es',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: 'Lo que ofrece {host}',
      wishPlaceholder: 'Ojal\u00e1 {host} pudiera\u2026',
      send: 'Enviar',
      wishNote: 'La IA est\u00e1 guionizada en esta demo. Elige un deseo.',
      installed: 'Instalados',
      filterPlaceholder: 'Filtrar vibes instalados\u2026',
      emptyInstalled: 'Nada aqu\u00ed a\u00fan. Pide un deseo.',
      sealedLegend: 'Los valores con candado est\u00e1n sellados. {host} los dibuja; el vibe nunca los ve.',
      portableVibes: 'Vibes port\u00e1tiles',
      portableSub: 'No necesitan nada de la app, as\u00ed que funcionan en cualquier lugar.',
      reads: 'Lee',
      shows: 'Muestra',
      cannot: 'No puede',
      onlyInsideBox: 'Solo dentro de su propia caja',
      changeNothing: 'Cambiar algo en {host}',
      nothingFromHost: 'Nada de {host}',
      allowAndAdd: 'Permitir y a\u00f1adir',
      update: 'Actualizar',
      cancel: 'Cancelar',
      noNewPermissions: 'Versi\u00f3n {version}. Sin permisos nuevos.',
      inspect: 'Inspeccionar',
      hideInspect: 'Ocultar inspecci\u00f3n',
      share: 'Compartir',
      edit: 'Editar',
      rename: 'Renombrar',
      pause: 'Pausar',
      resume: 'Reanudar',
      pinToTop: 'Fijar arriba',
      unpin: 'Desfijar',
      moveUp: 'Subir',
      moveDown: 'Bajar',
      revert: 'Revertir',
      deleteLabel: 'Eliminar',
      undo: 'Deshacer',
      temporary: 'Temporal',
      pinned: 'Fijado',
      pinToVibeSpace: 'Fijar en Vibe Space',
      pinnedToVibeSpace: 'Fijado en Vibe Space',
      madeByAgent: 'Hecho por el agente para esta respuesta',
      retry: 'Reintentar',
      previewSample: 'Ver muestra',
      returnToLive: 'Volver a en vivo',
      sourceOffline: 'Fuente desconectada',
      sourceRevoked: 'Acceso desactivado',
      sourceMissing: 'Fuente no disponible'
    },
    fr: {
      locale: 'fr',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: 'Ce que propose {host}',
      wishPlaceholder: 'Je voudrais que {host}\u2026',
      send: 'Envoyer',
      wishNote: 'L\u2019IA est script\u00e9e dans cette d\u00e9mo. Choisissez un souhait.',
      installed: 'Install\u00e9s',
      filterPlaceholder: 'Filtrer les vibes install\u00e9s\u2026',
      emptyInstalled: 'Rien ici pour le moment. Faites un souhait.',
      sealedLegend: 'Les valeurs verrouill\u00e9es sont scell\u00e9es. {host} les affiche sans les r\u00e9v\u00e9ler.',
      portableVibes: 'Vibes portables',
      portableSub: 'Aucun acc\u00e8s requis, ils fonctionnent partout.',
      reads: 'Lit',
      shows: 'Affiche',
      cannot: 'Ne peut pas',
      onlyInsideBox: 'Uniquement dans sa propre bo\u00eete',
      changeNothing: 'Modifier quoi que ce soit dans {host}',
      nothingFromHost: 'Rien depuis {host}',
      allowAndAdd: 'Autoriser et ajouter',
      update: 'Mettre \u00e0 jour',
      cancel: 'Annuler',
      noNewPermissions: 'Version {version}. Aucune nouvelle permission.',
      inspect: 'Inspecter',
      hideInspect: 'Masquer l\u2019inspection',
      share: 'Partager',
      edit: 'Modifier',
      rename: 'Renommer',
      pause: 'Mettre en pause',
      resume: 'Reprendre',
      pinToTop: '\u00c9pingler en haut',
      unpin: 'D\u00e9s\u00e9pingler',
      moveUp: 'Monter',
      moveDown: 'Descendre',
      revert: 'R\u00e9tablir',
      deleteLabel: 'Supprimer',
      undo: 'Annuler',
      temporary: 'Temporaire',
      pinned: '\u00c9pingl\u00e9',
      pinToVibeSpace: '\u00c9pingler dans Vibe Space',
      pinnedToVibeSpace: '\u00c9pingl\u00e9 dans Vibe Space',
      madeByAgent: 'Cr\u00e9\u00e9 par l\u2019agent pour cette r\u00e9ponse',
      retry: 'R\u00e9essayer',
      previewSample: 'Aper\u00e7u exemple',
      returnToLive: 'Revenir au direct',
      sourceOffline: 'Source hors ligne',
      sourceRevoked: 'Acc\u00e8s d\u00e9sactiv\u00e9',
      sourceMissing: 'Source indisponible'
    },
    de: {
      locale: 'de',
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: 'Was {host} bietet',
      wishPlaceholder: 'Ich w\u00fcnschte, {host} w\u00fcrde\u2026',
      send: 'Senden',
      wishNote: 'Die KI ist in dieser Demo geskriptet. W\u00e4hle einen Wunsch.',
      installed: 'Installiert',
      filterPlaceholder: 'Installierte Vibes filtern\u2026',
      emptyInstalled: 'Noch nichts hier. \u00c4u\u00dfere einen Wunsch.',
      sealedLegend: 'Werte mit Schloss sind versiegelt. {host} zeichnet sie; der Vibe sieht sie nie.',
      portableVibes: 'Portable Vibes',
      portableSub: 'Ben\u00f6tigen nichts von der App und laufen \u00fcberall.',
      reads: 'Liest',
      shows: 'Zeigt',
      cannot: 'Kann nicht',
      onlyInsideBox: 'Nur in seiner eigenen Box',
      changeNothing: 'Etwas in {host} \u00e4ndern',
      nothingFromHost: 'Nichts von {host}',
      allowAndAdd: 'Erlauben & hinzuf\u00fcgen',
      update: 'Aktualisieren',
      cancel: 'Abbrechen',
      noNewPermissions: 'Version {version}. Keine neuen Berechtigungen.',
      inspect: 'Pr\u00fcfen',
      hideInspect: 'Pr\u00fcfung ausblenden',
      share: 'Teilen',
      edit: 'Bearbeiten',
      rename: 'Umbenennen',
      pause: 'Pausieren',
      resume: 'Fortsetzen',
      pinToTop: 'Oben anheften',
      unpin: 'L\u00f6sen',
      moveUp: 'Nach oben',
      moveDown: 'Nach unten',
      revert: 'Zur\u00fccksetzen',
      deleteLabel: 'L\u00f6schen',
      undo: 'R\u00fcckg\u00e4ngig',
      temporary: 'Tempor\u00e4r',
      pinned: 'Angeheftet',
      pinToVibeSpace: 'An Vibe Space anheften',
      pinnedToVibeSpace: 'An Vibe Space angeheftet',
      madeByAgent: 'Vom Agenten f\u00fcr diese Antwort erstellt',
      retry: 'Erneut versuchen',
      previewSample: 'Beispiel ansehen',
      returnToLive: 'Zur\u00fcck zu Live',
      sourceOffline: 'Quelle offline',
      sourceRevoked: 'Zugriff deaktiviert',
      sourceMissing: 'Quelle nicht verf\u00fcgbar'
    },
    ar: {
      locale: 'ar',
      rtl: true,
      panelTitle: '\u0645\u0633\u0627\u062d\u0629 Vibe',
      whatOffers: '\u0645\u0627 \u064a\u0642\u062f\u0645\u0647 {host}',
      wishPlaceholder: '\u0623\u062a\u0645\u0646\u0649 \u0644\u0648 \u064a\u0642\u0648\u0645 {host} \u0628\u0640\u2026',
      send: '\u0625\u0631\u0633\u0627\u0644',
      wishNote: '\u0627\u0644\u0630\u0643\u0627\u0621 \u0627\u0644\u0627\u0635\u0637\u0646\u0627\u0639\u064a \u0641\u064a \u0647\u0630\u0627 \u0627\u0644\u0639\u0631\u0636 \u0645\u0628\u0631\u0645\u062c \u0645\u0633\u0628\u0642\u064b\u0627.',
      installed: '\u0627\u0644\u0645\u062b\u0628\u062a\u0629',
      filterPlaceholder: '\u062a\u0635\u0641\u064a\u0629 \u0627\u0644\u0639\u0646\u0627\u0635\u0631 \u0627\u0644\u0645\u062b\u0628\u062a\u0629\u2026',
      emptyInstalled: '\u0644\u0627 \u064a\u0648\u062c\u062f \u0634\u064a\u0621 \u0628\u0639\u062f.',
      sealedLegend: '\u0627\u0644\u0642\u064a\u0645 \u0630\u0627\u062a \u0627\u0644\u0642\u0641\u0644 \u0645\u062e\u062a\u0648\u0645\u0629. \u064a\u0639\u0631\u0636\u0647\u0627 {host} \u062f\u0648\u0646 \u0623\u0646 \u064a\u0631\u0627\u0647\u0627 \u0627\u0644\u0628\u0631\u0646\u0627\u0645\u062c.',
      portableVibes: '\u0623\u062f\u0648\u0627\u062a \u0645\u062d\u0645\u0648\u0644\u0629',
      portableSub: '\u0644\u0627 \u062a\u062d\u062a\u0627\u062c \u0625\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062a\u0637\u0628\u064a\u0642.',
      reads: '\u064a\u0642\u0631\u0623',
      shows: '\u064a\u0639\u0631\u0636',
      cannot: '\u0644\u0627 \u064a\u0645\u0643\u0646\u0647',
      onlyInsideBox: '\u062f\u0627\u062e\u0644 \u0635\u0646\u062f\u0648\u0642\u0647 \u0641\u0642\u0637',
      changeNothing: '\u062a\u063a\u064a\u064a\u0631 \u0623\u064a \u0634\u064a\u0621 \u0641\u064a {host}',
      nothingFromHost: '\u0644\u0627 \u0634\u064a\u0621 \u0645\u0646 {host}',
      allowAndAdd: '\u0633\u0645\u0627\u062d \u0648\u0625\u0636\u0627\u0641\u0629',
      update: '\u062a\u062d\u062f\u064a\u062b',
      cancel: '\u0625\u0644\u063a\u0627\u0621',
      noNewPermissions: '\u0627\u0644\u0625\u0635\u062f\u0627\u0631 {version}. \u0644\u0627 \u062a\u0648\u062c\u062f \u0623\u0630\u0648\u0646\u0627\u062a \u062c\u062f\u064a\u062f\u0629.',
      inspect: '\u0641\u062d\u0635',
      hideInspect: '\u0625\u062e\u0641\u0627\u0621 \u0627\u0644\u0641\u062d\u0635',
      share: '\u0645\u0634\u0627\u0631\u0643\u0629',
      edit: '\u062a\u0639\u062f\u064a\u0644',
      rename: '\u0625\u0639\u0627\u062f\u0629 \u062a\u0633\u0645\u064a\u0629',
      pause: '\u0625\u064a\u0642\u0627\u0641 \u0645\u0624\u0642\u062a',
      resume: '\u0627\u0633\u062a\u0626\u0646\u0627\u0641',
      pinToTop: '\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0627\u0644\u0623\u0639\u0644\u0649',
      unpin: '\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u062a\u062b\u0628\u064a\u062a',
      moveUp: '\u062a\u062d\u0631\u064a\u0643 \u0644\u0644\u0623\u0639\u0644\u0649',
      moveDown: '\u062a\u062d\u0631\u064a\u0643 \u0644\u0644\u0623\u0633\u0641\u0644',
      revert: '\u0627\u0633\u062a\u0639\u0627\u062f\u0629',
      deleteLabel: '\u062d\u0630\u0641',
      undo: '\u062a\u0631\u0627\u062c\u0639',
      temporary: '\u0645\u0624\u0642\u062a',
      pinned: '\u0645\u062b\u0628\u062a',
      pinToVibeSpace: '\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0645\u0633\u0627\u062d\u0629 Vibe',
      pinnedToVibeSpace: '\u062a\u0645 \u0627\u0644\u062a\u062b\u0628\u064a\u062a \u0641\u064a \u0645\u0633\u0627\u062d\u0629 Vibe',
      madeByAgent: '\u0623\u0646\u0634\u0623\u0647 \u0627\u0644\u0648\u0643\u064a\u0644 \u0644\u0647\u0630\u0647 \u0627\u0644\u0625\u062c\u0627\u0628\u0629',
      retry: '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629',
      previewSample: '\u0645\u0639\u0627\u064a\u0646\u0629 \u0639\u064a\u0646\u0629',
      returnToLive: '\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062d\u064a\u0629',
      sourceOffline: '\u0627\u0644\u0645\u0635\u062f\u0631 \u063a\u064a\u0631 \u0645\u062a\u0635\u0644',
      sourceRevoked: '\u062a\u0645 \u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u0648\u0635\u0648\u0644 \u0644\u0644\u0645\u0635\u062f\u0631',
      sourceMissing: '\u0627\u0644\u0645\u0635\u062f\u0631 \u063a\u064a\u0631 \u0645\u062a\u0627\u062d'
    }
  };

  function isRtlLocale(locale) {
    if (typeof locale !== 'string' || !locale.trim()) return false;
    var base = locale.trim().toLowerCase().split(/[-_]/)[0];
    return base === 'ar' || base === 'he' || base === 'fa' || base === 'ur';
  }

  function getVibeStrings(locale, overrides) {
    var base = typeof locale === 'string' && locale.trim()
      ? locale.trim().toLowerCase().split(/[-_]/)[0]
      : 'en';
    var pack = DEMO_LOCALE_PACKS[base] || DEMO_LOCALE_PACKS.en;
    var merged = {};
    var keys = Object.keys(pack);
    for (var i = 0; i < keys.length; i++) merged[keys[i]] = pack[keys[i]];
    if (isPlainObject(overrides)) {
      var oKeys = Object.keys(overrides);
      for (var j = 0; j < oKeys.length; j++) {
        var ok = oKeys[j];
        if (typeof overrides[ok] === 'string') merged[ok] = overrides[ok];
        else if (ok === 'rtl' && typeof overrides[ok] === 'boolean') merged.rtl = overrides[ok];
      }
    }
    return merged;
  }

  var A2UI_TYPES = new Set([
    'Text', 'Heading', 'Badge', 'Button', 'Card', 'Row', 'Column',
    'TextField', 'CheckBox', 'MultipleChoice', 'ProgressBar', 'LinearProgress',
    'Metric', 'Stat', 'Table', 'Divider', 'Bar', 'Sparkline'
  ]);

  function isExternalUiDialect(raw) {
    if (typeof raw === 'string') return true;
    if (!isPlainObject(raw)) return false;
    if (raw.format === 'markdown' || typeof raw.markdown === 'string') return true;
    if (raw.type === 'AdaptiveCard') return true;
    if (isPlainObject(raw.surfaceUpdate) && Array.isArray(raw.surfaceUpdate.components)) return true;
    if (Array.isArray(raw.components)) return true;
    if (isPlainObject(raw.component)) return true;
    return typeof raw.type === 'string' && A2UI_TYPES.has(raw.type);
  }

  function sanitizeAdapterSlot(val) {
    if (isSealedHandle(val)) return { sealed: val.sealed };
    if (typeof val === 'number' && Number.isFinite(val)) return val;
    if (typeof val === 'string') return val.length > 4096 ? val.slice(0, 4096) : val;
    if (typeof val === 'boolean') return String(val);
    if (isPlainObject(val)) {
      if (typeof val.sealed === 'string' && val.sealed.length > 0) return { sealed: val.sealed };
      if (typeof val.literalString === 'string') return sanitizeAdapterSlot(val.literalString);
      if (typeof val.literalNumber === 'number') return sanitizeAdapterSlot(val.literalNumber);
      if (val.text !== undefined) return sanitizeAdapterSlot(val.text);
    }
    return '';
  }

  function mapAdapterTone(color) {
    var c = typeof color === 'string' ? color.toLowerCase() : '';
    if (c === 'good' || c === 'ok') return 'ok';
    if (c === 'warning' || c === 'warn') return 'warn';
    if (c === 'attention' || c === 'danger') return 'danger';
    return 'default';
  }

  function adaptMarkdownView(md) {
    var lines = String(md || '').slice(0, 65536).split(/\r?\n/);
    var children = [];
    for (var i = 0; i < lines.length && children.length < 200; i++) {
      var line = lines[i].trim();
      if (!line) continue;
      if (/^---+$/.test(line) || /^\*\*\*+$/.test(line)) {
        children.push({ type: 'divider' });
        continue;
      }
      var hm = line.match(/^#{1,6}\s+(.+)$/);
      if (hm) {
        children.push({ type: 'heading', text: hm[1].trim() });
        continue;
      }
      if (line.indexOf('|') === 0 && i + 1 < lines.length && /^\|[\s:-]+\|/.test(lines[i + 1].trim())) {
        var splitRow = function (r) {
          return r.replace(/^\|/, '').replace(/\|$/, '').split('|').map(function (c) { return c.trim(); });
        };
        var headers = splitRow(line);
        i += 2;
        var rows = [];
        while (i < lines.length && lines[i].trim().indexOf('|') === 0 && rows.length < 100) {
          rows.push(splitRow(lines[i].trim()));
          i += 1;
        }
        i -= 1;
        children.push({ type: 'table', headers: headers, rows: rows });
        continue;
      }
      var lm = line.match(/^[-*+]\s+(.+)$/);
      children.push({ type: 'text', text: lm ? ('\u2022 ' + lm[1].trim()) : line });
    }
    return { type: 'column', children: children };
  }

  function adaptAdaptiveNode(node, budget) {
    if (!isPlainObject(node) || budget.count >= MAX_VIEW_NODES) return null;
    budget.count += 1;
    var t = node.type;
    if (t === 'TextBlock') {
      var tone = mapAdapterTone(node.color);
      if (node.style === 'heading' || node.size === 'Large' || node.size === 'ExtraLarge' || node.size === 'Medium') {
        return { type: 'heading', text: sanitizeAdapterSlot(node.text), tone: tone };
      }
      return { type: 'text', text: sanitizeAdapterSlot(node.text), tone: tone, strong: node.weight === 'Bolder' };
    }
    if (t === 'Container' || t === 'Column') {
      var items = Array.isArray(node.items) ? node.items : [];
      var kids = [];
      for (var i = 0; i < items.length; i++) {
        var child = adaptAdaptiveNode(items[i], budget);
        if (child) kids.push(child);
      }
      return {
        type: t === 'Container' && node.style ? 'card' : 'column',
        children: kids,
        tone: mapAdapterTone(node.style)
      };
    }
    if (t === 'ColumnSet') {
      var cols = Array.isArray(node.columns) ? node.columns : [];
      var rowKids = [];
      for (var c = 0; c < cols.length; c++) {
        var cNode = adaptAdaptiveNode(cols[c], budget);
        if (cNode) rowKids.push(cNode);
      }
      return { type: 'row', children: rowKids };
    }
    if (t === 'FactSet') {
      var facts = Array.isArray(node.facts) ? node.facts : [];
      return {
        type: 'table',
        headers: ['Key', 'Value'],
        rows: facts.slice(0, 100).map(function (f) {
          return [sanitizeAdapterSlot(f && f.title), sanitizeAdapterSlot(f && f.value)];
        })
      };
    }
    if (t === 'ActionSet') {
      var acts = Array.isArray(node.actions) ? node.actions : [];
      var aKids = [];
      for (var a = 0; a < acts.length; a++) {
        var aNode = adaptAdaptiveNode(acts[a], budget);
        if (aNode) aKids.push(aNode);
      }
      return { type: 'row', children: aKids };
    }
    if (t === 'Action.Submit' || t === 'Action.Execute') {
      var cmd = typeof node.verb === 'string' && node.verb ? node.verb : (node.data && typeof node.data.command === 'string' ? node.data.command : 'submit');
      return {
        type: 'button',
        text: sanitizeAdapterSlot(node.title || 'Run'),
        command: cmd,
        args: isPlainObject(node.data) ? jsonClone(node.data) : undefined,
        tone: node.style === 'destructive' ? 'danger' : (node.style === 'positive' ? 'ok' : 'default')
      };
    }
    if (t === 'ProgressBar') {
      var pv = typeof node.value === 'number' && Number.isFinite(node.value) ? Math.max(0, Math.min(1, node.value)) : 0;
      return { type: 'bar', label: sanitizeAdapterSlot(node.title || 'Progress'), value: pv, max: 1 };
    }
    return null;
  }

  function adaptA2uiTree(nodeOrId, byId, visiting, depth, budget) {
    if (depth >= MAX_VIEW_DEPTH || budget.count >= MAX_VIEW_NODES) return null;
    var comp = nodeOrId;
    var idKey = null;
    if (typeof nodeOrId === 'string') {
      if (visiting.has(nodeOrId)) return null;
      comp = byId.get(nodeOrId);
      if (!comp) return null;
      idKey = nodeOrId;
      visiting.add(nodeOrId);
    }
    var out = null;
    try {
      if (!isPlainObject(comp)) return null;
      budget.count += 1;
      var typeName = comp.type;
      var props = comp;
      if (isPlainObject(comp.component)) {
        var keys = Object.keys(comp.component);
        if (keys.length > 0) {
          typeName = keys[0];
          props = isPlainObject(comp.component[typeName]) ? comp.component[typeName] : {};
        }
      }
      var collectChildren = function (rawKids) {
        var refs = [];
        if (Array.isArray(rawKids)) refs = rawKids;
        else if (isPlainObject(rawKids) && Array.isArray(rawKids.explicitList)) refs = rawKids.explicitList;
        else if (typeof props.child === 'string') refs = [props.child];
        var res = [];
        for (var i = 0; i < refs.length; i++) {
          var child = adaptA2uiTree(refs[i], byId, visiting, depth + 1, budget);
          if (child) res.push(child);
        }
        return res;
      };
      var tone = VALID_TONES.has(props.tone) ? props.tone : 'default';
      if (typeName === 'Heading') out = { type: 'heading', text: sanitizeAdapterSlot(props.text), tone: tone };
      else if (typeName === 'Text') {
        var hint = typeof props.usageHint === 'string' ? props.usageHint.toLowerCase() : '';
        out = (hint === 'h1' || hint === 'h2' || hint === 'h3' || hint === 'heading')
          ? { type: 'heading', text: sanitizeAdapterSlot(props.text), tone: tone }
          : { type: 'text', text: sanitizeAdapterSlot(props.text), tone: tone, strong: Boolean(props.strong || props.bold), mono: Boolean(props.mono || props.code) };
      } else if (typeName === 'Badge') out = { type: 'badge', text: sanitizeAdapterSlot(props.text), tone: tone };
      else if (typeName === 'Metric' || typeName === 'Stat') out = { type: 'stat', label: sanitizeAdapterSlot(props.label), value: sanitizeAdapterSlot(props.value), tone: tone };
      else if (typeName === 'Bar') out = {
        type: 'bar',
        label: sanitizeAdapterSlot(props.label),
        value: Number.isFinite(Number(props.value)) ? Number(props.value) : 0,
        max: Number.isFinite(Number(props.max)) && Number(props.max) > 0 ? Number(props.max) : 1,
        caption: props.caption !== undefined ? sanitizeAdapterSlot(props.caption) : undefined,
        swatch: typeof props.swatch === 'string' && HEX_COLOR_RE.test(props.swatch) ? props.swatch : undefined,
        tone: tone
      };
      else if (typeName === 'Sparkline') out = {
        type: 'sparkline',
        values: Array.isArray(props.values) ? props.values.filter(function (n) { return typeof n === 'number' && Number.isFinite(n); }).slice(0, 240) : [],
        tone: tone
      };
      else if (typeName === 'Button') {
        var bText = props.text;
        if (bText === undefined && typeof props.child === 'string') {
          var childBtn = adaptA2uiTree(props.child, byId, visiting, depth + 1, budget);
          if (childBtn && childBtn.text !== undefined) bText = childBtn.text;
        }
        var cmdName = isPlainObject(props.action) && typeof props.action.name === 'string' ? props.action.name : (typeof props.command === 'string' ? props.command : 'action');
        var cmdArgs = isPlainObject(props.action) && isPlainObject(props.action.context) ? props.action.context : (isPlainObject(props.args) ? props.args : undefined);
        out = { type: 'button', text: sanitizeAdapterSlot(bText !== undefined ? bText : 'Action'), command: cmdName, args: cmdArgs ? jsonClone(cmdArgs) : undefined, tone: tone };
      } else if (typeName === 'Card') out = { type: 'card', children: collectChildren(props.children), tone: tone };
      else if (typeName === 'Row') out = { type: 'row', children: collectChildren(props.children), tone: tone };
      else if (typeName === 'Column') out = { type: 'column', children: collectChildren(props.children), tone: tone };
      else if (typeName === 'ProgressBar' || typeName === 'LinearProgress') out = {
        type: 'bar',
        label: sanitizeAdapterSlot(props.label || 'Progress'),
        value: typeof props.value === 'number' && Number.isFinite(props.value) ? Math.max(0, Math.min(1, props.value)) : 0,
        max: 1,
        tone: tone
      };
      else if (typeName === 'Table') out = {
        type: 'table',
        headers: (Array.isArray(props.headers) ? props.headers : []).slice(0, 30).map(sanitizeAdapterSlot),
        rows: (Array.isArray(props.rows) ? props.rows : []).slice(0, 200).map(function (r) {
          return (Array.isArray(r) ? r : []).slice(0, 30).map(sanitizeAdapterSlot);
        })
      };
      else if (typeName === 'Divider') out = { type: 'divider' };
    } finally {
      if (idKey !== null) visiting.delete(idKey);
    }
    return out;
  }

  function adaptExternalUi(raw) {
    if (typeof raw === 'string') return adaptMarkdownView(raw);
    if (!isPlainObject(raw)) throw new Error('External UI payload must be an object or markdown string');
    if (raw.format === 'markdown' || typeof raw.markdown === 'string') return adaptMarkdownView(raw.markdown || '');
    if (raw.type === 'AdaptiveCard') {
      var budget = { count: 0 };
      var body = Array.isArray(raw.body) ? raw.body : [];
      var actions = Array.isArray(raw.actions) ? raw.actions : [];
      var children = [];
      for (var i = 0; i < body.length; i++) {
        var bNode = adaptAdaptiveNode(body[i], budget);
        if (bNode) children.push(bNode);
      }
      if (actions.length > 0) {
        var actRow = [];
        for (var j = 0; j < actions.length; j++) {
          var aNode = adaptAdaptiveNode(actions[j], budget);
          if (aNode) actRow.push(aNode);
        }
        if (actRow.length > 0) children.push({ type: 'row', children: actRow });
      }
      return { type: 'column', children: children };
    }
    if (isExternalUiDialect(raw)) {
      var surface = isPlainObject(raw.surfaceUpdate) ? raw.surfaceUpdate : raw;
      if (Array.isArray(surface.components)) {
        var byId = new Map();
        for (var k = 0; k < surface.components.length; k++) {
          var entry = surface.components[k];
          if (isPlainObject(entry) && typeof entry.id === 'string') byId.set(entry.id, entry);
        }
        var rootId = typeof surface.root === 'string'
          ? surface.root
          : (byId.has('root') ? 'root' : (surface.components[0] && surface.components[0].id));
        if (!rootId) return { type: 'column', children: [] };
        return adaptA2uiTree(rootId, byId, new Set(), 0, { count: 0 }) || { type: 'column', children: [] };
      }
      return adaptA2uiTree(raw, new Map(), new Set(), 0, { count: 0 }) || { type: 'column', children: [] };
    }
    return raw;
  }

  function maybeAdaptExternalUi(view) {
    if (!isExternalUiDialect(view)) return view;
    try {
      return adaptExternalUi(view);
    } catch (_) {
      return view;
    }
  }

  function resolveAdapterSlot(val, resolveSealed) {
    if (isSealedHandle(val)) {
      if (typeof resolveSealed !== 'function') return { text: '', sealed: true, sealedResolved: false };
      var res = resolveSealed(val);
      if (res === undefined || res === null || String(res) === '') return { text: '', sealed: true, sealedResolved: false };
      return { text: String(res), sealed: true, sealedResolved: true };
    }
    return { text: val === undefined || val === null ? '' : String(val), sealed: false, sealedResolved: false };
  }

  function resolveViewTree(view, options) {
    var resolveSealed = options && typeof options.resolveSealed === 'function' ? options.resolveSealed : null;
    var normalized = maybeAdaptExternalUi(view);
    function walk(node) {
      if (!isPlainObject(node)) return null;
      var t = node.type;
      var tone = VALID_TONES.has(node.tone) ? node.tone : 'default';
      if (t === 'column' || t === 'row' || t === 'card') {
        return {
          type: t,
          tone: tone,
          children: (Array.isArray(node.children) ? node.children : []).map(walk).filter(Boolean)
        };
      }
      if (t === 'heading' || t === 'text' || t === 'badge') {
        var s = resolveAdapterSlot(node.text, resolveSealed);
        return { type: t, tone: tone, text: s.text, sealed: s.sealed, sealedResolved: s.sealedResolved, strong: Boolean(node.strong), mono: Boolean(node.mono) };
      }
      if (t === 'stat') {
        var sl = resolveAdapterSlot(node.label, resolveSealed);
        var sv = resolveAdapterSlot(node.value, resolveSealed);
        return { type: 'stat', tone: tone, label: sl.text, labelSealed: sl.sealed, labelSealedResolved: sl.sealedResolved, value: sv.text, valueSealed: sv.sealed, valueSealedResolved: sv.sealedResolved };
      }
      if (t === 'bar') {
        var bl = resolveAdapterSlot(node.label, resolveSealed);
        var bc = hasBarCaption(node) ? resolveAdapterSlot(node.caption, resolveSealed) : null;
        var max = typeof node.max === 'number' && node.max > 0 ? node.max : 1;
        var val = typeof node.value === 'number' && Number.isFinite(node.value) ? node.value : 0;
        return {
          type: 'bar',
          tone: tone,
          label: bl.text,
          labelSealed: bl.sealed,
          labelSealedResolved: bl.sealedResolved,
          caption: bc ? bc.text : '',
          captionSealed: bc ? bc.sealed : false,
          captionSealedResolved: bc ? bc.sealedResolved : false,
          value: val,
          max: max,
          ratio: Math.max(0, Math.min(1, val / max)),
          swatch: isValidSwatch(node.swatch) ? node.swatch : undefined
        };
      }
      if (t === 'sparkline') {
        return { type: 'sparkline', tone: tone, values: Array.isArray(node.values) ? node.values.slice() : [] };
      }
      if (t === 'button' || t === 'action') {
        var bt = resolveAdapterSlot(t === 'button' ? node.text : node.title, resolveSealed);
        return { type: 'button', tone: tone, text: bt.text, sealed: bt.sealed, sealedResolved: bt.sealedResolved, command: node.command, args: node.args || node.arguments || {} };
      }
      if (t === 'table') {
        return {
          type: 'table',
          headers: (Array.isArray(node.headers) ? node.headers : []).map(function (h) { return resolveAdapterSlot(h, resolveSealed); }),
          rows: (Array.isArray(node.rows) ? node.rows : []).map(function (r) {
            return (Array.isArray(r) ? r : []).map(function (c) { return resolveAdapterSlot(c, resolveSealed); });
          })
        };
      }
      if (t === 'divider') return { type: 'divider' };
      return null;
    }
    return walk(normalized);
  }

  function renderWithH(h, view, options) {
    if (typeof h !== 'function') throw new Error('renderWithH requires a hyperscript function');
    var opts = options || {};
    var prefix = typeof opts.classPrefix === 'string' && opts.classPrefix ? opts.classPrefix : 'vk';
    var tree = resolveViewTree(view, opts);
    function slotChild(s) {
      if (s.sealed) return s.sealedResolved ? h('span', { className: prefix + '-sealed' }, s.text) : '';
      return s.text;
    }
    function walk(node, key) {
      if (!node) return null;
      var tCls = node.tone && node.tone !== 'default' ? ' ' + prefix + '-tone-' + node.tone : '';
      var t = node.type;
      if (t === 'column' || t === 'row' || t === 'card') {
        return h.apply(null, ['div', { key: key, className: prefix + '-' + t + tCls }].concat((node.children || []).map(walk)));
      }
      if (t === 'heading') return h('div', { key: key, className: prefix + '-heading' + tCls }, slotChild(node));
      if (t === 'text') return h('div', { key: key, className: prefix + '-text' + tCls + (node.strong ? ' ' + prefix + '-strong' : '') + (node.mono ? ' ' + prefix + '-mono' : '') }, slotChild(node));
      if (t === 'badge') return h('span', { key: key, className: prefix + '-badge' + tCls }, slotChild(node));
      if (t === 'stat') return h('div', { key: key, className: prefix + '-stat' + tCls },
        h('div', { className: prefix + '-stat-value' }, slotChild({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved })),
        h('div', { className: prefix + '-stat-label' }, slotChild({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }))
      );
      if (t === 'bar') {
        var head = [];
        if (node.swatch) head.push(h('span', { className: prefix + '-bar-swatch', style: { backgroundColor: node.swatch } }));
        head.push(h('span', { className: prefix + '-bar-label' }, slotChild({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved })));
        if (node.caption || node.captionSealed) head.push(h('span', { className: prefix + '-bar-caption' }, slotChild({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved })));
        return h('div', { key: key, className: prefix + '-bar' + tCls },
          h.apply(null, ['div', { className: prefix + '-bar-head' }].concat(head)),
          h('div', { className: prefix + '-bar-track' }, h('div', { className: prefix + '-bar-fill', style: { width: (Math.round(node.ratio * 1000) / 10) + '%' } }))
        );
      }
      if (t === 'sparkline') return h('svg', { key: key, className: prefix + '-sparkline' + tCls, viewBox: '0 0 100 28', preserveAspectRatio: 'none' }, h('polyline', { points: sparklinePoints(node.values), fill: 'none' }));
      if (t === 'button') return h('button', { key: key, type: 'button', className: prefix + '-button' + tCls, onClick: function () { if (typeof opts.onCommand === 'function') opts.onCommand(node.command, node.args || {}); } }, slotChild(node));
      if (t === 'table') return h('table', { key: key, className: prefix + '-table' },
        h('thead', null, h.apply(null, ['tr', null].concat(node.headers.map(function (hdr, idx) { return h('th', { key: idx }, slotChild(hdr)); })))),
        h.apply(null, ['tbody', null].concat(node.rows.map(function (r, rIdx) {
          return h.apply(null, ['tr', { key: rIdx }].concat(r.map(function (c, cIdx) { return h('td', { key: cIdx }, slotChild(c)); })));
        })))
      );
      if (t === 'divider') return h('hr', { key: key, className: prefix + '-divider' });
      return null;
    }
    return walk(tree, 0);
  }

  function formatPlainSlot(s) {
    if (!s.sealed) return s.text;
    return s.sealedResolved ? '\ud83d\udd12 ' + s.text : '';
  }

  function renderToTerminal(view, options) {
    var opts = options || {};
    var width = typeof opts.width === 'number' ? opts.width : 72;
    var ansi = Boolean(opts.ansi);
    var tree = resolveViewTree(view, opts);
    var lines = [];
    var barWidth = Math.max(10, Math.min(28, Math.floor(width / 3)));
    var sparks = '\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588';
    function colorize(str, tone) {
      if (!ansi) return str;
      if (tone === 'ok') return '\x1b[32m' + str + '\x1b[0m';
      if (tone === 'warn') return '\x1b[33m' + str + '\x1b[0m';
      if (tone === 'danger') return '\x1b[31m' + str + '\x1b[0m';
      return str;
    }
    function walk(node) {
      if (!node) return;
      var t = node.type;
      if (t === 'column' || t === 'row' || t === 'card') {
        for (var i = 0; i < (node.children || []).length; i++) walk(node.children[i]);
        return;
      }
      if (t === 'heading') lines.push(colorize(formatPlainSlot(node).toUpperCase(), node.tone));
      else if (t === 'text') lines.push(colorize(formatPlainSlot(node), node.tone));
      else if (t === 'badge') lines.push(colorize('[' + formatPlainSlot(node) + ']', node.tone));
      else if (t === 'stat') lines.push(formatPlainSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) + ': ' + colorize(formatPlainSlot({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved }), node.tone));
      else if (t === 'bar') {
        var filled = Math.round(node.ratio * barWidth);
        var track = '\u2588'.repeat(filled) + '\u2591'.repeat(Math.max(0, barWidth - filled));
        var lbl = formatPlainSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
        var cap = formatPlainSlot({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved });
        lines.push(lbl + ' ' + colorize(track, node.tone) + (cap ? ' ' + cap : ''));
      } else if (t === 'sparkline' && node.values && node.values.length) {
        var min = Math.min.apply(null, node.values);
        var max = Math.max.apply(null, node.values);
        var span = max - min || 1;
        lines.push(colorize(node.values.map(function (v) { return sparks[Math.max(0, Math.min(7, Math.round(((v - min) / span) * 7)))]; }).join(''), node.tone));
      } else if (t === 'table') {
        if (node.headers.length) {
          lines.push(node.headers.map(formatPlainSlot).join(' | '));
          lines.push(node.headers.map(function () { return '---'; }).join('-|-'));
        }
        for (var r = 0; r < node.rows.length; r++) lines.push(node.rows[r].map(formatPlainSlot).join(' | '));
      } else if (t === 'divider') lines.push('\u2500'.repeat(Math.min(width, 40)));
      else if (t === 'button') lines.push('[ ' + formatPlainSlot(node) + ' ]');
    }
    walk(tree);
    return lines.join('\n');
  }

  function renderToMarkdown(view, options) {
    var tree = resolveViewTree(view, options);
    var lines = [];
    function walk(node) {
      if (!node) return;
      var t = node.type;
      if (t === 'column' || t === 'row' || t === 'card') {
        for (var i = 0; i < (node.children || []).length; i++) walk(node.children[i]);
      } else if (t === 'heading') lines.push('## ' + formatPlainSlot(node));
      else if (t === 'text') lines.push(formatPlainSlot(node));
      else if (t === 'badge') lines.push('`' + formatPlainSlot(node) + '`');
      else if (t === 'stat') lines.push('- **' + formatPlainSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) + ':** ' + formatPlainSlot({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved }));
      else if (t === 'bar') {
        var lbl = formatPlainSlot({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved });
        var cap = formatPlainSlot({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved });
        lines.push('- **' + lbl + '**: ' + (cap || Math.round(node.ratio * 100) + '%'));
      } else if (t === 'table') {
        var hdrs = node.headers.map(formatPlainSlot);
        if (hdrs.length) {
          lines.push('| ' + hdrs.join(' | ') + ' |');
          lines.push('| ' + hdrs.map(function () { return '---'; }).join(' | ') + ' |');
        }
        for (var r = 0; r < node.rows.length; r++) lines.push('| ' + node.rows[r].map(formatPlainSlot).join(' | ') + ' |');
      } else if (t === 'divider') lines.push('---');
      else if (t === 'button') lines.push('[' + formatPlainSlot(node) + ']');
    }
    walk(tree);
    return lines.join('\n');
  }

  function escapeXml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function renderToHtmlString(view, options) {
    var tree = resolveViewTree(view, options);
    function slotXml(s) {
      if (s.sealed) return s.sealedResolved ? '<span class="vk-sealed">' + escapeXml(s.text) + '</span>' : '';
      return escapeXml(s.text);
    }
    function walk(node) {
      if (!node) return '';
      var tCls = node.tone && node.tone !== 'default' ? ' vk-tone-' + escapeXml(node.tone) : '';
      var t = node.type;
      if (t === 'column' || t === 'row' || t === 'card') return '<div class="vk-' + t + tCls + '">' + (node.children || []).map(walk).join('') + '</div>';
      if (t === 'heading') return '<div class="vk-heading' + tCls + '">' + slotXml(node) + '</div>';
      if (t === 'text') return '<div class="vk-text' + tCls + (node.strong ? ' vk-strong' : '') + (node.mono ? ' vk-mono' : '') + '">' + slotXml(node) + '</div>';
      if (t === 'badge') return '<span class="vk-badge' + tCls + '">' + slotXml(node) + '</span>';
      if (t === 'stat') return '<div class="vk-stat' + tCls + '"><div class="vk-stat-value">' + slotXml({ text: node.value, sealed: node.valueSealed, sealedResolved: node.valueSealedResolved }) + '</div><div class="vk-stat-label">' + slotXml({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) + '</div></div>';
      if (t === 'bar') {
        var sw = node.swatch && HEX_COLOR_RE.test(node.swatch) ? '<span class="vk-bar-swatch" style="background-color:' + node.swatch + '"></span>' : '';
        var cp = node.caption || node.captionSealed ? '<span class="vk-bar-caption">' + slotXml({ text: node.caption, sealed: node.captionSealed, sealedResolved: node.captionSealedResolved }) + '</span>' : '';
        return '<div class="vk-bar' + tCls + '"><div class="vk-bar-head">' + sw + '<span class="vk-bar-label">' + slotXml({ text: node.label, sealed: node.labelSealed, sealedResolved: node.labelSealedResolved }) + '</span>' + cp + '</div><div class="vk-bar-track"><div class="vk-bar-fill" style="width:' + (Math.round(node.ratio * 1000) / 10) + '%"></div></div></div>';
      }
      if (t === 'sparkline') return '<svg class="vk-sparkline' + tCls + '" viewBox="0 0 100 28" preserveAspectRatio="none"><polyline points="' + sparklinePoints(node.values) + '"></polyline></svg>';
      if (t === 'table') return '<table class="vk-table"><thead><tr>' + node.headers.map(function (h) { return '<th>' + slotXml(h) + '</th>'; }).join('') + '</tr></thead><tbody>' + node.rows.map(function (r) { return '<tr>' + r.map(function (c) { return '<td>' + slotXml(c) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table>';
      if (t === 'button') return '<button type="button" class="vk-button' + tCls + '">' + slotXml(node) + '</button>';
      if (t === 'divider') return '<hr class="vk-divider">';
      return '';
    }
    return walk(tree);
  }

  function defineVibeWebComponents(env) {
    var hostEnv = env || global;
    if (!hostEnv || !hostEnv.customElements || typeof hostEnv.HTMLElement !== 'function') {
      return false;
    }
    var Base = hostEnv.HTMLElement;
    var registry = hostEnv.customElements;

    function VibeViewElement() {
      return Reflect.construct(Base, [], VibeViewElement);
    }
    Object.setPrototypeOf(VibeViewElement.prototype, Base.prototype);
    Object.setPrototypeOf(VibeViewElement, Base);
    Object.defineProperty(VibeViewElement.prototype, 'view', {
      get: function () { return this._view; },
      set: function (v) { this._view = v; this.render(); }
    });
    Object.defineProperty(VibeViewElement.prototype, 'resolveSealed', {
      get: function () { return this._resolveSealed; },
      set: function (fn) { this._resolveSealed = fn; this.render(); }
    });
    VibeViewElement.prototype.connectedCallback = function () { this.render(); };
    VibeViewElement.prototype.render = function () {
      var raw = this._view;
      if (!raw && typeof this.getAttribute === 'function') {
        var attr = this.getAttribute('view');
        if (attr) {
          try { raw = JSON.parse(attr); } catch (_) { raw = attr; }
        }
      }
      if (!raw) return;
      renderView(raw, this, { resolve: this._resolveSealed });
    };

    function VibeEmbedElement() {
      return Reflect.construct(Base, [], VibeEmbedElement);
    }
    Object.setPrototypeOf(VibeEmbedElement.prototype, Base.prototype);
    Object.setPrototypeOf(VibeEmbedElement, Base);
    VibeEmbedElement.prototype.mount = function (host, vibe, opts) {
      this._host = host;
      this._vibe = vibe;
      this._opts = opts || {};
      this.render();
    };
    VibeEmbedElement.prototype.disconnectedCallback = function () {
      if (this._run && typeof this._run.stop === 'function') this._run.stop();
    };
    VibeEmbedElement.prototype.render = function () {
      if (!this._host || !this._vibe || !hostEnv.VibeSpace || typeof hostEnv.VibeSpace.embed !== 'function') return;
      if (this._run && typeof this._run.stop === 'function') this._run.stop();
      this._run = hostEnv.VibeSpace.embed(this._host, this, this._vibe, this._opts);
    };

    function VibeSpaceElement() {
      return Reflect.construct(Base, [], VibeSpaceElement);
    }
    Object.setPrototypeOf(VibeSpaceElement.prototype, Base.prototype);
    Object.setPrototypeOf(VibeSpaceElement, Base);
    VibeSpaceElement.prototype.mount = function (host, opts) {
      this._host = host;
      this._opts = opts || {};
      this.render();
    };
    VibeSpaceElement.prototype.disconnectedCallback = function () {
      if (this._panel && typeof this._panel.stop === 'function') this._panel.stop();
    };
    VibeSpaceElement.prototype.render = function () {
      if (!this._host || !hostEnv.VibeSpace || typeof hostEnv.VibeSpace.mountPanel !== 'function') return;
      if (this._panel && typeof this._panel.stop === 'function') this._panel.stop();
      this._panel = hostEnv.VibeSpace.mountPanel(this._host, this, this._opts);
    };

    var entries = [
      ['vibe-view', VibeViewElement],
      ['vibe-embed', VibeEmbedElement],
      ['vibe-space', VibeSpaceElement]
    ];
    for (var i = 0; i < entries.length; i++) {
      if (typeof registry.get !== 'function' || !registry.get(entries[i][0])) {
        registry.define(entries[i][0], entries[i][1]);
      }
    }
    return { VibeViewElement: VibeViewElement, VibeEmbedElement: VibeEmbedElement, VibeSpaceElement: VibeSpaceElement };
  }

  try {
    defineVibeWebComponents(global);
  } catch (_) {
    // Ignore custom element registration errors in restricted contexts.
  }

  global.VibeKit = {
    createHost: createHost,
    validate: validateVibe,
    share: share,
    renderView: renderView,
    adaptUi: adaptExternalUi,
    adapters: {
      adaptExternalUi: adaptExternalUi,
      resolveViewTree: resolveViewTree,
      renderWithH: renderWithH,
      renderToTerminal: renderToTerminal,
      renderToMarkdown: renderToMarkdown,
      renderToHtmlString: renderToHtmlString,
      defineVibeWebComponents: defineVibeWebComponents,
      getVibeStrings: getVibeStrings,
      isRtlLocale: isRtlLocale
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
