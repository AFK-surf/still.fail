// Runs a program in a sandbox reached over SSH (station/src/agents/sandbox.ts), as if it ran here: what a runner starts
// in place of the program itself. One SSH exec channel carries everything, as the sandbox's front door forwards no
// ports: the program's stdin, stdout and stderr, its exit, and TCP connections it makes to the station's ports on
// 127.0.0.1 (its tools, a job's notify), which the far side listens for at the same ports in the sandbox.
//
//   node sandbox-bridge.mjs host '<json>'     here: {ssh: [argv…], program, args, cwd, ports: [n…]}; env is this process's.
//                                            A port may be {sandbox, here} to be listened for at another port there.
//                                            `create` (argv): run first, to make a sandbox of a size (l4es `create`).
//   node … -e '<this file>' remote            in the sandbox, started by the host side through ssh
//
// Frames both ways: type (1 byte), stream (4, big-endian), length (4), then the payload.
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";

const T = { init: 0, stdin: 1, stdinEnd: 2, signal: 3, data: 5, close: 6, stdout: 10, stderr: 11, exit: 12, open: 13, error: 14 };
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
  const env = { ...process.env };
  delete env.STILLFAIL_SANDBOX_BRIDGE;
  send(T.init, 0, JSON.stringify({ program: spec.program, args: spec.args, cwd: spec.cwd, env, ports: spec.ports }));
  process.stdin.on("data", (b) => send(T.stdin, 0, b));
  process.stdin.on("end", () => send(T.stdinEnd, 0));
  process.stdin.on("error", () => {});
  for (const name of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(name, () => send(T.signal, 0, name));

  const sockets = new Map();
  let exit = null;
  ssh.stdout.on(
    "data",
    reader((type, stream, payload) => {
      if (type === T.stdout) process.stdout.write(payload);
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
    if (exit === null) {
      process.stderr.write(`sandbox: the connection to the sandbox ended (ssh exited ${code})\n`);
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

/// In the sandbox: runs the program, listens for its connections to the station, and says how it ended.
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
    // it either way. Tried again while this one runs, in case that one ends first.
    server.on("error", () => setTimeout(() => child !== null && server.listen(port, "127.0.0.1"), 2000).unref());
    server.listen(port, "127.0.0.1");
    servers.push(server);
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
  process.stdin.on("end", orphaned);
  process.stdin.on("error", orphaned);
  process.stdout.on("error", orphaned);
  process.stdin.on(
    "data",
    reader((type, stream, payload) => {
      if (type === T.init) {
        const spec = JSON.parse(payload.toString());
        const env = { ...spec.env };
        for (const name of OWN) {
          if (process.env[name] === undefined) delete env[name];
          else env[name] = process.env[name];
        }
        // The station's directories first (a job's bin), then the sandbox's own.
        env.PATH = [spec.env.PATH, process.env.PATH].filter(Boolean).join(":");
        // The station's path to the program, or the sandbox's program of that name where that path is not here.
        const program = spec.program.includes("/") && !existsSync(spec.program) ? basename(spec.program) : spec.program;
        if (!existsSync(spec.cwd)) {
          out(T.error, 0, `${spec.cwd} is not in the sandbox: the station's data directory must be on storage the sandbox mounts`);
          out(T.exit, 0, JSON.stringify({ code: 127, signal: null }));
          process.exit(0);
        }
        for (const port of spec.ports ?? []) listen(typeof port === "number" ? port : port.sandbox);
        child = spawn(program, spec.args, { cwd: spec.cwd, env, stdio: ["pipe", "pipe", "pipe"], detached: true });
        child.stdout.on("data", (b) => out(T.stdout, 0, b));
        child.stderr.on("data", (b) => out(T.stderr, 0, b));
        child.stdin.on("error", () => {});
        child.on("error", (e) => {
          out(T.error, 0, `${program} did not start: ${e.message}`);
          out(T.exit, 0, JSON.stringify({ code: 127, signal: null }));
          process.exit(0);
        });
        child.on("close", (code, signal) => {
          for (const server of servers) server.close();
          out(T.exit, 0, JSON.stringify({ code, signal }));
          process.stdout.end(() => process.exit(0));
        });
      } else if (type === T.stdin) child?.stdin.write(payload);
      else if (type === T.stdinEnd) child?.stdin.end();
      else if (type === T.signal) end(payload.toString());
      else if (type === T.data) sockets.get(stream)?.write(payload);
      else if (type === T.close) {
        const socket = sockets.get(stream);
        sockets.delete(stream);
        socket?.end();
      }
    }),
  );
}

// `node -e` gives its arguments from argv[1] on, a file from argv[2].
if (process.argv[1] === "remote") remote();
else if (process.argv[2] === "host") host(JSON.parse(process.argv[3]));
else {
  process.stderr.write("usage: sandbox-bridge.mjs host '<json>' | remote\n");
  process.exit(2);
}
