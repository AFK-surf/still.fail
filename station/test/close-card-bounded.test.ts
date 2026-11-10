import assert from "node:assert/strict";
import { test } from "node:test";
import { Store } from "../src/store/store.ts";

const card = JSON.stringify({ type: "options", options: [{ label: "yes", action: "close" }] });

test("closing an old card does not search through later ordinary messages", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "close", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", "one", "agent", "a", "choose", 1, card);
    db.exec("BEGIN");
    for (let n = 2; n <= 5001; n++) put.run(thread, n, "message", `m-${n}`, "agent", "a", "work", n, null);
    db.exec("COMMIT");
    let visited = 0;
    db.function("visit_close_card", () => { visited++; return 1; });
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (source: string) => target.prepare(source.replace(
          "WHERE thread = ? AND kind = 'message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY n DESC LIMIT 1",
          "WHERE thread = ? AND visit_close_card() AND kind = 'message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY n DESC LIMIT 1",
        ).replaceAll(
          "WHERE thread = ?1 AND n > ?2 AND", "WHERE thread = ?1 AND n > ?2 AND visit_close_card() AND",
        ));
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    try {
      assert.equal(store.closeCard("person", thread, 1, "yes"), true);
      assert.ok(visited <= 16, `closing the card examined ${visited} later entries`);
    } finally { Object.defineProperty(store, "db", { configurable: true, value: db }); }
  } finally { store.close(); }
});

for (const { name, kind, author, nextCard, options, closes } of [
  { name: "an ordinary message", kind: "message", author: "agent", nextCard: null, options: null, closes: true },
  { name: "a card edit", kind: "edit", author: "agent", nextCard: "{}", options: null, closes: true },
  { name: "a person edit", kind: "edit", author: "person", nextCard: null, options: null, closes: true },
  { name: "a person's message", kind: "message", author: "person", nextCard: null, options: null, closes: false },
  { name: "a newer card", kind: "message", author: "agent", nextCard: "{}", options: null, closes: false },
  { name: "newer legacy options", kind: "message", author: "agent", nextCard: null, options: "[]", closes: false },
  { name: "a malformed newer card", kind: "message", author: "agent", nextCard: "invalid", options: null, closes: false },
]) {
  test(`a card ${closes ? "can" : "cannot"} be closed after ${name}`, () => {
    const store = Store.open(":memory:");
    try {
      const thread = store.openThread("ember", "CHAT", name, null, null).id;
      const put = store.db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
      put.run(thread, 1, "message", "card", "agent", "a", "choose", 1, card, null);
      put.run(thread, 2, kind, "next", author, "someone", "next", 2, nextCard, options);
      assert.equal(store.closeCard("person", thread, 1, "yes"), closes);
    } finally { store.close(); }
  });
}

test("a previously closed card stays closed even after a later message", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "CHAT", "closed", null, null).id;
    const put = store.db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", "card", "agent", "a", "choose", 1, card);
    assert.equal(store.closeCard("person", thread, 1, "yes"), true);
    put.run(thread, 2, "message", "next", "person", "person", "next", 2, null);
    assert.equal(store.closeCard("person", thread, 1, "yes"), true);
  } finally { store.close(); }
});

test("the choices a session has not been told are read by their index, the oldest first, and only its own", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "choices", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    for (let n = 1; n <= 3; n++) {
      put.run(thread, n, "message", `card-${n}`, "agent", n === 2 ? "b" : "a", `choose ${n}`, n, card);
      assert.equal(store.closeCard("person", thread, n, "yes"), true);
    }
    assert.deepEqual(store.untoldCardChoices("a").map((c) => [c.n, c.ts, c.where, c.question, c.by, c.option]), [
      [1, "card-1", ["CHAT", "choices"], "choose 1", "person", "yes"], [3, "card-3", ["CHAT", "choices"], "choose 3", "person", "yes"],
    ]);
    assert.deepEqual(store.untoldCardChoices("a", 1).map((c) => c.n), [1]);
    const plan = db.prepare("EXPLAIN QUERY PLAN SELECT thread, n, ts, viewer, option, at FROM card_choices INDEXED BY card_choices_untold WHERE session = ? AND told_at IS NULL ORDER BY at LIMIT ?").all("a", 20);
    assert.ok(plan.every((row: any) => /USING INDEX card_choices_untold \(session=\?\)/.test(row.detail) && !/TEMP B-TREE/.test(row.detail)), JSON.stringify(plan));
    store.markCardChoicesTold("a", [{ thread, n: 1 }]);
    store.markCardChoicesTold("a", [{ thread, n: 2 }]);
    assert.deepEqual(store.untoldCardChoices("a").map((c) => c.n), [3]);
    assert.deepEqual(store.untoldCardChoices("b").map((c) => c.n), [2], "another session's choice is not marked through this one");
    assert.deepEqual([...store.cardChoices(thread, [1, 2, 3, 4]).keys()], [1, 2, 3]);
  } finally { store.close(); }
});
