const MAX_TRIGGER_DEPTH = 16;
const MAX_PATTERN_LENGTH = 512;
const MAX_BRANCH_ITEMS = 64;

function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function globToRegExp(glob, caseSensitive = true) {
  let out = '^';
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i];
    if (ch === '*') out += '.*';
    else if (ch === '?') out += '.';
    else if ('.+^$(){}[]|\\'.includes(ch)) out += '\\' + ch;
    else out += ch;
  }
  out += '$';
  return new RegExp(out, caseSensitive ? '' : 'i');
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
    const n = Number(expected.trim());
    return Number.isFinite(n) && expected.trim() !== '' && actual === n;
  }
  if (typeof actual === 'string' && typeof expected === 'number') {
    const n = Number(actual.trim());
    return Number.isFinite(n) && actual.trim() !== '' && n === expected;
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
      ? {kind: 'glob', value: raw, caseSensitive: true}
      : {kind: 'exact', value: raw, caseSensitive: true};
  }
  if (typeof raw === 'boolean') return {kind: 'exact', value: raw, caseSensitive: true};
  if (typeof raw === 'number' && Number.isFinite(raw)) return {kind: 'exact', value: raw, caseSensitive: true};
  if (Array.isArray(raw)) {
    if (raw.length === 0 || raw.length > MAX_BRANCH_ITEMS) throw Error('Trigger oneOf must have 1..64 items');
    for (const item of raw) {
      if (!['string', 'number', 'boolean'].includes(typeof item) || (typeof item === 'number' && !Number.isFinite(item))) {
        throw Error('Invalid trigger oneOf item');
      }
      if (typeof item === 'string' && item.length > MAX_PATTERN_LENGTH) throw Error('Trigger pattern exceeds 512 chars');
    }
    return {kind: 'oneOf', values: raw.slice(), caseSensitive: true};
  }
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    const cs = typeof raw.caseSensitive === 'boolean' ? raw.caseSensitive : true;
    if ('exists' in raw) {
      if (typeof raw.exists !== 'boolean') throw Error('Trigger exists must be boolean');
      return {kind: 'exists', value: raw.exists, caseSensitive: true};
    }
    if ('exact' in raw || 'equals' in raw) {
      const v = 'exact' in raw ? raw.exact : raw.equals;
      if (v !== null && !['string', 'number', 'boolean'].includes(typeof v)) throw Error('Invalid exact matcher');
      return {kind: 'exact', value: v, caseSensitive: cs};
    }
    if ('glob' in raw || 'wildcard' in raw) {
      const p = raw.glob ?? raw.wildcard;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid glob matcher');
      return {kind: 'glob', value: p, caseSensitive: cs};
    }
    if ('regex' in raw || 'pattern' in raw) {
      const p = raw.regex ?? raw.pattern;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid regex matcher');
      new RegExp(p, cs ? '' : 'i');
      return {kind: 'regex', value: p, caseSensitive: cs};
    }
    if ('contains' in raw) {
      return {kind: 'contains', value: raw.contains, caseSensitive: cs};
    }
    if ('prefix' in raw || 'startsWith' in raw) {
      const p = raw.prefix ?? raw.startsWith;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid prefix matcher');
      return {kind: 'prefix', value: p, caseSensitive: cs};
    }
    if ('suffix' in raw || 'endsWith' in raw) {
      const p = raw.suffix ?? raw.endsWith;
      if (typeof p !== 'string' || !p.length || p.length > MAX_PATTERN_LENGTH) throw Error('Invalid suffix matcher');
      return {kind: 'suffix', value: p, caseSensitive: cs};
    }
    if ('oneOf' in raw || 'in' in raw) {
      const arr = raw.oneOf ?? raw.in;
      if (!Array.isArray(arr) || !arr.length || arr.length > MAX_BRANCH_ITEMS) throw Error('Invalid oneOf matcher');
      return {kind: 'oneOf', values: arr.slice(), caseSensitive: cs};
    }
  }
  throw Error('Invalid trigger matcher');
}

export function validateTriggerCondition(raw, depth = 0) {
  if (depth > MAX_TRIGGER_DEPTH) throw Error('Trigger condition exceeds depth limit');
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw Error('Trigger condition must be an object');
  if ('always' in raw && raw.always !== undefined && typeof raw.always !== 'boolean') throw Error('Trigger always must be boolean');
  for (const key of ['program', 'command', 'window', 'surface', 'windowTitle', 'cwd', 'pathPattern']) {
    if (raw[key] !== undefined && raw[key] !== null) parseMatcher(raw[key]);
  }
  for (const mapKey of ['env', 'context']) {
    if (raw[mapKey] !== undefined && raw[mapKey] !== null) {
      if (typeof raw[mapKey] !== 'object' || Array.isArray(raw[mapKey])) throw Error(`Trigger ${mapKey} must be an object`);
      const entries = Object.entries(raw[mapKey]);
      if (entries.length > MAX_BRANCH_ITEMS) throw Error(`Trigger ${mapKey} exceeds limit`);
      for (const [, v] of entries) parseMatcher(v);
    }
  }
  for (const listKey of ['all', 'any']) {
    if (raw[listKey] !== undefined && raw[listKey] !== null) {
      if (!Array.isArray(raw[listKey]) || raw[listKey].length > MAX_BRANCH_ITEMS) throw Error(`Trigger ${listKey} invalid`);
      for (const item of raw[listKey]) validateTriggerCondition(item, depth + 1);
    }
  }
  if (raw.not !== undefined && raw.not !== null) validateTriggerCondition(raw.not, depth + 1);
  return raw;
}

function evalMatcher(parsed, actual) {
  if (parsed.kind === 'exists') return parsed.value ? valueExists(actual) : !valueExists(actual);
  if (actual === null || actual === undefined) return false;
  if (Array.isArray(actual)) return actual.some(item => evalMatcher(parsed, item));
  const str = typeof actual === 'string' ? actual : (typeof actual === 'number' || typeof actual === 'boolean' ? String(actual) : null);
  switch (parsed.kind) {
    case 'exact': return scalarEquals(actual, parsed.value, parsed.caseSensitive);
    case 'glob': return str !== null && globToRegExp(parsed.value, parsed.caseSensitive).test(str);
    case 'regex': return str !== null && new RegExp(parsed.value, parsed.caseSensitive ? '' : 'i').test(str);
    case 'contains': {
      const needle = typeof parsed.value === 'string' ? parsed.value : String(parsed.value ?? '');
      if (str === null) return false;
      return parsed.caseSensitive ? str.includes(needle) : str.toLowerCase().includes(needle.toLowerCase());
    }
    case 'prefix': return str !== null && (parsed.caseSensitive ? str.startsWith(parsed.value) : str.toLowerCase().startsWith(parsed.value.toLowerCase()));
    case 'suffix': return str !== null && (parsed.caseSensitive ? str.endsWith(parsed.value) : str.toLowerCase().endsWith(parsed.value.toLowerCase()));
    case 'oneOf': return parsed.values.some(item => (typeof item === 'string' && (item.includes('*') || item.includes('?')))
      ? (str !== null && globToRegExp(item, parsed.caseSensitive).test(str))
      : scalarEquals(actual, item, parsed.caseSensitive));
    default: return false;
  }
}

function matchCandidates(rawMatcher, candidates) {
  const parsed = parseMatcher(rawMatcher);
  const nonEmpty = candidates.filter(c => typeof c === 'string' && c.length > 0);
  if (parsed.kind === 'exists') return parsed.value ? nonEmpty.length > 0 : nonEmpty.length === 0;
  return nonEmpty.some(c => evalMatcher(parsed, c));
}

function normalizePath(p) {
  if (typeof p !== 'string' || !p.length) return null;
  const f = p.replace(/\\/g, '/');
  return f.length > 1 && f.endsWith('/') ? f.slice(0, -1) : f;
}

function lookupContextValue(ctx, key) {
  const cMap = ctx?.context && typeof ctx.context === 'object' ? ctx.context : {};
  const eMap = ctx?.env && typeof ctx.env === 'object' ? ctx.env : {};
  if (key in cMap) return cMap[key];
  if (key === 'portOpen' && 'ports' in cMap) return cMap.ports;
  if (key === 'ports' && 'portOpen' in cMap) return cMap.portOpen;
  if (key in eMap) return eMap[key];
  if (key.startsWith('env.')) return eMap[key.slice(4)];
  if (key.startsWith('context.')) return lookupContextValue(ctx, key.slice(8));
  if (key in (ctx ?? {})) return ctx[key];
  return undefined;
}

export function evaluateTriggerCondition(condition, context = {}) {
  validateTriggerCondition(condition);
  if (condition.always === false) return false;
  const progCandidates = [];
  const addProg = p => {
    if (typeof p !== 'string' || !p.trim()) return;
    const t = p.trim();
    progCandidates.push(t);
    const norm = t.replace(/\\/g, '/');
    const base = norm.includes('/') ? norm.slice(norm.lastIndexOf('/') + 1) : norm;
    if (base !== t) progCandidates.push(base);
  };
  addProg(context.program);
  if (Array.isArray(context.argv) && context.argv.length) addProg(String(context.argv[0]));
  if (typeof context.command === 'string' && context.command.trim()) addProg(context.command.trim().split(/\s+/)[0]);

  if (condition.program !== undefined && condition.program !== null && !matchCandidates(condition.program, progCandidates)) return false;
  const cmdCandidates = [context.command, Array.isArray(context.argv) && context.argv.length ? context.argv.join(' ') : null, context.program];
  if (condition.command !== undefined && condition.command !== null && !matchCandidates(condition.command, cmdCandidates)) return false;
  if (condition.surface !== undefined && condition.surface !== null && !evalMatcher(parseMatcher(condition.surface), context.surface)) return false;
  if (condition.windowTitle !== undefined && condition.windowTitle !== null && !matchCandidates(condition.windowTitle, [context.windowTitle, context.window])) return false;
  if (condition.window !== undefined && condition.window !== null && !matchCandidates(condition.window, [context.window, context.windowTitle, context.surface])) return false;
  const normCwd = normalizePath(context.cwd);
  if (condition.cwd !== undefined && condition.cwd !== null && !evalMatcher(parseMatcher(condition.cwd), normCwd)) return false;
  if (condition.pathPattern !== undefined && condition.pathPattern !== null && !evalMatcher(parseMatcher(condition.pathPattern), normCwd)) return false;
  if (condition.env) {
    for (const [k, m] of Object.entries(condition.env)) {
      const val = context.env && k in context.env ? context.env[k] : lookupContextValue(context, k);
      if (!evalMatcher(parseMatcher(m), val)) return false;
    }
  }
  if (condition.context) {
    for (const [k, m] of Object.entries(condition.context)) {
      if (!evalMatcher(parseMatcher(m), lookupContextValue(context, k))) return false;
    }
  }
  if (Array.isArray(condition.all) && !condition.all.every(c => evaluateTriggerCondition(c, context))) return false;
  if (Array.isArray(condition.any) && condition.any.length > 0 && !condition.any.some(c => evaluateTriggerCondition(c, context))) return false;
  if (condition.not && evaluateTriggerCondition(condition.not, context)) return false;
  return true;
}

export function hydrateVibeTemplate(template, context = {}, options = {}) {
  if (typeof template !== 'string' || !template.includes('{{')) return template;
  return template.replace(/\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g, (_, key) => {
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
      const sorted = [...entries].sort((a, b) => {
        if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
        if ((a.priority ?? 0) !== (b.priority ?? 0)) return (b.priority ?? 0) - (a.priority ?? 0);
        if ((a.order ?? 0) !== (b.order ?? 0)) return (a.order ?? 0) - (b.order ?? 0);
        return String(a.id).localeCompare(String(b.id));
      });
      const activeEntries = [];
      const nextIds = new Set();
      const heldIds = [];
      for (const entry of sorted) {
        if (entry.enabled === false) {
          lastMatchedAtMs.delete(entry.id);
          dismissedIds.delete(entry.id);
          continue;
        }
        const cond = entry.when ?? entry.condition;
        const matched = entry.pinned === true || (cond != null && evaluateTriggerCondition(cond, context));
        if (matched) {
          lastMatchedAtMs.set(entry.id, nowMs);
          if (dismissedIds.has(entry.id) && !entry.pinned) continue;
          activeEntries.push(entry);
          nextIds.add(entry.id);
        } else {
          const lastAt = lastMatchedAtMs.get(entry.id);
          const holdMs = entry.holdMs ?? 0;
          if (holdMs > 0 && lastAt !== undefined && nowMs - lastAt >= 0 && nowMs - lastAt < holdMs && activeIds.has(entry.id) && !dismissedIds.has(entry.id)) {
            activeEntries.push(entry);
            nextIds.add(entry.id);
            heldIds.push(entry.id);
          } else {
            lastMatchedAtMs.delete(entry.id);
            dismissedIds.delete(entry.id);
          }
        }
      }
      const newlyTriggeredIds = [...nextIds].filter(id => !activeIds.has(id));
      const deactivatedIds = [...activeIds].filter(id => !nextIds.has(id));
      activeIds.clear();
      for (const id of nextIds) activeIds.add(id);
      return {context, activeEntries, activeIds: [...nextIds], newlyTriggeredIds, deactivatedIds, heldIds, changed: newlyTriggeredIds.length > 0 || deactivatedIds.length > 0};
    }
  };
}
