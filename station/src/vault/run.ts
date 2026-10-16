// A command run with a grant (secret_run, docs/vault.md 三种用法): through the proxy, with the grant's SSH key in an
// agent, or with the secret in its environment. The station runs it, in the session's workspace, and gives back what it
// said with the secret hidden (scrub.ts) and cut to a size an agent reads, and how it ended.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { type Held, valueOf } from "./keeper.ts";
import { type Proxy, placeholder } from "./proxy.ts";
import { Scrubber } from "./scrub.ts";
import { parseSshKey, serveAgent } from "./ssh-agent.ts";

/// What of a command's output an agent is given: its start and its end, this much of each.
const HEAD = 4 * 1024;
const TAIL = 28 * 1024;

export type RunAsk = { command: string; cwd: string; env?: string; timeoutMs: number };
export type Ran = { code: number | null; signal: string | null; output: string; cut: boolean; timedOut: boolean };

/// The variable every run has the secret (or its placeholder) in, besides the one the item or the agent names.
export const SECRET_VAR = "STILLFAIL_SECRET";

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

function spawned(ask: RunAsk, env: Record<string, string>, hidden: string[]): Promise<Ran> {
  return new Promise((resolve) => {
    const child = spawn("sh", ["-c", ask.command], { cwd: ask.cwd, env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
    const kept = new Kept();
    const out = new Scrubber(hidden);
    const err = new Scrubber(hidden);
    child.stdout.on("data", (b: Buffer) => kept.add(out.push(b)));
    child.stderr.on("data", (b: Buffer) => kept.add(err.push(b)));
    let timedOut = false;
    // The command's time, the machine's: a run left going is stopped, its whole process group.
    const stop = wall.after(ask.timeoutMs, () => {
      timedOut = true;
      try {
        process.kill(-child.pid!, "SIGKILL");
      } catch {
        child.kill("SIGKILL");
      }
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
