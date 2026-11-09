// A tool of tools/ built for wasm-gc, run in Node: `node scripts/wasmrun.mjs TOOL.wasm ARGS…`, as its .exe would be
// run (what its arguments, environment, files, stdout, stderr and exit status are). The system's side of tools/sys
// (sys.c on native) is "tsys" here; chk logwait's events (events.c) "chkev"; the core's env (args, the environment,
// the time, an exit) is moonrun's "__moonbit_fs_unstable" & co., as the core asks them. Bytes cross as strings of a
// character a byte (Latin-1); the tool's own strings are JavaScript's (use-js-builtin-string).
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { Worker } from 'node:worker_threads';

const [file, ...args] = process.argv.slice(2);
if (!file) {
  process.stderr.write('usage: node scripts/wasmrun.mjs TOOL.wasm ARGS…\n');
  process.exit(2);
}

class Exit {
  constructor(code) { this.code = code; }
}

const bin = s => Buffer.from(s, 'latin1');
const text = b => Buffer.from(b).toString('latin1');
let ok = 0;

function readAll(fd) {
  const parts = [];
  const buf = Buffer.alloc(1 << 16);
  for (;;) {
    let n;
    try {
      n = fs.readSync(fd, buf, 0, buf.length, null);
    } catch (e) {
      if (e.code === 'EAGAIN') continue;
      if (e.code === 'EOF') break;
      throw e;
    }
    if (n === 0) break;
    parts.push(Buffer.from(buf.subarray(0, n)));
  }
  return Buffer.concat(parts);
}

function write(fd, s) {
  const b = bin(s);
  for (let at = 0; at < b.length;) {
    try {
      at += fs.writeSync(fd, b, at);
    } catch (e) {
      if (e.code !== 'EAGAIN') throw e;
    }
  }
}

const tsys = {
  ok: () => ok,
  read(path) {
    try {
      const b = fs.readFileSync(bin(path));
      ok = 1;
      return text(b);
    } catch {
      ok = 0;
      return '';
    }
  },
  write(path, data) {
    try {
      fs.writeFileSync(bin(path), bin(data));
      return 1;
    } catch {
      return 0;
    }
  },
  // 0 none, 1 a file, 2 a directory, 3 something else
  kind(path) {
    try {
      const st = fs.statSync(bin(path));
      return st.isFile() ? 1 : st.isDirectory() ? 2 : 3;
    } catch {
      return 0;
    }
  },
  mkdir(path) {
    try {
      fs.mkdirSync(bin(path));
      return 1;
    } catch {
      return 0;
    }
  },
  // remove(3): a file or an empty directory
  remove(path) {
    const p = bin(path);
    try {
      if (fs.lstatSync(p).isDirectory()) fs.rmdirSync(p);
      else fs.unlinkSync(p);
      return 1;
    } catch {
      return 0;
    }
  },
  // the names in a directory, each ended by a NUL
  list(path) {
    try {
      return fs.readdirSync(bin(path), { encoding: 'buffer' }).map(n => text(n) + '\0').join('');
    } catch {
      return '';
    }
  },
  getenv(name) {
    const v = process.env[bin(name).toString()];
    ok = v === undefined ? 0 : 1;
    return v === undefined ? '' : text(Buffer.from(v));
  },
  getcwd: () => text(Buffer.from(process.cwd())),
  out: (s, err) => write(err ? 2 : 1, s),
  exit(code) {
    throw new Exit(code);
  },
  isLink(path) {
    try {
      return fs.lstatSync(bin(path)).isSymbolicLink() ? 1 : 0;
    } catch {
      return 0;
    }
  },
  readStdin: () => text(readAll(0)),
  // a shell command's stdout, whole; ok 0 when it could not be run or did not exit 0 (its stderr the tool's)
  runOut(cmd) {
    try {
      const b = execSync(bin(cmd).toString(), { stdio: ['inherit', 'pipe', 'inherit'], maxBuffer: 1 << 30 });
      ok = 1;
      return text(b);
    } catch (e) {
      ok = 0;
      return e.stdout ? text(e.stdout) : '';
    }
  },
};

// chk logwait's events: the files and directories watched, and the process waited on, by a worker of their own
// (fs.watch's events, the process's end as the system's own waiter tells it), which wakes `wait` through the shared
// word: bit 1 something changed, bit 2 the process ended; word 2 is that waiter's pid. Each watch is set before the call that asks for it returns.
const word = new Int32Array(new SharedArrayBuffer(12));
let watcher = null;
const files = [];
function ask(msg) {
  Atomics.store(word, 1, 0);
  watcher.postMessage(msg);
  Atomics.wait(word, 1, 0);
  return Atomics.load(word, 1) === 1 ? 1 : 0;
}
const chkev = {
  init() {
    if (process.platform !== 'darwin' && process.platform !== 'linux') return 0;
    watcher = new Worker(new URL('./wasmrun-watch.mjs', import.meta.url), { workerData: word });
    watcher.unref();
    return 1;
  },
  open(k, path) {
    try {
      files[k] = { fd: fs.openSync(bin(path), 'r'), path: bin(path).toString() };
      return 1;
    } catch {
      return 0;
    }
  },
  read: k => (files[k] === undefined ? '' : text(readAll(files[k].fd))),
  file: k => ask({ kind: 'file', path: files[k].path }),
  dir: path => ask({ kind: 'dir', path: bin(path).toString() }),
  // the process's end watched; 0 when it is gone already
  pid(pid) {
    try {
      process.kill(pid, 0);
    } catch (e) {
      if (e.code === 'ESRCH') return 0;
    }
    return ask({ kind: 'pid', pid });
  },
  // until an event or ms: 1 when the process ended
  wait(ms) {
    if (Atomics.load(word, 0) === 0) Atomics.wait(word, 0, 0, ms);
    return Atomics.exchange(word, 0, 0) & 2 ? 1 : 0;
  },
};

// The core's env, as moonrun gives it: strings made and read a character at a
// time through handles, a string array ended by "ffi_end_of_/string_array".
const handles = new Map();
let next = 1;
function handle(v) {
  handles.set(next, v);
  return next++;
}
const END = 'ffi_end_of_/string_array';
const fsUnstable = {
  begin_create_string: () => handle({ s: '' }),
  string_append_char: (h, c) => {
    handles.get(h).s += String.fromCharCode(c);
  },
  finish_create_string: h => {
    const { s } = handles.get(h);
    handles.delete(h);
    return s;
  },
  begin_read_string: s => handle({ s: Array.from(s), i: 0 }),
  string_read_char: h => {
    const r = handles.get(h);
    return r.i < r.s.length ? r.s[r.i++].codePointAt(0) : -1;
  },
  finish_read_string: h => {
    handles.delete(h);
  },
  begin_read_string_array: a => handle({ a, i: 0 }),
  string_array_read_string: h => {
    const r = handles.get(h);
    return r.i < r.a.length ? r.a[r.i++] : END;
  },
  finish_read_string_array: h => {
    handles.delete(h);
  },
  args_get: () => [file, ...args],
  current_dir: () => process.cwd(),
  get_env_var: k => process.env[k] ?? '',
  get_env_var_exists: k => (k in process.env ? 1 : 0),
  get_env_vars: () => Object.entries(process.env).flat(),
  set_env_var: (k, v) => {
    process.env[k] = v;
  },
  unset_env_var: k => {
    delete process.env[k];
  },
};

let printed = '';
const imports = {
  tsys,
  chkev,
  __moonbit_fs_unstable: fsUnstable,
  __moonbit_sys_unstable: {
    exit(code) {
      throw new Exit(code);
    },
  },
  __moonbit_time_unstable: { now: () => BigInt(Date.now()) },
  // println's, a UTF-16 unit at a time: a line written whole
  spectest: {
    print_char(c) {
      if (c === 10) {
        write(1, text(Buffer.from(printed + '\n')));
        printed = '';
      } else printed += String.fromCharCode(c);
    },
  },
};

const module = await WebAssembly.compile(fs.readFileSync(file), { builtins: ['js-string'], importedStringConstants: '_' });
for (const i of WebAssembly.Module.imports(module)) {
  if (i.module === '_' || i.module.startsWith('wasm:')) continue;
  if (imports[i.module]?.[i.name] === undefined) {
    process.stderr.write(`wasmrun: ${file} asks for ${i.module}.${i.name}, which this host has not\n`);
    process.exit(2);
  }
}
let code = 0;
try {
  const instance = await WebAssembly.instantiate(module, imports);
  instance.exports._start?.();
} catch (e) {
  if (e instanceof Exit) code = e.code;
  else {
    process.stderr.write(`${e?.stack ?? e}\n`);
    code = 1;
  }
}
if (printed) write(1, text(Buffer.from(printed)));
// (the process's waiter, which outlives this one otherwise)
if (Atomics.load(word, 2) > 0) try { process.kill(Atomics.load(word, 2)); } catch {}
process.exit(code);
