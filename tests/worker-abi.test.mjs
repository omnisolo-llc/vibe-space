import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const worker = await readFile(new URL('../web/worker.js', import.meta.url), 'utf8');
function leb(value) {
  const bytes = [];
  do {
    const byte = Number(value & 127n);
    value >>= 7n;
    const done = value === 0n && !(byte & 64);
    bytes.push(byte | (done ? 0 : 128));
    if (done) return bytes;
  } while (true);
}
const string = value => [Buffer.byteLength(value), ...Buffer.from(value)];
const section = (id, bytes) => [id, bytes.length, ...bytes];
function guest(prefix) {
  const response = Buffer.from('{"view":"hello"}');
  const alloc = [0, 65, ...leb(1024n), 11];
  const invoke = [0, 66, ...leb((BigInt(response.length) << 32n) | 32n), 11];
  return Buffer.from([
    0, 97, 115, 109, 1, 0, 0, 0,
    ...section(1, [2, 96, 1, 127, 1, 127, 96, 2, 127, 127, 1, 126]),
    ...section(3, [2, 0, 1]),
    ...section(5, [1, 0, 1]),
    ...section(7, [3, ...string('memory'), 2, 0,
      ...string(`${prefix}_alloc`), 0, 0, ...string(`${prefix}_invoke`), 0, 1]),
    ...section(10, [2, alloc.length, ...alloc, invoke.length, ...invoke]),
    ...section(11, [1, 0, 65, 32, 11, response.length, ...response]),
  ]);
}

test('worker executes a real guest using standard vibe ABI exports', async () => {
  let reply;
  const self = {postMessage: value => { reply = JSON.parse(value); }};
  runInNewContext(worker, {self, WebAssembly, Uint8Array, TextDecoder, atob});
  await self.onmessage({data: JSON.stringify({
    module: guest('vibe').toString('base64'), request: Buffer.from('{}').toString('base64'),
  })});
  assert.deepEqual(reply, {result: {view: 'hello'}});
});

test('worker requires host-configured entrypointPrefixes for non-standard exports', async () => {
  let reply;
  const self = {postMessage: value => { reply = JSON.parse(value); }};
  runInNewContext(worker, {self, WebAssembly, Uint8Array, TextDecoder, atob});
  await self.onmessage({data: JSON.stringify({
    module: guest('custom').toString('base64'), request: Buffer.from('{}').toString('base64'),
  })});
  assert.deepEqual(reply, {error: true, phase: 'abi'});

  await self.onmessage({data: JSON.stringify({
    module: guest('custom').toString('base64'),
    request: Buffer.from('{}').toString('base64'),
    entrypointPrefixes: ['custom_'],
  })});
  assert.deepEqual(reply, {result: {view: 'hello'}});
});
