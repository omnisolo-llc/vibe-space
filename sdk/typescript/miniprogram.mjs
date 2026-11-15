import { adaptExternalUi, isSealedHandle } from './adapters.mjs';

export const MAX_SET_DATA_BYTES = 65536;
export const MAX_SET_DATA_RATE_PER_SEC = 30;
export const MAX_CANVAS_COMMANDS = 2000;

const MAX_EXPR_LENGTH = 2048;
const MAX_EXPR_DEPTH = 16;
const MAX_TEMPLATE_DEPTH = 16;
const MAX_TEMPLATE_NODES = 1024;
const MAX_ARRAY_INDEX = 1024;
const MAX_PATH_CACHE = 512;
const TEXT_ENCODER = new TextEncoder();
const PARSED_PATH_CACHE = new Map();

const FORBIDDEN_SOURCE_TOKENS = [
  'window', 'document', 'globalThis', 'self', 'top', 'parent', 'frames', 'opener',
  'fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource', 'WebTransport',
  'RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel',
  'Worker', 'SharedWorker', 'ServiceWorker', 'ServiceWorkerContainer', 'BroadcastChannel',
  'navigator', 'location', 'localStorage', 'sessionStorage', 'indexedDB',
  'caches', 'cookieStore', 'importScripts', 'postMessage', 'sendBeacon',
  'open', 'alert', 'confirm', 'prompt', 'eval', 'Function', 'WebAssembly',
  'Proxy', 'Reflect'
];

const FORBIDDEN_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

const FORBIDDEN_METHOD_NAMES = new Set([
  '__proto__', 'constructor', 'prototype',
  'toString', 'toLocaleString', 'valueOf',
  'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable',
  '__defineGetter__', '__defineSetter__', '__lookupGetter__', '__lookupSetter__'
]);

const VALID_HANDLER_NAME_RE = /^[a-zA-Z_$][a-zA-Z0-9_$]{0,63}$/;
const NUM_LITERAL_RE = /^-?\d+(?:\.\d+)?$/;
const SINGLE_BINDING_RE = /^\{\{\s*([^{}]+?)\s*\}\}$/;
const MULTI_BINDING_RE = /\{\{\s*([^{}]+?)\s*\}\}/g;
const FOR_IN_RE = /^\(?\s*([a-zA-Z_$][\w$]*)(?:\s*,\s*([a-zA-Z_$][\w$]*))?\s*\)?\s+in\s+(.+)$/;
const DATA_CAMEL_RE = /-([a-z])/g;

const DYNAMIC_IMPORT_RE = /(?<![.\w$])import\s*\(/;
const FORBIDDEN_SOURCE_IDENT_RE = new RegExp(`(?<![.\\w$])(?:${FORBIDDEN_SOURCE_TOKENS.join('|')})\\b`);
const FORBIDDEN_PROTO_WORD_RE = /\b(?:__proto__|constructor|prototype)\b/;
const FORBIDDEN_PROTO_BRACKET_RE = /\[\s*['"`](?:__proto__|constructor|prototype)['"`]\s*\]/;
const LINE_CONT_RE = /\\\r?\n/g;
const ESC_UNICODE_BRACE_RE = /\\u\{([0-9a-fA-F]{1,6})\}/g;
const ESC_UNICODE_4_RE = /\\u([0-9a-fA-F]{4})/g;
const ESC_HEX_2_RE = /\\x([0-9a-fA-F]{2})/g;
const ESC_OCTAL_RE = /\\([0-3]?[0-7]{1,2})/g;
const TPL_STR_INTERP_RE = /`([a-zA-Z0-9_$]{0,32})\$\{\s*(?:'([a-zA-Z0-9_$]{0,32})'|"([a-zA-Z0-9_$]{0,32})")\s*\}([^`\\]{0,64})`/g;
const CONCAT_IDENT_STR_RE = /(['"`])([a-zA-Z0-9_$]{1,32})\1\s*\+\s*(['"`])([a-zA-Z0-9_$]{1,32})\3/g;

function decodeJsEscapes(str) {
  return str
    .replace(LINE_CONT_RE, '')
    .replace(ESC_UNICODE_BRACE_RE, (_, hex) => {
      const cp = parseInt(hex, 16);
      return cp <= 0x10ffff ? String.fromCodePoint(cp) : '';
    })
    .replace(ESC_UNICODE_4_RE, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
    .replace(ESC_HEX_2_RE, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
    .replace(ESC_OCTAL_RE, (_, oct) => String.fromCharCode(parseInt(oct, 8)));
}

function collapseConcatStrings(str) {
  let out = str;
  for (let pass = 0; pass < 4; pass++) {
    let next = out.replace(TPL_STR_INTERP_RE, (_, head, s1, d1, tail) =>
      `\`${head}${s1 !== undefined ? s1 : d1}${tail}\``
    );
    next = next.replace(CONCAT_IDENT_STR_RE, (_, _q1, s1, _q2, s2) => `'${s1}${s2}'`);
    if (next === out) break;
    out = next;
  }
  return out;
}

/**
 * Single-pass linear scanner that strips comments and replaces literal string
 * contents with `""` while preserving `${...}` template interpolations so
 * sandbox escapes cannot hide inside template expressions.
 */
function scanSourceForSecurity(src) {
  const noComments = [];
  const stripped = [];
  const tplBraceStack = [];
  let i = 0;
  const len = src.length;

  while (i < len) {
    const ch = src[i];

    // Line comment
    if (ch === '/' && src[i + 1] === '/') {
      i += 2;
      while (i < len && src[i] !== '\n') i++;
      noComments.push(' ');
      stripped.push(' ');
      continue;
    }

    // Block comment
    if (ch === '/' && src[i + 1] === '*') {
      i += 2;
      while (i + 1 < len && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2;
      noComments.push(' ');
      stripped.push(' ');
      continue;
    }

    // Single or double quoted string
    if (ch === "'" || ch === '"') {
      const start = i;
      i++;
      while (i < len && src[i] !== ch) {
        if (src[i] === '\\' && i + 1 < len) i++;
        i++;
      }
      if (i < len) i++;
      noComments.push(src.slice(start, i));
      stripped.push('""');
      continue;
    }

    // Template literal start or resume after closing `}` of `${...}`
    if (ch === '`') {
      const start = i;
      i++;
      let interpHit = false;
      while (i < len) {
        if (src[i] === '\\' && i + 1 < len) {
          i += 2;
          continue;
        }
        if (src[i] === '$' && src[i + 1] === '{') {
          i += 2;
          noComments.push(src.slice(start, i));
          stripped.push('""+(');
          tplBraceStack.push(1);
          interpHit = true;
          break;
        }
        if (src[i] === '`') {
          i++;
          break;
        }
        i++;
      }
      if (!interpHit) {
        noComments.push(src.slice(start, i));
        stripped.push('""');
      }
      continue;
    }

    if (tplBraceStack.length > 0) {
      if (ch === '{') {
        tplBraceStack[tplBraceStack.length - 1] += 1;
      } else if (ch === '}') {
        tplBraceStack[tplBraceStack.length - 1] -= 1;
        if (tplBraceStack[tplBraceStack.length - 1] === 0) {
          tplBraceStack.pop();
          i++;
          // Continue scanning template literal tail until next `${` or closing `` ` ``
          const tailStart = i;
          let nextInterp = false;
          while (i < len) {
            if (src[i] === '\\' && i + 1 < len) {
              i += 2;
              continue;
            }
            if (src[i] === '$' && src[i + 1] === '{') {
              i += 2;
              noComments.push('}' + src.slice(tailStart, i));
              stripped.push(')+""+(');
              tplBraceStack.push(1);
              nextInterp = true;
              break;
            }
            if (src[i] === '`') {
              i++;
              break;
            }
            i++;
          }
          if (!nextInterp) {
            noComments.push('}' + src.slice(tailStart, i));
            stripped.push(')+""');
          }
          continue;
        }
      }
    }

    noComments.push(ch);
    stripped.push(ch);
    i++;
  }

  return {
    noComments: noComments.join(''),
    stripped: stripped.join('')
  };
}

function isPlainObject(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function deepClone(val) {
  if (val === null || val === undefined || typeof val !== 'object') return val;
  if (Array.isArray(val)) {
    const arr = new Array(val.length);
    for (let i = 0; i < val.length; i++) arr[i] = deepClone(val[i]);
    return arr;
  }
  const out = {};
  const keys = Object.keys(val);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (!FORBIDDEN_KEYS.has(k)) {
      Object.defineProperty(out, k, {
        value: deepClone(val[k]),
        writable: true,
        enumerable: true,
        configurable: true
      });
    }
  }
  return out;
}

/**
 * Validates air-gapped `AppService` Vibe Mini Program source: enforces `<= 64 KiB`
 * UTF-8 and rejects DOM, network, storage, popup, prototype, unicode/hex
 * escape obfuscation, and dynamic `import()` / `eval` / `Function` vectors.
 */
export function validateMiniProgramSource(source) {
  if (typeof source !== 'string' || !source.trim()) {
    throw new Error('Vibe Mini Program source must be a non-empty string');
  }
  if (TEXT_ENCODER.encode(source).length > MAX_SET_DATA_BYTES) {
    throw new Error(`Vibe Mini Program source exceeds ${MAX_SET_DATA_BYTES} B limit`);
  }
  const { noComments, stripped } = scanSourceForSecurity(source);
  const decodedStripped = decodeJsEscapes(stripped);
  const decodedAll = decodeJsEscapes(noComments);
  const collapsedAll = collapseConcatStrings(decodedAll);

  if (DYNAMIC_IMPORT_RE.test(stripped) || DYNAMIC_IMPORT_RE.test(decodedStripped)) {
    throw new Error('Forbidden dynamic import() in air-gapped Vibe Mini Program');
  }

  const sourceMatch = FORBIDDEN_SOURCE_IDENT_RE.exec(stripped) || FORBIDDEN_SOURCE_IDENT_RE.exec(decodedStripped);
  if (sourceMatch) {
    throw new Error(`Forbidden global capability "${sourceMatch[0]}" in air-gapped Vibe Mini Program`);
  }

  const protoWordMatch = FORBIDDEN_PROTO_WORD_RE.exec(stripped) || FORBIDDEN_PROTO_WORD_RE.exec(decodedStripped);
  if (protoWordMatch) {
    throw new Error(`Forbidden prototype access "${protoWordMatch[0]}" in air-gapped Vibe Mini Program`);
  }

  const protoBracketMatch =
    FORBIDDEN_PROTO_BRACKET_RE.exec(noComments) ||
    FORBIDDEN_PROTO_BRACKET_RE.exec(decodedAll) ||
    FORBIDDEN_PROTO_BRACKET_RE.exec(collapsedAll);
  if (protoBracketMatch) {
    throw new Error(`Forbidden prototype access "${protoBracketMatch[0]}" in air-gapped Vibe Mini Program`);
  }
  return true;
}

export const validateVibeSnippetSource = validateMiniProgramSource;

function parseSetDataPath(rawPath) {
  if (typeof rawPath !== 'string' || !rawPath.trim()) {
    throw new Error('setData path must be a non-empty string');
  }
  const cached = PARSED_PATH_CACHE.get(rawPath);
  if (cached !== undefined) return cached;

  const tokens = [];
  const len = rawPath.length;
  let i = 0;

  while (i < len) {
    const ch = rawPath[i];
    if (ch === '.') {
      if (i === 0 || i === len - 1 || rawPath[i + 1] === '.' || rawPath[i - 1] === '.') {
        throw new Error(`Invalid setData path "${rawPath}"`);
      }
      i++;
      continue;
    }
    if (ch === '[') {
      const closeIdx = rawPath.indexOf(']', i + 1);
      if (closeIdx <= i + 1) {
        throw new Error(`Invalid setData path "${rawPath}"`);
      }
      let num = 0;
      for (let j = i + 1; j < closeIdx; j++) {
        const code = rawPath.charCodeAt(j);
        if (code < 48 || code > 57) {
          throw new Error(`Invalid setData path "${rawPath}"`);
        }
        num = num * 10 + (code - 48);
      }
      if (!Number.isSafeInteger(num) || num > MAX_ARRAY_INDEX) {
        throw new Error('setData array index out of bounds');
      }
      tokens.push(num);
      i = closeIdx + 1;
      continue;
    }
    if (ch === ']') {
      throw new Error(`Invalid setData path "${rawPath}"`);
    }
    const start = i;
    while (i < len && rawPath[i] !== '.' && rawPath[i] !== '[' && rawPath[i] !== ']') {
      i++;
    }
    const seg = rawPath.slice(start, i);
    if (FORBIDDEN_METHOD_NAMES.has(seg)) {
      throw new Error(`Forbidden setData key "${seg}"`);
    }
    tokens.push(seg);
  }

  if (tokens.length === 0) {
    throw new Error(`Invalid setData path "${rawPath}"`);
  }
  if (PARSED_PATH_CACHE.size >= MAX_PATH_CACHE) {
    PARSED_PATH_CACHE.delete(PARSED_PATH_CACHE.keys().next().value);
  }
  PARSED_PATH_CACHE.set(rawPath, tokens);
  return tokens;
}

function shallowClonePlain(obj) {
  const out = {};
  const keys = Object.keys(obj);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (!FORBIDDEN_KEYS.has(k)) {
      Object.defineProperty(out, k, {
        value: obj[k],
        writable: true,
        enumerable: true,
        configurable: true
      });
    }
  }
  return out;
}

function assertNoForbiddenNestedKeys(val, depth = 0) {
  if (depth > 32) throw new Error('setData nesting exceeds limit');
  if (val === null || val === undefined || typeof val !== 'object') return;
  if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++) {
      assertNoForbiddenNestedKeys(val[i], depth + 1);
    }
    return;
  }
  if (!isPlainObject(val)) {
    throw new Error('Forbidden non-plain object in setData');
  }
  const keys = Object.keys(val);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (FORBIDDEN_METHOD_NAMES.has(k)) {
      throw new Error(`Forbidden setData key "${k}"`);
    }
    assertNoForbiddenNestedKeys(val[k], depth + 1);
  }
}

export function applySetData(currentData, patch) {
  if (!isPlainObject(patch)) {
    throw new Error('setData patch must be a plain object');
  }
  const encodedBytes = TEXT_ENCODER.encode(JSON.stringify(patch)).length;
  if (encodedBytes > MAX_SET_DATA_BYTES) {
    throw new Error(`setData payload (${encodedBytes} B) exceeds ${MAX_SET_DATA_BYTES} B limit`);
  }
  assertNoForbiddenNestedKeys(patch);
  const root = isPlainObject(currentData) ? shallowClonePlain(currentData) : {};
  const patchKeys = Object.keys(patch);

  for (let p = 0; p < patchKeys.length; p++) {
    const rawPath = patchKeys[p];
    const nextVal = patch[rawPath];
    const tokens = parseSetDataPath(rawPath);
    let cursor = root;
    for (let i = 0; i < tokens.length - 1; i++) {
      const seg = tokens[i];
      const nextSeg = tokens[i + 1];
      if (typeof seg === 'number') {
        if (!Array.isArray(cursor)) throw new Error(`Expected array at segment ${seg}`);
        if (seg < 0 || seg > MAX_ARRAY_INDEX) throw new Error('setData array index out of bounds');
        const existing = cursor[seg];
        if (existing === undefined || existing === null || typeof existing !== 'object') {
          cursor[seg] = typeof nextSeg === 'number' ? [] : {};
        } else {
          cursor[seg] = Array.isArray(existing) ? existing.slice() : shallowClonePlain(existing);
        }
        cursor = cursor[seg];
      } else {
        if (Array.isArray(cursor)) {
          throw new Error(`Forbidden non-numeric key "${seg}" on array in setData`);
        }
        const curChild = Object.hasOwn(cursor, seg) ? cursor[seg] : undefined;
        let nextChild;
        if (curChild === undefined || curChild === null || typeof curChild !== 'object') {
          nextChild = typeof nextSeg === 'number' ? [] : {};
        } else {
          nextChild = Array.isArray(curChild) ? curChild.slice() : shallowClonePlain(curChild);
        }
        Object.defineProperty(cursor, seg, {
          value: nextChild,
          writable: true,
          enumerable: true,
          configurable: true
        });
        cursor = nextChild;
      }
    }
    const leaf = tokens[tokens.length - 1];
    if (typeof leaf === 'number') {
      if (!Array.isArray(cursor) || leaf < 0 || leaf > MAX_ARRAY_INDEX) {
        throw new Error('setData array index out of bounds');
      }
      cursor[leaf] = deepClone(nextVal);
    } else {
      if (Array.isArray(cursor)) {
        throw new Error(`Forbidden non-numeric key "${leaf}" on array in setData`);
      }
      Object.defineProperty(cursor, leaf, {
        value: deepClone(nextVal),
        writable: true,
        enumerable: true,
        configurable: true
      });
    }
  }
  return root;
}

export function lookupScopePath(scope, expr) {
  const trimmed = String(expr || '').trim();
  if (!trimmed) return undefined;
  if (trimmed.length > MAX_EXPR_LENGTH) {
    throw new Error('Binding expression exceeds length limit');
  }
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;
  if (NUM_LITERAL_RE.test(trimmed)) return Number(trimmed);
  if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
    return trimmed.slice(1, -1);
  }
  if (!trimmed.includes('.') && !trimmed.includes('[')) {
    if (!scope || typeof scope !== 'object' || FORBIDDEN_METHOD_NAMES.has(trimmed)) {
      return undefined;
    }
    return Object.hasOwn(scope, trimmed) ? scope[trimmed] : undefined;
  }
  let tokens;
  try {
    tokens = parseSetDataPath(trimmed);
  } catch (err) {
    if (String((err && err.message) || '').startsWith('Forbidden')) return undefined;
    throw err;
  }
  if (tokens.length > MAX_EXPR_DEPTH) {
    throw new Error('Binding path exceeds depth limit');
  }
  let cur = scope;
  for (let i = 0; i < tokens.length; i++) {
    const seg = tokens[i];
    if (cur === null || cur === undefined) return undefined;
    if (typeof seg === 'number') {
      if (!Array.isArray(cur)) return undefined;
      cur = cur[seg];
    } else {
      if (typeof cur !== 'object' || FORBIDDEN_METHOD_NAMES.has(seg)) {
        return undefined;
      }
      if (!Object.hasOwn(cur, seg)) return undefined;
      cur = cur[seg];
    }
  }
  return cur;
}

function evalConditionExpr(expr, scope, depth = 0) {
  if (depth > MAX_EXPR_DEPTH) {
    throw new Error('Condition expression exceeds nesting limit');
  }
  let s = String(expr || '').trim();
  if (!s) return false;
  if (s.length > MAX_EXPR_LENGTH) {
    throw new Error('Condition expression exceeds length limit');
  }
  let negateCount = 0;
  while (s.startsWith('!')) {
    negateCount += 1;
    if (depth + negateCount > MAX_EXPR_DEPTH) {
      throw new Error('Condition expression exceeds nesting limit');
    }
    s = s.slice(1).trimStart();
  }
  if (!s) return false;

  let result;
  let matchedOp = false;
  for (const op of ['===', '!==', '==', '!=', '>=', '<=', '>', '<']) {
    const idx = s.indexOf(op);
    if (idx > 0) {
      const l = lookupScopePath(scope, s.slice(0, idx));
      const r = lookupScopePath(scope, s.slice(idx + op.length));
      if (op === '===' || op === '==') result = l === r;
      else if (op === '!==' || op === '!=') result = l !== r;
      else if (op === '>=') result = Number(l) >= Number(r);
      else if (op === '<=') result = Number(l) <= Number(r);
      else if (op === '>') result = Number(l) > Number(r);
      else result = Number(l) < Number(r);
      matchedOp = true;
      break;
    }
  }
  if (!matchedOp) {
    const v = lookupScopePath(scope, s);
    result = Array.isArray(v) ? v.length > 0 : Boolean(v);
  }
  return (negateCount & 1) === 1 ? !result : result;
}

function resolveBindingValue(raw, scope, depth = 0) {
  if (depth > 16) return raw;
  if (isSealedHandle(raw)) return { sealed: raw.sealed };
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    const single = trimmed.match(SINGLE_BINDING_RE);
    if (single) {
      const val = lookupScopePath(scope, single[1]);
      return val === undefined ? '' : deepClone(val);
    }
    if (raw.includes('{{')) {
      return raw.replace(MULTI_BINDING_RE, (_, inner) => {
        const val = lookupScopePath(scope, inner);
        if (val === undefined || val === null || isSealedHandle(val)) return '';
        return typeof val === 'object' ? JSON.stringify(val) : String(val);
      });
    }
    return raw;
  }
  if (Array.isArray(raw)) {
    const arr = new Array(raw.length);
    for (let i = 0; i < raw.length; i++) {
      arr[i] = resolveBindingValue(raw[i], scope, depth + 1);
    }
    return arr;
  }
  if (isPlainObject(raw)) {
    const out = {};
    const keys = Object.keys(raw);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (!FORBIDDEN_KEYS.has(k)) {
        out[k] = resolveBindingValue(raw[k], scope, depth + 1);
      }
    }
    return out;
  }
  return raw;
}

export function compileTemplate(template, scope = {}) {
  const budget = { count: 0 };

  function expandNode(tpl, curScope, depth) {
    if (depth > MAX_TEMPLATE_DEPTH) {
      throw new Error('VXML template exceeds maximum nesting depth');
    }
    if (!isPlainObject(tpl)) return [];
    if (++budget.count > MAX_TEMPLATE_NODES) {
      throw new Error('VXML template exceeds maximum node count');
    }

    const ifDirective = tpl.if ?? tpl['v-if'] ?? tpl['wx:if'];
    if (ifDirective !== undefined) {
      const cond = typeof ifDirective === 'boolean'
        ? ifDirective
        : evalConditionExpr(String(ifDirective).replace(/^\{\{|\}\}$/g, ''), curScope);
      if (!cond) return [];
    }

    const forDirective = tpl.for ?? tpl['v-for'] ?? tpl['wx:for'];
    if (forDirective !== undefined) {
      const rawItemAlias = tpl.forItem ?? tpl['wx:for-item'];
      const rawIndexAlias = tpl.forIndex ?? tpl['wx:for-index'];
      if (rawItemAlias !== undefined && typeof rawItemAlias !== 'string') {
        throw new Error('Forbidden loop item variable');
      }
      if (rawIndexAlias !== undefined && typeof rawIndexAlias !== 'string') {
        throw new Error('Forbidden loop index variable');
      }
      let itemVar = (rawItemAlias || 'item').trim();
      let indexVar = (rawIndexAlias || 'index').trim();
      if (!VALID_HANDLER_NAME_RE.test(itemVar) || FORBIDDEN_METHOD_NAMES.has(itemVar)) {
        throw new Error(`Forbidden loop item variable "${itemVar}"`);
      }
      if (!VALID_HANDLER_NAME_RE.test(indexVar) || FORBIDDEN_METHOD_NAMES.has(indexVar)) {
        throw new Error(`Forbidden loop index variable "${indexVar}"`);
      }

      let listVal;
      if (Array.isArray(forDirective)) {
        listVal = forDirective;
      } else {
        const fStr = String(forDirective).trim().replace(/^\{\{|\}\}$/g, '').trim();
        const inMatch = fStr.match(FOR_IN_RE);
        if (inMatch) {
          itemVar = inMatch[1];
          if (inMatch[2]) indexVar = inMatch[2];
          if (!VALID_HANDLER_NAME_RE.test(itemVar) || FORBIDDEN_METHOD_NAMES.has(itemVar)) {
            throw new Error(`Forbidden loop item variable "${itemVar}"`);
          }
          if (!VALID_HANDLER_NAME_RE.test(indexVar) || FORBIDDEN_METHOD_NAMES.has(indexVar)) {
            throw new Error(`Forbidden loop index variable "${indexVar}"`);
          }
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
      const limit = Math.min(listVal.length, 200);
      const childScope = { ...curScope };
      for (let idx = 0; idx < limit; idx++) {
        childScope[itemVar] = listVal[idx];
        childScope[indexVar] = idx;
        expanded.push(...expandNode(stripped, childScope, depth + 1));
      }
      return expanded;
    }

    const node = {};
    const dataset = isPlainObject(tpl.dataset) ? resolveBindingValue(tpl.dataset, curScope) : {};
    const keys = Object.keys(tpl);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (FORBIDDEN_KEYS.has(k)) continue;
      if (k === 'if' || k === 'v-if' || k === 'wx:if' || k === 'dataset') continue;
      const v = tpl[k];
      if (k === 'children' && Array.isArray(v)) {
        const kids = [];
        for (let c = 0; c < v.length; c++) {
          kids.push(...expandNode(v[c], curScope, depth + 1));
        }
        node.children = kids;
        continue;
      }
      if (k.startsWith('data-') && k.length > 5) {
        const camel = k.slice(5).replace(DATA_CAMEL_RE, (_, ch) => ch.toUpperCase());
        if (!FORBIDDEN_METHOD_NAMES.has(camel)) {
          dataset[camel] = resolveBindingValue(v, curScope);
        }
        continue;
      }
      if (k === 'bindtap' || k === 'catchtap' || k === 'bindinput' || k === 'bindchange') {
        const handlerVal = String(resolveBindingValue(v, curScope) || '').trim();
        if (VALID_HANDLER_NAME_RE.test(handlerVal) && !FORBIDDEN_METHOD_NAMES.has(handlerVal)) {
          node[k === 'catchtap' ? 'bindtap' : k] = handlerVal;
        }
        continue;
      }
      node[k] = resolveBindingValue(v, curScope);
    }
    if (Object.keys(dataset).length > 0) node.dataset = dataset;
    if ((node.type === 'button' || node.type === 'action' || node.type === 'canvas') &&
        typeof node.bindtap === 'string' && !node.command) {
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
  const safeMethods = Object.create(null);
  if (isPlainObject(spec.methods)) {
    const methodKeys = Object.keys(spec.methods);
    for (let i = 0; i < methodKeys.length; i++) {
      const k = methodKeys[i];
      const fn = spec.methods[k];
      if (FORBIDDEN_METHOD_NAMES.has(k) || !VALID_HANDLER_NAME_RE.test(k)) {
        throw new Error(`Forbidden Vibe Mini Program method name "${k}"`);
      }
      if (typeof fn === 'function') {
        Object.defineProperty(safeMethods, k, {
          value: fn,
          writable: true,
          enumerable: true,
          configurable: true
        });
      }
    }
  }
  return {
    data: deepClone(isPlainObject(spec.data) ? spec.data : {}),
    template: isPlainObject(spec.template) ? deepClone(spec.template) : null,
    onLoad: typeof spec.onLoad === 'function' ? spec.onLoad : null,
    onShow: typeof spec.onShow === 'function' ? spec.onShow : null,
    onHide: typeof spec.onHide === 'function' ? spec.onHide : null,
    onDataUpdate: typeof spec.onDataUpdate === 'function' ? spec.onDataUpdate : null,
    methods: safeMethods
  };
}

export function createMiniProgramSession(definition, { template, maxRatePerSec = MAX_SET_DATA_RATE_PER_SEC } = {}) {
  const def = defineMiniProgram(definition);
  const activeTemplate = template || def.template;
  let data = deepClone(def.data);
  let hostData = {};
  let context = {};
  let lifecycle = 'created';
  let timestamps = [];
  let head = 0;
  let viewDirty = true;
  let cachedView = null;

  function recordSetDataRate(nowMs = Date.now()) {
    while (head < timestamps.length && nowMs - timestamps[head] >= 1000) {
      head++;
    }
    if (head > 64) {
      timestamps = timestamps.slice(head);
      head = 0;
    }
    if (timestamps.length - head >= maxRatePerSec) {
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
      viewDirty = true;
    }
  };

  return {
    get data() { return deepClone(data); },
    get lifecycle() { return lifecycle; },
    setData(patch, nowMs = Date.now()) { ctx.setData(patch, nowMs); },
    load(initialHostData = {}, initialContext = {}) {
      hostData = deepClone(initialHostData);
      context = deepClone(initialContext);
      viewDirty = true;
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
      viewDirty = true;
      if (def.onDataUpdate) def.onDataUpdate.call(ctx, hostData, context);
    },
    dispatchEvent(event) {
      if (!isPlainObject(event)) return false;
      const handler = event.handler;
      if (
        typeof handler === 'string' &&
        VALID_HANDLER_NAME_RE.test(handler) &&
        !FORBIDDEN_METHOD_NAMES.has(handler) &&
        Object.hasOwn(def.methods, handler) &&
        typeof def.methods[handler] === 'function'
      ) {
        def.methods[handler].call(ctx, deepClone(event));
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
      if (viewDirty || cachedView === null) {
        cachedView = compileTemplate(activeTemplate, { ...hostData, ...data, data, hostData, context });
        viewDirty = false;
      }
      return deepClone(cachedView);
    }
  };
}

export const defineVibeSnippet = defineMiniProgram;
export const createVibeSnippetSession = createMiniProgramSession;
