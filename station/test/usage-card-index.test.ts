// The decision cards the usage page counts (read/store.ts decisionCards), as the database keeps them (store/schema.ts
// CARD_OUTCOMES): kept as messages are written, the same as working them out from
// every card's next message, and read without reading an entry.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { decisionCards, makeStore } from "../src/read/store.ts";
import { cardOf } from "../src/store/rows.ts";
import { Store, newMessage } from "../src/store/store.ts";

/// How each card was answered, worked out as it was before the outcomes were kept: each agent's options card, and the
/// first thing a person said after it in its chat (one of its labels, trimmed), or a close by someone not its author.
function workedOut(store: Store): string[] {
  const asked = store.db.prepare("SELECT thread, n, author, card, options FROM entries WHERE kind = 'message' AND author_kind = 'agent' AND (card IS NOT NULL OR options IS NOT NULL)").all() as any[];
  const next = store.db.prepare("SELECT text FROM entries WHERE thread = ? AND n > ? AND kind = 'message' AND author_kind = 'person' ORDER BY n LIMIT 1");
  const closed = store.db.prepare("SELECT viewer FROM closed_cards WHERE thread = ? AND n = ?");
  const out: string[] = [];
  for (const r of asked) {
    const card = cardOf(r.card ?? null, r.options ?? null);
    if (card?.type !== "options" || !Array.isArray(card.options)) continue;
    const labels = new Set(card.options.map((o: any) => (typeof o?.label === "string" ? o.label.trim() : "")).filter((l: string) => l !== ""));
    const said = next.get(r.thread, r.n) as any;
    const shut = closed.get(r.thread, r.n) as any;
    const picked = (said !== undefined && typeof said.text === "string" && labels.has(said.text.trim())) || (shut !== undefined && shut.viewer !== r.author);
    out.push(`${r.thread}:${r.n}:${picked}`);
  }
  return out.sort();
}

/// How each card was answered, as the database keeps it.
const kept = (store: Store) =>
  (store.db.prepare("SELECT c.thread, c.n, c.said OR EXISTS (SELECT 1 FROM closed_cards x WHERE x.thread = c.thread AND x.n = c.n AND x.viewer != c.author) AS picked FROM card_outcomes c").all() as any[])
    .map((r) => `${r.thread}:${r.n}:${r.picked === 1}`)
    .sort();

/// Chats with cards of every shape, answered every way.
function write(store: Store) {
  const a = store.openThread("ember", "EMBER", "a", null, null).id;
  const b = store.openThread("ember", "EMBER", "b", null, null).id;
  let ts = 0;
  const say = (thread: number, kind: "agent" | "person", text: string, more: { card?: unknown; options?: unknown } = {}) =>
    store.insertMessage({ ...newMessage(thread, String(++ts), kind, kind === "agent" ? "k1" : "p@x", text), ...more } as any)[0];
  const options = (...labels: unknown[]) => ({ card: { type: "options", options: labels.map((label) => (typeof label === "string" ? { label } : label)) } });
  // Answered with one of its labels, written around (a tab, a no-break space, a newline).
  say(a, "agent", "pick", options("yes", " no "));
  say(a, "agent", "working");
  say(a, "person", "\t no \n");
  // Two cards before one answer: both answered by it, one by a label of its own.
  say(a, "agent", "first", options("go"));
  say(a, "agent", "second", options("stay", { label: 3 }, "x", { label: "  " }));
  say(a, "person", "stay");
  // Answered in a person's own words, then closed by them.
  const closedByPerson = say(a, "agent", "close me", options("ok"));
  say(a, "person", "whatever");
  // Closed by its own agent: not picked.
  const closedByAgent = say(a, "agent", "withdrawn", options("ok"));
  // Options from before cards; a card that is none of options; one with no list.
  say(b, "agent", "old", { options: [{ label: "a" }, "b"] });
  say(b, "agent", "login", { card: { type: "login", login: "l1" } });
  say(b, "agent", "odd", { card: { type: "options", options: "none" } });
  say(b, "person", "a");
  // Not answered yet.
  say(b, "agent", "open", options("later"));
  store.db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, 1)").run(a, closedByPerson, "p@x");
  store.db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, 1)").run(a, closedByAgent, "k1");
  // A card a station before wrote whose own JSON does not read: its options from before cards count.
  store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at, card, options) VALUES (?, 100, 'message', 'agent', 'k1', 'broken', 1, '{nope', ?)").run(b, JSON.stringify([{ label: "fix" }]));
  store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, 101, 'message', 'person', 'p@x', 'fix', 1)").run(b);
}

test("answering new cards seeks past old answered cards, including after upgrading an old database", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-answers-scale-"));
  const path = join(dir, "stillfail.db");
  try {
    let store = Store.open(path, join(dir, "archive"));
    // An existing station's trigger, before the bounded range; opening it must update the trigger without a rebuild.
    store.db.exec(`DROP TRIGGER card_outcomes_answered;
      CREATE TRIGGER card_outcomes_answered AFTER INSERT ON entries WHEN NEW.kind = 'message' AND NEW.author_kind = 'person' BEGIN
        UPDATE card_outcomes SET answered = 1, said = NEW.text IS NOT NULL AND EXISTS (SELECT 1 FROM json_each(labels) l WHERE l.value = trim(NEW.text))
        WHERE thread = NEW.thread AND n < NEW.n AND answered = 0;
      END;`);
    store.close();
    store = Store.open(path, join(dir, "archive"));
    const thread = store.openThread("ember", "EMBER", "scale", null, null).id;
    const old = store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, ?, 'agent', '[]', 1, 0)");
    store.db.exec("BEGIN");
    for (let n = 1; n <= 2_000; n++) old.run(thread, n);
    store.db.exec("COMMIT");
    const person = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'person', ?, ?)");
    const card = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at, card) VALUES (?, ?, 'message', 'agent', 'agent', 'pick', ?, ?)");
    person.run(thread, 2_001, "before", 2_001);
    card.run(thread, 2_002, 2_002, JSON.stringify({ type: "options", options: [{ label: "yes" }] }));
    card.run(thread, 2_003, 2_003, JSON.stringify({ type: "options", options: [{ label: "no" }] }));
    person.run(thread, 2_004, "yes", 2_004);
    const outcomes = store.db.prepare("SELECT n, answered, said FROM card_outcomes WHERE thread = ? AND n >= 2002 ORDER BY n").all(thread) as { n: number; answered: number; said: number }[];
    assert.deepEqual(outcomes.map((r) => [r.n, r.answered, r.said]), [[2_002, 1, 1], [2_003, 1, 0]]);

    // Explain the actual installed trigger's UPDATE. Its lower bound is the previous person's message, so the
    // primary-key range excludes all 2,000 old cards; both that lookup and the previous-person lookup are indexed.
    const trigger = store.db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'card_outcomes_answered'").get() as { sql: string };
    const update = trigger.sql.match(/UPDATE card_outcomes SET[\s\S]+?;/)?.[0];
    assert.ok(update);
    const sql = update.replaceAll("NEW.thread", "?1").replaceAll("NEW.n", "?2").replaceAll("NEW.text", "?3");
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(thread, 2_004, "yes") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH card_outcomes USING PRIMARY KEY \(thread=\? AND n>\? AND n<\?\)/);
    assert.match(plan, /entries_people_by_n/);
    store.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the decision cards are kept as they are answered, the same as worked out from every card's next message", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-outcomes-"));
  const path = join(dir, "stillfail.db");
  try {
    const store = Store.open(path, join(dir, "archive"));
    write(store);
    const want = workedOut(store);
    // Five cards in the first chat, three in the second (not the login card, nor the one without a list); five picked.
    assert.equal(want.length, 8);
    assert.equal(want.filter((c) => c.endsWith(":true")).length, 5);
    assert.deepEqual(kept(store), want, "kept as they were written");
    store.close();
    const again = Store.open(path, join(dir, "archive"));
    assert.deepEqual(kept(again), want, "the saved outcomes survive reopening");
    // What the usage page counts, with the thread each is at home in; and none of it read from the entries.
    const counted = decisionCards(makeStore(again.db, dir));
    assert.deepEqual([counted.length, counted.filter((c) => c.picked).length], [8, 5]);
    const plan = (again.db.prepare("EXPLAIN QUERY PLAN SELECT t.home AS home, c.said OR EXISTS (SELECT 1 FROM closed_cards x WHERE x.thread = c.thread AND x.n = c.n AND x.viewer != c.author) AS picked FROM card_outcomes c LEFT JOIN threads t ON t.id = c.thread").all() as { detail: string }[]).map((r) => r.detail);
    assert.ok(!plan.some((line) => /\bentries\b/.test(line)), plan.join(" | "));
    // A chat removed with its entries takes its cards with it.
    const [first] = again.db.prepare("SELECT thread FROM card_outcomes ORDER BY thread LIMIT 1").all() as { thread: number }[];
    again.db.prepare("DELETE FROM entries WHERE thread = ?").run(first!.thread);
    assert.equal((again.db.prepare("SELECT COUNT(*) AS c FROM card_outcomes WHERE thread = ?").get(first!.thread) as { c: number }).c, 0);
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
