// What this station shares with the other stations of its workspace, and what it uses of theirs
// (docs/station-share.md). A profile or a skill is shared from the station that has it (its host); still.fail cloud only
// lists which station hosts what and which may use it (cloud.json `shares`), and everything else goes between the
// stations over the station transport (`share.*`, jobs/remote.ts hands them here):
//
// - a key profile and a skill: each station that may use it keeps a copy (config.json, <data>/share/<id>/), fetched
//   again whenever the host raises its version; the host being offline changes nothing for them.
// - a subscription: only its host keeps the login and renews it (a refresh token is spent when used, so two renewing
//   would sign each other out). The others borrow a short-lived access token for each process they start; with the host
//   offline they cannot.
// - edits to a skill made where it is copied go to its host, which keeps one order of them; one made on an older copy
//   is kept beside the skill as SKILL.conflict-<station>.md.
// - a subscription moves to another station only from its host, while it is up: it stops renewing, hands the login
//   over, says so to the cloud, and forgets its own copy.
//
// Config: a host's shared profile has `share: {id}`; a profile copied here has `share: {id, borrowed: true}` (made and
// removed only here). Shared skills are config.json `sharedSkills: {name: id}`. <data>/share/state.json keeps the
// versions and hashes this station last made or fetched.
import { createHash, randomBytes } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, readlinkSync, renameSync, rmSync, symlinkSync, unlinkSync, watch, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import type { Clock } from "effect";
import type { Env, MachineToken } from "../agents/machine-logins.ts";
import { codexAuthFile } from "../agents/machine-logins.ts";
import { signedPost } from "../cloud/signed.ts";
import type { StationKey } from "../cloud/key.ts";
import type { Cloud, Share } from "../cloud/state.ts";
import type { ConfigFile } from "../ops/config.ts";
import { Fibers } from "../ops/fibers.ts";
import { writePrivate } from "../ops/files.ts";
import { log } from "../ops/log.ts";

type Json = any;

/// What a skill may hold to be shared (sent whole in one request of the station transport, which takes 1 MB).
const MAX_SKILL_BYTES = 512 * 1024;
const MAX_SKILL_FILES = 200;
/// A host lends a Codex token it has for at least this long; one closer to its end is renewed first (when it can be).
const CODEX_LEND_MS = 24 * 3600_000;
const CODEX_MIN_MS = 3600_000;
/// Edits to a skill are taken once they have settled this long.
const SETTLE_MS = 2000;
/// What could not be done because another station did not answer is tried again this often (only while there is).
const RETRY_MS = 60_000;
const CODEX_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const CODEX_TOKEN_URL = "https://auth.openai.com/oauth/token";

export type ShareRole = "host" | "user";
/// What the overview says of a shared profile or skill.
export type ShareView = { id: string; role: ShareRole; host: string; allow: string[] | null; reachable: boolean | null };

export type SharingDeps = {
  data: string;
  config: ConfigFile;
  cloud: Cloud;
  key: StationKey;
  /// A request to another station of the workspace (the station transport).
  ask: (station: string, request: Json) => Promise<Json>;
  /// The agents' home (its skills/ directory is where shared skills are linked).
  agentHome: () => string;
  /// The station's environment (the machine's own logins are found in it).
  env: Env;
  /// A Claude profile's current access token, renewed when about to run out (the accounts module's).
  claudeToken: (profile: Json) => Promise<MachineToken>;
  /// Whether a Codex app-server runs on a profile here now (its login must not be renewed under it).
  codexRunning: (profileId: string) => boolean;
  /// A profile's check and allowance as this station has them (for the stations borrowing it).
  status: (profileId: string) => { check: Json; quota: Json };
  /// Something the overview shows changed.
  changed: () => void;
  /// A host that had not answered answers again: what is borrowed from it is checked again.
  recheck?: () => void;
  clock?: Clock.Clock;
  /// Tests: where still.fail cloud is asked (signedPost by default).
  post?: (path: string, tag: string, body: Json) => Promise<Json>;
  /// Tests: Codex's token endpoint.
  codexTokenUrl?: string;
};

type State = {
  hosted: Record<string, { version: number; hash: string }>;
  borrowed: Record<string, { version: number; hash: string; kind: "profile" | "skill"; name: string; pending?: boolean }>;
};

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const hashOf = (v: unknown) => createHash("sha256").update(typeof v === "string" ? v : JSON.stringify(v)).digest("hex");
const newId = () => `sh-${randomBytes(10).toString("hex")}`;
const keyed = (kind: unknown) => kind === "opencode-go" || kind === "anthropic-api" || kind === "api-provider";

/// A profile as another station gets it: what it is, its key when it has one, never where its files are or a login.
function portable(p: Json): Json {
  const out: Json = {};
  for (const k of ["name", "runtime", "access", "env", "model", "models", "backgroundOnMessage", "fast"]) if (p[k] !== undefined) out[k] = structuredClone(p[k]);
  if (isObject(out.access) && !keyed(out.access.kind)) delete out.access.key;
  return out;
}

/// A skill's files, relative paths to their bytes; refused past the limits (or with links in it).
function readSkill(dir: string): Record<string, Buffer> {
  const files: Record<string, Buffer> = {};
  let bytes = 0;
  const walk = (at: string) => {
    for (const name of readdirSync(at)) {
      const path = join(at, name);
      const meta = lstatSync(path);
      if (meta.isSymbolicLink()) continue;
      if (meta.isDirectory()) walk(path);
      else if (meta.isFile()) {
        // A conflict kept beside the skill is the host's to show, not part of what is shared.
        if (/^SKILL\.conflict-/.test(name)) continue;
        bytes += meta.size;
        if (bytes > MAX_SKILL_BYTES || Object.keys(files).length >= MAX_SKILL_FILES) throw new Error("the skill is too large to share (512 KB, 200 files at most)");
        files[relative(dir, path).split(sep).join("/")] = readFileSync(path);
      }
    }
  };
  walk(dir);
  return files;
}

const skillHash = (files: Record<string, Buffer>) =>
  hashOf(Object.keys(files).sort().map((k) => `${k}\0${createHash("sha256").update(files[k]!).digest("hex")}`).join("\n"));

/// A relative path that stays inside the skill.
const safePath = (p: string) => p !== "" && !p.startsWith("/") && !p.split("/").some((s) => s === ".." || s === "." || s === "");

function writeSkill(dir: string, files: Record<string, string>) {
  const temp = `${dir}.tmp-${randomBytes(4).toString("hex")}`;
  rmSync(temp, { recursive: true, force: true });
  for (const [path, data] of Object.entries(files)) {
    if (!safePath(path)) throw new Error(`bad path in a shared skill: ${path}`);
    mkdirSync(dirname(join(temp, path)), { recursive: true });
    writeFileSync(join(temp, path), Buffer.from(data, "base64"));
  }
  mkdirSync(temp, { recursive: true });
  rmSync(dir, { recursive: true, force: true });
  renameSync(temp, dir);
}

const encodeFiles = (files: Record<string, Buffer>) => Object.fromEntries(Object.entries(files).map(([k, v]) => [k, v.toString("base64")]));

/// When a JWT runs out (ms), if it says.
function jwtExpiry(token: unknown): number | null {
  if (typeof token !== "string") return null;
  try {
    const claims = JSON.parse(Buffer.from(token.split(".")[1] ?? "", "base64url").toString("utf8"));
    return typeof claims?.exp === "number" ? claims.exp * 1000 : null;
  } catch {
    return null;
  }
}

export class Sharing {
  private deps: SharingDeps;
  private time: Fibers;
  private watchers = new Map<string, { close(): void }>();
  private settle = new Map<string, () => void>();
  private retry: (() => void) | null = null;
  private stops: (() => void)[] = [];
  /// Hosts that did not answer lately, and when (for the overview's `reachable`).
  private unreachable = new Map<string, number>();
  /// Shares this station is handing to another right now: not lent meanwhile.
  private moving = new Set<string>();
  private reconciling: Promise<void> | null = null;
  private again = false;

  constructor(deps: SharingDeps) {
    this.deps = deps;
    this.time = new Fibers("share", deps.clock);
  }

  private get root() {
    return join(this.deps.data, "share");
  }

  private me(): string | null {
    return this.deps.cloud.state?.station ?? null;
  }

  /// The workspace's shares as the cloud said last.
  shares(): Share[] {
    return this.deps.cloud.state?.shares ?? [];
  }

  private share(id: string): Share | undefined {
    return this.shares().find((s) => s.id === id);
  }

  private mayUse(share: Share, station: string): boolean {
    return share.allow === null || share.allow.includes(station);
  }

  // ── state ──

  private readState(): State {
    try {
      const s = JSON.parse(readFileSync(join(this.root, "state.json"), "utf8"));
      return { hosted: isObject(s.hosted) ? s.hosted : {}, borrowed: isObject(s.borrowed) ? s.borrowed : {} };
    } catch {
      return { hosted: {}, borrowed: {} };
    }
  }

  private writeState(s: State) {
    mkdirSync(this.root, { recursive: true });
    writePrivate(join(this.root, "state.json"), JSON.stringify(s, null, 2));
  }

  private profiles(): Json[] {
    const raw = this.deps.config.raw();
    return Array.isArray(raw?.profiles) ? raw.profiles : [];
  }

  private home(p: Json): string {
    const home = String(p.home ?? `homes/${p.id}`);
    return home.startsWith("/") ? home : join(this.deps.data, home);
  }

  private skillsDir(): string {
    return join(this.deps.agentHome(), "skills");
  }

  // ── running ──

  start() {
    this.stops.push(this.deps.cloud.listen(() => this.reconcile()));
    this.stops.push(this.deps.config.listen(() => this.reconcile()));
    this.reconcile();
  }

  async close() {
    for (const stop of this.stops.splice(0)) stop();
    for (const w of this.watchers.values()) w.close();
    this.watchers.clear();
    await this.time.close();
  }

  /// Brings what is here in line with what the cloud says and what is configured: one at a time, again if asked meanwhile.
  reconcile(): Promise<void> {
    if (this.reconciling) {
      this.again = true;
      return this.reconciling;
    }
    this.reconciling = (async () => {
      do {
        this.again = false;
        try {
          await this.reconcileOnce();
        } catch (e) {
          log.warn("share", "bringing shares in line failed", { error: (e as Error).message });
        }
      } while (this.again);
    })().finally(() => (this.reconciling = null));
    return this.reconciling;
  }

  private async reconcileOnce() {
    const me = this.me();
    const cloud = this.deps.cloud;
    if (me === null || cloud.removed()) return;
    const current = cloud.sharesCurrent;
    const state = this.readState();
    let pending = false;
    const silent = new Set(this.unreachable.keys());

    // What this station hosts: its version raised when what it is changed, said to the cloud.
    for (const p of this.profiles()) {
      if (!isObject(p.share) || p.share.borrowed === true || typeof p.share.id !== "string") continue;
      const id = p.share.id as string;
      const listed = this.share(id);
      if (current && listed && listed.host !== me) continue;
      const hash = hashOf(portable(p));
      const was = state.hosted[id];
      if (was?.hash === hash && listed) continue;
      const version = (was?.version ?? listed?.version ?? 0) + (was?.hash === hash ? 0 : 1);
      try {
        await this.put({ op: "put", id, kind: "profile", name: String(p.name ?? p.id), allow: listed?.allow ?? null, version });
        state.hosted[id] = { version, hash };
      } catch (e) {
        pending = true;
        log.warn("share", "telling still.fail cloud of a shared profile failed", { id, error: (e as Error).message });
      }
    }
    const sharedSkills: Record<string, string> = isObject(this.deps.config.raw()?.sharedSkills) ? this.deps.config.raw().sharedSkills : {};
    for (const [name, id] of Object.entries(sharedSkills)) {
      const listed = this.share(id);
      if (current && listed && listed.host !== me) continue;
      const dir = join(this.skillsDir(), name);
      this.watchHosted(name, dir);
      let files: Record<string, Buffer>;
      try {
        files = readSkill(dir);
      } catch (e) {
        log.warn("share", "a shared skill could not be read", { name, error: (e as Error).message });
        continue;
      }
      const hash = skillHash(files);
      const was = state.hosted[id];
      if (was?.hash === hash && listed) continue;
      const version = (was?.version ?? listed?.version ?? 0) + (was?.hash === hash ? 0 : 1);
      try {
        await this.put({ op: "put", id, kind: "skill", name, allow: listed?.allow ?? null, version });
        state.hosted[id] = { version, hash };
      } catch (e) {
        pending = true;
        log.warn("share", "telling still.fail cloud of a shared skill failed", { id, error: (e as Error).message });
      }
    }

    // What others share with this station: copied here (or kept current), and what is no longer for it taken away.
    if (current) {
      const wanted = new Map(this.shares().filter((s) => s.host !== me && this.mayUse(s, me)).map((s) => [s.id, s]));
      for (const share of wanted.values()) {
        const had = state.borrowed[share.id];
        if (had && had.version === share.version && !had.pending) continue;
        try {
          if (had?.pending && share.kind === "skill") await this.sendSkillEdit(share, state);
          const got = await this.deps.ask(share.host, { method: "share.get", id: share.id });
          this.unreachable.delete(share.host);
          if (share.kind === "profile") this.placeProfile(share, got);
          else this.placeSkill(share, got, state);
          state.borrowed[share.id] = { version: Number(got?.version ?? share.version), hash: share.kind === "skill" ? String(got?.hash ?? "") : "", kind: share.kind, name: share.name };
        } catch (e) {
          pending = true;
          this.unreachable.set(share.host, this.time.now());
          log.info("share", "a share could not be fetched from its host", { id: share.id, host: share.host, error: (e as Error).message });
        }
      }
      for (const [id, had] of Object.entries(state.borrowed)) {
        if (wanted.has(id)) continue;
        // Moved here: what was a copy is now this station's own (taken over by `take`).
        if (this.share(id)?.host === me) {
          delete state.borrowed[id];
          continue;
        }
        if (had.kind === "profile") this.removeProfile(id);
        else this.removeSkill(id, had.name);
        delete state.borrowed[id];
      }
      // A share the cloud no longer lists (taken away there) is no longer shared here.
      const listed = new Set(this.shares().map((s) => s.id));
      const orphaned = this.profiles().filter((p) => isObject(p.share) && p.share.borrowed !== true && !listed.has(p.share.id) && state.hosted[p.share.id] !== undefined);
      if (orphaned.length > 0) {
        this.deps.config.update((raw) => {
          for (const p of raw.profiles ?? []) if (orphaned.some((o) => o.id === p.id)) delete p.share;
        });
        for (const p of orphaned) delete state.hosted[p.share.id];
      }
    }
    // Hosts of borrowed subscriptions that did not answer: asked whether they do now.
    for (const host of [...this.unreachable.keys()]) {
      const borrowed = this.profiles().find((p) => this.borrowedSubscription(p) && this.share(p.share.id)?.host === host);
      if (!borrowed) {
        this.unreachable.delete(host);
        continue;
      }
      try {
        await this.deps.ask(host, { method: "share.status", id: borrowed.share.id });
        this.unreachable.delete(host);
      } catch {
        pending = true;
      }
    }
    if ([...silent].some((h) => !this.unreachable.has(h))) this.deps.recheck?.();
    this.writeState(state);
    this.linkBorrowedSkills(state);
    // Hosts that did not answer are asked again later (and borrowed subscriptions checked again when they do).
    if (pending && this.retry === null) {
      this.retry = this.time.after(RETRY_MS, () => {
        this.retry = null;
        void this.reconcile();
      });
    }
    this.deps.changed();
  }

  private async put(body: Json): Promise<Json> {
    const post = this.deps.post ?? ((path: string, tag: string, value: Json) => signedPost(this.deps.cloud, this.deps.key, path, tag, value));
    return post("/v1/stations/shares", "stillfail-station-shares-v1", body);
  }

  // ── copies of others' shares ──

  private placeProfile(share: Share, got: Json) {
    const given = isObject(got?.profile) ? got.profile : null;
    if (!given) throw new Error("the host sent no profile");
    this.deps.config.update((raw) => {
      const list: Json[] = Array.isArray(raw.profiles) ? raw.profiles : [];
      const at = list.findIndex((p) => isObject(p?.share) && p.share.id === share.id);
      // One kept from before (a station that handed it over keeps its id and home: its chats go on with it).
      const id = at >= 0 ? String(list[at].id) : share.id;
      const home = at >= 0 && typeof list[at].home === "string" ? list[at].home : `homes/${share.id}`;
      const made: Json = { ...portable(given), id, home, share: { id: share.id, borrowed: true } };
      if (typeof got.email === "string") made.share.email = got.email;
      if (!isObject(made.env)) made.env = {};
      if (at >= 0) list[at] = made;
      else list.push(made);
      raw.profiles = list;
    });
    const placed = this.profiles().find((p) => isObject(p.share) && p.share.id === share.id);
    if (placed) mkdirSync(this.home(placed), { recursive: true });
  }

  private removeProfile(id: string) {
    this.deps.config.update((raw) => {
      raw.profiles = (Array.isArray(raw.profiles) ? raw.profiles : []).filter((p: Json) => !(isObject(p?.share) && p.share.id === id && p.share.borrowed === true));
    });
  }

  private mirror(id: string) {
    return join(this.root, id, "skill");
  }

  private placeSkill(share: Share, got: Json, state: State) {
    if (!isObject(got?.files)) throw new Error("the host sent no files");
    const dir = this.mirror(share.id);
    this.stopWatch(`borrowed:${share.id}`);
    writeSkill(dir, got.files);
    state.borrowed[share.id] = { version: Number(got.version ?? share.version), hash: String(got.hash ?? ""), kind: "skill", name: share.name };
  }

  private removeSkill(id: string, name: string) {
    this.stopWatch(`borrowed:${id}`);
    const link = join(this.skillsDir(), name);
    try {
      if (lstatSync(link).isSymbolicLink() && readlinkSync(link) === this.mirror(id)) unlinkSync(link);
    } catch {}
    rmSync(join(this.root, id), { recursive: true, force: true });
  }

  /// Each copied skill linked into the agents' skills under its name, unless one of this station's own has it; edits to
  /// the copy followed.
  private linkBorrowedSkills(state: State) {
    for (const [id, had] of Object.entries(state.borrowed)) {
      if (had.kind !== "skill") continue;
      const target = this.mirror(id);
      if (!existsSync(target)) continue;
      const link = join(this.skillsDir(), had.name);
      try {
        const meta = lstatSync(link);
        if (!meta.isSymbolicLink() || readlinkSync(link) !== target) continue;
      } catch {
        mkdirSync(this.skillsDir(), { recursive: true });
        symlinkSync(target, link);
      }
      this.watchBorrowed(id, target);
    }
  }

  /// Whether a copied skill shows under its name here (one of this station's own of that name wins).
  private skillLinked(id: string, name: string): boolean {
    try {
      const link = join(this.skillsDir(), name);
      return lstatSync(link).isSymbolicLink() && readlinkSync(link) === this.mirror(id);
    } catch {
      return false;
    }
  }

  // ── edits followed ──

  private stopWatch(key: string) {
    this.watchers.get(key)?.close();
    this.watchers.delete(key);
  }

  private watchDir(key: string, dir: string, then: () => void) {
    if (this.watchers.has(key) || !existsSync(dir)) return;
    try {
      const w = watch(dir, { recursive: true, persistent: false }, () => {
        this.settle.get(key)?.();
        this.settle.set(key, this.time.after(SETTLE_MS, () => (this.settle.delete(key), then())));
      });
      this.watchers.set(key, w);
    } catch (e) {
      log.warn("share", "a shared skill's directory cannot be followed", { dir, error: (e as Error).message });
    }
  }

  private watchHosted(name: string, dir: string) {
    this.watchDir(`hosted:${name}`, dir, () => void this.reconcile());
  }

  private watchBorrowed(id: string, dir: string) {
    this.watchDir(`borrowed:${id}`, dir, () => {
      const state = this.readState();
      const had = state.borrowed[id];
      if (!had) return;
      let files: Record<string, Buffer>;
      try {
        files = readSkill(dir);
      } catch {
        return;
      }
      if (skillHash(files) === had.hash) return;
      had.pending = true;
      this.writeState(state);
      const share = this.share(id);
      if (share) void this.sendSkillEdit(share, state).then(() => this.writeState(state), () => void this.reconcile());
    });
  }

  /// An edit made to a copied skill, sent to its host on the version it was made on.
  private async sendSkillEdit(share: Share, state: State) {
    const had = state.borrowed[share.id];
    if (!had?.pending) return;
    const files = readSkill(this.mirror(share.id));
    const answer = await this.deps.ask(share.host, { method: "share.put", id: share.id, base: had.version, files: encodeFiles(files) });
    had.pending = false;
    had.hash = skillHash(files);
    if (typeof answer?.version === "number") had.version = answer.version;
    if (answer?.conflict === true) had.version = -1; // fetched again: the host's, with the edit beside it
  }

  // ── what others ask (share.*) ──

  /// A request of another station of the workspace (the transport checked it is one).
  async handle(peer: string, request: Json): Promise<Json> {
    const method = String(request?.method ?? "");
    const id = String(request?.id ?? "");
    const me = this.me();
    if (method === "share.take") return this.take(peer, request);
    const share = this.share(id);
    if (!share || share.host !== me) throw new Error("this station does not share that");
    if (!this.mayUse(share, peer)) throw new Error("that share is not for this station");
    if (share.kind === "profile") {
      const p = this.profiles().find((x) => isObject(x.share) && x.share.id === id && x.share.borrowed !== true);
      if (!p) throw new Error("this station does not share that");
      if (method === "share.get") {
        const state = this.readState();
        const email = p.access?.kind === "subscription" ? this.emailOf(p) : null;
        return { version: state.hosted[id]?.version ?? share.version, profile: portable(p), email };
      }
      if (method === "share.lend") {
        if (this.moving.has(id)) throw new Error("the login is being moved to another station");
        return this.lend(p);
      }
      if (method === "share.status") return this.deps.status(p.id);
    } else {
      const name = Object.entries(this.sharedSkills()).find(([, v]) => v === id)?.[0];
      if (!name) throw new Error("this station does not share that");
      const dir = join(this.skillsDir(), name);
      if (method === "share.get") {
        const files = readSkill(dir);
        return { version: this.readState().hosted[id]?.version ?? share.version, hash: skillHash(files), files: encodeFiles(files) };
      }
      if (method === "share.put") return this.takeEdit(peer, id, name, dir, request);
    }
    throw new Error(`unknown share request ${method}`);
  }

  private sharedSkills(): Record<string, string> {
    const s = this.deps.config.raw()?.sharedSkills;
    return isObject(s) ? (s as Record<string, string>) : {};
  }

  private emailOf(p: Json): string | null {
    if (typeof p.share?.email === "string") return p.share.email;
    const home = this.home(p);
    if (p.runtime === "codex") {
      try {
        const auth = JSON.parse(readFileSync(join(home, "auth.json"), "utf8"));
        const claims = JSON.parse(Buffer.from(String(auth?.tokens?.id_token ?? "").split(".")[1] ?? "", "base64url").toString("utf8"));
        const email = claims?.email ?? claims?.["https://api.openai.com/profile"]?.email;
        return typeof email === "string" ? email : null;
      } catch {
        return null;
      }
    }
    for (const file of [join(home, ".claude.json"), join(home, "claude.json")]) {
      try {
        const email = JSON.parse(readFileSync(file, "utf8"))?.oauthAccount?.emailAddress;
        if (typeof email === "string") return email;
      } catch {}
    }
    return null;
  }

  /// An edit from a station that copies a skill: taken when made on the current version; else kept beside it.
  private takeEdit(peer: string, id: string, name: string, dir: string, request: Json): Json {
    const state = this.readState();
    const version = state.hosted[id]?.version ?? 0;
    const files: Record<string, string> = isObject(request.files) ? request.files : {};
    let size = 0;
    for (const [path, data] of Object.entries(files)) {
      if (!safePath(path) || typeof data !== "string") throw new Error("bad file in a skill edit");
      size += Buffer.byteLength(data, "base64");
    }
    if (size > MAX_SKILL_BYTES) throw new Error("the skill is too large to share");
    let conflict = false;
    if (request.base === version) {
      writeSkill(dir, files);
    } else {
      conflict = true;
      const skill = files["SKILL.md"];
      if (typeof skill === "string") writeFileSync(join(dir, `SKILL.conflict-${peer.slice(0, 12)}.md`), Buffer.from(skill, "base64"));
    }
    const now = readSkill(dir);
    const next = version + 1;
    state.hosted[id] = { version: next, hash: skillHash(now) };
    this.writeState(state);
    log.info("share", conflict ? "a skill edit on an older copy kept beside it" : "a skill edit taken", { name, from: peer });
    void this.put({ op: "put", id, kind: "skill", name, allow: this.share(id)?.allow ?? null, version: next }).catch((e) =>
      log.warn("share", "telling still.fail cloud of a skill's new version failed", { id, error: (e as Error).message }),
    );
    return { version: next, conflict };
  }

  /// A short-lived access token of a shared subscription, renewed here when needed.
  private async lend(p: Json): Promise<Json> {
    if (p.access?.kind !== "subscription") throw new Error("only a subscription is lent");
    if (p.runtime === "claude") {
      const t = await this.deps.claudeToken(p);
      return { runtime: "claude", token: t.token, expiresAt: t.expiresAt };
    }
    const file = p.machine === true ? codexAuthFile(this.deps.env) : join(this.home(p), "auth.json");
    let auth = JSON.parse(readFileSync(file, "utf8"));
    let expiresAt = jwtExpiry(auth?.tokens?.access_token) ?? 0;
    if (expiresAt - this.time.now() < CODEX_LEND_MS && !this.deps.codexRunning(p.id)) {
      try {
        auth = await this.renewCodex(file, auth);
        expiresAt = jwtExpiry(auth?.tokens?.access_token) ?? 0;
      } catch (e) {
        log.warn("share", "renewing a shared Codex login failed", { profile: p.id, error: (e as Error).message });
      }
    }
    if (expiresAt - this.time.now() < CODEX_MIN_MS) throw new Error("the Codex login here runs out soon and cannot be renewed now");
    const tokens = auth.tokens ?? {};
    return { runtime: "codex", tokens: { id_token: tokens.id_token, access_token: tokens.access_token, account_id: tokens.account_id }, expiresAt };
  }

  /// Codex's own renewal of its ChatGPT login, done here while no Codex runs on it (it would hold the old refresh token).
  private async renewCodex(file: string, auth: Json): Promise<Json> {
    const refresh = auth?.tokens?.refresh_token;
    if (typeof refresh !== "string" || refresh === "") throw new Error("no refresh token");
    const response = await fetch(this.deps.codexTokenUrl ?? CODEX_TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ client_id: CODEX_CLIENT_ID, grant_type: "refresh_token", refresh_token: refresh, scope: "openid profile email" }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`the token endpoint answered ${response.status}`);
    const got = await response.json();
    const next = structuredClone(auth);
    next.tokens = { ...next.tokens };
    for (const k of ["id_token", "access_token", "refresh_token"]) if (typeof got?.[k] === "string") next.tokens[k] = got[k];
    next.last_refresh = new Date(this.time.now()).toISOString();
    writePrivate(file, JSON.stringify(next, null, 2));
    return next;
  }

  // ── borrowing (the agents' drivers) ──

  /// Whether a profile is a copy of another station's subscription (its login borrowed for each process).
  borrowedSubscription(profile: Json): boolean {
    return isObject(profile?.share) && profile.share.borrowed === true && profile.access?.kind === "subscription";
  }

  private hostOf(profile: Json): string {
    const share = this.share(String(profile.share?.id ?? ""));
    if (!share) throw new Error("this shared profile is no longer shared");
    return share.host;
  }

  /// A borrowed Claude subscription's token, from its host.
  async lendClaude(profile: Json): Promise<MachineToken> {
    const host = this.hostOf(profile);
    try {
      const got = await this.deps.ask(host, { method: "share.lend", id: profile.share.id });
      this.unreachable.delete(host);
      if (typeof got?.token !== "string") throw new Error("the host lent no token");
      return { token: got.token, expiresAt: Number(got.expiresAt ?? 0) };
    } catch (e) {
      this.unreachable.set(host, this.time.now());
      this.deps.changed();
      throw new Error(`the station this subscription is signed in on did not lend it: ${(e as Error).message}`);
    }
  }

  /// A borrowed Codex subscription: its home's auth.json written with the host's current tokens (no refresh token, so
  /// Codex never renews it here); when they run out.
  async lendCodex(profile: Json): Promise<number> {
    const host = this.hostOf(profile);
    let got: Json;
    try {
      got = await this.deps.ask(host, { method: "share.lend", id: profile.share.id });
      this.unreachable.delete(host);
    } catch (e) {
      this.unreachable.set(host, this.time.now());
      this.deps.changed();
      throw new Error(`the station this subscription is signed in on did not lend it: ${(e as Error).message}`);
    }
    const auth = {
      auth_mode: "chatgpt",
      OPENAI_API_KEY: null,
      tokens: { ...got.tokens, refresh_token: "lent-by-another-station" },
      last_refresh: new Date(this.time.now()).toISOString(),
    };
    const home = this.home(profile);
    mkdirSync(home, { recursive: true });
    writePrivate(join(home, "auth.json"), JSON.stringify(auth, null, 2));
    return Number(got.expiresAt ?? 0);
  }

  /// A borrowed profile's check and allowance, as its host has them.
  async status(profile: Json): Promise<{ check: Json; quota: Json }> {
    const host = this.hostOf(profile);
    try {
      const got = await this.deps.ask(host, { method: "share.status", id: profile.share.id });
      this.unreachable.delete(host);
      return { check: got?.check ?? null, quota: got?.quota ?? null };
    } catch (e) {
      this.unreachable.set(host, this.time.now());
      throw e;
    }
  }

  // ── what the pages ask (this station hosting) ──

  /// A profile shared, its stations changed, or no longer shared.
  async shareProfile(profileId: string, on: boolean, allow: string[] | null) {
    const p = this.profiles().find((x) => x.id === profileId);
    if (!p) throw new Error(`unknown profile ${profileId}`);
    if (isObject(p.share) && p.share.borrowed === true) throw new Error("this profile is another station's");
    const had = isObject(p.share) && typeof p.share.id === "string" ? (p.share.id as string) : null;
    if (!on) {
      if (had === null) return;
      await this.put({ op: "delete", id: had });
      this.deps.config.update((raw) => {
        for (const x of raw.profiles ?? []) if (x.id === profileId) delete x.share;
      });
      const state = this.readState();
      delete state.hosted[had];
      this.writeState(state);
      return;
    }
    const id = had ?? newId();
    const state = this.readState();
    const version = (state.hosted[id]?.version ?? 0) + 1;
    await this.put({ op: "put", id, kind: "profile", name: String(p.name ?? p.id), allow, version });
    state.hosted[id] = { version, hash: hashOf(portable(p)) };
    this.writeState(state);
    if (had === null) {
      this.deps.config.update((raw) => {
        for (const x of raw.profiles ?? []) if (x.id === profileId) x.share = { id };
      });
    }
  }

  /// A skill shared, its stations changed, or no longer shared.
  async shareSkill(name: string, on: boolean, allow: string[] | null) {
    const had = this.sharedSkills()[name] ?? null;
    if (!on) {
      if (had === null) return;
      await this.put({ op: "delete", id: had });
      this.deps.config.update((raw) => {
        if (isObject(raw.sharedSkills)) delete raw.sharedSkills[name];
      });
      this.stopWatch(`hosted:${name}`);
      return;
    }
    const dir = join(this.skillsDir(), name);
    if (lstatSync(dir).isSymbolicLink()) throw new Error("this skill is another station's");
    const files = readSkill(dir);
    if (files["SKILL.md"] === undefined) throw new Error("no SKILL.md in that skill");
    const id = had ?? newId();
    const state = this.readState();
    const version = (state.hosted[id]?.version ?? 0) + 1;
    await this.put({ op: "put", id, kind: "skill", name, allow, version });
    state.hosted[id] = { version, hash: skillHash(files) };
    this.writeState(state);
    if (had === null) {
      this.deps.config.update((raw) => {
        raw.sharedSkills = { ...(isObject(raw.sharedSkills) ? raw.sharedSkills : {}), [name]: id };
      });
    }
  }

  /// A shared subscription (or key) moved to another station: it stops lending, hands the profile and its login over,
  /// says so to the cloud, then keeps only a copy (the cloud's word is what decides, if an answer is lost on the way).
  async moveProfile(profileId: string, to: string) {
    const me = this.me();
    const p = this.profiles().find((x) => x.id === profileId);
    if (!p || !isObject(p.share) || p.share.borrowed === true) throw new Error("only a profile this station shares can be moved");
    if (p.machine === true) throw new Error("the machine's own login stays on its machine");
    if (to === me) return;
    const id = p.share.id as string;
    const share = this.share(id);
    if (!share || share.host !== me) throw new Error("this station is not where that profile is");
    const credentials: Record<string, string> = {};
    const home = this.home(p);
    for (const name of [".credentials.json", ".claude.json", "auth.json"]) {
      try {
        const path = join(home, name);
        if (!lstatSync(path).isSymbolicLink()) credentials[name] = readFileSync(path).toString("base64");
      } catch {}
    }
    this.moving.add(id);
    try {
      await this.deps.ask(to, { method: "share.take", id, profile: { ...portable(p), access: p.access }, email: this.emailOf(p), credentials, version: (this.readState().hosted[id]?.version ?? share.version) + 1 });
      await this.put({ op: "move", id, host: to });
    } catch (e) {
      this.moving.delete(id);
      throw e;
    }
    // Ours no more: the login forgotten (the new host renews it now), the profile kept as a copy under the same id.
    for (const name of Object.keys(credentials)) rmSync(join(home, name), { force: true });
    this.deps.config.update((raw) => {
      for (const x of raw.profiles ?? []) if (x.id === profileId) x.share = { id, borrowed: true, ...(typeof p.share.email === "string" ? { email: p.share.email } : {}) };
    });
    const state = this.readState();
    const was = state.hosted[id];
    delete state.hosted[id];
    state.borrowed[id] = { version: (was?.version ?? 0) + 1, hash: "", kind: "profile", name: String(p.name ?? p.id) };
    this.writeState(state);
    this.moving.delete(id);
    log.info("share", "a shared profile moved to another station", { profile: profileId, to });
  }

  /// A profile handed over by the station that had it (only that one may).
  private take(peer: string, request: Json): Json {
    const id = String(request?.id ?? "");
    const share = this.share(id);
    if (!share || share.host !== peer) throw new Error("only the station that has it can hand it over");
    const given = isObject(request.profile) ? request.profile : null;
    if (!given) throw new Error("nothing handed over");
    const existing = this.profiles().find((x) => isObject(x.share) && x.share.id === id);
    const localId = existing?.id ?? id;
    const home = join(this.deps.data, "homes", localId);
    mkdirSync(home, { recursive: true });
    for (const [name, data] of Object.entries(isObject(request.credentials) ? request.credentials : {})) {
      if (![".credentials.json", ".claude.json", "auth.json"].includes(name) || typeof data !== "string") continue;
      const path = join(home, name);
      try {
        if (lstatSync(path).isSymbolicLink()) unlinkSync(path);
      } catch {}
      writePrivate(path, Buffer.from(data, "base64"));
    }
    this.deps.config.update((raw) => {
      const list: Json[] = Array.isArray(raw.profiles) ? raw.profiles : [];
      const made: Json = { ...portable(given), access: given.access, id: localId, home: `homes/${localId}`, share: { id } };
      if (!isObject(made.env)) made.env = {};
      const at = list.findIndex((x) => x.id === localId);
      if (at >= 0) list[at] = made;
      else list.push(made);
      raw.profiles = list;
    });
    const state = this.readState();
    delete state.borrowed[id];
    state.hosted[id] = { version: Number(request.version ?? share.version + 1), hash: hashOf(portable(given)) };
    this.writeState(state);
    log.info("share", "a shared profile handed over to this station", { id, from: peer });
    return { taken: true };
  }

  // ── the overview ──

  /// What the overview says of a profile's sharing (null: not shared).
  profileView(p: Json): ShareView | null {
    if (!isObject(p?.share) || typeof p.share.id !== "string") return null;
    const share = this.share(p.share.id);
    const me = this.me() ?? "";
    if (!share) return p.share.borrowed === true ? null : { id: p.share.id, role: "host", host: me, allow: null, reachable: null };
    const role: ShareRole = share.host === me ? "host" : "user";
    return { id: share.id, role, host: share.host, allow: share.allow, reachable: role === "user" ? !this.unreachable.has(share.host) : null };
  }

  /// What the memory page says of a skill's sharing (null: not shared): by its name in the agents' skills.
  skillView(name: string): ShareView | null {
    const me = this.me() ?? "";
    const hosted = this.sharedSkills()[name];
    if (hosted) {
      const share = this.share(hosted);
      return { id: hosted, role: "host", host: me, allow: share?.allow ?? null, reachable: null };
    }
    for (const [id, had] of Object.entries(this.readState().borrowed)) {
      if (had.kind !== "skill" || had.name !== name || !this.skillLinked(id, name)) continue;
      const share = this.share(id);
      if (share) return { id, role: "user", host: share.host, allow: share.allow, reachable: !this.unreachable.has(share.host) };
    }
    return null;
  }

  /// Skills others share with this station that one of its own hides (same name).
  hiddenSkills(): { id: string; name: string; host: string }[] {
    return Object.entries(this.readState().borrowed).flatMap(([id, had]) => {
      const share = this.share(id);
      return had.kind === "skill" && share && !this.skillLinked(id, had.name) ? [{ id, name: had.name, host: share.host }] : [];
    });
  }

  /// Whether a share this station uses has a host that did not answer lately.
  hostUnreachable(id: string): boolean {
    const share = this.share(id);
    return share !== undefined && this.unreachable.has(share.host);
  }
}

export const sharedSkillConflicts = (dir: string): string[] => {
  try {
    return readdirSync(dir).filter((n) => /^SKILL\.conflict-.*\.md$/.test(n));
  } catch {
    return [];
  }
};
