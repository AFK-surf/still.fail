// Host observation of a bounded classic-Wasm executable, not the Wasm-GC tests.
// No model time or test input depends on this process's clock.
import fs from 'node:fs';
import { WASI } from 'node:wasi';

const wasi = new WASI({ version: 'preview1', args: [], env: {}, returnOnExit: true });
const mod = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
const instance = new WebAssembly.Instance(mod, {
  ...wasi.getImportObject(),
  spectest: { print_char(c) { process.stderr.write(String.fromCodePoint(c)); } },
});
const e = instance.exports;
if (typeof e._start === 'function') wasi.start(instance);
else wasi.initialize(instance);
const bytes = () => e.memory.buffer.byteLength;
const round = () => {
  if (e.run_round() !== 25) throw new Error('wrong lifetime count');
};
for (let n = 0; n < 4; n++) round();
const samples = [];
for (let n = 0; n < 20; n++) {
  round();
  samples.push(bytes());
}
console.log(JSON.stringify({ memory_bytes_after_each_25_lifetimes: samples }));
if (!samples.slice(-5).every(x => x === samples.at(-1))) {
  throw new Error('linear memory still grew over the last five rounds');
}
const before = bytes();
for (let n = 0; n < 8; n++) e.hold_control();
const retained = bytes();
console.log(JSON.stringify({ retained_allocation_control_before: before, after: retained }));
if (retained <= before) throw new Error('the memory observation missed deliberately retained allocations');
e.release_control();
for (let n = 0; n < 4; n++) round();
// Reallocate the control itself: the small page workload alone could fit into
// spare pages even if the supposedly released large arrays remained retained.
for (let n = 0; n < 5; n++) {
  for (let i = 0; i < 8; i++) e.hold_control();
  if (bytes() > retained) throw new Error('released control capacity was not reused');
  e.release_control();
}
console.log(JSON.stringify({ after_control_reused_five_times_and_100_lifetimes: bytes() }));
