// A command another station of the workspace sends to run here with a secret one of its chats holds a grant for
// (`secret_run` with a station), or whose output it takes as a secret to keep: the half of vault/secrets.ts that needs
// no vault, so a rig (rig/main.ts), which keeps none, runs them too. The secret comes with each command over the
// station transport and is in no file here; the command runs in the directory its session's tasks share on this
// machine (jobs/remote.ts `work`), answered at once and ended by asking that station back (`vault.done`).
import { mkdirSync } from "node:fs";
import { log } from "../ops/log.ts";
import type { Json } from "../store/store.ts";
import { hold } from "../updates/holds.ts";
import type { Mode } from "./crypto.ts";
import { type Held, valueOf } from "./keeper.ts";
import { MODES } from "./plain.ts";
import type { Proxy } from "./proxy.ts";
import { capture, runWith } from "./run.ts";

/// A command run with a grant is stopped after this long, unless it asks for less (at most an hour).
export const RUN_MS = 10 * 60_000;
/// A command printing a secret to keep is stopped after this long.
export const CAPTURE_MS = 2 * 60_000;

/// `dir`/`under`, made if need be.
function joinUnder(dir: string, under: string): string {
  const at = under === "" ? dir : `${dir}/${under}`;
  mkdirSync(at, { recursive: true });
  return at;
}

/// The station's environment, without what would let a command act as the station or its agents' accounts.
export const baseEnv = (): Record<string, string> =>
  Object.fromEntries(Object.entries(process.env).filter((e): e is [string, string] => e[1] !== undefined && !/^(STILLFAIL_|ANTHROPIC_|CLAUDE_|OPENAI_|CODEX_)/.test(e[0])));

export type IncomingDeps = {
  proxy: Proxy;
  /// The station's time, in milliseconds.
  now: () => number;
  /// A request to another station of the workspace (the station transport, mesh/bus.ts).
  ask?: (station: string, request: Json) => Promise<Json>;
  /// The directory a source session's tasks share here (jobs/remote.ts `work`), made and noted as used.
  workOf?: (workspace: string, peer: string, session: string) => string;
};

export class Incoming {
  readonly #d: IncomingDeps;
  /// The commands running here for other stations, by their id: whose, and whether its station took its grant back.
  readonly #incoming = new Map<string, { peer: string; revoked: boolean }>();

  constructor(deps: IncomingDeps) {
    this.#d = deps;
  }

  /// `vault.capabilities`, `vault.revoke`, `vault.run`, `vault.capture` of station `peer`, asked in workspace `ws`.
  async heard(peer: string, ws: string, request: Json): Promise<Json> {
    const r = (request ?? {}) as Record<string, unknown>;
    const method = typeof r.method === "string" ? r.method : "";
    const id = typeof r.id === "string" ? r.id : "";
    if (method === "vault.capabilities") return { timeouts: true };
    if (method === "vault.revoke") {
      const incoming = this.#incoming.get(id);
      if (!incoming || incoming.peer !== peer) throw new Error("no such command from that station");
      incoming.revoked = true;
      return { ok: true };
    }
    if (method !== "vault.run" && method !== "vault.capture") throw new Error(`unknown method ${method}`);
    const session = typeof r.session === "string" ? r.session : "";
    const command = typeof r.command === "string" ? r.command : "";
    const under = typeof r.under === "string" ? r.under : "";
    const timeoutMs = Number.isSafeInteger(r.timeoutMs) ? Math.min(Math.max(1, r.timeoutMs as number), 3600_000) : RUN_MS;
    if (!/^x_[0-9A-Z]{26}$/.test(id) || session === "" || session.length > 256 || command.trim() === "") throw new Error("id, session and command are required");
    if (under.startsWith("/") || under.split(/[\\/]/).includes("..")) throw new Error("under is a path inside the session's directory");
    if (!this.#d.workOf || !this.#d.ask) throw new Error("this station runs no commands for others");
    const ask = this.#d.ask;
    const cwd = joinUnder(this.#d.workOf(ws, peer, session), under);
    const tell = (result: Json) =>
      ask(peer, { method: "vault.done", workspace: ws, id, result }).catch((e) => log.warn("vault", "a command's end not told to its station", { error: (e as Error).message }));
    // The station does not update itself meanwhile: the proxy or ssh-agent the command uses is this process's.
    const letGo = hold();
    if (method === "vault.capture") {
      void capture(command, cwd, baseEnv(), Math.min(timeoutMs, CAPTURE_MS))
        .then((got) => tell(got as unknown as Json), (e) => tell({ code: null, signal: null, out: "", err: `could not run it: ${(e as Error).message}`, timedOut: false, tooLong: false }))
        .finally(letGo);
      return { started: true };
    }
    const mode = MODES.includes(r.mode as Mode) ? (r.mode as Mode) : null;
    const secret = r.secret as { kind?: unknown; name?: unknown; fields?: unknown } | null;
    const hosts = Array.isArray(r.hosts) ? r.hosts.filter((h): h is string => typeof h === "string") : [];
    const env = typeof r.env === "string" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(r.env) ? r.env : undefined;
    const grant = typeof r.grant === "string" ? r.grant : "";
    if (mode === null || grant === "" || secret === null || typeof secret !== "object" || typeof secret.fields !== "object" || secret.fields === null) {
      letGo();
      throw new Error("mode, grant and secret are required");
    }
    const fields = Object.fromEntries(Object.entries(secret.fields as Record<string, unknown>).filter((e): e is [string, string] => typeof e[1] === "string"));
    const held = { request: { id: grant }, grant: { mode, hosts }, secret: { kind: String(secret.kind ?? ""), name: String(secret.name ?? ""), fields }, uses: 0 } as unknown as Held;
    if (valueOf(held.secret) === null) {
      letGo();
      throw new Error("the secret holds no value");
    }
    let used = false;
    const incoming = { peer, revoked: false };
    this.#incoming.set(id, incoming);
    let expires = typeof r.expires === "number" && Number.isSafeInteger(r.expires) ? r.expires : Infinity;
    let reports: Promise<void> = Promise.resolve();
    const grantTimeout = r.grantTimeout as { kind?: unknown; seconds?: unknown } | undefined;
    const idle = grantTimeout?.kind === "idle" && typeof grantTimeout.seconds === "number" && Number.isSafeInteger(grantTimeout.seconds) && grantTimeout.seconds > 0 && grantTimeout.seconds <= 30 * 86400 ? grantTimeout.seconds : 0;
    void runWith(held, { command, cwd, timeoutMs, ...(env ? { env } : {}) }, this.#d.proxy, baseEnv(), () => {
      used = true;
      reports = reports.then(async () => {
        const answer = await ask(peer, { method: "vault.used", workspace: ws, id }) as { until?: unknown };
        if (idle && typeof answer?.until === "number" && Number.isSafeInteger(answer.until)) expires = answer.until;
      }).catch(() => {});
    }, () => !incoming.revoked && expires > Math.floor(this.#d.now() / 1000))
      .then((ran) => reports.then(() => tell({ ...ran, used } as unknown as Json)), (e) => tell({ code: null, signal: null, output: `could not run it: ${(e as Error).message}`, cut: false, timedOut: false }))
      .finally(() => { this.#incoming.delete(id); letGo(); });
    return { started: true };
  }
}
