const MAX_TRIGGER_DEPTH = 16;
const MAX_PATTERN_LENGTH = 512;
const MAX_REGEX_PATTERN_LENGTH = 256;
const MAX_BRANCH_ITEMS = 64;
const MAX_REGEX_CACHE = 512;

const BRACE_QUANT_RE = /\{(\d+)(?:,(\d*))?\}/y;
const HTML_ESCAPE_RE = /[&<>"']/g;
const HTML_ESCAPE_MAP = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
};
const BACKSLASH_RE = /\\/g;
const WS_SPLIT_RE = /\s+/;
const TEMPLATE_VAR_RE = /\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g;

const GLOB_REGEX_CACHE = new Map();
const USER_REGEX_CACHE = new Map();

const FORBIDDEN_LOOKUP_KEYS = new Set([
  '__proto__', 'constructor', 'prototype',
  'toString', 'toLocaleString', 'valueOf',
  'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable',
  '__defineGetter__', '__defineSetter__', '__lookupGetter__', '__lookupSetter__'
]);

function isRepeatingQuantifierAt(pattern, idx) {
  if (idx >= pattern.length) return false;
  const ch = pattern[idx];
  if (ch === '+' || ch === '*') return true;
  if (ch === '{') {
    BRACE_QUANT_RE.lastIndex = idx;
    const m = BRACE_QUANT_RE.exec(pattern);
    if (m) {
      const min = Number(m[1]);
      const max = m[2] === undefined ? min : (m[2] === '' ? Infinity : Number(m[2]));
      return max > 1;
    }
  }
  return false;
}

function hasUnsafeRegexConstructs(pattern) {
  let inCharClass = false;
  const groupStack = [];
  for (let i = 0; i < pattern.length; i++) {
    const ch = pattern[i];
    if (ch === '\\') {
      const next = pattern[i + 1];
      if (!inCharClass && next >= '1' && next <= '9') return true;
      if (groupStack.length > 0 && next !== undefined) {
        const top = groupStack[groupStack.length - 1];
        top.branches[top.branches.length - 1] += '\\' + next;
      }
      i += 1;
      continue;
    }
    if (inCharClass) {
      if (ch === ']') inCharClass = false;
      continue;
    }
    if (ch === '[') {
      inCharClass = true;
      continue;
    }
    if (ch === '(') {
      let skip = 0;
      if (pattern[i + 1] === '?') {
        if (pattern[i + 2] === ':' || pattern[i + 2] === '=' || pattern[i + 2] === '!') skip = 2;
        else if (pattern[i + 2] === '<' && (pattern[i + 3] === '=' || pattern[i + 3] === '!')) skip = 3;
      }
      groupStack.push({ hasQuantifier: false, branches: [''] });
      i += skip;
      continue;
    }
    if (ch === ')') {
      const grp = groupStack.pop();
      if (!grp) continue;
      const repeated = isRepeatingQuantifierAt(pattern, i + 1);
      if (repeated) {
        if (grp.hasQuantifier) return true;
        if (grp.branches.length > 1) {
          for (let a = 0; a < grp.branches.length; a++) {
            for (let b = a + 1; b < grp.branches.length; b++) {
              const ba = grp.branches[a];
              const bb = grp.branches[b];
              if (!ba || !bb || ba.startsWith(bb) || bb.startsWith(ba)) return true;
            }
          }
        }
      }
      if ((grp.hasQuantifier || repeated) && groupStack.length > 0) {
        groupStack[groupStack.length - 1].hasQuantifier = true;
      }
      continue;
    }
    if (ch === '|' && groupStack.length > 0) {
      groupStack[groupStack.length - 1].branches.push('');
      continue;
    }
    if (isRepeatingQuantifierAt(pattern, i)) {
      if (groupStack.length > 0) {
        groupStack[groupStack.length - 1].hasQuantifier = true;
      }
      continue;
    }
    if (groupStack.length > 0) {
      const top = groupStack[groupStack.length - 1];
      top.branches[top.branches.length - 1] += ch;
    }
  }
  return false;
}

function escapeHtml(text) {
  if (!HTML_ESCAPE_RE.test(text)) return text;
  HTML_ESCAPE_RE.lastIndex = 0;
  return text.replace(HTML_ESCAPE_RE, ch => HTML_ESCAPE_MAP[ch]);
}

function getCachedGlobRegExp(glob, caseSensitive = true) {
  const key = (caseSensitive ? '1:' : '0:') + glob;
  const cached = GLOB_REGEX_CACHE.get(key);
  if (cached !== undefined) return cached;

  let out = '^';
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i];
    if (ch === '*') out += '.*';
    else if (ch === '?') out += '.';
    else if ('.+^$(){}[]|\\'.includes(ch)) out += '\\' + ch;
    else out += ch;
  }
  out += '$';
  const re = new RegExp(out, caseSensitive ? '' : 'i');
  if (GLOB_REGEX_CACHE.size >= MAX_REGEX_CACHE) {
    GLOB_REGEX_CACHE.delete(GLOB_REGEX_CACHE.keys().next().value);
  }
  GLOB_REGEX_CACHE.set(key, re);
  return re;
}

function getCachedUserRegExp(pattern, caseSensitive = true) {
  const key = (caseSensitive ? '1:' : '0:') + pattern;
  const cached = USER_REGEX_CACHE.get(key);
  if (cached !== undefined) return cached;

  const re = new RegExp(pattern, caseSensitive ? '' : 'i');
  if (USER_REGEX_CACHE.size >= MAX_REGEX_CACHE) {
    USER_REGEX_CACHE.delete(USER_REGEX_CACHE.keys().next().value);
  }
  USER_REGEX_CACHE.set(key, re);
  return re;
}

function valueExists(val) {
  if (val === null || val === undefined) return false;
  if (typeof val === 'string') return val.length > 0;
  if (Array.isArray(val)) return val.length > 0;
  if (typeof val === 'object') return Object.keys(val).length > 0;
  return true;
}

function scalarEquals(actual, expected, caseSensitive = true) {
  if (actual === expected) return true;
  if (typeof actual === 'string' && typeof expected === 'string') {
    return caseSensitive ? actual === expected : actual.toLowerCase() === expected.toLowerCase();
  }
  if (typeof actual === 'number' && typeof expected === 'string') {
    const trimmed = expected.trim();
    if (!trimmed) return false;
    const n = Number(trimmed);
    return Number.isFinite(n) && actual === n;
  }
  if (typeof actual === 'string' && typeof expected === 'number') {
    const trimmed = actual.trim();
    if (!trimmed) return false;
    const n = Number(trimmed);
    return Number.isFinite(n) && n === expected;
  }
  if (typeof actual === 'string' && typeof expected === 'boolean') {
    const norm = actual.trim().toLowerCase();
    return expected ? (norm === 'true' || norm === '1') : (norm === 'false' || norm === '0');
  }
  return false;
}

function parseMatcher(raw) {
  if (typeof raw === 'string') {
    if (raw.length > MAX_PATTERN_LENGTH) throw Error('Trigger pattern exceeds 512 chars');
    return (raw.includes('*') || raw.includes('?'))
      ? { kind: 'glob', value: raw, caseSensitive: true, re: getCachedGlobRegExp(raw, true) }
      : { kind: 'exact', value: raw, caseSensitive: true };
  }
  if (typeof raw === 'boolean') return { kind: 'exact', value: raw, caseSensitive: true };
  if (typeof raw === 'number' && Number.isFinite(raw)) return { kind: 'exact', value: raw, caseSensitive: true };
  if (Array.isArray(raw)) {
    if (raw.length === 0 || raw.length > MAX_BRANCH_ITEMS) throw Error('Trigger oneOf must have 1..64 items');
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i];
      const t = typeof item;
      if ((t !== 'string' && t !== 'number' && t !== 'boolean') || (t === 'number' && !Number.isFinite(item))) {
        throw Error('Invalid trigger oneOf item');
      }
      if (t === 'string' && item.length > MAX_PATTERN_LENGTH) throw Error('Trigger pattern exceeds 512 chars');
    }
    return { kind: 'oneOf', values: raw.slice(), caseSensitive: true };
  }
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    const cs = typeof raw.caseSensitive === 'boolean' ? raw.caseSensitive : true;
    if (Object.hasOwn(raw, 'exists')) {
      if (typeof raw.exists !== 'boolean') throw Error('Trigger exists must be boolean');
      return { kind: 'exists', value: raw.exists, caseSensitive: true };
    }
    if (Object.hasOwn(raw, 'exact') || Object.hasOwn(raw, 'equals')) {
      const v = Object.hasOwn(raw, 'exact') ? raw.exact : raw.equals;
      if (v !== null && typeof v !== 'string' && typeof v !== 'number' && typeof v !== 'boolean') {
        throw Error('Invalid exact matcher');
      }
      return { kind: 'exact', value: v, caseSensitive: cs };
    }
    if (Object.hasOwn(raw, 'glob') || Object.hasOwn(raw, 'wildcard')) {
      const p = raw.glob ?? raw.wildcard;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid glob matcher');
      return { kind: 'glob', value: p, caseSensitive: cs, re: getCachedGlobRegExp(p, cs) };
    }
    if (Object.hasOwn(raw, 'regex') || Object.hasOwn(raw, 'pattern')) {
      const p = raw.regex ?? raw.pattern;
      if (typeof p !== 'string' || !p.length || p.length > MAX_REGEX_PATTERN_LENGTH) throw Error('Invalid regex matcher');
      if (hasUnsafeRegexConstructs(p)) throw Error('Unsafe regex matcher (catastrophic backtracking risk)');
      const re = getCachedUserRegExp(p, cs);
      return { kind: 'regex', value: p, caseSensitive: cs, re };
    }
    if (Object.hasOwn(raw, 'contains')) {
      return { kind: 'contains', value: raw.contains, caseSensitive: cs };
    }
    if (Object.hasOwn(raw, 'prefix') || Object.hasOwn(raw, 'startsWith')) {
      const p = raw.prefix ?? raw.startsWith;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid prefix matcher');
      return { kind: 'prefix', value: p, caseSensitive: cs };
    }
    if (Object.hasOwn(raw, 'suffix') || Object.hasOwn(raw, 'endsWith')) {
      const p = raw.suffix ?? raw.endsWith;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid suffix matcher');
      return { kind: 'suffix', value: p, caseSensitive: cs };
    }
    if (Object.hasOwn(raw, 'oneOf') || Object.hasOwn(raw, 'in')) {
      const arr = raw.oneOf ?? raw.in;
      if (!Array.isArray(arr) || !arr.length || arr.length > MAX_BRANCH_ITEMS) throw Error('Invalid oneOf matcher');
      return { kind: 'oneOf', values: arr.slice(), caseSensitive: cs };
    }
  }
  throw Error('Invalid trigger matcher');
}

export function validateTriggerCondition(raw, depth = 0) {
  if (depth > MAX_TRIGGER_DEPTH) throw Error('Trigger condition exceeds depth limit');
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw Error('Trigger condition must be an object');
  if (Object.hasOwn(raw, 'always') && raw.always !== undefined && typeof raw.always !== 'boolean') {
    throw Error('Trigger always must be boolean');
  }
  for (const key of ['program', 'command', 'window', 'surface', 'windowTitle', 'cwd', 'pathPattern']) {
    if (raw[key] !== undefined && raw[key] !== null) parseMatcher(raw[key]);
  }
  for (const mapKey of ['env', 'context']) {
    if (raw[mapKey] !== undefined && raw[mapKey] !== null) {
      if (typeof raw[mapKey] !== 'object' || Array.isArray(raw[mapKey])) throw Error(`Trigger ${mapKey} must be an object`);
      const keys = Object.keys(raw[mapKey]);
      if (keys.length > MAX_BRANCH_ITEMS) throw Error(`Trigger ${mapKey} exceeds limit`);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (FORBIDDEN_LOOKUP_KEYS.has(k)) throw Error(`Forbidden trigger ${mapKey} key "${k}"`);
        parseMatcher(raw[mapKey][k]);
      }
    }
  }
  for (const listKey of ['all', 'any']) {
    if (raw[listKey] !== undefined && raw[listKey] !== null) {
      if (!Array.isArray(raw[listKey]) || raw[listKey].length > MAX_BRANCH_ITEMS) throw Error(`Trigger ${listKey} invalid`);
      for (let i = 0; i < raw[listKey].length; i++) {
        validateTriggerCondition(raw[listKey][i], depth + 1);
      }
    }
  }
  if (raw.not !== undefined && raw.not !== null) validateTriggerCondition(raw.not, depth + 1);
  return raw;
}

function evalMatcher(parsed, actual) {
  if (parsed.kind === 'exists') return parsed.value ? valueExists(actual) : !valueExists(actual);
  if (actual === null || actual === undefined) return false;
  if (Array.isArray(actual)) return actual.some(item => evalMatcher(parsed, item));
  const str = typeof actual === 'string'
    ? actual
    : (typeof actual === 'number' || typeof actual === 'boolean' ? String(actual) : null);

  switch (parsed.kind) {
    case 'exact':
      return scalarEquals(actual, parsed.value, parsed.caseSensitive);
    case 'glob':
      return str !== null && (parsed.re || getCachedGlobRegExp(parsed.value, parsed.caseSensitive)).test(str);
    case 'regex':
      return str !== null && (parsed.re || getCachedUserRegExp(parsed.value, parsed.caseSensitive)).test(str);
    case 'contains': {
      if (str === null) return false;
      const needle = typeof parsed.value === 'string' ? parsed.value : String(parsed.value ?? '');
      return parsed.caseSensitive ? str.includes(needle) : str.toLowerCase().includes(needle.toLowerCase());
    }
    case 'prefix':
      return str !== null && (parsed.caseSensitive
        ? str.startsWith(parsed.value)
        : str.toLowerCase().startsWith(parsed.value.toLowerCase()));
    case 'suffix':
      return str !== null && (parsed.caseSensitive
        ? str.endsWith(parsed.value)
        : str.toLowerCase().endsWith(parsed.value.toLowerCase()));
    case 'oneOf':
      return parsed.values.some(item =>
        (typeof item === 'string' && (item.includes('*') || item.includes('?')))
          ? (str !== null && getCachedGlobRegExp(item, parsed.caseSensitive).test(str))
          : scalarEquals(actual, item, parsed.caseSensitive)
      );
    default:
      return false;
  }
}

function matchCandidates(rawMatcher, candidates) {
  const parsed = parseMatcher(rawMatcher);
  let hasNonEmpty = false;
  if (parsed.kind === 'exists') {
    for (let i = 0; i < candidates.length; i++) {
      if (typeof candidates[i] === 'string' && candidates[i].length > 0) {
        hasNonEmpty = true;
        break;
      }
    }
    return parsed.value ? hasNonEmpty : !hasNonEmpty;
  }
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    if (typeof c === 'string' && c.length > 0 && evalMatcher(parsed, c)) return true;
  }
  return false;
}

function normalizePath(p) {
  if (typeof p !== 'string' || !p.length) return null;
  const f = p.replace(BACKSLASH_RE, '/');
  return f.length > 1 && f.endsWith('/') ? f.slice(0, -1) : f;
}

function lookupContextValue(ctx, key) {
  if (typeof key !== 'string' || !key || FORBIDDEN_LOOKUP_KEYS.has(key)) return undefined;
  const cMap = ctx && ctx.context && typeof ctx.context === 'object' ? ctx.context : null;
  const eMap = ctx && ctx.env && typeof ctx.env === 'object' ? ctx.env : null;
  if (cMap) {
    if (Object.hasOwn(cMap, key)) return cMap[key];
    if (key === 'portOpen' && Object.hasOwn(cMap, 'ports')) return cMap.ports;
    if (key === 'ports' && Object.hasOwn(cMap, 'portOpen')) return cMap.portOpen;
  }
  if (eMap && Object.hasOwn(eMap, key)) return eMap[key];
  if (key.startsWith('env.')) {
    const sub = key.slice(4);
    if (!FORBIDDEN_LOOKUP_KEYS.has(sub) && eMap && Object.hasOwn(eMap, sub)) return eMap[sub];
    return undefined;
  }
  if (key.startsWith('context.')) return lookupContextValue(ctx, key.slice(8));
  if (ctx && typeof ctx === 'object' && Object.hasOwn(ctx, key)) return ctx[key];
  return undefined;
}

function prepareTriggerContext(context = {}) {
  const ctx = context && typeof context === 'object' ? context : {};
  let progCandidates = null;
  let cmdCandidates = null;
  let winTitleCandidates = null;
  let winCandidates = null;
  let normCwd = undefined;

  return {
    ctx,
    get progCandidates() {
      if (progCandidates !== null) return progCandidates;
      const list = [];
      const addProg = p => {
        if (typeof p !== 'string') return;
        const t = p.trim();
        if (!t) return;
        list.push(t);
        const norm = t.replace(BACKSLASH_RE, '/');
        const slashIdx = norm.lastIndexOf('/');
        const base = slashIdx >= 0 ? norm.slice(slashIdx + 1) : norm;
        if (base !== t) list.push(base);
      };
      addProg(ctx.program);
      if (Array.isArray(ctx.argv) && ctx.argv.length) addProg(String(ctx.argv[0]));
      if (typeof ctx.command === 'string' && ctx.command.trim()) {
        addProg(ctx.command.trim().split(WS_SPLIT_RE)[0]);
      }
      progCandidates = list;
      return progCandidates;
    },
    get cmdCandidates() {
      if (cmdCandidates !== null) return cmdCandidates;
      cmdCandidates = [
        ctx.command,
        Array.isArray(ctx.argv) && ctx.argv.length ? ctx.argv.join(' ') : null,
        ctx.program
      ];
      return cmdCandidates;
    },
    get winTitleCandidates() {
      if (winTitleCandidates !== null) return winTitleCandidates;
      winTitleCandidates = [ctx.windowTitle, ctx.window];
      return winTitleCandidates;
    },
    get winCandidates() {
      if (winCandidates !== null) return winCandidates;
      winCandidates = [ctx.window, ctx.windowTitle, ctx.surface];
      return winCandidates;
    },
    get normCwd() {
      if (normCwd !== undefined) return normCwd;
      normCwd = normalizePath(ctx.cwd);
      return normCwd;
    }
  };
}

function evalValidatedCondition(condition, prepared) {
  if (condition.always === false) return false;
  const ctx = prepared.ctx;

  if (condition.program !== undefined && condition.program !== null && !matchCandidates(condition.program, prepared.progCandidates)) return false;
  if (condition.command !== undefined && condition.command !== null && !matchCandidates(condition.command, prepared.cmdCandidates)) return false;
  if (condition.surface !== undefined && condition.surface !== null && !evalMatcher(parseMatcher(condition.surface), ctx.surface)) return false;
  if (condition.windowTitle !== undefined && condition.windowTitle !== null && !matchCandidates(condition.windowTitle, prepared.winTitleCandidates)) return false;
  if (condition.window !== undefined && condition.window !== null && !matchCandidates(condition.window, prepared.winCandidates)) return false;
  if (condition.cwd !== undefined && condition.cwd !== null && !evalMatcher(parseMatcher(condition.cwd), prepared.normCwd)) return false;
  if (condition.pathPattern !== undefined && condition.pathPattern !== null && !evalMatcher(parseMatcher(condition.pathPattern), prepared.normCwd)) return false;

  if (condition.env) {
    const eKeys = Object.keys(condition.env);
    for (let i = 0; i < eKeys.length; i++) {
      const k = eKeys[i];
      if (FORBIDDEN_LOOKUP_KEYS.has(k)) return false;
      const val = ctx.env && Object.hasOwn(ctx.env, k) ? ctx.env[k] : lookupContextValue(ctx, k);
      if (!evalMatcher(parseMatcher(condition.env[k]), val)) return false;
    }
  }
  if (condition.context) {
    const cKeys = Object.keys(condition.context);
    for (let i = 0; i < cKeys.length; i++) {
      const k = cKeys[i];
      if (FORBIDDEN_LOOKUP_KEYS.has(k)) return false;
      if (!evalMatcher(parseMatcher(condition.context[k]), lookupContextValue(ctx, k))) return false;
    }
  }
  if (Array.isArray(condition.all)) {
    for (let i = 0; i < condition.all.length; i++) {
      if (!evalValidatedCondition(condition.all[i], prepared)) return false;
    }
  }
  if (Array.isArray(condition.any) && condition.any.length > 0) {
    let anyMatched = false;
    for (let i = 0; i < condition.any.length; i++) {
      if (evalValidatedCondition(condition.any[i], prepared)) {
        anyMatched = true;
        break;
      }
    }
    if (!anyMatched) return false;
  }
  if (condition.not && evalValidatedCondition(condition.not, prepared)) return false;
  return true;
}

export function evaluateTriggerCondition(condition, context = {}) {
  validateTriggerCondition(condition);
  return evalValidatedCondition(condition, prepareTriggerContext(context));
}

export function hydrateVibeTemplate(template, context = {}, options = {}) {
  if (typeof template !== 'string' || !template.includes('{{')) return template;
  return template.replace(TEMPLATE_VAR_RE, (_, key) => {
    const raw = lookupContextValue(context, key);
    const text = raw === null || raw === undefined ? '' : (Array.isArray(raw) ? raw.join(', ') : String(raw));
    if (options.escapeHtml) return escapeHtml(text);
    if (options.escapeJson) return JSON.stringify(text).slice(1, -1);
    return text;
  });
}

export function createTriggerEvaluator() {
  const activeIds = new Set();
  const lastMatchedAtMs = new Map();
  const dismissedIds = new Set();

  return {
    dismiss(id) { dismissedIds.add(id); },
    undismiss(id) { dismissedIds.delete(id); },
    reset() { activeIds.clear(); lastMatchedAtMs.clear(); dismissedIds.clear(); },
    evaluate(entries, context = {}, nowMs = Date.now()) {
      const sorted = Array.isArray(entries) ? (entries.length > 1 ? entries.slice() : entries) : Array.from(entries);
      if (sorted.length > 1) {
        sorted.sort((a, b) => {
          if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
          if ((a.priority ?? 0) !== (b.priority ?? 0)) return (b.priority ?? 0) - (a.priority ?? 0);
          if ((a.order ?? 0) !== (b.order ?? 0)) return (a.order ?? 0) - (b.order ?? 0);
          return String(a.id).localeCompare(String(b.id));
        });
      }
      const prepared = prepareTriggerContext(context);
      const activeEntries = [];
      const nextIds = new Set();
      const activeIdsOut = [];
      const heldIds = [];
      for (let i = 0; i < sorted.length; i++) {
        const entry = sorted[i];
        if (entry.enabled === false) {
          lastMatchedAtMs.delete(entry.id);
          dismissedIds.delete(entry.id);
          continue;
        }
        const cond = entry.when ?? entry.condition;
        let matched = entry.pinned === true;
        if (!matched && cond != null) {
          validateTriggerCondition(cond);
          matched = evalValidatedCondition(cond, prepared);
        }
        if (matched) {
          lastMatchedAtMs.set(entry.id, nowMs);
          if (dismissedIds.has(entry.id) && !entry.pinned) continue;
          activeEntries.push(entry);
          if (!nextIds.has(entry.id)) {
            nextIds.add(entry.id);
            activeIdsOut.push(entry.id);
          }
        } else {
          const lastAt = lastMatchedAtMs.get(entry.id);
          const holdMs = entry.holdMs ?? 0;
          if (holdMs > 0 && lastAt !== undefined && nowMs - lastAt >= 0 && nowMs - lastAt < holdMs && activeIds.has(entry.id) && !dismissedIds.has(entry.id)) {
            activeEntries.push(entry);
            if (!nextIds.has(entry.id)) {
              nextIds.add(entry.id);
              activeIdsOut.push(entry.id);
            }
            heldIds.push(entry.id);
          } else {
            lastMatchedAtMs.delete(entry.id);
            dismissedIds.delete(entry.id);
          }
        }
      }
      const newlyTriggeredIds = [];
      for (let i = 0; i < activeIdsOut.length; i++) {
        const id = activeIdsOut[i];
        if (!activeIds.has(id)) newlyTriggeredIds.push(id);
      }
      const deactivatedIds = [];
      for (const id of activeIds) {
        if (!nextIds.has(id)) deactivatedIds.push(id);
      }
      activeIds.clear();
      for (let i = 0; i < activeIdsOut.length; i++) activeIds.add(activeIdsOut[i]);
      return { context, activeEntries, activeIds: activeIdsOut, newlyTriggeredIds, deactivatedIds, heldIds, changed: newlyTriggeredIds.length > 0 || deactivatedIds.length > 0 };
    }
  };
}
