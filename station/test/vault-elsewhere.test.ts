// A vault's secret used on another station of the workspace (docs/vault.md 在另一台 station 上用; src/vault/secrets.ts
// `heard`): a grant asked for that station runs its commands there, in the chat's directory on it, and nowhere else; a
// secret to keep read there. Two stations' Secrets ask each other directly, as the station transport would carry it.
// Nothing waits on time: a request's answer is awaited once it is decided, a command's once it has ended.
import assert from "node:assert/strict";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { PLAIN, PlainStore } from "../src/vault/plain.ts";
import { Secrets } from "../src/vault/secrets.ts";
import { VaultStore } from "../src/vault/store.ts";
import { STILLFAIL_SURFACE } from "../src/store/store.ts";
import type { Json } from "../src/store/store.ts";

const WS = "ws1";
const TOKEN = "tok-elsewhere-0123456789abcdef";
const tick = () => new Promise((r) => setImmediate(r));

/// Two stations: `here` (ccvm, where the chat is) and `there` (Studio), each with its Secrets, asking each other.
function stations() {
  const dir = realpathSync(mkdtempSync(join(tmpdir(), "vault-elsewhere-")));
  const cards: { text: string; card: any }[] = [];
  const told: string[] = [];
  const hub = {
    store: {
      getSession: (k: string) => (k === "s1" ? { key: "s1", ws: null, workspace: join(dir, "here"), archivedAt: null } : null),
      starter: () => "bob@x.com",
      latestThread: () => ({ connect: "c", thread: { id: 1, channel: "EMBER", threadTs: "1.0", surface: STILLFAIL_SURFACE } }),
      withdrawCard: () => true,
      restateCard: () => true,
      insertMessage: (m: { text: string; card: unknown }) => (cards.push({ text: m.text, card: m.card }), [1]),
      subscribe: () => () => {},
    },
    chat: () => ({ post: async () => "1.0" }),
    shared: () => {},
    notify: (_k: string, text: string) => void told.push(text),
  };
  const rooms: string[] = [];
  const made = (name: string, peer: (given: string) => { id: string; name: string } | null, ask: (station: string, request: Json) => Promise<Json>) => {
    const db = new DatabaseSync(":memory:");
    return new Secrets({
      db, vaults: new VaultStore(db), plain: new PlainStore(db), home: () => WS, hub: hub as never, data: join(dir, name), lock: () => null, now: () => 1_000_000,
      peer, ask, workOf: (ws, from, session) => (rooms.push(`${ws}/${from}/${session}`), join(dir, name, "room")),
    });
  };
  // ccvm names Studio; Studio is asked by ccvm. A station that is not there is refused, as the transport would.
  const studio = { id: "st-studio", name: "Studio" };
  let here: Secrets;
  const there: Secrets = made("there", () => null, (station, request) => here.heard("st-studio", WS, request));
  here = made(
    "here",
    (given) => {
      if (given === "ccvm") return null;
      if (given.toLowerCase() === "studio" || given === studio.id) return studio;
      throw new Error(`no station ${given} in this station's workspaces`);
    },
    async (station, request) => {
      if (station !== studio.id) throw new Error("peer is not another station in this workspace");
      return there.heard("st-ccvm", WS, request);
    },
  );
  return { dir, cards, told, rooms, here, there };
}

test("a grant asked for another station: its commands run there, in the chat's directory, the value hidden; nowhere else", async () => {
  const s = stations();
  try {
    // bob's token, kept without security mode on ccvm.
    const kept = s.here.save("s1", { name: "Router", kind: "token", reason: "keep", value: TOKEN, env: "ROUTER_TOKEN", cwd: s.dir });
    await tick();
    const [toKeep] = s.here.pending(WS, null, { sub: "bob", email: "bob@x.com" });
    assert.ok(typeof s.here.savedPlain(WS, null, "bob@x.com", { request: toKeep!.id }) !== "string");
    await kept;

    await assert.rejects(s.here.ask("s1", { item: "Router", reason: "x", station: "mini" }), /no station mini/);
    const asked = s.here.ask("s1", { item: "Router", reason: "read the router's counters", command: "curl …", station: "studio" });
    await tick();
    const [r] = s.here.pending(WS, null, { sub: "bob", email: "bob@x.com" });
    assert.deepEqual(r!.runOn, { id: "st-studio", name: "Studio" });
    assert.match(s.cards.at(-1)!.text, /运行在：Studio/);
    assert.equal(s.cards.at(-1)!.card.vault.station, "Studio");
    assert.equal(s.here.grantPlain(WS, null, "bob@x.com", { request: r!.id, scope: "chat" }), null);
    await asked;
    assert.match(s.told.at(-1)!, /Its commands run on Studio/);

    // Run there: in the chat's directory on Studio, the value in its variable, hidden in what comes back.
    const out = await s.here.run("s1", { grant: r!.id, command: 'pwd; echo "token=$ROUTER_TOKEN"', cwd: join(s.dir, "here"), timeoutMs: 60_000 });
    assert.match(out, /^exit code 0/);
    assert.ok(out.includes(join(s.dir, "there", "room")), out);
    assert.ok(out.includes("token=[已隐藏]") && !out.includes(TOKEN), out);
    assert.deepEqual(s.rooms, [`${WS}/st-ccvm/s1`]);
    // A directory under it; never above it.
    const sub = await s.here.run("s1", { grant: r!.id, command: "pwd", cwd: join(s.dir, "here", "logs"), under: "logs", timeoutMs: 60_000 });
    assert.ok(sub.includes(join(s.dir, "there", "room", "logs")), sub);
    await assert.rejects(s.here.run("s1", { grant: r!.id, command: "pwd", cwd: s.dir, under: "../x", timeoutMs: 60_000 }), /inside the session's directory/);
    // Named the same station, or not at all; not this one.
    assert.match(await s.here.run("s1", { grant: r!.id, command: "true", cwd: s.dir, station: "Studio", timeoutMs: 60_000 }), /^exit code 0/);
    await assert.rejects(s.here.run("s1", { grant: r!.id, command: "true", cwd: s.dir, station: "ccvm" }), /for commands on Studio/);

    // A grant for this station is not taken elsewhere.
    const local = s.here.ask("s1", { item: "Router", reason: "here" });
    await tick();
    const [mine] = s.here.pending(WS, null, { sub: "bob", email: "bob@x.com" });
    assert.equal(s.here.grantPlain(WS, null, "bob@x.com", { request: mine!.id, scope: "chat" }), null);
    await local;
    await assert.rejects(s.here.run("s1", { grant: mine!.id, command: "true", cwd: s.dir, station: "Studio" }), /ask again with secret_use \{station: "Studio"\}/);

    // Only the station a command was sent to says how it ended.
    await assert.rejects(s.here.heard("st-other", WS, { method: "vault.done", id: "x_01HZZZZZZZZZZZZZZZZZZZZZZZ", result: {} }), /no such command/);
    await assert.rejects(s.there.heard("st-ccvm", WS, { method: "vault.run", id: "x_01HZZZZZZZZZZZZZZZZZZZZZZZ", session: "s1", command: "true", mode: "env", grant: "r_1", secret: { kind: "token", fields: {} } }), /holds no value/);
  } finally {
    rmSync(s.dir, { recursive: true, force: true });
  }
});

test("a secret to keep read on another station: its command runs there; the value comes back to be kept, never shown", async () => {
  const s = stations();
  try {
    process.env.TOKEN_ON_STUDIO = TOKEN;
    const made = new Promise<any>((resolve) => s.here.listen((r) => r.status === "pending" && resolve(r)));
    void s.here.save("s1", { name: "1Password item", kind: "token", reason: "keep it", command: 'printf "%s" "$TOKEN_ON_STUDIO"', station: "Studio", cwd: s.dir });
    const r = await made;
    delete process.env.TOKEN_ON_STUDIO;
    assert.deepEqual(r.runOn, { id: "st-studio", name: "Studio" });
    assert.equal(s.cards.at(-1)!.card.vault.station, "Studio");
    assert.ok(!JSON.stringify(r).includes(TOKEN));
    const item = s.here.savedPlain(WS, null, "bob@x.com", { request: r.id });
    assert.ok(typeof item !== "string" && item.fields.value === TOKEN && r.vault === PLAIN);
    // One whose command fails there says so, the value hidden.
    await assert.rejects(
      s.here.save("s1", { name: "Bad", kind: "token", reason: "x", command: `printf '${TOKEN}'; echo "oops ${TOKEN}" >&2; exit 2`, station: "Studio", cwd: s.dir }),
      (e: Error) => /exit code 2/.test(e.message) && e.message.includes("oops [已隐藏]") && !e.message.includes(TOKEN),
    );
    await assert.rejects(s.here.save("s1", { name: "V", kind: "token", reason: "x", value: "v", station: "Studio", cwd: s.dir }), /give command/);
  } finally {
    rmSync(s.dir, { recursive: true, force: true });
  }
});
