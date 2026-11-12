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

  global.VibeKit = {
    createHost: createHost,
    validate: validateVibe,
    share: share,
    renderView: renderView
  };
})(typeof window !== 'undefined' ? window : globalThis);
