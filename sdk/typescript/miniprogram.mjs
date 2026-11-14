import { adaptExternalUi, isSealedHandle } from './adapters.mjs';

export const MAX_SET_DATA_BYTES = 65536;
export const MAX_SET_DATA_RATE_PER_SEC = 30;
export const MAX_CANVAS_COMMANDS = 2000;

const FORBIDDEN_SOURCE_TOKENS = [
  'window', 'document', 'globalThis', 'self', 'fetch', 'XMLHttpRequest',
  'WebSocket', 'EventSource', 'RTCPeerConnection', 'navigator', 'location',
  'localStorage', 'sessionStorage', 'indexedDB', 'caches', 'cookieStore',
  'importScripts', 'postMessage', 'open', 'alert', 'confirm', 'prompt',
  'eval', 'Function'
];

const FORBIDDEN_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

function isPlainObject(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function deepClone(val) {
  if (val === null || val === undefined || typeof val !== 'object') return val;
  if (Array.isArray(val)) return val.map(deepClone);
  const out = {};
  for (const [k, v] of Object.entries(val)) {
    if (!FORBIDDEN_KEYS.has(k)) out[k] = deepClone(v);
  }
  return out;
}

export function validateMiniProgramSource(source) {
  if (typeof source !== 'string' || !source.trim()) {
    throw new Error('Mini program source must be a non-empty string');
  }
  if (new TextEncoder().encode(source).length > 131072) {
    throw new Error('Mini program source exceeds 128 KiB limit');
  }
  const stripped = source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`/g, '""');
  for (const token of FORBIDDEN_SOURCE_TOKENS) {
    const re = new RegExp(`(?<![.\\w$])${token}\\b`);
    if (re.test(stripped)) {
      throw new Error(`Forbidden global capability "${token}" in air-gapped Mini Program`);
    }
  }
  return true;
}

function parseSetDataPath(rawPath) {
  if (typeof rawPath !== 'string' || !rawPath.trim()) {
    throw new Error('setData path must be a non-empty string');
  }
  const tokens = [];
  const re = /([^[.\]]+)|\[(\d+)\]/g;
  let m;
  let consumed = 0;
  while ((m = re.exec(rawPath)) !== null) {
    const seg = m[1] !== undefined ? m[1] : Number(m[2]);
    if (typeof seg === 'string' && FORBIDDEN_KEYS.has(seg)) {
      throw new Error(`Forbidden setData key "${seg}"`);
    }
    tokens.push(seg);
    consumed += m[0].length;
  }
  const dots = (rawPath.match(/\./g) || []).length;
  if (tokens.length === 0 || consumed + dots < rawPath.length) {
    throw new Error(`Invalid setData path "${rawPath}"`);
  }
  return tokens;
}

function assertNoForbiddenNestedKeys(val, depth = 0) {
  if (depth > 32) throw new Error('setData nesting exceeds limit');
  if (Array.isArray(val)) {
    for (const item of val) assertNoForbiddenNestedKeys(item, depth + 1);
  } else if (val && typeof val === 'object') {
    for (const [k, v] of Object.entries(val)) {
      if (FORBIDDEN_KEYS.has(k)) throw new Error(`Forbidden setData key "${k}"`);
      assertNoForbiddenNestedKeys(v, depth + 1);
    }
  }
}

export function applySetData(currentData, patch) {
  if (!isPlainObject(patch)) {
    throw new Error('setData patch must be a plain object');
  }
  const encodedBytes = new TextEncoder().encode(JSON.stringify(patch)).length;
  if (encodedBytes > MAX_SET_DATA_BYTES) {
    throw new Error(`setData payload (${encodedBytes} B) exceeds ${MAX_SET_DATA_BYTES} B limit`);
  }
  assertNoForbiddenNestedKeys(patch);
  const root = deepClone(isPlainObject(currentData) ? currentData : {});
  for (const [rawPath, nextVal] of Object.entries(patch)) {
    const tokens = parseSetDataPath(rawPath);
    let cursor = root;
    for (let i = 0; i < tokens.length - 1; i++) {
      const seg = tokens[i];
      const nextSeg = tokens[i + 1];
      if (typeof seg === 'number') {
        if (!Array.isArray(cursor)) throw new Error(`Expected array at segment ${seg}`);
        if (seg < 0 || seg > 1024) throw new Error('setData array index out of bounds');
        if (cursor[seg] === undefined || cursor[seg] === null || typeof cursor[seg] !== 'object') {
          cursor[seg] = typeof nextSeg === 'number' ? [] : {};
        } else {
          cursor[seg] = Array.isArray(cursor[seg]) ? cursor[seg].slice() : { ...cursor[seg] };
        }
        cursor = cursor[seg];
      } else {
        const curChild = cursor[seg];
        if (curChild === undefined || curChild === null || typeof curChild !== 'object') {
          cursor[seg] = typeof nextSeg === 'number' ? [] : {};
        } else {
          cursor[seg] = Array.isArray(curChild) ? curChild.slice() : { ...curChild };
        }
        cursor = cursor[seg];
      }
    }
    const leaf = tokens[tokens.length - 1];
    if (typeof leaf === 'number') {
      if (!Array.isArray(cursor) || leaf < 0 || leaf > 1024) {
        throw new Error('setData array index out of bounds');
      }
      cursor[leaf] = deepClone(nextVal);
    } else {
      cursor[leaf] = deepClone(nextVal);
    }
  }
  return root;
}

export function lookupScopePath(scope, expr) {
  const trimmed = String(expr || '').trim();
  if (!trimmed) return undefined;
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;
  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) return Number(trimmed);
  if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
    return trimmed.slice(1, -1);
  }
  const tokens = parseSetDataPath(trimmed);
  let cur = scope;
  for (const seg of tokens) {
    if (cur === null || cur === undefined) return undefined;
    if (typeof seg === 'number') {
      if (!Array.isArray(cur)) return undefined;
      cur = cur[seg];
    } else {
      if (typeof cur !== 'object' || FORBIDDEN_KEYS.has(seg)) return undefined;
      cur = cur[seg];
    }
  }
  return cur;
}

function evalConditionExpr(expr, scope) {
  const s = String(expr || '').trim();
  if (!s) return false;
  if (s.startsWith('!')) return !evalConditionExpr(s.slice(1), scope);
  for (const op of ['===', '!==', '==', '!=', '>=', '<=', '>', '<']) {
    const idx = s.indexOf(op);
    if (idx > 0) {
      const l = lookupScopePath(scope, s.slice(0, idx));
      const r = lookupScopePath(scope, s.slice(idx + op.length));
      if (op === '===' || op === '==') return l === r;
      if (op === '!==' || op === '!=') return l !== r;
      if (op === '>=') return Number(l) >= Number(r);
      if (op === '<=') return Number(l) <= Number(r);
      if (op === '>') return Number(l) > Number(r);
      if (op === '<') return Number(l) < Number(r);
    }
  }
  const v = lookupScopePath(scope, s);
  if (Array.isArray(v)) return v.length > 0;
  return Boolean(v);
}

function resolveBindingValue(raw, scope, depth = 0) {
  if (depth > 16) return raw;
  if (isSealedHandle(raw)) return { sealed: raw.sealed };
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    const single = trimmed.match(/^\{\{\s*([^{}]+?)\s*\}\}$/);
    if (single) {
      const val = lookupScopePath(scope, single[1]);
      return val === undefined ? '' : deepClone(val);
    }
    if (raw.includes('{{')) {
      return raw.replace(/\{\{\s*([^{}]+?)\s*\}\}/g, (_, inner) => {
        const val = lookupScopePath(scope, inner);
        if (val === undefined || val === null || isSealedHandle(val)) return '';
        return typeof val === 'object' ? JSON.stringify(val) : String(val);
      });
    }
    return raw;
  }
  if (Array.isArray(raw)) {
    return raw.map(item => resolveBindingValue(item, scope, depth + 1));
  }
  if (isPlainObject(raw)) {
    const out = {};
    for (const [k, v] of Object.entries(raw)) {
      if (!FORBIDDEN_KEYS.has(k)) out[k] = resolveBindingValue(v, scope, depth + 1);
    }
    return out;
  }
  return raw;
}

export function compileTemplate(template, scope = {}) {
  function expandNode(tpl, curScope, depth) {
    if (!isPlainObject(tpl) || depth > 16) return [];
    const ifDirective = tpl.if ?? tpl['v-if'] ?? tpl['wx:if'];
    if (ifDirective !== undefined) {
      const cond = typeof ifDirective === 'boolean'
        ? ifDirective
        : evalConditionExpr(String(ifDirective).replace(/^\{\{|\}\}$/g, ''), curScope);
      if (!cond) return [];
    }

    const forDirective = tpl.for ?? tpl['v-for'] ?? tpl['wx:for'];
    if (forDirective !== undefined) {
      let itemVar = tpl.forItem || tpl['wx:for-item'] || 'item';
      let indexVar = tpl.forIndex || tpl['wx:for-index'] || 'index';
      let listVal;
      if (Array.isArray(forDirective)) {
        listVal = forDirective;
      } else {
        const fStr = String(forDirective).trim().replace(/^\{\{|\}\}$/g, '').trim();
        const inMatch = fStr.match(/^\(?([a-zA-Z_$][\w$]*)(?:\s*,\s*([a-zA-Z_$][\w$]*))?\)?\s+in\s+(.+)$/);
        if (inMatch) {
          itemVar = inMatch[1];
          if (inMatch[2]) indexVar = inMatch[2];
          listVal = lookupScopePath(curScope, inMatch[3]);
        } else {
          listVal = lookupScopePath(curScope, fStr);
        }
      }
      if (!Array.isArray(listVal)) return [];
      const stripped = { ...tpl };
      delete stripped.for;
      delete stripped['v-for'];
      delete stripped['wx:for'];
      delete stripped.forItem;
      delete stripped['wx:for-item'];
      delete stripped.forIndex;
      delete stripped['wx:for-index'];
      const expanded = [];
      for (let idx = 0; idx < Math.min(listVal.length, 200); idx++) {
        const childScope = { ...curScope, [itemVar]: listVal[idx], [indexVar]: idx };
        expanded.push(...expandNode(stripped, childScope, depth + 1));
      }
      return expanded;
    }

    const node = {};
    const dataset = isPlainObject(tpl.dataset) ? resolveBindingValue(tpl.dataset, curScope) : {};
    for (const [k, v] of Object.entries(tpl)) {
      if (k === 'if' || k === 'v-if' || k === 'wx:if' || k === 'dataset') continue;
      if (k === 'children' && Array.isArray(v)) {
        const kids = [];
        for (const child of v) {
          kids.push(...expandNode(child, curScope, depth + 1));
        }
        node.children = kids;
        continue;
      }
      if (k.startsWith('data-') && k.length > 5) {
        const camel = k.slice(5).replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
        dataset[camel] = resolveBindingValue(v, curScope);
        continue;
      }
      node[k] = resolveBindingValue(v, curScope);
    }
    if (Object.keys(dataset).length > 0) node.dataset = dataset;
    if ((node.type === 'button' || node.type === 'action') && typeof node.bindtap === 'string' && !node.command) {
      node.command = `mp:tap:${node.bindtap}`;
      node.args = {
        __mpEvent: true,
        type: 'tap',
        handler: node.bindtap,
        ...(node.id ? { id: node.id } : {}),
        ...(node.dataset ? { dataset: node.dataset } : {})
      };
    }
    return [node];
  }

  const roots = expandNode(template, scope, 0);
  const root = roots.length === 0
    ? { type: 'column', children: [] }
    : (roots.length === 1 ? roots[0] : { type: 'column', children: roots });
  return adaptExternalUi(root);
}

export function defineMiniProgram(spec) {
  if (!isPlainObject(spec)) {
    throw new Error('defineMiniProgram expects an object descriptor');
  }
  return {
    data: deepClone(isPlainObject(spec.data) ? spec.data : {}),
    template: isPlainObject(spec.template) ? deepClone(spec.template) : null,
    onLoad: typeof spec.onLoad === 'function' ? spec.onLoad : null,
    onShow: typeof spec.onShow === 'function' ? spec.onShow : null,
    onHide: typeof spec.onHide === 'function' ? spec.onHide : null,
    onDataUpdate: typeof spec.onDataUpdate === 'function' ? spec.onDataUpdate : null,
    methods: isPlainObject(spec.methods) ? { ...spec.methods } : {}
  };
}

export function createMiniProgramSession(definition, { template, maxRatePerSec = MAX_SET_DATA_RATE_PER_SEC } = {}) {
  const def = defineMiniProgram(definition);
  const activeTemplate = template || def.template;
  let data = deepClone(def.data);
  let hostData = {};
  let context = {};
  let lifecycle = 'created';
  const timestamps = [];

  function recordSetDataRate(nowMs = Date.now()) {
    while (timestamps.length > 0 && nowMs - timestamps[0] >= 1000) {
      timestamps.shift();
    }
    if (timestamps.length >= maxRatePerSec) {
      throw new Error(`setData rate limit (${maxRatePerSec}/s) exceeded`);
    }
    timestamps.push(nowMs);
  }

  const ctx = {
    get data() { return data; },
    get hostData() { return hostData; },
    get context() { return context; },
    setData(patch, nowMs = Date.now()) {
      recordSetDataRate(nowMs);
      data = applySetData(data, patch);
    }
  };

  return {
    get data() { return deepClone(data); },
    get lifecycle() { return lifecycle; },
    setData(patch, nowMs = Date.now()) { ctx.setData(patch, nowMs); },
    load(initialHostData = {}, initialContext = {}) {
      hostData = deepClone(initialHostData);
      context = deepClone(initialContext);
      lifecycle = 'loaded';
      if (def.onLoad) def.onLoad.call(ctx, context);
      lifecycle = 'shown';
      if (def.onShow) def.onShow.call(ctx);
      if (Object.keys(hostData).length > 0 && def.onDataUpdate) {
        def.onDataUpdate.call(ctx, hostData, context);
      }
    },
    updateHostData(nextHostData = {}, nextContext = {}) {
      hostData = deepClone(nextHostData);
      context = deepClone(nextContext);
      if (def.onDataUpdate) def.onDataUpdate.call(ctx, hostData, context);
    },
    dispatchEvent(event) {
      const handler = event?.handler;
      if (typeof handler === 'string' && typeof def.methods[handler] === 'function') {
        def.methods[handler].call(ctx, event);
        return true;
      }
      return false;
    },
    hide() {
      lifecycle = 'hidden';
      if (def.onHide) def.onHide.call(ctx);
    },
    buildView() {
      if (!activeTemplate) return null;
      return compileTemplate(activeTemplate, { ...hostData, ...data, data, hostData, context });
    }
  };
}
