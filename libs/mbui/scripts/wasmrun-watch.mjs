// wasmrun.mjs's watcher (chk logwait's events on Wasm): what it is asked to watch, watched (fs.watch: kqueue's and
// FSEvents' on macOS, inotify's on Linux), and a process's end as the system's own waiter tells it (`caffeinate -w` on
// macOS, kqueue's; on Linux `tail --pid`). Each change or end is said in the shared word 0: bit 1 something changed,
// bit 2 the process ended. Word 1 says 1 (watched) or 2 (could not be) once a watch asked for is set; word 2 is the
// waiter's pid.
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { parentPort, workerData } from 'node:worker_threads';

const word = workerData;
function tell(bit) {
  Atomics.or(word, 0, bit);
  Atomics.notify(word, 0);
}
function answer(good) {
  Atomics.store(word, 1, good ? 1 : 2);
  Atomics.notify(word, 1);
}
const keep = [];
parentPort.on('message', m => {
  try {
    if (m.kind === 'file' || m.kind === 'dir') keep.push(fs.watch(m.path, () => tell(1)));
    else if (m.kind === 'pid') {
      const [cmd, args] = process.platform === 'darwin'
        ? ['caffeinate', ['-w', String(m.pid)]]
        : ['tail', [`--pid=${m.pid}`, '-f', '/dev/null']];
      const waiter = spawn(cmd, args, { stdio: 'ignore' });
      Atomics.store(word, 2, waiter.pid ?? 0);
      waiter.on('exit', () => tell(2));
      waiter.on('error', () => tell(2));
      keep.push(waiter);
    }
    answer(true);
  } catch {
    answer(false);
  }
});
