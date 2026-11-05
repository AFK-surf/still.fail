import assert from "node:assert/strict";
import { test } from "node:test";
import { Keeper, type Held } from "../src/vault/keeper.ts";

function held(id: string, session: string, seen: () => void = () => {}): Held {
  const request: Held["request"] = { id, ws: "w", vault: "v", item: "i", session, chat: "", mode: "env",
    reason: "", box: "", at: 0, status: "granted" };
  Object.defineProperty(request, "session", { enumerable: true, get: () => { seen(); return session; } });
  return { request, grant: { v: 1, ws: "w", request: id, vault: "v", item: "i", mode: "env", hosts: [],
    scope: "chat", exp: 1000, secret: "", at: 0, sig: { key: "", alg: "Ed25519", sig: "" } },
    secret: { kind: "token", name: "token", fields: { value: "x" } }, uses: 0 };
}

test("a session's grants do not traverse other sessions' grants", () => {
  const counts: number[][] = [];
  for (const others of [40, 400]) {
    let visited = 0;
    const keeper = new Keeper(() => 0), ids: string[] = [];
    try {
      for (let i = 0; i < others; i++) {
        const id = `other-${i}`;
        ids.push(id);
        keeper.restore(held(id, id, () => { visited++; }));
      }
      ids.push("mine");
      keeper.restore(held("mine", "s", () => { visited++; }));
      visited = 0;
      assert.equal(keeper.holds("s"), true);
      const has = visited;
      visited = 0;
      assert.deepEqual(keeper.held("s").map((h) => h.request.id), ["mine"]);
      const list = visited;
      visited = 0;
      keeper.end("s");
      const end = visited;
      assert.equal(keeper.holds("s"), false);
      counts.push([has, list, end]);
    } finally { for (const id of ids) keeper.drop(id); }
  }
  assert.deepEqual(counts[1], counts[0], `other sessions increased grant visits: ${JSON.stringify(counts)}`);
});

test("restoring an existing id in another session keeps its original grant order", () => {
  const keeper = new Keeper(() => 0);
  try {
    keeper.restore(held("a", "old"));
    keeper.restore(held("b", "new"));
    keeper.restore(held("c", "new"));
    keeper.restore(held("a", "new"));
    assert.equal(keeper.holds("old"), false);
    assert.deepEqual(keeper.held("new").map((h) => h.request.id), ["a", "b", "c"]);
    keeper.end("new");
    assert.deepEqual(keeper.carried().held, []);
  } finally { for (const id of ["a", "b", "c"]) keeper.drop(id); }
});

test("ending a session forgets its grants in order and leaves other sessions intact", () => {
  const forgotten: string[] = [];
  const keeper = new Keeper(() => 0, { kept: { save: () => {}, forget: (h) => { forgotten.push(h.request.id); } } });
  try {
    keeper.restore(held("a", "s"));
    keeper.restore(held("other", "other"));
    keeper.restore(held("b", "s"));
    keeper.restore(held("a", "s"));
    keeper.end("s");
    assert.deepEqual(forgotten, ["a", "b"]);
    assert.equal(keeper.holds("s"), false);
    assert.deepEqual(keeper.held("other").map((h) => h.request.id), ["other"]);
  } finally { keeper.drop("other"); }
});

test("a carried session keeps its order and discards only its expired grants", () => {
  let now = 0;
  const before = new Keeper(() => now), after = new Keeper(() => now);
  try {
    const expired = held("expired", "s");
    expired.grant.exp = 10;
    before.restore(expired);
    before.restore(held("other", "other"));
    before.restore(held("live", "s"));
    after.carry(before.carried());
    now = 11;
    assert.deepEqual(after.held("s").map((h) => h.request.id), ["live"]);
    assert.equal(after.holds("s"), true);
    assert.deepEqual(after.held("other").map((h) => h.request.id), ["other"]);
    after.drop("live");
    assert.equal(after.holds("s"), false);
  } finally {
    for (const id of ["expired", "other", "live"]) { before.drop(id); after.drop(id); }
  }
});

test("an exhausted one-use grant is held until its session ends", () => {
  const keeper = new Keeper(() => 0);
  try {
    const once = held("once", "s");
    once.grant.scope = "once";
    keeper.restore(once);
    keeper.spend("once");
    assert.equal(keeper.holds("s"), true);
    assert.deepEqual(keeper.held("s"), []);
    keeper.end("s");
    assert.equal(keeper.holds("s"), false);
  } finally { keeper.drop("once"); }
});
