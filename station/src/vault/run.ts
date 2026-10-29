// A command run with a grant (secret_run, docs/vault.md 三种用法): through the proxy, with the grant's SSH key in an
// agent, with the secret in its environment, or with a file kept in the vault written out for it. The station runs it, in the session's workspace, and gives back what it
// said with the secret hidden (scrub.ts) and cut to a size an agent reads, and how it ended.
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { endCommand, startCommand } from "../ops/processes.ts";
import { type Held, accountOf, valueOf } from "./keeper.ts";
import { type Proxy, placeholder } from "./proxy.ts";
import { Scrubber, scrub } from "./scrub.ts";
import { parseSshKey, serveAgent } from "./ssh-agent.ts";

/// What of a command's output an agent is given: its start and its end, this much of each.
const HEAD = 4 * 1024;
const TAIL = 28 * 1024;

export type RunAsk = { command: string; cwd: string; env?: string; timeoutMs: number };
export type Ran = { code: number | null; signal: string | null; output: string; cut: boolean; timedOut: boolean };

/// The variable every run has the secret (or its placeholder) in, besides the one the item or the agent names.
export const SECRET_VAR = "STILLFAIL_SECRET";
/// The variable every run of a login's grant has its account in (not secret, so not hidden in the output).
export const ACCOUNT_VAR = "STILLFAIL_USERNAME";

/// Output kept as it comes: all of it while short, then its first HEAD bytes and its last TAIL.
class Kept {
  head = Buffer.alloc(0);
  tail = Buffer.alloc(0);
  cut = false;
  add(b: Buffer) {
    if (this.head.length < HEAD) {
      const take = b.subarray(0, HEAD - this.head.length);
      this.head = Buffer.concat([this.head, take]);
      b = b.subarray(take.length);
    }
    const all = Buffer.concat([this.tail, b]);
    if (all.length > TAIL) this.cut = true;
    this.tail = all.subarray(Math.max(0, all.length - TAIL));
  }
  text(): string {
    return this.cut ? `${this.head.toString("utf8")}\n…(cut)…\n${this.tail.toString("utf8")}` : Buffer.concat([this.head, this.tail]).toString("utf8");
  }
}

/// Runs `ask.command` (by sh -c) with grant `held`; `env`: the environment it starts from; `used` is told each use of
/// the secret (a host the proxy put it in, an SSH signature, the start of a command given it in its environment).
export async function runWith(held: Held, ask: RunAsk, proxy: Proxy, env: Record<string, string>, used: (detail: string) => void): Promise<Ran> {
  const value = valueOf(held.secret)!;
  const id = held.request.id;
  const vars: Record<string, string> = { ...env };
  const account = accountOf(held.secret);
  if (account !== null) vars[ACCOUNT_VAR] = account;
  const ends: (() => void)[] = [];
  try {
    if (held.grant.mode === "proxy") {
      await proxy.start();
      const admitted = proxy.admit({ hosts: held.grant.hosts, placeholder: placeholder(id), value, used: (host) => used(host) });
      ends.push(admitted.end);
      const stand = placeholder(id);
      Object.assign(vars, {
        HTTPS_PROXY: admitted.url, https_proxy: admitted.url, NO_PROXY: "", no_proxy: "",
        NODE_EXTRA_CA_CERTS: proxy.bundle, SSL_CERT_FILE: proxy.bundle, REQUESTS_CA_BUNDLE: proxy.bundle, CURL_CA_BUNDLE: proxy.bundle, GIT_SSL_CAINFO: proxy.bundle,
        [SECRET_VAR]: stand,
      });
      if (ask.env) vars[ask.env] = stand;
    } else if (held.grant.mode === "ssh") {
      const key = parseSshKey(value);
      const dir = mkdtempSync(join(tmpdir(), "sf-ssh-"));
      const sock = join(dir, "agent.sock");
      const server = await serveAgent(sock, key, () => {
        used("ssh signature");
        return true;
      });
      ends.push(() => {
        server.close();
        rmSync(dir, { recursive: true, force: true });
      });
      vars.SSH_AUTH_SOCK = sock;
    } else if (held.grant.mode === "file") {
      // Written where only this user reads it, for this command alone: its path is what the command is given.
      used("file");
      const dir = mkdtempSync(join(tmpdir(), "sf-file-"));
      chmodSync(dir, 0o700);
      ends.push(() => rmSync(dir, { recursive: true, force: true }));
      const path = join(dir, fileName(held.secret.fields.filename));
      const bytes = Buffer.from(value, "base64");
      writeFileSync(path, bytes, { mode: 0o600 });
      vars[SECRET_VAR] = path;
      if (ask.env) vars[ask.env] = path;
      return await spawned(ask, vars, fileHidden(bytes, value));
    } else {
      used("environment");
      vars[SECRET_VAR] = value;
      if (ask.env) vars[ask.env] = value;
    }
    return await spawned(ask, vars, [value]);
  } finally {
    for (const end of ends) end();
  }
}

/// The name a file is written under: its own, where it is a plain name, else "secret".
function fileName(name: string | undefined): string {
  const n = (name ?? "").trim();
  return n === "" || n === "." || n === ".." || /[/\\\0]/.test(n) ? "secret" : n;
}

/// What of a file is hidden in a command's output, as a value in the environment is: its text whole (the command
/// printing it) and its bytes' base64; a file not text, its base64 only.
function fileHidden(bytes: Buffer, b64: string): string[] {
  const text = bytes.toString("utf8");
  return Buffer.from(text, "utf8").equals(bytes) ? [text.replace(/\r?\n$/, ""), b64] : [b64];
}

function spawned(ask: RunAsk, env: Record<string, string>, hidden: string[]): Promise<Ran> {
  return new Promise((resolve) => {
    const child = startCommand("sh", ["-c", ask.command], { cwd: ask.cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    const kept = new Kept();
    const out = new Scrubber(hidden);
    const err = new Scrubber(hidden);
    child.stdout!.on("data", (b: Buffer) => kept.add(out.push(b)));
    child.stderr!.on("data", (b: Buffer) => kept.add(err.push(b)));
    let timedOut = false;
    // The command's time, the machine's: a run left going is stopped, its whole process group.
    const stop = wall.after(ask.timeoutMs, () => {
      timedOut = true;
      endCommand(child, "SIGKILL");
    });
    child.on("error", (e) => {
      stop();
      resolve({ code: null, signal: null, output: `could not start sh: ${e.message}`, cut: false, timedOut: false });
    });
    child.on("close", (code, signal) => {
      stop();
      kept.add(out.end());
      kept.add(err.end());
      resolve({ code, signal, output: kept.text(), cut: kept.cut, timedOut });
    });
  });
}

/// What a command printed, for a secret an agent asks to keep (secret_save): its standard output, kept here (never
/// given to the agent), and its standard error with that output hidden in it.
/// `raw`: its standard output as printed, in base64 (a file kept as its bytes; absent from a station from before files).
export type Captured = { code: number | null; signal: string | null; out: string; raw?: string; err: string; timedOut: boolean; tooLong: boolean };

/// The most of a command's standard output taken as a secret.
const CAPTURE_MAX = 64 * 1024;

/// Runs `command` (by sh -c) in `cwd` and takes what it prints as a secret: none of it is shown, its standard error only
/// with the output hidden in it.
export function capture(command: string, cwd: string, env: Record<string, string>, timeoutMs: number): Promise<Captured> {
  return new Promise((resolve) => {
    const child = startCommand("sh", ["-c", command], { cwd, env, stdio: ["ignore", "pipe", "pipe"] });
    const out: Buffer[] = [];
    let size = 0;
    let tooLong = false;
    const err = new Kept();
    child.stdout!.on("data", (b: Buffer) => {
      size += b.length;
      if (size > CAPTURE_MAX) tooLong = true;
      else out.push(b);
    });
    child.stderr!.on("data", (b: Buffer) => err.add(b));
    let timedOut = false;
    // The command's time, the machine's: one left going is stopped, its whole process group.
    const stop = wall.after(timeoutMs, () => {
      timedOut = true;
      endCommand(child, "SIGKILL");
    });
    child.on("error", (e) => {
      stop();
      resolve({ code: null, signal: null, out: "", err: `could not start sh: ${e.message}`, timedOut: false, tooLong: false });
    });
    child.on("close", (code, signal) => {
      stop();
      const bytes = Buffer.concat(out);
      const value = bytes.toString("utf8").replace(/\r?\n$/, "");
      resolve({ code, signal, out: tooLong ? "" : value, raw: tooLong ? "" : bytes.toString("base64"), err: value === "" ? err.text() : scrub(err.text(), [value]), timedOut, tooLong });
    });
  });
}
