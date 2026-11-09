import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { answersSince, LAST_MESSAGE_RECENT_EDIT, makeStore } from "../src/read/store.ts";
import { chatMarks } from "../src/read/views.ts";
import { installLegacyEdits, legacyEditDrain, legacyEditStep } from "../src/store/legacy-edits-build.ts";
import { addClientColumn } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";
import { referenceAnswersSince } from "./card-answer-reference.ts";

function oldAnswers(size: number, prepared = false, path = ":memory:") {
  const store = Store.open(path), db = store.db;
  const thread = store.openThread("ember", "CHAT", `old-answers-${size}-${prepared}`, null, null).id;
  db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,card,at) VALUES(?,1,'message','1.1','agent','a','question',?,1)")
    .run(thread, JSON.stringify({ type: "text" }));
  db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at) VALUES(?,2,'message','2.1','person','p','answer',100)").run(thread);
  db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
  const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','a','other',?)");
  db.exec("BEGIN");
  for (let n = 3; n < size + 3; n++) edit.run(thread, n, prepared ? 1 : n + 1000, n);
  db.exec("COMMIT");
  installLegacyEdits(db);
  if (prepared) {
    while (!legacyEditStep(db).ready) { /* bounded preparation */ }
    db.prepare("UPDATE entries SET target=n+1000 WHERE thread=? AND kind='edit'").run(thread);
  }
  addClientColumn(db);
  return { store, db, thread };
}

for (const prepared of [false, true])
  test(`recent card answers leave a long old edit lookup to preparation (prepared ${prepared})`, () => {
    for (const size of [80, 800]) {
      const { store, db, thread } = oldAnswers(size, prepared);
      try {
        const read = makeStore(db, "");
        assert.throws(() => answersSince(read, 100, [thread]), { status: 503, message: "legacy edit lookup pending" });
        while (!legacyEditStep(db).ready) { /* bounded preparation */ }
        while (legacyEditDrain(db) > 0) { /* bounded reconciliation */ }
        assert.deepEqual(answersSince(read, 100, [thread]), referenceAnswersSince(store, 100));
      } finally { store.close(); }
    }
  });

test("recent card answers stop their old edit probes at a bounded tail", () => {
  for (const size of [62, 63]) {
    const { store, db, thread } = oldAnswers(size);
    try {
      const read = makeStore(db, "");
      if (size === 62) assert.deepEqual(answersSince(read, 100, [thread]), referenceAnswersSince(store, 100));
      else assert.throws(() => answersSince(read, 100, [thread]), { status: 503, message: "legacy edit lookup pending" });
    } finally { store.close(); }
  }
});

test("recent edits of both question and answer remain readable during old edit preparation", () => {
  const { store, db, thread } = oldAnswers(150);
  try {
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','a',?,200)");
    edit.run(thread, 9007199254740993n, 1, "new question");
    edit.run(thread, 9007199254740994n, 2, "new answer");
    const actual = answersSince(makeStore(db, ""), 100, [thread]);
    assert.deepEqual(actual.map((a) => [a.question.text, a.answer?.text]), [["new question", "new answer"]]);
    assert.deepEqual(actual, referenceAnswersSince(store, 100));
    assert.equal(db.prepare("SELECT scanned FROM legacy_edit_meta WHERE id=1").get()?.scanned, 0);
  } finally { store.close(); }
});

test("a recently closed card also leaves its old edit lookup to preparation", () => {
  const { store, db, thread } = oldAnswers(80);
  try {
    db.prepare("DELETE FROM entries WHERE thread=? AND n=2").run(thread);
    db.prepare("INSERT INTO closed_cards(thread,n,viewer,at) VALUES(?,1,'p',100)").run(thread);
    const read = makeStore(db, "");
    assert.throws(() => answersSince(read, 100, [thread]), { status: 503, message: "legacy edit lookup pending" });
    while (!legacyEditStep(db).ready) { /* bounded preparation */ }
    assert.deepEqual(answersSince(read, 100, [thread]), referenceAnswersSince(store, 100));
  } finally { store.close(); }
});

test("a card question and its answer share a snapshot during old edit probing", () => {
  const dir = mkdtempSync(join(tmpdir(), "card-answers-snapshot-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldAnswers(80, false, path), writer = new DatabaseSync(path);
  try {
    const edit = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','a',?,200)");
    edit.run(thread, 83, 1, "before question");
    edit.run(thread, 84, 2, "before answer");
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LAST_MESSAGE_RECENT_EDIT && !changed) {
          changed = true;
          writer.exec("BEGIN");
          writer.prepare("UPDATE entries SET text='after question' WHERE thread=? AND n=83").run(thread);
          writer.prepare("UPDATE entries SET text='after answer' WHERE thread=? AND n=84").run(thread);
          writer.exec("COMMIT");
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = makeStore(observed, dir);
    assert.deepEqual(answersSince(read, 100, [thread]).map((a) => [a.question.text, a.answer?.text]), [["before question", "before answer"]]);
    assert.ok(changed);
    assert.deepEqual(answersSince(read, 100, [thread]).map((a) => [a.question.text, a.answer?.text]), [["after question", "after answer"]]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("sidebar marks share old answer preparation after handover when one reader cancels", async () => {
  const dir = mkdtempSync(join(tmpdir(), "card-answers-reader-")), path = join(dir, "stillfail.db");
  const { store, db, thread } = oldAnswers(150, false, path);
  db.prepare("UPDATE entries SET at=? WHERE thread=? AND n=2").run(Date.now(), thread);
  const viewer = { sub: "p", email: "p", name: "P", role: "owner", workspace: "w", device: "d" } as const;
  const args = { viewer, scope: { sessions: [], threads: [thread] } };
  const previous = Promise.withResolvers<void>(), readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    assert.throws(() => chatMarks(makeStore(db, dir), viewer, args.scope), { status: 503, message: "legacy edit lookup pending" });
    const controller = new AbortController();
    const abandoned = readers.read("chatMarks", args, "en", { signal: controller.signal });
    const kept = readers.read("chatMarks", args, "en");
    void abandoned.catch(() => {}); void kept.catch(() => {});
    assert.deepEqual(JSON.parse(await readers.read("chatMarks", { viewer, scope: { sessions: [], threads: [] } }, "en")).answered, {});
    controller.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    const result = JSON.parse(await kept);
    assert.equal(result.answered[thread]?.[0]?.text, "question");
  } finally { previous.resolve(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
