// Runs a program in a sandbox reached over SSH (station/src/agents/sandbox.ts), as if it ran here: what a runner starts
// in place of the program itself. One SSH exec channel carries everything, as the sandbox's front door forwards no
// ports: the program's stdin, stdout and stderr, its exit, TCP connections it makes to the station's ports on
// 127.0.0.1 (its tools, a job's notify), which the far side listens for at the same ports in the sandbox, and the files
// the station and the program both use. The sandbox shares no file system with the station: what the station gives
// the program (its home's settings and skills, the session's uploads) is copied there before it starts, and what the
// program writes that the station reads (its transcripts, its memory and skills) is copied back as it changes.
//
//   node sandbox-bridge.mjs host '<json>'     here: {ssh: [argv…], program, args, cwd, ports: [n…]}; env is this process's.
//                                            A port may be {sandbox, here} to be listened for at another port there.
//                                            `create` (argv): run first, to make a sandbox of a size (l4es `create`).
//                                            `agent`: a runtime's process; those started before in the sandbox are ended
//                                            first (one runtime per sandbox: a session's, or a profile's shared host).
//                                            `lostFile`: written when the connection is lost (sandbox.ts LOST_EXIT).
//                                            `silentMs`: how long without a frame is lost (SILENT_MS; tests shorten it).
//                                            `root`: {path, persist?}: the station's data directory, made at the same
//                                            path there (a link to `persist`, storage the sandboxes keep, when given).
//                                            `dirs`: directories made there. `sync`: what is copied (below).
//                                            No `program`: only the copying, then it ends (a session's new uploads).
//                                            `gh`: the station's GitHub login lent to the program (`lendGh`).
//   node … -e '<this file>' remote            in the sandbox, started by the host side through ssh
//
// `sync`: [{path, to?, mode, skip?, push?, back?}]: a file or directory here (`path`) and there (`to`, the same path by
// default). `mode` "whole": a file is copied whole when it changed; "append": a file only grows (a transcript), so what
// it gained is copied. `push` (default true): copied there when newer here; `back` (default true): copied here when
// newer there, at the start and as the program changes it. `skip`: names of entries left out, at any depth. A link
// whose target is in the data directory is copied as the link; any other is followed. Newer: by size for "append", by
// modification time (whole seconds) for "whole".
//
// Frames both ways: type (1 byte), stream (4, big-endian), length (4), then the payload. Each side pings the other every
// PING_MS and takes the connection as lost after SILENT_MS without a frame: a connection broken without either end
// being told (the front door does not notice its station gone) ends within that, not when TCP gives up.
//
// Lost after the program started (not its own end): `CONNECTION_LOST` on stderr, exit code `LOST_EXIT`, and `lostFile`
// written; the station starts it again once (sessions/actor.ts, jobs/jobs.ts).
import { spawn, spawnSync } from "node:child_process";
import {
  closeSync, existsSync, ftruncateSync, lstatSync, mkdirSync, openSync, readFileSync, readSync, readdirSync, readlinkSync, realpathSync,
  renameSync, rmSync, statSync, symlinkSync, utimesSync, watch, writeFileSync, writeSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { createConnection, createServer } from "node:net";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const T = {
  init: 0, stdin: 1, stdinEnd: 2, signal: 3, ping: 4, data: 5, close: 6, prepare: 7, put: 8, want: 9, synced: 16,
  stdout: 10, stderr: 11, exit: 12, open: 13, error: 14, started: 15, manifest: 17, file: 18,
};
const PING_MS = 10_000;
const SILENT_MS = 30_000;
/// As agents/sandbox.ts has them.
const CONNECTION_LOST = "sandbox: the connection to the sandbox was lost";
const LOST_EXIT = 75;
/// A file larger is not copied; nor anything more once this much has gone at the start.
const MAX_FILE = 64 * 1024 * 1024;
const MAX_PUSH = 512 * 1024 * 1024;
/// How long changes the program makes are gathered before they are copied back.
const SETTLE_MS = 300;
/// Where the runtime processes the bridge started in this sandbox are kept (their process groups), one a line.
const AGENTS = () => `${process.env.XDG_RUNTIME_DIR || "/tmp"}/stillfail-bridge-agents`;
/// Variables naming certificate files or directories (OpenSSL, Codex, Node, Python, curl).
const CERT_VARS = ["SSL_CERT_FILE", "SSL_CERT_DIR", "CODEX_CA_CERTIFICATE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE"];
/// What the sandbox keeps of its own environment over the station's: who it is, where its home and tools are.
const OWN = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "XDG_RUNTIME_DIR", "SSH_AUTH_SOCK", "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY", "MAIL", "PWD", "OLDPWD", "SHLVL", "_"];

function frame(type, stream, payload = Buffer.alloc(0)) {
  const body = typeof payload === "string" ? Buffer.from(payload) : payload;
  const head = Buffer.alloc(9);
  head.writeUInt8(type, 0);
  head.writeUInt32BE(stream, 1);
  head.writeUInt32BE(body.length, 5);
  return Buffer.concat([head, body]);
}

/// A frame's payload of a JSON header and bytes after it.
const packed = (header, bytes = Buffer.alloc(0)) => {
  const h = Buffer.from(JSON.stringify(header));
  const len = Buffer.alloc(4);
  len.writeUInt32BE(h.length, 0);
  return Buffer.concat([len, h, bytes]);
};
const unpacked = (payload) => {
  const n = payload.readUInt32BE(0);
  return [JSON.parse(payload.subarray(4, 4 + n).toString()), payload.subarray(4 + n)];
};

/// Splits what arrives into frames.
function reader(onFrame) {
  let buffered = Buffer.alloc(0);
  return (chunk) => {
    buffered = buffered.length === 0 ? chunk : Buffer.concat([buffered, chunk]);
    while (buffered.length >= 9) {
      const length = buffered.readUInt32BE(5);
      if (buffered.length < 9 + length) break;
      const type = buffered.readUInt8(0);
      const stream = buffered.readUInt32BE(1);
      const payload = buffered.subarray(9, 9 + length);
      buffered = buffered.subarray(9 + length);
      onFrame(type, stream, payload);
    }
  };
}

// ── files, the same on both sides ──

const seconds = (ms) => Math.floor(ms / 1000);
const within = (dir, path) => {
  const r = relative(dir, path);
  return r === "" || (!r.startsWith("..") && !isAbsolute(r));
};

/// What a sync entry has here: path (absolute, on this side) → [kind, size, mtime ms, link?]; kind "f" a file, "l" a
/// link kept as one. `root` says which links are kept.
function scan(entry, base, root) {
  const out = new Map();
  // Links are told by where they lead, the data directory too (on macOS /tmp is /private/tmp).
  if (root) {
    try {
      root = realpathSync(root);
    } catch {}
  }
  const skip = new Set(entry.skip ?? []);
  const walk = (path, depth) => {
    let st;
    try {
      st = lstatSync(path);
    } catch {
      return;
    }
    if (st.isSymbolicLink()) {
      const target = readlinkSync(path);
      let real = null;
      try {
        real = realpathSync(path);
      } catch {}
      if (real !== null && root && within(root, real)) return void out.set(path, ["l", 0, 0, target]);
      if (real === null) return;
      try {
        st = statSync(path);
      } catch {
        return;
      }
    }
    if (st.isDirectory()) {
      if (depth > 32) return;
      let names = [];
      try {
        names = readdirSync(path);
      } catch {
        return;
      }
      for (const name of names) if (!skip.has(name)) walk(join(path, name), depth + 1);
    } else if (st.isFile() && st.size <= MAX_FILE) out.set(path, ["f", st.size, st.mtimeMs]);
  };
  walk(base, 0);
  return out;
}

/// Writes a file copied from the other side, through links here (a link to the station's memory stays one), with the
/// other side's time. `offset` (an "append" file): from there, what is beyond dropped.
function place(path, bytes, mtimeMs, offset = null) {
  let target = path;
  try {
    target = realpathSync(path);
  } catch {
    try {
      target = join(realpathSync(dirname(path)), basename(path));
    } catch {
      mkdirSync(dirname(path), { recursive: true });
    }
  }
  if (offset === null || !existsSync(target)) {
    const tmp = `${target}.sbx-${process.pid}`;
    writeFileSync(tmp, bytes);
    renameSync(tmp, target);
  } else {
    const fd = openSync(target, "r+");
    try {
      ftruncateSync(fd, offset);
      writeSync(fd, bytes, 0, bytes.length, offset);
    } finally {
      closeSync(fd);
    }
  }
  const t = new Date(mtimeMs);
  try {
    utimesSync(target, t, t);
  } catch {}
}

function placeLink(path, target) {
  mkdirSync(dirname(path), { recursive: true });
  try {
    if (lstatSync(path).isSymbolicLink() && readlinkSync(path) === target) return;
    rmSync(path, { recursive: true, force: true });
  } catch {}
  symlinkSync(target, path);
}

/// The station's GitHub login (gh's, on this machine) lent to a program in the sandbox, as its subscriptions' are: its
/// token, read now, as GH_TOKEN, and git's credentials for github.com from gh there (`gh auth git-credential`, through
/// GIT_CONFIG_* so nothing is written there). Nothing when gh here is not signed in, or the program has a token already.
function lendGh(env) {
  if (env.GH_TOKEN || env.GITHUB_TOKEN) return;
  const got = spawnSync("gh", ["auth", "token", "-h", "github.com"], { env, encoding: "utf8", timeout: 10_000 });
  const token = got.status === 0 ? got.stdout.trim() : "";
  if (token === "") return;
  env.GH_TOKEN = token;
  const n = Number(env.GIT_CONFIG_COUNT) || 0;
  env[`GIT_CONFIG_KEY_${n}`] = "credential.https://github.com.helper";
  env[`GIT_CONFIG_VALUE_${n}`] = "!gh auth git-credential";
  env.GIT_CONFIG_COUNT = String(n + 1);
}

/// Here: makes the sandbox when asked to (its size), then stands in for the program.
function host(spec) {
  if (spec.create === undefined) return connect(spec);
  const made = spawn(spec.create[0], spec.create.slice(1), { stdio: ["ignore", "pipe", "pipe"] });
  let said = "";
  made.stdout.on("data", (b) => (said += b));
  made.stderr.on("data", (b) => (said += b));
  made.on("error", (e) => {
    process.stderr.write(`sandbox: ssh did not start: ${e.message}\n`);
    process.exit(255);
  });
  made.on("close", (code) => {
    // Made now, or there already with this size: on to it.
    if (code === 0) return connect(spec);
    process.stderr.write(`sandbox: the sandbox was not made: ${said.trim()}\n`);
    process.exit(255);
  });
}

/// Starts the far side through ssh and stands in for the program.
function connect(spec) {
  const source = readFileSync(fileURLToPath(import.meta.url), "utf8");
  // The far side's own file, given on its command line: nothing to install in the sandbox.
  const remote = `exec node --input-type=module -e "$(printf %s ${Buffer.from(source).toString("base64")} | base64 -d)" remote`;
  const ssh = spawn(spec.ssh[0], [...spec.ssh.slice(1), remote], { stdio: ["pipe", "pipe", "inherit"] });
  const send = (type, stream, payload) => {
    if (ssh.stdin.writable) ssh.stdin.write(frame(type, stream, payload));
  };
  // ssh gone before it read what was sent: said by its close (below).
  ssh.stdin.on("error", () => {});
  const env = { ...process.env };
  delete env.STILLFAIL_SANDBOX_BRIDGE;
  if (spec.gh && spec.program !== undefined) lendGh(env);
  const silent = spec.silentMs ?? SILENT_MS;
  const sync = (spec.sync ?? []).map((e) => ({ ...e, to: e.to ?? e.path }));
  const root = spec.root?.path ?? null;
  // First the files: what each side has, then what goes either way; the program once both have them.
  // A directory here (or one not made yet) is watched there as one; a single file (one fetched) is not.
  const isDir = (e) => e.dir ?? (!existsSync(e.path) || statSync(e.path).isDirectory());
  send(T.prepare, 0, JSON.stringify({ root: spec.root ?? null, dirs: spec.dirs ?? [], sync: sync.map((e) => ({ path: e.to, mode: e.mode, skip: e.skip, back: e.back, dir: isDir(e) })) }));
  let heard = Date.now();
  setInterval(() => {
    if (Date.now() - heard > silent) ssh.kill("SIGKILL");
    else send(T.ping, 0);
  }, Math.min(PING_MS, silent / 3));
  const run = spec.program !== undefined;
  if (run) {
    process.stdin.on("data", (b) => send(T.stdin, 0, b));
    process.stdin.on("end", () => send(T.stdinEnd, 0));
    process.stdin.on("error", () => {});
    for (const name of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(name, () => send(T.signal, 0, name));
  }

  /// The manifest come: what is newer here goes there, what is newer there is asked for.
  const exchange = (theirs) => {
    let pushed = 0;
    for (const e of sync) {
      const mine = scan(e, e.path, root);
      const there = new Map(Object.entries(theirs[e.to] ?? {}));
      const asked = [];
      const map = (path) => join(e.to, relative(e.path, path));
      const unmap = (path) => join(e.path, relative(e.to, path));
      for (const [path, [kind, size, mtime, link]] of mine) {
        const other = there.get(map(path));
        if (kind === "l") {
          if (e.push !== false && (!other || other[0] !== "l" || other[3] !== link)) send(T.put, 0, packed({ path: map(path), link }));
          continue;
        }
        const newer = !other ? "here" : e.mode === "append" ? (size > other[1] ? "here" : size < other[1] ? "there" : null) : seconds(mtime) > seconds(other[2]) ? "here" : seconds(mtime) < seconds(other[2]) ? "there" : size !== other[1] ? "here" : null;
        if (newer === "here" && e.push !== false) {
          if (pushed + size > MAX_PUSH) {
            process.stderr.write(`sandbox: over ${MAX_PUSH} bytes to copy there; ${path} and what follows left out\n`);
            continue;
          }
          try {
            send(T.put, 0, packed({ path: map(path), mtime }, readFileSync(path)));
            pushed += size;
          } catch {}
        } else if (newer === "there" && e.back !== false) asked.push(map(path));
      }
      if (e.back !== false) for (const [path, v] of there) if (v[0] === "f" && !mine.has(unmap(path))) asked.push(path);
      for (const path of asked) send(T.want, 0, JSON.stringify({ path, have: e.mode === "append" ? (mine.get(unmap(path))?.[1] ?? 0) : 0 }));
    }
    if (run) {
      send(T.init, 0, JSON.stringify({ program: spec.program, args: spec.args, cwd: spec.cwd, env, ports: spec.ports, agent: spec.agent === true, silentMs: silent }));
    } else send(T.synced, 0);
  };
  /// A file copied back: to its place here.
  const receive = (header, bytes) => {
    const e = sync.find((x) => within(x.to, header.path) && x.back !== false);
    if (!e) return;
    const path = join(e.path, relative(e.to, header.path));
    try {
      if (header.link !== undefined) placeLink(path, header.link);
      else place(path, bytes, header.mtime, header.offset ?? null);
    } catch (error) {
      process.stderr.write(`sandbox: ${path} not copied back: ${error.message}\n`);
    }
  };

  const sockets = new Map();
  let exit = null;
  let started = false;
  let synced = false;
  ssh.stdout.on(
    "data",
    reader((type, stream, payload) => {
      heard = Date.now();
      if (type === T.stdout) process.stdout.write(payload);
      else if (type === T.manifest) exchange(JSON.parse(payload.toString()));
      else if (type === T.file) receive(...unpacked(payload));
      else if (type === T.synced) {
        synced = true;
        ssh.stdin.end();
      } else if (type === T.started) started = true;
      else if (type === T.stderr) process.stderr.write(payload);
      else if (type === T.exit) exit = JSON.parse(payload.toString());
      else if (type === T.error) process.stderr.write(`sandbox: ${payload.toString()}\n`);
      else if (type === T.open) {
        const asked = Number(payload.toString());
        const port = spec.ports.map((p) => (typeof p === "number" ? { sandbox: p, here: p } : p)).find((p) => p.sandbox === asked);
        if (port === undefined) return send(T.close, stream);
        const socket = createConnection({ host: "127.0.0.1", port: port.here });
        sockets.set(stream, socket);
        socket.on("data", (b) => send(T.data, stream, b));
        socket.on("close", () => {
          if (sockets.delete(stream)) send(T.close, stream);
        });
        socket.on("error", () => socket.destroy());
      } else if (type === T.data) sockets.get(stream)?.write(payload);
      else if (type === T.close) {
        const socket = sockets.get(stream);
        sockets.delete(stream);
        socket?.end();
      }
    }),
  );
  ssh.on("error", (e) => {
    process.stderr.write(`sandbox: ssh did not start: ${e.message}\n`);
    process.exit(255);
  });
  ssh.on("close", (code) => {
    if (!run) {
      if (synced) process.exit(0);
      process.stderr.write(`sandbox: the files were not copied (ssh exited ${code})\n`);
      process.exit(255);
    }
    if (exit === null && started) {
      process.stderr.write(`${CONNECTION_LOST} (ssh exited ${code})\n`);
      if (spec.lostFile) writeFileSync(spec.lostFile, "");
      process.exit(LOST_EXIT);
    }
    if (exit === null) {
      process.stderr.write(`sandbox: the sandbox could not be reached (ssh exited ${code})\n`);
      process.exit(255);
    }
    const done = () => {
      if (exit.signal) process.kill(process.pid, exit.signal);
      process.exit(exit.code ?? 1);
    };
    // What was written to stdout reaches the runner before this process says it ended.
    if (process.stdout.writableLength > 0) process.stdout.once("drain", done);
    else done();
  });
}

/// In the sandbox: makes the files there as the station has them, runs the program, listens for its connections to the
/// station, copies back what it changes, and says how it ended.
function remote() {
  const out = (type, stream, payload) => process.stdout.write(frame(type, stream, payload));
  const sockets = new Map();
  let next = 1;
  let child = null;
  const servers = [];
  const listen = (port) => {
    const server = createServer((socket) => {
      const stream = next++;
      sockets.set(stream, socket);
      out(T.open, stream, String(port));
      socket.on("data", (b) => out(T.data, stream, b));
      socket.on("close", () => {
        if (sockets.delete(stream)) out(T.close, stream);
      });
      socket.on("error", () => socket.destroy());
    });
    // Another program of the same station in this sandbox may serve the port already: the same station's door behind
    // it either way. Tried again while this one runs (or is about to), in case that one ends first.
    const running = () => child === null || (child.exitCode === null && child.signalCode === null);
    server.on("error", () => setTimeout(() => running() && server.listen(port, "127.0.0.1"), 2000).unref());
    servers.push(server);
    // Listening (or served by that other one) before the program starts: a connection it makes at once found nothing
    // there and was refused (the test of the bridge saw its curl answered by nothing, main 573471e1, 40853552409).
    return new Promise((done) => {
      server.once("listening", done);
      server.once("error", done);
      server.listen(port, "127.0.0.1");
    });
  };
  const end = (signal) => {
    if (child === null || child.exitCode !== null || child.signalCode !== null) return;
    try {
      process.kill(-child.pid, signal);
    } catch {}
  };
  // The host side gone (the station let go, the connection broke): nothing would read what the program says.
  const orphaned = () => {
    end("SIGTERM");
    setTimeout(() => (end("SIGKILL"), process.exit(255)), 5000).unref();
  };
  // Before a program (only copying files, or the station gone while they were): nothing to end.
  process.stdin.on("end", () => (child === null ? process.exit(0) : orphaned()));
  process.stdin.on("error", orphaned);
  process.stdout.on("error", orphaned);
  let heard = Date.now();
  let silent = SILENT_MS;
  const ticking = () =>
    setTimeout(() => {
      if (Date.now() - heard > silent) orphaned();
      else (out(T.ping, 0), ticking());
    }, Math.min(PING_MS, silent / 3)).unref();
  ticking();

  // ── the files ──
  // The station's paths as they are here: the same, but under STILLFAIL_SANDBOX_PREFIX when it is set (the tests'
  // stand-in for a sandbox on the station's own machine).
  const P = process.env.STILLFAIL_SANDBOX_PREFIX ?? "";
  const L = (p) => (P && p.startsWith("/") ? P + p : p);
  const S = (p) => (P && p.startsWith(P) ? p.slice(P.length) : p);
  let sync = null;
  let root = null;
  /// What was last copied either way, by path: [size, mtime s], so a change seen is the program's, not a copy.
  const known = new Map();
  const dirty = new Set();
  const sent = new Map();
  let flushing = null;
  const entryOf = (path) => sync?.find((e) => within(e.path, path) && !(e.skip ?? []).some((s) => relative(e.path, path).split("/").includes(s)));
  /// Sends back what changed of `path`, if it is the program's change.
  const back = (path) => {
    const e = entryOf(path);
    if (!e) return;
    let st;
    try {
      st = lstatSync(path);
    } catch {
      return;
    }
    if (st.isSymbolicLink()) {
      const target = readlinkSync(path);
      let real = null;
      try {
        real = realpathSync(path);
      } catch {}
      if (real !== null && root && within(root, real)) return void out(T.file, 0, packed({ path: S(path), link: S(target) }));
      try {
        st = statSync(path);
      } catch {
        return;
      }
    }
    if (!st.isFile() || st.size > MAX_FILE) return;
    const was = known.get(path);
    if (was && was[0] === st.size && was[1] === seconds(st.mtimeMs)) return;
    if (e.mode === "append") {
      const from = sent.get(path) ?? 0;
      if (st.size === from) return;
      const start = st.size > from ? from : 0;
      const fd = openSync(path, "r");
      const bytes = Buffer.alloc(st.size - start);
      try {
        readSyncAll(fd, bytes, start);
      } finally {
        closeSync(fd);
      }
      sent.set(path, st.size);
      out(T.file, 0, packed({ path: S(path), mtime: st.mtimeMs, offset: start }, bytes));
    } else {
      let bytes;
      try {
        bytes = readFileSync(path);
      } catch {
        return;
      }
      out(T.file, 0, packed({ path: S(path), mtime: st.mtimeMs }, bytes));
    }
    known.set(path, [st.size, seconds(st.mtimeMs)]);
  };
  const flush = () => {
    flushing = null;
    for (const path of [...dirty]) {
      dirty.delete(path);
      back(path);
    }
  };
  const changed = (path) => {
    dirty.add(path);
    flushing ??= setTimeout(flush, SETTLE_MS);
  };
  /// Everything of the sync entries looked at again: what a watch missed.
  const rescan = () => {
    for (const e of sync ?? []) if (e.back !== false) for (const [path] of scan(e, e.path, root)) back(path);
  };
  const watching = [];
  const prepare = (asked) => {
    root = asked.root ? L(asked.root.path) : null;
    if (asked.root) makeRoot({ path: root, ...(asked.root.persist ? { persist: L(asked.root.persist) } : {}) });
    if (root) {
      try {
        root = realpathSync(root);
      } catch {}
    }
    for (const dir of asked.dirs) mkdirSync(L(dir), { recursive: true });
    sync = asked.sync.map((e) => ({ ...e, path: L(e.path) }));
    const manifest = {};
    for (const e of sync) {
      const there = scan(e, e.path, root);
      const listed = {};
      for (const [path, v] of there) {
        listed[S(path)] = v[0] === "l" ? [v[0], v[1], v[2], S(v[3])] : v;
        if (v[0] === "f") {
          known.set(path, [v[1], seconds(v[2])]);
          if (e.mode === "append") sent.set(path, v[1]);
        }
      }
      manifest[S(e.path)] = listed;
      if (e.back !== false && e.dir) {
        mkdirSync(e.path, { recursive: true });
        try {
          const w = watch(e.path, { recursive: true }, (_event, name) => name && changed(join(e.path, name.toString())));
          w.on("error", () => {});
          watching.push(w);
        } catch {}
      }
    }
    out(T.manifest, 0, JSON.stringify(manifest));
  };
  const put = (station, bytes) => {
    const header = { ...station, path: L(station.path), ...(station.link !== undefined ? { link: L(station.link) } : {}) };
    try {
      if (header.link !== undefined) placeLink(header.path, header.link);
      else {
        place(header.path, bytes, header.mtime);
        known.set(header.path, [bytes.length, seconds(header.mtime)]);
        if (entryOf(header.path)?.mode === "append") sent.set(header.path, bytes.length);
      }
    } catch (error) {
      out(T.error, 0, `${header.path} not copied: ${error.message}`);
    }
  };
  const want = (station) => {
    const asked = { ...station, path: L(station.path) };
    const e = entryOf(asked.path);
    if (!e) return;
    if (e.mode === "append") sent.set(asked.path, asked.have);
    known.delete(asked.path);
    back(asked.path);
  };

  process.stdin.on(
    "data",
    reader((type, stream, payload) => {
      heard = Date.now();
      if (type === T.prepare) prepare(JSON.parse(payload.toString()));
      else if (type === T.put) put(...unpacked(payload));
      else if (type === T.want) want(JSON.parse(payload.toString()));
      else if (type === T.synced) out(T.synced, 0);
      else if (type === T.init) void start(JSON.parse(payload.toString()));
      else if (type === T.stdin) (child ? child.stdin.write(payload) : early.push(payload));
      else if (type === T.stdinEnd) (child ? child.stdin.end() : early.push(null));
      else if (type === T.signal) end(payload.toString());
      else if (type === T.data) sockets.get(stream)?.write(payload);
      else if (type === T.close) {
        const socket = sockets.get(stream);
        sockets.delete(stream);
        socket?.end();
      }
    }),
  );
  // Input that comes while an earlier runtime is being ended waits for the program.
  const early = [];
  async function start(spec) {
    silent = spec.silentMs ?? SILENT_MS;
    if (spec.agent) await endEarlier();
    const env = { ...spec.env };
    for (const name of OWN) {
      if (process.env[name] === undefined) delete env[name];
      else env[name] = process.env[name];
    }
    // The station's directories first (a job's bin), then the sandbox's own.
    env.PATH = [spec.env.PATH, process.env.PATH].filter(Boolean).join(":");
    // Certificates named by a path of the station's machine (the Codex driver's SSL_CERT_FILE=/etc/ssl/cert.pem on
    // macOS): one the sandbox does not have would make every TLS connection fail; its own are used.
    for (const name of CERT_VARS) if (env[name] && !existsSync(L(env[name]))) delete env[name];
    // Codex's state database (SQLite) on the sandbox's own disk: the home it is in may be on NFS (`persist`), where
    // Codex cannot open it ("failed to initialize sqlite state runtime"). It goes with the sandbox; the transcripts
    // stay in the home.
    if (env.CODEX_HOME && !env.CODEX_SQLITE_HOME) {
      env.CODEX_SQLITE_HOME = join(process.env.HOME || "/tmp", ".cache", "stillfail", "codex-sqlite", createHash("sha256").update(env.CODEX_HOME).digest("hex").slice(0, 16));
      mkdirSync(env.CODEX_SQLITE_HOME, { recursive: true });
    }
    // The station's path to the program, or the sandbox's program of that name where that path is not here.
    const program = spec.program.includes("/") && !existsSync(spec.program) ? basename(spec.program) : spec.program;
    const cwd = L(spec.cwd);
    if (!existsSync(cwd)) mkdirSync(cwd, { recursive: true });
    // Where it runs as the station names it: the data directory there is a link (into `persist`), and a shell's `pwd`
    // says the path it was given, not where the link leads, when PWD is that path.
    env.PWD = cwd;
    await Promise.all((spec.ports ?? []).map((port) => listen(typeof port === "number" ? port : port.sandbox)));
    child = spawn(program, spec.args, { cwd, env, stdio: ["pipe", "pipe", "pipe"], detached: true });
    if (spec.agent) keep(child.pid);
    out(T.started, 0);
    for (const b of early.splice(0)) b === null ? child.stdin.end() : child.stdin.write(b);
    child.stdout.on("data", (b) => out(T.stdout, 0, b));
    child.stderr.on("data", (b) => out(T.stderr, 0, b));
    child.stdin.on("error", () => {});
    child.on("error", (e) => {
      out(T.error, 0, `${program} did not start: ${e.message}`);
      out(T.exit, 0, JSON.stringify({ code: 127, signal: null }));
      process.exit(0);
    });
    child.on("close", (code, signal) => {
      if (spec.agent) keep(null, child.pid);
      for (const server of servers) server.close();
      // What it changed at the last, before it is said to have ended: the station reads it then.
      if (flushing) clearTimeout(flushing);
      flush();
      rescan();
      for (const w of watching) w.close();
      out(T.exit, 0, JSON.stringify({ code, signal }));
      process.stdout.end(() => process.exit(0));
    });
  }
}

function readSyncAll(fd, buffer, position) {
  let done = 0;
  while (done < buffer.length) {
    const n = readSync(fd, buffer, done, buffer.length - done, position + done);
    if (n === 0) break;
    done += n;
  }
}

/// The station's data directory at its path here, as `root` says: a link to `persist` (storage the sandboxes keep),
/// made with sudo where its parent is not this user's; else a directory of this user's.
function makeRoot(root) {
  const path = resolve(root.path);
  if (existsSync(path)) return;
  const target = root.persist ? resolve(root.persist) : null;
  if (target) mkdirSync(target, { recursive: true });
  try {
    mkdirSync(dirname(path), { recursive: true });
    if (target) symlinkSync(target, path);
    else mkdirSync(path);
  } catch {
    const user = process.env.USER || String(process.getuid());
    const q = (s) => `'${s.replace(/'/g, `'\\''`)}'`;
    const made = target ? `ln -sfn ${q(target)} ${q(path)}` : `mkdir -p ${q(path)}`;
    const r = spawnSync("sudo", ["-n", "sh", "-c", `mkdir -p ${q(dirname(path))} && ${made} && chown -h ${q(user)} ${q(path)}`], { stdio: "ignore" });
    if (r.status !== 0) throw new Error(`${path} could not be made here (sudo)`);
  }
}

const alive = (pgid) => {
  try {
    process.kill(-pgid, 0);
    return true;
  } catch {
    return false;
  }
};

/// The runtime processes started here before, as AGENTS has them, still running.
function kept() {
  try {
    return readFileSync(AGENTS(), "utf8").split("\n").map(Number).filter((n) => n > 0 && alive(n));
  } catch {
    return [];
  }
}

/// Adds `add` to AGENTS and takes `drop` off it.
function keep(add, drop = null) {
  const now = kept().filter((n) => n !== drop);
  if (add !== null) now.push(add);
  writeFileSync(AGENTS(), now.join("\n"));
}

/// Ends every runtime process an earlier bridge started here (with what they started, their groups): one left over
/// from a connection lost would otherwise run beside the new one, on the same transcript.
async function endEarlier() {
  const earlier = kept();
  for (const pgid of earlier) {
    try {
      process.kill(-pgid, "SIGKILL");
    } catch {}
  }
  while (earlier.some(alive)) await new Promise((r) => setTimeout(r, 50));
  keep(null);
}

// `node -e` gives its arguments from argv[1] on, a file from argv[2].
if (process.argv[1] === "remote") remote();
else if (process.argv[2] === "host") host(JSON.parse(process.argv[3]));
else {
  process.stderr.write("usage: sandbox-bridge.mjs host '<json>' | remote\n");
  process.exit(2);
}
