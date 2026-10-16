export const slots = Object.freeze(['app_page','sidebar_inspector','mobile_bottom_sheet','quick_command','status_bar_item','terminal_action']);
export const validApiName = value => typeof value === 'string' && value.length <= 128 && /^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$/.test(value);
export const validCapability = value => ['network','terminal_read','terminal_write'].includes(value) || (typeof value === 'string' && value.startsWith('api:') && validApiName(value.slice(4)));
export function freezeJson(value, depth = 0) {
  if (depth > 64) throw Error('JSON exceeds depth limit');
  if (value === null || typeof value === 'string' || typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) return value;
  if (Array.isArray(value)) return Object.freeze(value.map(v => freezeJson(v, depth + 1)));
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.freeze(Object.fromEntries(Object.entries(value).map(([k,v]) => [k,freezeJson(v, depth + 1)])));
  }
  throw Error('Invalid JSON value');
}
export function effectCapability(effect) {
  let required = {'network.fetch':'network','terminal.read':'terminal_read','terminal.write':'terminal_write'}[effect.method];
  if (effect.method === 'host.call' && validApiName(effect.arguments?.api)) required = `api:${effect.arguments.api}`;
  if (!required || effect.capability !== required) throw Error('Effect capability does not match method');
  if (!effect.arguments || Array.isArray(effect.arguments) || typeof effect.arguments !== 'object') throw Error('Invalid effect arguments');
  return required;
}
export function effectBatch(effects) {
  if (!Array.isArray(effects) || effects.length > 32 || new TextEncoder().encode(JSON.stringify(effects)).length > 1048576) throw Error('Effect limit exceeded');
  const snapshot = freezeJson(effects), ids = new Set();
  for (const effect of snapshot) {
    effectCapability(effect);
    if (typeof effect.id !== 'string' || !effect.id.length || effect.id.length > 128 || ids.has(effect.id)) throw Error('Invalid effect ID');
    ids.add(effect.id);
  }
  return snapshot;
}
export function validateManifest(manifest) {
  if (!manifest || typeof manifest.id !== 'string' || !/^[a-zA-Z0-9_-][a-zA-Z0-9_.-]{0,127}$/.test(manifest.id) ||
      !Number.isSafeInteger(manifest.version) || manifest.version < 1 || manifest.api_version !== 1 ||
      typeof manifest.name !== 'string' || !manifest.name.length || manifest.name.length > 256 ||
      !['MIT','Apache-2.0','BSD-3-Clause','MIT OR Apache-2.0'].includes(manifest.license) ||
      !Array.isArray(manifest.capabilities) || manifest.capabilities.length > 64 || !manifest.capabilities.every(validCapability)) throw Error('Incompatible extension manifest');
  if (!Array.isArray(manifest.network_origins ?? []) || (manifest.network_origins?.length ?? 0) > 32) throw Error('Invalid network origins');
  for (const origin of manifest.network_origins ?? []) {
    const url = new URL(origin);
    if (url.protocol !== 'https:' || url.username || url.password || url.origin !== origin) throw Error('Invalid network origin');
  }
  const ids = new Set();
  if (!Array.isArray(manifest.contributions ?? []) || (manifest.contributions?.length ?? 0) > 64) throw Error('Invalid contributions');
  for (const c of manifest.contributions ?? []) {
    if (!slots.includes(c.slot) || !['id','title','command'].every(k => typeof c[k] === 'string' && c[k].length > 0 && c[k].length <= 256) || ids.has(c.id)) throw Error('Invalid contribution');
    ids.add(c.id);
  }
  return freezeJson({...manifest, network_origins:manifest.network_origins ?? [], contributions:manifest.contributions ?? []});
}
const unbase64 = value => {
  if (typeof value !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) throw Error('Invalid base64');
  return Uint8Array.from(atob(value), c => c.charCodeAt(0));
};
const base64 = bytes => btoa(Array.from(bytes, b => String.fromCharCode(b)).join(''));
/** Publisher must come from a trusted, separate channel, never from the package. */
export async function verifyPackage(pkg, publisher) {
  if (typeof pkg.manifest !== 'string' || new TextEncoder().encode(pkg.manifest).length > 65536 ||
      typeof pkg.module !== 'string' || pkg.module.length > 22369624 || typeof pkg.signature !== 'string' || pkg.signature.length !== 88 || typeof publisher !== 'string' || publisher.length !== 44) throw Error('Package exceeds limits');
  const keyBytes = unbase64(publisher), signature = unbase64(pkg.signature);
  if (keyBytes.length !== 32 || signature.length !== 64) throw Error('Invalid signing key');
  const key = await crypto.subtle.importKey('raw', keyBytes, 'Ed25519', false, ['verify']);
  if (!await crypto.subtle.verify('Ed25519', key, signature, new TextEncoder().encode(pkg.manifest))) throw Error('Invalid package signature');
  const manifest = validateManifest(JSON.parse(pkg.manifest)), module = unbase64(pkg.module);
  if (module.length > 16777216 || module.length < 8 || ![0,97,115,109,1,0,0,0].every((v,i) => module[i] === v) ||
      base64(new Uint8Array(await crypto.subtle.digest('SHA-256', module))) !== manifest.module_sha256) throw Error('Invalid module digest');
  return {manifest, module};
}
