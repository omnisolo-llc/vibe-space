import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign,createHash} from 'node:crypto';
import {verifyPackage,effectBatch,validCapability,validateManifest} from '../sdk/typescript/index.mjs';

function fixture() {
  const {privateKey,publicKey} = generateKeyPairSync('ed25519');
  const module = Buffer.from([0,97,115,109,1,0,0,0]);
  const manifest = JSON.stringify({id:'demo',version:1,api_version:1,name:'Demo',license:'MIT',capabilities:['api:leapterm.ui'],network_origins:[],contributions:[{id:'open',slot:'quick_command',title:'Demo',command:'open'}],module_sha256:createHash('sha256').update(module).digest('base64')});
  return {pkg:{manifest,module:module.toString('base64'),signature:sign(null,Buffer.from(manifest),privateKey).toString('base64')},publisher:publicKey.export({type:'spki',format:'der'}).subarray(-32).toString('base64')};
}
test('exact manifest signature, publisher pin, and module digest',async () => {
  const {pkg,publisher} = fixture();
  assert.equal((await verifyPackage(pkg,publisher)).manifest.id,'demo');
  await assert.rejects(verifyPackage({...pkg,manifest:pkg.manifest+' '},publisher));
  await assert.rejects(verifyPackage({...pkg,module:'AGFzbQEAAAAAAA=='},publisher));
  await assert.rejects(verifyPackage(pkg,fixture().publisher));
});
test('only implemented capabilities and contribution names are accepted',() => {
  assert.equal(validCapability('api:leapterm.ui'),true);
  for (const value of ['filesystem','vault_read','api:','api:a/b','api:a..b']) assert.equal(validCapability(value),false);
  const manifest = JSON.parse(fixture().pkg.manifest);
  assert.throws(() => validateManifest({...manifest,contributions:[{id:'html',slot:'raw_html',command:'open',title:'HTML'}]}));
});
test('effect review uses an immutable exact request and denies capability borrowing',() => {
  const original = {id:'ui',method:'host.call',capability:'api:leapterm.ui',arguments:{api:'leapterm.ui',version:1,input:{accent:'purple'}}};
  const batch = effectBatch([original]);
  original.arguments.input.accent = 'red';
  assert.equal(batch[0].arguments.input.accent,'purple');
  assert.throws(() => { batch[0].arguments.input.accent = 'red'; });
  assert.throws(() => effectBatch([{...original,capability:'terminal_read'}]));
  assert.throws(() => effectBatch([original,original]));
});
