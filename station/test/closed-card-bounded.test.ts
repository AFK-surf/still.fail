import assert from "node:assert/strict";
import { test } from "node:test";
import { CLOSED_CARD_AFTER, Store } from "../src/store/store.ts";

test("a card closed after many ordinary messages does not read the intervening history", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "EMBER", "card", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", "one", "agent", "a", "choose", 1, JSON.stringify({ type: "options", options: [{ label: "yes" }] }));
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES (?,1,'person',2)").run(thread);
    db.exec("BEGIN");
    for (let n = 2; n <= 5_001; n++) put.run(thread, n, "message", `m-${n}`, "agent", "a", "work", n, null);
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_closed_card", (_n) => { visited++; return 1; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => target.prepare(source.replaceAll(
          "WHERE thread = ?1 AND n > ?2 AND", "WHERE thread = ?1 AND n > ?2 AND visit_closed_card(n) IS NOT NULL AND",
        ).replace(
          "AND (author_kind = 'person' OR card IS NOT NULL OR options IS NOT NULL)",
          "AND visit_closed_card(n) IS NOT NULL AND (author_kind = 'person' OR card IS NOT NULL OR options IS NOT NULL)",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      const closed = store.closedCard(thread, 1);
      assert.equal(closed?.[0].n, 1);
      assert.equal(closed?.[2], "person");
      assert.ok(visited <= 16, `checking the closed card visited ${visited} later entries`);
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${CLOSED_CARD_AFTER}`).all(thread, 1) as { detail: string }[]).map((row) => row.detail).join(" | ");
      for (const index of ["entries_people_by_n", "entries_cards", "entries_options"]) assert.ok(plan.includes(index), plan);
      visited = 0;
      assert.equal(store.closedCard(thread, 2), null);
      assert.equal(visited, 0, "a post with no close does not look at its later entries");
    } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
  } finally { store.close(); }
});

for (const { name, kind, author, card, options, ended } of [
  { name: "a person speaks", kind: "message", author: "person", card: null, options: null, ended: true },
  { name: "a later card", kind: "message", author: "agent", card: "{}", options: null, ended: true },
  { name: "later legacy options", kind: "message", author: "agent", card: null, options: "[]", ended: true },
  { name: "a card edit", kind: "edit", author: "agent", card: "{}", options: null, ended: false },
  { name: "a person edit", kind: "edit", author: "person", card: null, options: null, ended: false },
  { name: "an ordinary message", kind: "message", author: "agent", card: null, options: null, ended: false },
]) {
  test(`a closed card's wait ${ended ? "has" : "has not"} ended when there is ${name}`, () => {
    const store = Store.open(":memory:");
    try {
      const thread = store.openThread("ember", "EMBER", name, null, null).id;
      const put = store.db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
      put.run(thread, 1, "message", "card", "agent", "a", "choose", 1, JSON.stringify({ type: "options", options: [{ label: "yes" }] }), null);
      put.run(thread, 2, kind, "next", author, "someone", "next", 2, card, options);
      store.db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES (?,1,'person',3)").run(thread);
      assert.equal(store.closedCard(thread, 1) === null, ended);
      assert.equal(store.closedCard(thread, 2), null, "a post with no close is not a closed card");
    } finally { store.close(); }
  });
}
