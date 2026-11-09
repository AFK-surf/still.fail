// The workspace lock read of its stations and brought to them, not the cloud (the root AGENTS.md,
// The cloud is the account system): the cloud asked only where no station answers, and what is signed sent to it too
// for the stations and devices from before, never waited on; a station that tells its lock moved is read again.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { Lock, fold, held, read } from "../src/views/lock.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";
import { Status, stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);

/// A station of the lock as station/src/mesh/serve.ts answers it: its chain (`chain`), the devices that came to it
/// (`came`); `old`: one from before, which serves none of it.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const came: Record<string, unknown>[] = [];
  const say = { old: false, asked: [] as string[] };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    say.asked.push(`${method} ${path}`);
    if (say.old) return path.startsWith("/lock?") || path === "/lock" ? Effect.succeed({ head: head(), entries: [], takes: ["person"] }) : Effect.fail(new CoreError("http_404", "no route", 404));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (body as { entries: Entry[] }).entries) if (e.seq === chain.length) chain.push(e);
      return Effect.succeed({ taken: 1, head: head() });
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: came });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, came, say, head, answer };
}

async function setUp() {
  const g = grant();
  let me: Signer | null = null;
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME, []) }), undefined, A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!);
  // What the cloud is asked of the lock, and whether it answers.
  const cloud = { asked: [] as string[], down: false };
  stationReplies(r.host, (req) => {
    if (!/\/v1\/workspaces\/ws\/(lock|devices)/.test(req.url)) return r.cloud.reply(req);
    cloud.asked.push(`${req.method} ${req.url.replace(/^.*\/v1\/workspaces\/ws/, "")}`);
    return cloud.down ? new Status(503, { error: "down" }) : r.cloud.reply(req);
  });
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return st.answer(method, path, body);
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let out: X | undefined;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    for (let i = 0; i < 500 && !done; i++) await r.host.time.pass(10);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  return { r, inner, st, cloud, run, signer: () => me! };
}

test("the lock is read of its stations, the devices that came with it; the cloud is not asked", async () => {
  const { inner, st, cloud, run, signer } = await setUp();
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  st.came.push({ sub: "s1", email: "a@x.com", device: "dd".repeat(32), base: ME, kind: "app", label: "Mac", first_seen: 900, last_seen: 1000 });
  cloud.asked.length = 0;
  await run(read(inner, "ws"));
  const h = held(inner, "ws")!;
  assert.equal(h.head?.seq, 1);
  assert.ok(fold(h.entries).members.has("s3"));
  assert.deepEqual(h.seen?.map((d) => d.label), ["Mac"]);
  assert.equal(cloud.asked.length, 0, cloud.asked.join());
  // A station from before serves none of it: the cloud is read, as before.
  st.say.old = true;
  await run(read(inner, "ws"));
  assert.ok(cloud.asked.some((a) => a.startsWith("GET /lock")));
});

test("an entry is brought to the stations and done once one took it: the cloud, down, is not waited on", async () => {
  const { inner, st, cloud, run, r } = await setUp();
  await run(read(inner, "ws"));
  cloud.down = true;
  const done = await run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s3", email: "c@x.com", role: "member" }));
  assert.equal((done as { head: Head }).head.seq, 1);
  assert.equal(st.chain.length, 2);
  // Sent to the cloud as well, for those from before.
  await r.host.time.pass(100);
  assert.ok(cloud.asked.includes("POST /lock"));
  // No station takes it (one from before): the cloud is what takes it, and its failure is the call's.
  st.say.old = true;
  await assert.rejects(run(new Lock(inner, "ws", "s1", null).append("member", { sub: "s4", email: "d@x.com", role: "member" })));
});

test("a station that tells its lock moved is read again", async () => {
  const { inner, st, run, signer, r } = await setUp();
  await run(read(inner, "ws"));
  st.chain.push(signer().sign(next("ws", st.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" })));
  inner.stations.onEvent(`ws/${A}`, "lock", JSON.stringify({ workspace: "ws", head: st.head() }));
  for (let i = 0; i < 50 && held(inner, "ws")?.head?.seq !== 1; i++) await r.host.time.pass(10);
  assert.equal(held(inner, "ws")?.head?.seq, 1);
});
