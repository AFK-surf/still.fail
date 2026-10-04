// Stations sharing profiles and skills (src/share/index.ts, docs/station-share.md): two stations, a cloud that only
// lists who hosts what (as cloud/src/directory.ts `stationShare` keeps it), and the station transport as a direct call.
import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { Share } from "../src/cloud/state.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { Sharing } from "../src/share/index.ts";

const A = "a".repeat(64);
const B = "b".repeat(64);

/// What still.fail cloud keeps of shares, and the stations' cloud.json as its frames leave them.
class FakeCloud {
  shares: Share[] = [];
  listeners = new Map<string, Set<() => void>>();
  cloudFor(station: string) {
    const cloud = this;
    const mine = new Set<() => void>();
    this.listeners.set(station, mine);
    return {
      sharesCurrent: true,
      get state() {
        return { station, workspace: "w", peers: [{ id: A, name: "studio" }, { id: B, name: "mini" }], shares: cloud.shares } as any;
      },
      removed: () => false,
      listen(f: () => void) {
        mine.add(f);
        return () => mine.delete(f);
      },
    } as any;
  }
  tell() {
    for (const set of this.listeners.values()) for (const f of set) f();
  }
  /// directory.ts stationShare, as far as these tests go.
  post(station: string, body: any) {
    const at = this.shares.findIndex((s) => s.id === body.id);
    if (at >= 0 && this.shares[at]!.host !== station) throw new Error("not_host");
    if (body.op === "delete") this.shares = this.shares.filter((s) => s.id !== body.id);
    else if (body.op === "move") this.shares[at] = { ...this.shares[at]!, host: body.host, version: this.shares[at]!.version + 1 };
    else if (at >= 0) this.shares[at] = { ...this.shares[at]!, name: body.name, allow: body.allow ?? null, version: body.version };
    else this.shares.push({ id: body.id, kind: body.kind, name: body.name, host: station, allow: body.allow ?? null, version: body.version, updated_at: 0 });
    this.shares = [...this.shares];
    setImmediate(() => this.tell());
    return { shares: this.shares };
  }
}

type Station = { data: string; config: ConfigFile; sharing: Sharing; lent: string[] };

function station(cloud: FakeCloud, id: string, others: () => Map<string, Station>, profiles: any[] = []): Station {
  const data = mkdtempSync(join(tmpdir(), "share-"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles }));
  const config = new ConfigFile(data);
  config.check = checkConfig;
  mkdirSync(join(data, "agent", "skills"), { recursive: true });
  const lent: string[] = [];
  const sharing = new Sharing({
    data, config, key: null as any, cloud: cloud.cloudFor(id),
    ask: async (to, request) => {
      const other = others().get(to);
      if (!other) throw new Error("peer unavailable");
      return other.sharing.handle(id, request);
    },
    agentHome: () => join(data, "agent"),
    env: {},
    claudeToken: async (p) => (lent.push(p.id), { token: `token-of-${p.id}`, expiresAt: Date.now() + 3600_000 }),
    codexRunning: () => false,
    status: (pid) => ({ check: { state: "ok", detail: `checked ${pid}`, models: null, checkedAt: 1 }, quota: null }),
    changed: () => {},
    post: async (_path, _tag, body) => cloud.post(id, body),
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
  a.config.update((raw) => (raw.profiles[0].name = "DeepSeek 2"));
  await settle(b);
  assert.equal(b.config.raw().profiles.length, 1);
  all.set(A, a);
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

test("a shared subscription: the other borrows tokens from its host, with no login of its own; not while the host is away", async () => {
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
  await assert.rejects(b.sharing.lendClaude(copy), /did not lend/);
  assert.equal(b.sharing.profileView(copy)!.reachable, false);
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
  assert.equal(cloud.shares.find((s) => s.id === id)!.host, B);
  const taken = b.config.raw().profiles.find((p: any) => p.share?.id === id);
  assert.equal(taken.share.borrowed, undefined);
  assert.equal(JSON.parse(readFileSync(join(b.data, "homes", taken.id, ".credentials.json"), "utf8")).claudeAiOauth.refreshToken, "r");
  // The old host forgot the login and borrows now (under the same profile id: its chats go on).
  const left = a.config.raw().profiles.find((p: any) => p.id === "max");
  assert.equal(left.share.borrowed, true);
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
  const id = a.config.raw().sharedSkills.ember;
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
