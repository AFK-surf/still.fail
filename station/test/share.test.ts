// Stations sharing profiles and skills (src/share/index.ts, docs/station-share.md): two stations, a cloud that only
// lists who hosts what (as cloud/src/directory.ts `stationShare` keeps it), and the station transport as a direct call.
import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { checkConfig } from "../src/accounts/check.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Sharing } from "../src/share/index.ts";
import { Refused } from "../src/mesh/bus.ts";
import { memory } from "../src/read/memory.ts";
import { Cloud } from "../src/cloud/state.ts";
import { allowedIn } from "../src/sessions/config.ts";

const A = "a".repeat(64);
const B = "b".repeat(64);

/// Each workspace's roster as still.fail cloud gives it (the only thing it says here), and each station's view of them:
/// its home workspace's at the top, the others it is in joined.
class FakeCloud {
  rosters: Record<string, { id: string; name: string }[]> = { w: [{ id: A, name: "studio" }, { id: B, name: "mini" }] };
  /// Each station's home workspace (none said: "w").
  homes: Record<string, string> = {};
  get peers() {
    return this.rosters.w!;
  }
  set peers(peers) {
    this.rosters.w = peers;
  }
  listeners = new Set<() => void>();
  cloudFor(station: string) {
    const cloud = this;
    // On Cloud's own methods (memberships, home…), its state these rosters.
    return Object.defineProperties(Object.create(Cloud.prototype), Object.getOwnPropertyDescriptors({
      peersCurrent: true,
      lock: null,
      get state() {
        const home = cloud.homes[station] ?? "w";
        const joined = Object.entries(cloud.rosters)
          .filter(([ws, peers]) => ws !== home && peers.some((p) => p.id === station))
          .map(([ws, peers]) => ({ workspace: ws, workspace_name: ws, name: "", peers, revocations: [] }));
        return { station, workspace: home, workspace_name: home, peers: cloud.rosters[home] ?? [], revocations: [], joined } as any;
      },
      listen(f: () => void) {
        cloud.listeners.add(f);
        return () => cloud.listeners.delete(f);
      },
    })) as any;
  }
  tell() {
    for (const f of this.listeners) f();
  }
}

type Station = { data: string; config: ConfigFile; sharing: Sharing; lent: string[] };

function station(cloud: FakeCloud, id: string, others: () => Map<string, Station>, profiles: any[] = [], codexRenewRunning: (id: string) => Promise<boolean> = async () => false): Station {
  const data = mkdtempSync(join(tmpdir(), "share-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  mkdirSync(join(data, "agent", "skills"), { recursive: true });
  const lent: string[] = [];
  const sharing = new Sharing({
    data, config, cloud: cloud.cloudFor(id),
    // As the transport takes it (mesh/peer.ts `member`): in the workspace said, or the first of the asker's both are in.
    ask: async (to, workspace, request) => {
      const other = others().get(to);
      if (!other) throw new Error("peer unavailable");
      const both = (ws: string) => [id, to].every((s) => cloud.rosters[ws]?.some((p) => p.id === s));
      const ws = workspace ?? (cloud.cloudFor(id) as Cloud).memberships().find((m) => both(m.workspace))?.workspace;
      if (ws === undefined || !both(ws)) throw new Error("peer is not another station in this workspace");
      return other.sharing.handle(id, request, ws);
    },
    agentHome: () => join(data, "agent"),
    env: {},
    claudeToken: async (p) => (lent.push(p.id), { token: `token-of-${p.id}`, expiresAt: Date.now() + 2 * 3600_000 }),
    codexRenewRunning,
    status: async (pid) => ({ check: { state: "ok", detail: `checked ${pid}`, models: null, checkedAt: 1 }, quota: null }),
    changed: () => {},
  });
  return { data, config, sharing, lent };
}

const settle = async (...stations: Station[]) => {
  for (let i = 0; i < 4; i++) {
    await new Promise((r) => setImmediate(r));
    await Promise.all(stations.map((s) => s.sharing.reconcile()));
  }
};

const KEY = { id: "deepseek", name: "DeepSeek", access: { kind: "api-provider", provider: "deepseek", key: "sk-secret" }, home: "homes/deepseek", env: {} };
const SUB = { id: "max", name: "Claude Max", runtime: "claude", access: { kind: "subscription" }, home: "homes/max", env: {} };

test("a shared key profile is copied to the other station, key and all; stopping takes it away", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [KEY]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  await a.sharing.shareProfile("deepseek", true, null);
  await settle(a, b);
  const id = a.config.raw().profiles[0].share.id;
  assert.match(id, /^sh-[0-9a-f]{20}$/);
  const copy = b.config.raw().profiles.find((p: any) => p.share?.id === id);
  assert.ok(copy, "copied to the other station");
  assert.equal(copy.id, id);
  assert.equal(copy.access.key, "sk-secret");
  assert.equal(copy.share.borrowed, true);
  assert.deepEqual(b.sharing.profileView(copy), { id, role: "user", host: A, allow: null, reachable: true });
  // An edit on its host reaches the copy.
  a.config.update((raw) => (raw.profiles[0].access.key = "sk-new"));
  await settle(a, b);
  assert.equal(b.config.raw().profiles.find((p: any) => p.id === id).access.key, "sk-new");
  // The host offline: the copy stays.
  all.delete(A);
  await settle(b);
  assert.equal(b.config.raw().profiles.length, 1);
  all.set(A, a);
  // The other away when it changed: told once it can be (the host tries again), over the mesh, not through the cloud.
  all.delete(B);
  a.config.update((raw) => (raw.profiles[0].name = "DeepSeek 2"));
  await settle(a);
  assert.equal(b.config.raw().profiles[0].name, "DeepSeek");
  all.set(B, b);
  await settle(a, b);
  assert.equal(b.config.raw().profiles[0].name, "DeepSeek 2");
  await a.sharing.shareProfile("deepseek", false, null);
  await settle(a, b);
  assert.equal(b.config.raw().profiles.length, 0);
  assert.equal(a.config.raw().profiles[0].share, undefined);
});

test("a station left out of a share's stations does not get it, and refuses to be asked for it", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [KEY]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  await a.sharing.shareProfile("deepseek", true, [A]);
  await settle(a, b);
  assert.equal(b.config.raw().profiles.length, 0);
  const id = a.config.raw().profiles[0].share.id;
  await assert.rejects(a.sharing.handle(B, { method: "share.get", id }), /not for this station/);
});

const H = "c".repeat(64);
const O = "d".repeat(64);
const R1 = "e".repeat(64);
const R2 = "f".repeat(64);

/// A station in two workspaces (H: home W1, joined W2) and the others of each: O only in W1, R1 at home in W2, R2 at
/// home in W3 and joined to W2.
function joinedWorkspaces() {
  const cloud = new FakeCloud();
  cloud.rosters = {
    W1: [{ id: H, name: "mini" }, { id: O, name: "studio" }],
    W2: [{ id: H, name: "mini" }, { id: R1, name: "macbook" }, { id: R2, name: "texas" }],
    W3: [{ id: R2, name: "texas" }],
  };
  cloud.homes = { [H]: "W1", [O]: "W1", [R1]: "W2", [R2]: "W3" };
  const all = new Map<string, Station>();
  const h = station(cloud, H, () => all, [KEY]);
  const o = station(cloud, O, () => all);
  const r1 = station(cloud, R1, () => all);
  const r2 = station(cloud, R2, () => all);
  all.set(H, h).set(O, o).set(R1, r1).set(R2, r2);
  return { cloud, h, o, r1, r2, every: [h, o, r1, r2] };
}

test("a profile is shared with the stations of every workspace it serves, whichever is theirs or its home, its copies serving those only; withheld from one, taken back there", async () => {
  const { h, o, r1, r2, every } = joinedWorkspaces();
  await h.sharing.shareProfile("deepseek", true, null);
  await settle(...every);
  const id = h.config.raw().profiles[0].share.id;
  for (const s of [o, r1, r2]) assert.equal(s.config.raw().profiles.find((p: any) => p.share?.id === id)?.access.key, "sk-secret");
  assert.deepEqual(h.sharing.profileView(h.config.raw().profiles[0])!.users!.sort(), [O, R1, R2].sort());
  // Each copy serves the workspaces H shares it in, not the others its station is in: on R2, W2's chats, not its home W3's.
  const copy = (s: Station) => s.config.raw().profiles.find((p: any) => p.share?.id === id);
  assert.deepEqual(copy(r2).share.workspaces, ["W1", "W2"]);
  assert.deepEqual([allowedIn(copy(r2), "W2", "W3"), allowedIn(copy(r2), "W3", "W3"), allowedIn(copy(r2), null, "W3")], [true, false, false]);
  assert.equal(allowedIn(copy(o), null, "W1"), true);
  // Kept from W2: taken from the stations only there, kept where it still serves, there for W1 alone.
  h.config.update((raw) => (raw.profiles[0].withheld = ["W2"]));
  await settle(...every);
  assert.equal(o.config.raw().profiles.length, 1);
  assert.deepEqual(copy(o).share.workspaces, ["W1"]);
  assert.equal(r1.config.raw().profiles.length, 0);
  assert.equal(r2.config.raw().profiles.length, 0);
  assert.deepEqual(h.sharing.profileView(h.config.raw().profiles[0])!.users, [O]);
  await assert.rejects(h.sharing.handle(R1, { method: "share.get", id }, "W2"), /not for this station/);
});

test("a skill is shared with its home workspace's stations only, and linked into the skills of the workspace it came in", async () => {
  const { cloud, h, o, r1, r2, every } = joinedWorkspaces();
  const skill = (s: Station, name: string) => {
    const dir = join(s.data, "agent", "skills", name);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "SKILL.md"), `---\nname: ${name}\ndescription: 项目记忆：${name}\n---\n`);
  };
  // H's own skills are W1's.
  skill(h, "w1-lessons");
  await h.sharing.shareSkill("w1-lessons", true, null);
  // R1's are W2's: H and R2 have them in W2's skills, not their home's.
  skill(r1, "w2-lessons");
  await r1.sharing.shareSkill("w2-lessons", true, null);
  await settle(...every);
  const linked = (s: Station, ...at: string[]) => existsSync(join(s.data, "agent", ...at, "SKILL.md"));
  assert.ok(linked(o, "skills", "w1-lessons"));
  for (const s of [r1, r2]) assert.equal(linked(s, "skills", "w1-lessons") || linked(s, "workspaces", "W2", "skills", "w1-lessons"), false);
  for (const s of [h, r2]) {
    assert.ok(linked(s, "workspaces", "W2", "skills", "w2-lessons"));
    assert.equal(linked(s, "skills", "w2-lessons"), false);
  }
  assert.equal(linked(o, "skills", "w2-lessons"), false);
  // A copy that cannot be linked is its own failure alone: H's W2 skills unmade, O's W1 skill is linked all the same.
  rmSync(join(h.data, "agent", "workspaces", "W2"), { recursive: true });
  writeFileSync(join(h.data, "agent", "workspaces", "W2"), "");
  skill(o, "o-lessons");
  await o.sharing.shareSkill("o-lessons", true, null);
  await settle(...every);
  assert.ok(linked(h, "skills", "o-lessons"));
  rmSync(join(h.data, "agent", "workspaces", "W2"));
  await settle(...every);
  assert.ok(linked(h, "workspaces", "W2", "skills", "w2-lessons"));
  // R1 leaves W2: the copies of its skill go.
  cloud.rosters.W2 = cloud.rosters.W2!.filter((p) => p.id !== R1);
  await settle(h, r2);
  for (const s of [h, r2]) assert.equal(linked(s, "workspaces", "W2", "skills", "w2-lessons"), false);
});

test("a shared subscription: the other borrows tokens from its host, with no login of its own; while the host is away, only the one lent before", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [SUB]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  await a.sharing.shareProfile("max", true, null);
  await settle(a, b);
  const copy = b.config.raw().profiles[0];
  assert.equal(copy.access.kind, "subscription");
  assert.equal(copy.access.key, undefined);
  assert.equal(b.sharing.borrowedSubscription(copy), true);
  assert.equal(existsSync(join(b.data, "homes", copy.id, ".credentials.json")), false);
  const token = await b.sharing.lendClaude(copy);
  assert.equal(token.token, "token-of-max");
  assert.deepEqual(a.lent, ["max"]);
  assert.equal((await b.sharing.status(copy)).check.detail, "checked max");
  all.delete(A);
  assert.equal((await b.sharing.lendClaude(copy)).token, "token-of-max", "the token lent before, while it lasts");
  assert.equal(b.sharing.profileView(copy)!.reachable, false);
  await assert.rejects(b.sharing.lendClaude({ ...copy, id: "never-lent" }), /did not lend/);
});

test("a login wanted before the cloud has said the workspace's stations waits for them; one kept to go on with does not", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [SUB]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  await a.sharing.shareProfile("max", true, null);
  await settle(a, b);
  const copy = b.config.raw().profiles[0];
  const own = (b.sharing as any).deps.cloud;
  await b.sharing.lendClaude(copy);
  a.lent.length = 0;
  own.peersCurrent = false;
  assert.equal((await b.sharing.lendClaude(copy)).token, "token-of-max", "kept: no wait");
  a.lent.length = 0;
  const waited = b.sharing.lendClaude({ ...copy, id: "just-started" });
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.deepEqual(a.lent, [], "its host not asked yet");
  own.peersCurrent = true;
  for (const f of cloud.listeners) f();
  assert.equal((await waited).token, "token-of-max");
  assert.deepEqual(a.lent, ["max"]);
});

test("a borrowed Codex subscription's login is written in its home, the profile as the runtime has it (its home resolved)", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const CODEX = { id: "plus", name: "ChatGPT Plus", runtime: "codex", access: { kind: "subscription" }, home: "homes/plus", env: {} };
  const a = station(cloud, A, () => all, [CODEX]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  const jwt = (claims: object) => ["{}", JSON.stringify(claims), "s"].map((p) => Buffer.from(p).toString("base64url")).join(".");
  mkdirSync(join(a.data, "homes", "plus"), { recursive: true });
  writeFileSync(join(a.data, "homes", "plus", "auth.json"), JSON.stringify({ tokens: { id_token: "id", access_token: jwt({ exp: Math.floor(Date.now() / 1000) + 86400 }), account_id: "acct", refresh_token: "r" } }));
  await a.sharing.shareProfile("plus", true, null);
  await settle(a, b);
  const copy = b.config.raw().profiles[0];
  // As sessions/config.ts gives it to the runtime: its home absolute (C:\… on Windows; a doubled one was made there).
  const home = join(b.data, copy.home);
  await b.sharing.lendCodex({ ...copy, home });
  const auth = JSON.parse(readFileSync(join(home, "auth.json"), "utf8"));
  assert.equal(auth.tokens.account_id, "acct");
  assert.equal(auth.tokens.refresh_token, "lent-by-another-station");
  // The host away: the login lent before is used while it has long enough, not once it runs out soon.
  all.delete(A);
  assert.ok((await b.sharing.lendCodex({ ...copy, home })) > Date.now() + 23 * 3600_000);
  auth.tokens.access_token = jwt({ exp: Math.floor(Date.now() / 1000) + 600 });
  writeFileSync(join(home, "auth.json"), JSON.stringify(auth));
  await assert.rejects(b.sharing.lendCodex({ ...copy, home }), /did not lend/);
});

test("a shared Codex login about to run out while a Codex runs on it here: that Codex is asked to renew it, then it is lent", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const CODEX = { id: "plus", name: "ChatGPT Plus", runtime: "codex", access: { kind: "subscription" }, home: "homes/plus", env: {} };
  const jwt = (claims: object) => ["{}", JSON.stringify(claims), "s"].map((p) => Buffer.from(p).toString("base64url")).join(".");
  const login = (seconds: number) => JSON.stringify({ tokens: { id_token: "id", access_token: jwt({ exp: Math.floor(Date.now() / 1000) + seconds }), account_id: "acct", refresh_token: "r" } });
  const asked: string[] = [];
  let data = "";
  // As the app-server does: renewed, written in the profile's home.
  const a = station(cloud, A, () => all, [CODEX], async (id) => (asked.push(id), writeFileSync(join(data, "homes", "plus", "auth.json"), login(10 * 86400)), true));
  data = a.data;
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  mkdirSync(join(a.data, "homes", "plus"), { recursive: true });
  writeFileSync(join(a.data, "homes", "plus", "auth.json"), login(600));
  await a.sharing.shareProfile("plus", true, null);
  await settle(a, b);
  const copy = b.config.raw().profiles[0];
  assert.ok((await b.sharing.lendCodex({ ...copy, home: join(b.data, copy.home) })) > Date.now() + 9 * 86400_000);
  assert.deepEqual(asked, ["plus"]);
});

test("a running Codex asked to renew a shared login answers with an error after renewing it (a step after the renewal failed): the renewed login is lent", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const CODEX = { id: "plus", name: "ChatGPT Plus", runtime: "codex", access: { kind: "subscription" }, home: "homes/plus", env: {} };
  const jwt = (claims: object) => ["{}", JSON.stringify(claims), "s"].map((p) => Buffer.from(p).toString("base64url")).join(".");
  const login = (seconds: number) => JSON.stringify({ tokens: { id_token: "id", access_token: jwt({ exp: Math.floor(Date.now() / 1000) + seconds }), account_id: "acct", refresh_token: "r" } });
  let data = "";
  // As the real app-server did (account/read: "workspace routing discovery unauthorized"), its new login written first.
  const a = station(cloud, A, () => all, [CODEX], async () => {
    writeFileSync(join(data, "homes", "plus", "auth.json"), login(10 * 86400));
    throw new Error("workspace routing discovery unauthorized (401)");
  });
  data = a.data;
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  mkdirSync(join(a.data, "homes", "plus"), { recursive: true });
  writeFileSync(join(a.data, "homes", "plus", "auth.json"), login(600));
  await a.sharing.shareProfile("plus", true, null);
  await settle(a, b);
  const copy = b.config.raw().profiles[0];
  assert.ok((await b.sharing.lendCodex({ ...copy, home: join(b.data, copy.home) })) > Date.now() + 9 * 86400_000);
});

test("a shared subscription moves to another station: login handed over, the old host keeps a copy", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [SUB]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  mkdirSync(join(a.data, "homes", "max"), { recursive: true });
  writeFileSync(join(a.data, "homes", "max", ".credentials.json"), JSON.stringify({ claudeAiOauth: { accessToken: "x", refreshToken: "r" } }));
  await a.sharing.shareProfile("max", true, null);
  await settle(a, b);
  const id = a.config.raw().profiles[0].share.id;
  await a.sharing.moveProfile("max", B);
  await settle(a, b);
  const taken = b.config.raw().profiles.find((p: any) => p.share?.id === id);
  assert.equal(taken.share.borrowed, undefined);
  assert.equal(b.sharing.profileView(taken)!.role, "host");
  assert.deepEqual(b.sharing.profileView(taken)!.users, [A], "it knows who borrows it");
  assert.equal(JSON.parse(readFileSync(join(b.data, "homes", taken.id, ".credentials.json"), "utf8")).claudeAiOauth.refreshToken, "r");
  // The old host forgot the login and borrows now (under the same profile id: its chats go on).
  const left = a.config.raw().profiles.find((p: any) => p.id === "max");
  assert.equal(left.share.borrowed, true);
  assert.equal(left.share.host, B, "it knows whom it borrows from");
  assert.equal(existsSync(join(a.data, "homes", "max", ".credentials.json")), false);
  assert.equal((await a.sharing.lendClaude(left)).token, `token-of-${taken.id}`);
  // Only the station that has it can hand it over.
  await assert.rejects(a.sharing.moveProfile("max", A), /only a profile this station shares/);
});

test("a shared skill: copied and linked under its name, edits go back to the host, one made on an older copy is kept beside it", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  const dir = join(a.data, "agent", "skills", "ember");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "SKILL.md"), "---\nname: ember\ndescription: 项目记忆：ember\n---\nfirst\n");
  await a.sharing.shareSkill("ember", true, null);
  await settle(a, b);
  const link = join(b.data, "agent", "skills", "ember");
  assert.ok(lstatSync(link).isSymbolicLink());
  assert.match(readFileSync(join(link, "SKILL.md"), "utf8"), /first/);
  const id = a.config.raw().sharedSkills.ember.id;
  assert.equal(b.sharing.skillView("ember")!.role, "user");
  // An edit on the copy, sent to the host on the version it was made on.
  writeFileSync(join(readlinkSync(link), "SKILL.md"), "---\nname: ember\ndescription: 项目记忆：ember\n---\nfrom mini\n");
  const state = JSON.parse(readFileSync(join(b.data, "share", "state.json"), "utf8"));
  const base = state.borrowed[id].version;
  const answer = await a.sharing.handle(B, { method: "share.put", id, base, files: { "SKILL.md": Buffer.from("from mini\n").toString("base64") } });
  assert.deepEqual(answer, { version: base + 1, conflict: false });
  assert.equal(readFileSync(join(dir, "SKILL.md"), "utf8"), "from mini\n");
  // One made on the version before: kept beside, the host's stays.
  const late = await a.sharing.handle(B, { method: "share.put", id, base, files: { "SKILL.md": Buffer.from("late\n").toString("base64") } });
  assert.equal(late.conflict, true);
  assert.equal(readFileSync(join(dir, "SKILL.md"), "utf8"), "from mini\n");
  assert.equal(readFileSync(join(dir, `SKILL.conflict-${B.slice(0, 12)}.md`), "utf8"), "late\n");
  // One of the station's own by that name wins over a shared one.
  await a.sharing.shareSkill("ember", false, null);
  await settle(a, b);
  assert.equal(existsSync(link), false);
});

test("a shared skill's watch failing (macOS turning it down: EMFILE) is dropped, not the station, and followed again", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  const dir = join(a.data, "agent", "skills", "ember");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "SKILL.md"), "---\nname: ember\ndescription: 项目记忆：ember\n---\nfirst\n");
  await a.sharing.shareSkill("ember", true, null);
  await settle(a, b);
  const watchers = (a.sharing as any).watchers as Map<string, any>;
  const failed = watchers.get("hosted:ember");
  assert.ok(failed, "the shared skill is followed");
  // As Node tells it when FSEventStreamStart fails: an 'error' event on the watcher.
  assert.doesNotThrow(() => failed.emit("error", Object.assign(new Error("EMFILE: too many open files, watch"), { code: "EMFILE" })));
  await settle(a, b);
  assert.ok(watchers.get("hosted:ember") && watchers.get("hosted:ember") !== failed, "followed again");
  await a.sharing.close();
  await b.sharing.close();
});

test("a skill named in any script is shared; renamed, it is linked under its new name; deleted, it is no longer shared", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  const skills = (s: Station) => join(s.data, "agent", "skills");
  const linked = (name: string) => {
    try {
      return lstatSync(join(skills(b), name)).isSymbolicLink();
    } catch {
      return false;
    }
  };
  mkdirSync(join(skills(a), "测试"));
  writeFileSync(join(skills(a), "测试", "SKILL.md"), "---\nname: 测试\ndescription: 项目记忆：测试\n---\nfirst\n");
  await a.sharing.shareSkill("测试", true, null);
  await settle(a, b);
  assert.ok(linked("测试"), "copied and linked under its name");
  assert.match(readFileSync(join(skills(b), "测试", "SKILL.md"), "utf8"), /first/);
  const id = a.config.raw().sharedSkills["测试"].id;
  // Renamed on its host: shared on under the new name, the copy linked under it only.
  renameSync(join(skills(a), "测试"), join(skills(a), "测验"));
  await settle(a, b);
  assert.deepEqual(Object.keys(a.config.raw().sharedSkills), ["测验"]);
  assert.equal(a.config.raw().sharedSkills["测验"].id, id);
  assert.ok(linked("测验"));
  assert.equal(linked("测试"), false);
  // Deleted on its host: no longer shared, the copy taken away.
  rmSync(join(skills(a), "测验"), { recursive: true });
  await settle(a, b);
  assert.deepEqual(a.config.raw().sharedSkills, {});
  assert.equal(linked("测验"), false);
  // A name that is not one directory's on every machine is refused, by the station told of it as by the one sharing it.
  for (const name of ["../x", "a:b", "CON"]) {
    await assert.rejects(b.sharing.handle(A, { method: "share.changed", id: "sh-0123456789abcdef0123", kind: "skill", name, version: 1 }), /bad skill name/);
  }
});

test("where a skill is shared, which stations have it and why one does not are said", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  const make = (s: Station, name: string, body = "first\n") => {
    mkdirSync(join(s.data, "agent", "skills", name), { recursive: true });
    writeFileSync(join(s.data, "agent", "skills", name, "SKILL.md"), `---\nname: ${name}\ndescription: ${name}\n---\n${body}`);
  };
  const shareOf = (name: string) => memory(a.data).skills.find((k: any) => k.name === name).share;
  make(a, "ember");
  // B has one of its own by this name: it keeps its own, and A hears so.
  make(a, "mine");
  make(b, "mine");
  await a.sharing.shareSkill("ember", true, null);
  await a.sharing.shareSkill("mine", true, null);
  await settle(a, b);
  assert.deepEqual(shareOf("ember").users, [B]);
  assert.deepEqual(shareOf("ember").missing, []);
  assert.deepEqual(shareOf("mine").users, []);
  assert.deepEqual(shareOf("mine").missing, [{ station: B, why: "same-name" }]);
  // B's own goes: the copy is linked, and A hears it is had.
  rmSync(join(b.data, "agent", "skills", "mine"), { recursive: true });
  await settle(a, b);
  assert.ok(lstatSync(join(b.data, "agent", "skills", "mine")).isSymbolicLink());
  assert.deepEqual(shareOf("mine").users, [B]);
  assert.deepEqual(shareOf("mine").missing, []);
  // Grown past what may be shared: said, the stations keeping the last of it.
  writeFileSync(join(a.data, "agent", "skills", "ember", "big.bin"), Buffer.alloc(600 * 1024));
  await settle(a, b);
  assert.equal(shareOf("ember").unread, "too-large");
  assert.match(readFileSync(join(b.data, "agent", "skills", "ember", "SKILL.md"), "utf8"), /first/);
  rmSync(join(a.data, "agent", "skills", "ember", "big.bin"));
  await settle(a, b);
  assert.equal(shareOf("ember").unread, undefined);
  // A station that refuses it (one from before, whose names were ASCII only): said why, asked again later.
  const handle = b.sharing.handle.bind(b.sharing);
  b.sharing.handle = async (peer, request, ws) => {
    if (request.method === "share.changed" && request.kind === "skill") throw new Refused("bad skill name");
    return handle(peer, request, ws);
  };
  make(a, "测试");
  await a.sharing.shareSkill("测试", true, null);
  await settle(a, b);
  assert.deepEqual(shareOf("测试").missing, [{ station: B, why: "name" }]);
});

test("a station gone from the workspace: what it shared is taken away, what it used forgotten", async () => {
  const cloud = new FakeCloud();
  const all = new Map<string, Station>();
  const a = station(cloud, A, () => all, [KEY]);
  const b = station(cloud, B, () => all);
  all.set(A, a).set(B, b);
  await a.sharing.shareProfile("deepseek", true, null);
  await settle(a, b);
  const id = a.config.raw().profiles[0].share.id;
  assert.deepEqual(a.sharing.profileView(a.config.raw().profiles[0])!.users, [B]);
  cloud.peers = cloud.peers.filter((p) => p.id !== A);
  cloud.tell();
  await settle(b);
  assert.equal(b.config.raw().profiles.length, 0, "its copy taken away");
  cloud.peers = [{ id: A, name: "studio" }];
  cloud.tell();
  await settle(a);
  assert.deepEqual(a.sharing.profileView(a.config.raw().profiles[0])!.users, [], "no one borrows it now");
  assert.equal(a.config.raw().profiles[0].share.id, id);
});
