// Renewing a Claude login without sending a prompt: under Claude Code's own locks (its
// current one in the config directory and its legacy one beside it), read again once locked, and saved back where it
// was (the keychain for the machine's login on macOS, else the file), never as a copy. Used for the machine profile's
// and a local subscription profile's token (the Claude driver's `machineToken` and `subscriptionToken`), for checking a
// profile and for reading a subscription's allowance. A login that can no longer be renewed (none to renew it with, or
// its refresh token refused) is over: RenewRefused.
import { execFile, spawn } from "node:child_process";
import { type FileHandle, mkdir, open, readFile, realpath, rmdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { type Env, readClaudeKeychain } from "../agents/machine-logins.ts";
import { takeBackMissing } from "../agents/no-keychain.ts";
import { writePrivateSoon } from "../ops/files.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type Lang, Said, stationLang, tr } from "../ops/i18n.ts";
import { platform } from "../platform/index.ts";
import { profileFetch } from "../ops/agent-env.ts";
import { RenewRefused } from "./console.ts";

type Json = any;

const CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const ITEM = "Claude Code-credentials";
const MARGIN_MS = 5 * 60_000;
const LOCK_WAIT_MS = 40_000;
const LOCK_STALE_MS = 60_000;
const HEARTBEAT_MS = 5_000;

/// The OAuth access token Claude Code keeps in this config directory's file.
export async function claudeToken(home: string): Promise<string | undefined> {
  try {
    const token = JSON.parse(await readFile(join(home, ".credentials.json"), "utf8"))?.claudeAiOauth?.accessToken;
    return typeof token === "string" && token !== "" ? token : undefined;
  } catch {
    return undefined;
  }
}

type Credentials = { data: Json; keychain: boolean };

function access(c: Credentials, lang: Lang): [string, number] {
  const oauth = c.data?.claudeAiOauth;
  const token = oauth?.accessToken;
  if (typeof token !== "string" || token === "") throw new Said(tr(lang, "station.claudeAuth.noCredentials"));
  return [token, Number.isInteger(oauth.expiresAt) ? oauth.expiresAt : 0];
}

function usable(c: Credentials, rejected: string | null, lang: Lang, margin = MARGIN_MS): boolean {
  try {
    const [token, expires] = access(c, lang);
    return rejected !== token && (expires === 0 || expires - wall.now() > margin);
  } catch {
    return false;
  }
}

const homeOf = (env: Env) => platform.home(env) ?? ".";

function run(command: string, args: string[], env: Env, input?: string): Promise<{ ok: boolean; stdout: string } | undefined> {
  return new Promise((resolve) => {
    const r = platform.runnable(command, args, env as NodeJS.ProcessEnv);
    const child = execFile(r.file, r.args, { env: env as NodeJS.ProcessEnv, timeout: 10_000, killSignal: "SIGKILL", windowsVerbatimArguments: r.windowsVerbatimArguments }, (error, stdout) => {
      if (error && (error as NodeJS.ErrnoException).code === "ENOENT") resolve(undefined);
      else resolve({ ok: !error, stdout: String(stdout) });
    });
    if (input !== undefined) child.stdin?.end(input);
    else child.stdin?.end();
  });
}

async function read(env: Env, home: string, machine: boolean, lang: Lang): Promise<Credentials> {
  if (machine && platform.hasKeychain) {
    const found = await readClaudeKeychain(env);
    if (found.kind === "unreadable") throw new Said(tr(lang, "station.claudeAuth.keychainUnreadable"));
    if (found.kind === "found") {
      // An unreadable keychain entry must not be replaced with a stale file's login.
      try {
        return { data: JSON.parse(found.text), keychain: true };
      } catch {
        throw new Said(tr(lang, "station.claudeAuth.keychainUnreadable"));
      }
    }
  }
  const file = join(home, ".credentials.json");
  let text: string;
  try {
    // Off the station's thread: six of these at once held it 1 s on a station short of memory (2026-11-03).
    text = await readFile(file, "utf8");
  } catch (error) {
    if (!machine && (error as NodeJS.ErrnoException).code === "ENOENT" && (await takeBackMissing(home))) {
      try {
        text = await readFile(file, "utf8");
      } catch {
        throw new Said(tr(lang, "station.claudeAuth.noCredentials"));
      }
    } else {
      throw new Said(tr(lang, "station.claudeAuth.noCredentials"));
    }
  }
  try {
    return { data: JSON.parse(text), keychain: false };
  } catch {
    throw new Said(tr(lang, "station.claudeAuth.credentialsUnreadable"));
  }
}

async function save(env: Env, home: string, c: Credentials, lang: Lang) {
  if (!c.keychain) {
    try {
      await writePrivateSoon(join(home, ".credentials.json"), JSON.stringify(c.data));
      return;
    } catch {
      throw new Said(tr(lang, "station.claudeAuth.saveFailed"));
    }
  }
  // Secrets kept off argv, as Claude Code does: `security -i` reads its commands from stdin.
  const who = await run("/usr/bin/id", ["-un"], process.env as Env);
  const account = who?.stdout.trim() ?? "";
  if (!who?.ok || account === "" || /["\\\n\r]/.test(account)) throw new Said(tr(lang, "station.claudeAuth.keychainAccount"));
  const input = `add-generic-password -U -a "${account}" -s "${ITEM}" -X "${Buffer.from(JSON.stringify(c.data)).toString("hex")}"\n`;
  await new Promise<void>((resolve, reject) => {
    const child = spawn("security", ["-i"], { env: env as NodeJS.ProcessEnv, stdio: ["pipe", "ignore", "ignore"] });
    const timer = wall.after(10_000, () => {
      child.kill("SIGKILL");
      reject(new Said(tr(lang, "station.claudeAuth.keychainTimeout")));
    });
    child.on("error", () => {
      timer();
      reject(new Said(tr(lang, "station.claudeAuth.keychainWrite")));
    });
    child.on("exit", (code) => {
      timer();
      if (code === 0) resolve();
      else reject(new Said(tr(lang, "station.claudeAuth.keychainSaveFailed")));
    });
    child.stdin.end(input);
  });
}

/// How long a lend to another station waits for its login's renewal before the token it has is lent (still lasting the
/// usual margin), its renewal going on behind: well under the 30 s the station that asked waits (mesh/peer.ts
/// ANSWER_MS). Claude's here (accounts/index.ts), Codex's in share/index.ts `lend`.
export const LEND_BOUND_MS = 10_000;

/// How long a lend waits for its login's renewal, on whose clock (`after`: `f` once `ms` from now, called off by what it
/// returns).
export type Bound = { ms: number; after: (ms: number, f: () => void) => () => void };

/// A current access token and when it runs out: the one kept, unless it is about to run out or is `rejected` (a 401
/// said so); then renewed. `home`: a profile's config directory; null: the machine's own login (~/.claude, and on
/// macOS the keychain first).
/// `margin`: how long the token given must still last, renewed first when it lasts less (a token handed to a process
/// that cannot renew it is asked for with longer). `bound` (a token lent to another station): the renewal of one that
/// still lasts the usual margin is waited for `bound.ms` at most, on its clock (`after`), then the token it has is given
/// and the renewal goes on behind: the station that asked waits 30 s for its answer (mesh/peer.ts ANSWER_MS), as long as
/// the renewal's call may take, and a renewal that timed out had its token lent 343 ms after it gave up, the chat's turn
/// lost (2026-11-14).
export async function claudeOAuthToken(env: Env, home: string | null, rejected: string | null, endpoint: string, lang: Lang = stationLang(), margin = MARGIN_MS, bound?: Bound): Promise<[string, number]> {
  const machine = home === null;
  const dir = home ?? join(homeOf(env), ".claude");
  const initial = await read(env, dir, machine, lang);
  if (usable(initial, rejected, lang, margin)) return access(initial, lang);
  if (bound !== undefined && margin > MARGIN_MS && usable(initial, rejected, lang)) {
    const given = access(initial, lang);
    const renewed = renewal(dir, given, () => renewLocked(env, dir, machine, rejected, endpoint, lang, margin));
    return new Promise((resolve) => {
      const began = wall.now();
      let over = false;
      const stop = bound.after(bound.ms, () => {
        over = true;
        log.warn("accounts", "a Claude login's renewal outlasted the lend's bound; the token it has was lent, the renewal goes on", {
          login: dir, ms: wall.now() - began, lastsMin: lastsMin(given[1]),
        });
        resolve(given);
      });
      void renewed.then((got) => {
        if (over) return;
        stop();
        resolve(got ?? given);
      });
    });
  }
  const began = wall.now();
  try {
    const got = await renewLocked(env, dir, machine, rejected, endpoint, lang, margin);
    // (its provider refused it for now, the token it has given while it lasts the usual margin: renew's own way)
    if (margin > MARGIN_MS && !usableFor(got, margin)) notRenewed(dir, began, got[1], new Error("its provider did not renew it"));
    return got;
  } catch (error) {
    // Renewed early and it could not be: the token is still given while it lasts the usual margin.
    if (margin > MARGIN_MS) {
      const latest = await read(env, dir, machine, lang);
      if (usable(latest, rejected, lang)) {
        const given = access(latest, lang);
        notRenewed(dir, began, given[1], error);
        return given;
      }
    }
    throw error;
  }
}

/// The renewals of lent logins going on, one a login (what is asked meanwhile waits on the same): what each renewed, or
/// null where it did not (said: notRenewed).
const renewing = new Map<string, Promise<[string, number] | null>>();

function renewal(dir: string, given: [string, number], renew: () => Promise<[string, number]>): Promise<[string, number] | null> {
  const going = renewing.get(dir);
  if (going !== undefined) return going;
  const began = wall.now();
  const done = renew().then(
    (got) => {
      if (got[0] !== given[0]) return got;
      notRenewed(dir, began, given[1], new Error("its provider did not renew it"));
      return null;
    },
    (error) => (notRenewed(dir, began, given[1], error), null),
  ).finally(() => renewing.delete(dir));
  renewing.set(dir, done);
  return done;
}

/// Whether a token given lasts `margin` more (one that says no end does).
const usableFor = ([, expiresAt]: [string, number], margin: number) => expiresAt === 0 || expiresAt - wall.now() > margin;
const lastsMin = (expiresAt: number) => (expiresAt === 0 ? null : Math.round((expiresAt - wall.now()) / 60_000));

/// Once the renewal of a lent login at `dir` going on, if any, is over (tests).
export function renewedBehind(dir: string): Promise<void> {
  return (renewing.get(dir) ?? Promise.resolve()).then(() => {});
}

/// Said, as nothing else says it: which login, how long its renewal took, how long the token given instead still lasts.
function notRenewed(dir: string, began: number, expiresAt: number, error: unknown) {
  log.warn("accounts", "a Claude login was not renewed early; the token it has was given meanwhile", {
    login: dir, ms: wall.now() - began, lastsMin: lastsMin(expiresAt), error: (error as Error).message,
  });
}

async function renewLocked(env: Env, dir: string, machine: boolean, rejected: string | null, endpoint: string, lang: Lang, margin: number): Promise<[string, number]> {
  await mkdir(dir, { recursive: true });
  const current = await RefreshLock.acquire(join(dir, ".oauth_refresh.lock"), lang);
  try {
    const legacy = await RefreshLock.acquire(`${await realpath(dir)}.lock`, lang);
    try {
      return await renew(env, dir, machine, rejected, endpoint, lang, margin);
    } finally {
      await legacy.release();
    }
  } finally {
    await current.release();
  }
}

async function renew(env: Env, home: string, machine: boolean, rejected: string | null, endpoint: string, lang: Lang, margin: number): Promise<[string, number]> {
  const t = (key: string, args?: Record<string, unknown>) => tr(lang, key, args);
  const credentials = await read(env, home, machine, lang);
  if (usable(credentials, rejected, lang, margin)) return access(credentials, lang);
  const oauth = credentials.data?.claudeAiOauth ?? {};
  const refresh = oauth.refreshToken;
  if (typeof refresh !== "string" || refresh === "") throw new RenewRefused(null, t("station.claudeAuth.expiredNoRefresh"));
  const body: Json = { grant_type: "refresh_token", refresh_token: refresh, client_id: typeof oauth.clientId === "string" && oauth.clientId !== "" ? oauth.clientId : CLIENT_ID };
  if (Array.isArray(oauth.scopes)) {
    const scopes = oauth.scopes.filter((s: unknown) => typeof s === "string");
    if (scopes.length > 0) body.scope = scopes.join(" ");
  }
  let response: Response;
  try {
    response = await profileFetch(endpoint, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), redirect: "manual", signal: AbortSignal.timeout(30_000) });
  } catch {
    throw new Said(t("station.claudeAuth.refreshFailed"));
  }
  if (!response.ok) {
    // A CLI version using different locks may have won: its credentials are never erased or rolled back.
    const latest = await read(env, home, machine, lang);
    if (usable(latest, rejected, lang)) return access(latest, lang);
    const status = response.status;
    if (status === 400 || status === 401) throw new RenewRefused(status, t("station.claudeAuth.refreshRefused", { status }));
    throw new Said(t("station.claudeAuth.refreshUnavailable", { status }));
  }
  let answer: Json;
  try {
    answer = await response.json();
  } catch {
    throw new Said(t("station.claudeAuth.badResponse"));
  }
  const token = answer?.access_token;
  if (typeof token !== "string" || token === "") throw new Said(t("station.claudeAuth.noAccessToken"));
  const seconds = answer?.expires_in;
  const sane = (s: unknown): s is number => Number.isInteger(s) && (s as number) > 0 && (s as number) < Number.MAX_SAFE_INTEGER / 2000;
  if (!sane(seconds)) throw new Said(t("station.claudeAuth.noExpiry"));
  const latest = await read(env, home, machine, lang);
  if (latest.keychain !== credentials.keychain || JSON.stringify(latest.data?.claudeAiOauth?.refreshToken) !== JSON.stringify(oauth.refreshToken)) {
    // A simultaneous login wins over this refresh, even of another account.
    if (usable(latest, null, lang)) return access(latest, lang);
    throw new Said(t("station.claudeAuth.changedDuringRefresh"));
  }
  const updated = latest.data.claudeAiOauth;
  updated.accessToken = token;
  updated.expiresAt = wall.now() + seconds * 1000;
  if (typeof answer.refresh_token === "string" && answer.refresh_token !== "") updated.refreshToken = answer.refresh_token;
  if (typeof answer.scope === "string") updated.scopes = answer.scope.split(/\s+/).filter((s: string) => s !== "");
  if (sane(answer.refresh_token_expires_in)) updated.refreshTokenExpiresAt = wall.now() + answer.refresh_token_expires_in * 1000;
  let error: unknown;
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await wall.sleep(100);
    try {
      await save(env, home, latest, lang);
      error = undefined;
      break;
    } catch (e) {
      error = e;
    }
  }
  if (error) throw error;
  return access(latest, lang);
}

/// proper-lockfile-compatible mkdir locks, as Claude Code takes them: a 5 s heartbeat and a 60 s stale threshold. The
/// directory is held open, so an owner from before cannot touch or remove a lock that replaced its own. Off the station's
/// thread, its heartbeat too.
export class RefreshLock {
  private path: string;
  private fd: FileHandle;
  private heartbeat: () => void;

  private constructor(path: string, fd: FileHandle, heartbeat: () => void) {
    this.path = path;
    this.fd = fd;
    this.heartbeat = heartbeat;
  }

  static async acquire(path: string, lang: Lang = stationLang()): Promise<RefreshLock> {
    const deadline = wall.now() + LOCK_WAIT_MS;
    for (;;) {
      try {
        await mkdir(path);
        break;
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw new Said(tr(lang, "station.claudeAuth.lockFailed"));
        let age = 0;
        try {
          age = wall.now() - (await stat(path)).mtimeMs;
        } catch {
          continue;
        }
        if (age > LOCK_STALE_MS) {
          try {
            await rmdir(path);
            continue;
          } catch (e) {
            if ((e as NodeJS.ErrnoException).code === "ENOENT") continue;
          }
        }
        if (wall.now() >= deadline) throw new Said(tr(lang, "station.claudeAuth.refreshLocked"));
        await wall.sleep(100);
      }
    }
    const fd = await open(path, "r");
    const heartbeat = wall.every(HEARTBEAT_MS, () => { // timer: a heartbeat that keeps the lock
      const now = new Date(wall.now());
      fd.utimes(now, now).catch(() => heartbeat());
    });
    return new RefreshLock(path, fd, heartbeat);
  }

  async release(): Promise<void> {
    this.heartbeat();
    try {
      const held = await this.fd.stat();
      const current = await stat(this.path);
      if (held.dev === current.dev && held.ino === current.ino) await rmdir(this.path);
    } catch {}
    await this.fd.close().catch(() => undefined);
  }
}
