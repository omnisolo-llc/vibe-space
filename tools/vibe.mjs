#!/usr/bin/env node
import {readFile,writeFile,mkdir,cp} from 'node:fs/promises';
import {resolve,dirname,basename,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {generateKeyPairSync,createPrivateKey,createPublicKey,sign,createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {verifyPackage,validateManifest} from '../sdk/typescript/index.mjs';

const root = fileURLToPath(new URL('../',import.meta.url));
const [command,...args] = process.argv.slice(2);
function run(bin,argv,cwd) {
  const result = spawnSync(bin,argv,{cwd,stdio:'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw Error(`${bin} failed (${result.status})`);
}
async function build(dir,language) {
  dir = resolve(dir); const output = join(dir,'build'); await mkdir(output,{recursive:true});
  if (language === 'rust') {
    run('cargo',['build','--manifest-path',join(dir,'Cargo.toml'),'--release','--target','wasm32-unknown-unknown','--target-dir',join(output,'target')],dir);
    const cargo = await readFile(join(dir,'Cargo.toml'),'utf8');
    const name = cargo.match(/^name\s*=\s*"([a-zA-Z0-9_-]+)"/m)?.[1]?.replaceAll('-','_');
    if (!name) throw Error('Cargo package name unavailable');
    await cp(join(output,'target/wasm32-unknown-unknown/release',`${name}.wasm`),join(output,'module.wasm'));
  } else if (language === 'c') {
    run('clang',['--target=wasm32','-O2','-nostdlib',`-I${join(root,'sdk/c')}`,'-Wl,--no-entry','-Wl,--export-memory','-Wl,--max-memory=33554432','-Wl,--initial-memory=2097152',join(dir,'main.c'),'-o',join(output,'module.wasm')],dir);
  } else throw Error('Language must be rust or c');
  console.log(join(output,'module.wasm'));
}
try {
  if (command === 'init') {
    const [dir,language = 'rust'] = args;
    if (!dir || !['rust','c'].includes(language)) throw Error('Usage: init DIRECTORY rust|c');
    await mkdir(resolve(dir)); // Existing directories are never overwritten.
    await cp(join(root,`examples/hello-${language}`),resolve(dir),{recursive:true,filter:source => !['build','target','Cargo.lock'].includes(basename(source))});
    if (language === 'rust') {
      const file = join(resolve(dir),'Cargo.toml'), text = await readFile(file,'utf8');
      await writeFile(file,text.replace('path = "../../sdk/rust"',`path = ${JSON.stringify(join(root,'sdk/rust'))}`));
    }
    console.log(`Created ${resolve(dir)}. Run: node ${join(root,'tools/vibe.mjs')} build ${resolve(dir)} ${language}`);
  } else if (command === 'build') {
    if (!args[0]) throw Error('Usage: build DIRECTORY rust|c');
    await build(args[0],args[1] ?? 'rust');
  } else if (command === 'keygen') {
    const prefix = args[0]; if (!prefix) throw Error('Usage: keygen PATH_PREFIX');
    const {privateKey,publicKey} = generateKeyPairSync('ed25519');
    await writeFile(`${prefix}.pem`,privateKey.export({type:'pkcs8',format:'pem'}),{flag:'wx',mode:0o600});
    await writeFile(`${prefix}.pub`,publicKey.export({type:'spki',format:'der'}).subarray(-32).toString('base64')+'\n',{flag:'wx'});
    console.log(`Created ${prefix}.pem and ${prefix}.pub. Keep the .pem private.`);
  } else if (command === 'pack') {
    const [manifestFile,moduleFile,keyFile,out] = args;
    if (!out) throw Error('Usage: pack MANIFEST MODULE PRIVATE_KEY OUTPUT');
    const manifest = JSON.parse(await readFile(manifestFile,'utf8')), module = await readFile(moduleFile);
    if (module.length > 16777216) throw Error('Module exceeds limit');
    manifest.module_sha256 = createHash('sha256').update(module).digest('base64');
    validateManifest(manifest);
    const raw = JSON.stringify(manifest), key = createPrivateKey(await readFile(keyFile));
    const pkg = {manifest:raw,module:module.toString('base64'),signature:sign(null,Buffer.from(raw),key).toString('base64')};
    const publisher = createPublicKey(key).export({type:'spki',format:'der'}).subarray(-32).toString('base64');
    await verifyPackage(pkg,publisher);
    await writeFile(out,JSON.stringify(pkg,null,2)+'\n'); console.log(`Package: ${out}\nPublisher: ${publisher}`);
  } else if (command === 'inspect') {
    const [file,publisherFile,guestCommand = 'open'] = args;
    if (!publisherFile) throw Error(`Usage: ${command} PACKAGE TRUSTED_PUBLISHER_FILE [COMMAND]`);
    const pkg = JSON.parse(await readFile(file,'utf8'));
    const verified = await verifyPackage(pkg,(await readFile(publisherFile,'utf8')).trim());
    console.log(JSON.stringify(verified.manifest,null,2));
  } else {
    console.log('Vibe Space: init DIRECTORY rust|c · build DIRECTORY rust|c · keygen PREFIX\npack MANIFEST MODULE PRIVATE_KEY OUTPUT · inspect PACKAGE PUBLISHER_FILE\nNative execution: cargo run -p vibe-space-runtime --example run -- PACKAGE PUBLISHER_FILE [COMMAND]');
    if (command && command !== '--help') process.exitCode = 1;
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
