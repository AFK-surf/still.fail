#!/usr/bin/env node
// Waits for an event, not a time (detlint's script-wait), on every platform the scripts run on (macOS, Windows' Git
// Bash, Linux): the file system's own change events (fs.watch), or a command's output as it comes.
//   node scripts/waitfor.mjs [--deadline S] --log FILE --line REGEX   until a line of FILE matches (from its start,
//                                                                    or from byte --from N: what was written after)
//   node scripts/waitfor.mjs [--deadline S] --exists PATH             until PATH is there (a file not empty)
//   node scripts/waitfor.mjs [--deadline S] --run CMD --line REGEX    until a line CMD prints matches (CMD then ended)
//   node scripts/waitfor.mjs [--deadline S] --watch PATH --check CMD  until CMD succeeds, asked at once and each time PATH
//                                                                    (a file, or a directory's files) changes
//   node scripts/waitfor.mjs --tee FILE --line REGEX --mark MARK -- CMD ARG…
//                                       runs CMD (a server: as long as it runs), its output into FILE, and makes MARK
//                                       (the line) once a line matches: what another waitfor's --exists MARK waits for.
//                                       Windows says nothing of a file another process holds open growing (fs.watch
//                                       on a log stays quiet until it is closed): the output read from its pipe there.
// The line found is printed; exit 0. --deadline (s, default 120): how long at most, what a run that hangs is given
// before it fails (not what it is expected to take): exit 2, saying what it waited for. --run's command ended without
// such a line: exit 1. --what TEXT names what is waited for in that message.
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

const all = process.argv.slice(2);
const dd = all.indexOf("--");
const args = dd >= 0 ? all.slice(0, dd) : all;
const cmd = dd >= 0 ? all.slice(dd + 1) : null;
const opt = {};
for (let i = 0; i < args.length; i++) {
  const k = args[i].replace(/^--/, "");
  opt[k] = args[i + 1];
  i++;
}
const deadline = Number(opt.deadline ?? 120);
const what = opt.what ?? (opt.line ? `a line /${opt.line}/ in ${opt.log ?? opt.run}` : `${opt.exists}`);
const re = opt.line ? new RegExp(opt.line) : null;
const done = (code, line) => {
  if (line !== undefined) console.log(line);
  process.exit(code);
};
const ms = deadline * 1000;
const tee = Boolean(opt.tee && cmd && cmd.length);
// (--tee runs as long as its command: no deadline)
if (!tee)
  setTimeout(() => {
    console.error(`waitfor: no ${what} after ${deadline} s`);
    process.exit(2);
  }, ms).unref?.();
const timer = tee ? null : setInterval(() => {}, ms); // (keeps the process alive while it waits on the watchers)

function watchFor(file, check) {
  const dir = path.dirname(path.resolve(file));
  if (check()) return;
  // The file's own events (kqueue on macOS, inotify on Linux): what it is written, as long as it is open elsewhere. The
  // directory's (FSEvents on macOS) say it was made or renamed in, not each write a process holding it open makes: a
  // file made after this started (a log a backgrounded shell's redirection makes a moment later) is watched itself
  // once it is there (on GitHub's macOS runner the relay's "serving on" line, written 7 s later, was never seen).
  let f = null;
  const own = () => {
    if (f) return;
    try {
      f = fs.watch(file, { persistent: true }, () => check());
    } catch {}
  };
  const w = fs.watch(dir, { persistent: true }, () => {
    own();
    if (check()) w.close();
  });
  own();
  if (check()) w.close();
}

if (tee) {
  const out = fs.openSync(opt.tee, "w");
  if (opt.mark) fs.rmSync(opt.mark, { force: true });
  const p = spawn(cmd[0], cmd.slice(1), { shell: process.platform === "win32", stdio: ["ignore", "pipe", "pipe"] });
  let buf = "";
  let marked = !(opt.mark && re);
  const on = (d) => {
    fs.writeSync(out, d);
    if (marked) return;
    buf += d;
    const lines = buf.split(/\r?\n/);
    buf = lines.pop() ?? "";
    for (const l of lines)
      if (re.test(l)) {
        marked = true;
        fs.writeFileSync(opt.mark, l + "\n");
        break;
      }
  };
  p.stdout.on("data", on);
  p.stderr.on("data", on);
  for (const sig of ["SIGTERM", "SIGINT"]) process.on(sig, () => p.kill(sig));
  p.on("exit", (code) => process.exit(code ?? 1));
} else if (opt.log && re) {
  let seen = Number(opt.from ?? 0);
  let rest = "";
  const check = () => {
    let text;
    try {
      text = fs.readFileSync(opt.log, "utf8");
    } catch {
      return false;
    }
    if (Buffer.byteLength(text) < seen) seen = 0, rest = "";
    text = Buffer.from(text).subarray(seen).toString("utf8");
    seen += Buffer.byteLength(text);
    const lines = (rest + text).split(/\r?\n/);
    rest = lines.pop() ?? "";
    for (const l of lines.concat(rest ? [rest] : [])) if (re.test(l)) done(0, l);
    return false;
  };
  watchFor(opt.log, check);
} else if (opt.exists) {
  const check = () => {
    try {
      const st = fs.statSync(opt.exists);
      if (st.isDirectory() || st.size > 0) done(0, opt.exists);
    } catch {}
    return false;
  };
  watchFor(opt.exists, check);
} else if (opt.run && re) {
  const p = spawn(opt.run, { shell: true, stdio: ["ignore", "pipe", "pipe"] });
  let buf = "";
  const on = (d) => {
    buf += d;
    const lines = buf.split(/\r?\n/);
    buf = lines.pop() ?? "";
    for (const l of lines) if (re.test(l)) {
      p.kill();
      done(0, l);
    }
  };
  p.stdout.on("data", on);
  p.stderr.on("data", on);
  p.on("exit", () => {
    if (buf && re.test(buf)) done(0, buf);
    console.error(`waitfor: ${opt.run} ended without ${what}`);
    clearInterval(timer);
    process.exit(1);
  });
} else if (opt.watch && opt.check) {
  const { spawnSync } = await import("node:child_process");
  let asking = false;
  let again = false;
  const ask = () => {
    if (asking) return (again = true);
    asking = true;
    do {
      again = false;
      if (spawnSync(opt.check, { shell: true, stdio: "ignore" }).status === 0) done(0, opt.check);
    } while (again);
    asking = false;
  };
  const target = path.resolve(opt.watch);
  let isDir = false;
  try {
    isDir = fs.statSync(target).isDirectory();
  } catch {}
  ask();
  fs.watch(isDir ? target : path.dirname(target), { persistent: true }, (_, f) => {
    if (isDir || !f || path.resolve(path.dirname(target), String(f)) === target) ask();
  });
} else {
  console.error("usage: waitfor.mjs [--deadline S] (--log FILE --line REGEX | --exists PATH | --run CMD --line REGEX | --watch PATH --check CMD | --tee FILE --line REGEX --mark MARK -- CMD…)");
  process.exit(64);
}
