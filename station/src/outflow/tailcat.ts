// Data outflow from another machine, through Tailcat (docs/data-outflow.md, 「经 Tailcat 从别的机器申请」): an admin
// turns it on in 数据外流, and the station serves the same requests as on its socket at a loopback port that a
// `tailcat serve` of its own forwards a Tailcat address to. Whoever is given that address (and its port) reaches them
// from anywhere, without an account or an open port; a connection to the port counts only when it is that tailcat's
// (the station asks the system which process the other end is), so a program of this machine cannot come in by it.
// Asking and reading are as on the socket: an admin answers, the program reads with its token. The address stays the
// same across restarts (a key of the station's own, `<data>/tailcat/outflow.private.json`); turning it off stops it.
import { type ChildProcess, execFile, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import type { Identity } from "./grants.ts";
import type { Identify, OutflowServer } from "./server.ts";

/// The tailcat the station gets when the machine has none (Tailcat's own releases; macOS's, which Tailcat does not
/// publish, Homebrew's bottle of the same release), each by its SHA-256.
export const TAILCAT_VERSION = "0.7.0";
const BUILDS: Record<string, { url: string; sha256: string; inner: string; headers?: Record<string, string> }> = {
  "macos-arm64": {
    url: "https://ghcr.io/v2/homebrew/core/tailcat/blobs/sha256:6b9a79a9c847a94c7ac4544ef8b975db39fcc5db94dc9285b9a15ae24e52e6d4",
    sha256: "6b9a79a9c847a94c7ac4544ef8b975db39fcc5db94dc9285b9a15ae24e52e6d4",
    inner: `tailcat/${TAILCAT_VERSION}/bin/tailcat`,
    // ghcr's anonymous token, as Homebrew sends it.
    headers: { authorization: "Bearer QQ==" },
  },
  "linux-x64": release("linux_amd64.tar.gz", "23c0b1887a5ec422f0d18a9c52b4f5357815febdaae738a1eb54036d10bd9ee6", "tailcat"),
  "linux-arm64": release("linux_arm64.tar.gz", "bbb1ab50f24f00effe1e1fd86d0501803fb80793a90785a2a16ff3428f03d8ef", "tailcat"),
  "linux-arm": release("linux_armv7.tar.gz", "cad3994b1f336b67e8a3a5273a9cecb44331d14d57eb32bfe7d0919adeab22b7", "tailcat"),
  "windows-x64": release("windows_amd64.zip", "f04cac07e3bf6c700b0b543df0d3315a3b312cd5a05ee76714e1cc848e9b2dff", "tailcat.exe"),
  "windows-arm64": release("windows_arm64.zip", "1c2d081375ade2365402f9fcf611e89dbb2c5c5ee06936aaff2b205dbe427578", "tailcat.exe"),
};
function release(file: string, sha256: string, inner: string) {
  return { url: `https://github.com/tailscale/tailcat/releases/download/v${TAILCAT_VERSION}/tailcat_${TAILCAT_VERSION}_${file}`, sha256, inner };
}

/// The loopback port tried first; the next ones when it is taken.
export const TAILCAT_PORT = 7480;
const PORTS_TRIED = 10;
/// How long a tailcat that ended is given before it is started again.
const AGAIN_MS = 10_000;

/// Who comes in through the link: not a program the station knows, only one given the address.
export const VIA_TAILCAT: Identity = { path: "tailcat", valid: false, teamId: null, identifier: null, signer: null, app: "Tailcat", sha256: null, via: "tailcat" };

/// The link as 数据外流 shows it to an admin: whether it is on, how it is (`starting`: getting tailcat, its key or its
/// address; `failed`: why in `error`), and, running, the address and port to give the program on the other machine.
export type TailcatView = { on: boolean; state: "off" | "starting" | "running" | "failed"; address: string | null; port: number | null; error: string | null };

export type TailcatOptions = {
  data: string;
  server: OutflowServer;
  /// Told whenever the view changed.
  changed: () => void;
  /// Which processes hold the other end of a loopback connection from `port` (platform.tcpPortPids).
  holders?: (port: number) => Promise<number[]>;
  /// The tailcat command to use, instead of finding or getting one (tests).
  command?: string;
};

export class TailcatLink {
  readonly #o: TailcatOptions;
  readonly #dir: string;
  #on: boolean;
  #state: TailcatView["state"] = "off";
  #address: string | null = null;
  #port: number | null = null;
  #error: string | null = null;
  #child: ChildProcess | null = null;
  #closePort: (() => Promise<void>) | null = null;
  #again: (() => void) | null = null;
  #closed = false;
  /// Bumped by each start and stop: a start overtaken by another leaves what it made alone.
  #run = 0;

  constructor(options: TailcatOptions) {
    this.#o = options;
    this.#dir = join(options.data, "tailcat");
    this.#on = readOn(join(options.data, "outflow-tailcat.json"));
  }

  view(): TailcatView {
    return { on: this.#on, state: this.#state, address: this.#state === "running" ? this.#address : null, port: this.#state === "running" ? this.#port : null, error: this.#error };
  }

  /// Started once the process before this one is gone, when an admin left it on: until then it holds the port, and a
  /// link started beside it would move to the next one, away from the line the admin gave out.
  start(): void {
    if (this.#on && !this.#closed && this.#state === "off") void this.#begin();
  }

  /// Turned on or off by an admin; kept for the station's next start.
  async set(on: boolean): Promise<void> {
    if (on === this.#on && (on ? this.#state !== "failed" : this.#state === "off")) return;
    this.#on = on;
    const file = join(this.#o.data, "outflow-tailcat.json");
    writeFileSync(`${file}.tmp`, JSON.stringify({ on }), { mode: 0o600 });
    renameSync(`${file}.tmp`, file);
    if (on) await this.#begin();
    else await this.#end("off");
  }

  async close(): Promise<void> {
    this.#closed = true;
    await this.#end("off");
  }

  /// Whether a connection to the port is the link's tailcat's: anything else on this machine is turned away.
  readonly identify: Identify = async (socket) => {
    const child = this.#child?.pid;
    const port = socket.remotePort;
    if (child === undefined || port === undefined) return null;
    const holders = await (this.#o.holders ?? ((p) => platform.tcpPortPids(p)))(port).catch((): number[] => []);
    return holders.includes(child) ? VIA_TAILCAT : null;
  };

  async #begin(): Promise<void> {
    await this.#end("starting");
    const run = this.#run;
    try {
      const command = this.#o.command ?? (await this.#command());
      if (run !== this.#run) return;
      const key = join(this.#dir, "outflow.private.json");
      mkdirSync(this.#dir, { recursive: true, mode: 0o700 });
      if (!existsSync(key)) await exec(command, ["genkey", "--key", key, "--fixed-region"]);
      if (run !== this.#run) return;
      const { port, close } = await this.#listen();
      if (run !== this.#run) return void close();
      this.#closePort = close;
      this.#port = port;
      this.#serve(command, key, run);
    } catch (e) {
      if (run === this.#run) this.#failed((e as Error).message);
    }
  }

  /// The loopback port, the first free of those tried.
  async #listen(): Promise<{ port: number; close: () => Promise<void> }> {
    let last: Error | null = null;
    for (let port = TAILCAT_PORT; port < TAILCAT_PORT + PORTS_TRIED; port++) {
      try {
        return await this.#o.server.listenTcp(port, this.identify);
      } catch (e) {
        last = e as Error;
      }
    }
    throw new Error(`no free port from ${TAILCAT_PORT}: ${last?.message ?? ""}`);
  }

  /// tailcat serving the port at the key's address; started again a while after it ends, while the link is on.
  #serve(command: string, key: string, run: number) {
    const child = spawn(command, ["--key", key, "--json", "serve", String(this.#port)], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    this.#child = child;
    let out = "";
    let err = "";
    child.stdout!.setEncoding("utf8").on("data", (chunk: string) => {
      out += chunk;
      const line = out.split("\n").find((l) => l.includes("listenAddr"));
      if (line === undefined || this.#state === "running" || run !== this.#run) return;
      try {
        this.#address = String(JSON.parse(line).listenAddr);
        this.#state = "running";
        this.#error = null;
        log.info("outflow", "the tailcat link is up", { port: this.#port });
        this.#o.changed();
      } catch {}
    });
    child.stderr!.setEncoding("utf8").on("data", (chunk: string) => (err = (err + chunk).slice(-2000)));
    child.once("error", (e) => (err = e.message));
    child.once("close", (code) => {
      if (this.#child === child) this.#child = null;
      if (run !== this.#run) return;
      const why = err.trim().split("\n").filter((l) => !l.startsWith("#")).at(-1) ?? `tailcat ended (${code})`;
      log.warn("outflow", "the tailcat link ended", { code, why });
      this.#failed(why);
      this.#again = wall.after(AGAIN_MS, () => {
        if (run === this.#run && this.#on) this.#serve(command, key, run);
      });
    });
  }

  #failed(error: string) {
    this.#state = "failed";
    this.#error = error;
    this.#o.changed();
  }

  /// Everything of a run before stopped: tailcat, its port, a start again waiting.
  async #end(state: "off" | "starting") {
    this.#run++;
    this.#again?.();
    this.#again = null;
    const child = this.#child;
    this.#child = null;
    if (child !== null && child.exitCode === null) child.kill();
    const close = this.#closePort;
    this.#closePort = null;
    await close?.();
    this.#state = state;
    this.#address = null;
    this.#port = null;
    this.#error = null;
    this.#o.changed();
  }

  /// tailcat as the machine has it, or the station's own copy, got the first time.
  async #command(): Promise<string> {
    const found = platform.findCommand("tailcat", process.env);
    if (found !== null) return found.real;
    const build = BUILDS[`${platform.os}-${process.arch}`];
    if (build === undefined) throw new Error(`no tailcat for ${platform.os}-${process.arch}: install it (https://github.com/tailscale/tailcat)`);
    const bin = join(this.#dir, TAILCAT_VERSION, platform.exe("tailcat"));
    if (existsSync(bin)) return bin;
    mkdirSync(this.#dir, { recursive: true, mode: 0o700 });
    const got = await fetch(build.url, { headers: build.headers ?? {} });
    if (!got.ok) throw new Error(`tailcat could not be downloaded (${got.status})`);
    const bytes = Buffer.from(await got.arrayBuffer());
    if (createHash("sha256").update(bytes).digest("hex") !== build.sha256) throw new Error("the tailcat downloaded is not the one expected");
    const work = mkdtempSync(join(this.#dir, "get-"));
    try {
      const archive = join(work, "archive");
      writeFileSync(archive, bytes);
      await exec("tar", ["-xf", archive, "-C", work]);
      mkdirSync(join(this.#dir, TAILCAT_VERSION), { recursive: true });
      renameSync(join(work, build.inner), bin);
      chmodSync(bin, 0o755);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
    return bin;
  }
}

function readOn(file: string): boolean {
  try {
    return JSON.parse(readFileSync(file, "utf8"))?.on === true;
  } catch {
    return false;
  }
}

const exec = (command: string, args: string[]) =>
  new Promise<void>((resolve, reject) =>
    execFile(command, args, { timeout: 60_000, windowsHide: true }, (e, _out, err) => (e ? reject(new Error(String(err).trim() || e.message)) : resolve())),
  );
