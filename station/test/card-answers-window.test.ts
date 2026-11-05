import assert from "node:assert/strict";
import { test } from "node:test";
import { answersSince, makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

test("a scoped recent-answer read does not enumerate a chat's old cards", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "answer-window", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
    const card = JSON.stringify({ type: "options", options: [{ label: "yes" }] });
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, "message", `old-${n}`, "agent", "a", "choose", 1, card, null);
    db.exec("COMMIT");
    put.run(thread, 5_001, "message", "answer-1", "person", "p", "yes", 100, null, null);
    put.run(thread, 5_002, "message", "more", "person", "p", "more", 110, null, null);
    put.run(thread, 5_003, "message", "legacy", "agent", "a", "again", 2, null, '["yes"]');
    put.run(thread, 5_004, "message", "answer-2", "person", "p", "yes", 120, null, null);
    const expected = store.answersSince(100);
    assert.deepEqual(expected.map((a) => [a.question.n, a.answer?.n]), [[5_000, 5_001], [5_003, 5_004]]);
    let cardsRead = 0;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(query, method) {
              if (method === "all") return (...args: any[]) => {
                const rows = query.all(...args);
                if (/\bfrom card_posts\b/i.test(sql)) cardsRead += rows.length;
                return rows;
              };
              const value = Reflect.get(query, method, query);
              return typeof value === "function" ? value.bind(query) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const actual = answersSince(makeStore(traced, "."), 100, [thread]);
    assert.deepEqual(actual, expected);
    assert.ok(cardsRead > 0 && cardsRead <= 65, `reading recent answers returned ${cardsRead} old card entries`);
  } finally { store.close(); }
});

test("a short card history does not enumerate many recent ordinary messages", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "few-cards", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    put.run(thread, 1, "message", "card", "agent", "a", "choose", 1, JSON.stringify({ type: "text" }));
    db.exec("BEGIN");
    for (let n = 2; n <= 5_001; n++) put.run(thread, n, "message", `p-${n}`, "person", "p", "yes", 100 + n, null);
    db.exec("COMMIT");
    const expected = store.answersSince(100);
    assert.equal(expected.length, 1);
    let peopleRead = 0;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(query, method) {
              if (method === "all") return (...args: any[]) => {
                const rows = query.all(...args);
                if (/\bfrom entries\b/i.test(sql) && /author_kind\s*=\s*'person'/i.test(sql)) peopleRead += rows.length;
                return rows;
              };
              const value = Reflect.get(query, method, query);
              return typeof value === "function" ? value.bind(query) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    assert.deepEqual(answersSince(makeStore(traced, "."), 100, [thread]), expected);
    assert.ok(peopleRead <= 2, `reading one answer returned ${peopleRead} recent messages`);
  } finally { store.close(); }
});

test("many old cards and many recent ordinary messages do not require a lookup for each message", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "many-of-both", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    const card = JSON.stringify({ type: "text" });
    db.exec("BEGIN");
    for (let n = 1; n <= 5_000; n++) put.run(thread, n, "message", `c-${n}`, "agent", "a", "choose", 1, card);
    for (let n = 5_001; n <= 10_000; n++) put.run(thread, n, "message", `p-${n}`, "person", "p", "yes", 100, null);
    db.exec("COMMIT");
    let gets = 0;
    let rows = 0;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          return new Proxy(statement, {
            get(query, method) {
              if (method === "get") return (...args: any[]) => { gets++; return query.get(...args); };
              if (method === "all") return (...args: any[]) => { const found = query.all(...args); rows += found.length; return found; };
              const value = Reflect.get(query, method, query);
              return typeof value === "function" ? value.bind(query) : value;
            },
          });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const answers = answersSince(makeStore(traced, "."), 100, [thread]);
    assert.deepEqual(answers.map((a) => [a.question.n, a.answer?.n]), [[5_000, 5_001]]);
    assert.ok(gets < 30 && rows <= 130, `reading one answer used ${gets} lookups and returned ${rows} rows`);
  } finally { store.close(); }
});

test("out-of-order message times do not hide a later card's recent answer", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "time-order", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    const card = JSON.stringify({ type: "text" });
    let n = 0;
    const add = (author: string, at: number, value: string | null = null) => {
      n++;
      put.run(thread, n, "message", `${n}`, author, author, `${n}`, at, value);
      return n;
    };
    for (let i = 0; i < 70; i++) add("agent", 1, card);
    add("person", 100);
    for (let i = 0; i < 70; i++) { add("agent", 1, card); add("person", 1); }
    const lastCard = add("agent", 1, card);
    const lastAnswer = add("person", 100);
    for (let i = 0; i < 70; i++) add("person", 100);
    const answers = answersSince(makeStore(db, "."), 100, [thread]);
    assert.deepEqual(answers.map((a) => [a.question.n, a.answer?.n]), [[70, 71], [lastCard, lastAnswer]]);
    const ordered = store.answersSince(100).filter((a) => a.question.thread === thread).sort((a, b) => a.question.n - b.question.n);
    assert.deepEqual(answers, ordered);
  } finally { store.close(); }
});

test("a person's answer can itself carry the next card", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const thread = store.openThread("ember", "CHAT", "answer-with-card", null, null).id;
    const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card) VALUES (?,?,?,?,?,?,?,?,?)");
    const card = JSON.stringify({ type: "text" });
    for (let n = 1; n <= 70; n++) put.run(thread, n, "message", `old-${n}`, "agent", "a", "choose", 1, card);
    put.run(thread, 71, "message", "answer-and-card", "person", "p", "first", 100, card);
    put.run(thread, 72, "message", "answer-next", "person", "p", "second", 101, null);
    const expected = store.answersSince(100).filter((a) => a.question.thread === thread);
    assert.deepEqual(expected.map((a) => [a.question.n, a.answer?.n]), [[70, 71], [71, 72]]);
    assert.deepEqual(answersSince(makeStore(db, "."), 100, [thread]), expected);
  } finally { store.close(); }
});

test("a scoped read agrees with the whole-station read for mixed card and message histories", () => {
  for (let seed = 1; seed <= 12; seed++) {
    const store = Store.open(":memory:");
    const db = store.db;
    try {
      const thread = store.openThread("ember", "CHAT", `mixed-${seed}`, null, null).id;
      const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
      const card = JSON.stringify({ type: "text" });
      let state = seed;
      const random = (max: number) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % max; };
      db.exec("BEGIN");
      for (let n = 1; n <= 500; n++) {
        const kind = random(5) === 0 ? "edit" : "message";
        const author = random(2) === 0 ? "person" : "agent";
        const withCard = random(3) === 0;
        const legacy = withCard && random(2) === 0;
        const value = withCard && !legacy ? (random(10) === 0 ? "bad-json" : card) : null;
        put.run(thread, n, kind, `${n}`, author, author, `${n}`, random(200), value, legacy ? '["yes"]' : null);
      }
      db.exec("COMMIT");
      const expected = store.answersSince(100).filter((a) => a.question.thread === thread)
        .sort((a, b) => a.question.n - b.question.n);
      assert.deepEqual(answersSince(makeStore(db, "."), 100, [thread]), expected, `history ${seed}`);
    } finally { store.close(); }
  }
});

test("recent answers agree on both sides of the card-history cutoff", () => {
  for (const count of [0, 63, 64, 65, 80]) {
    for (const filler of ["message", "edit"] as const) {
      const store = Store.open(":memory:");
      const db = store.db;
      try {
        const thread = store.openThread("ember", "CHAT", `cutoff-${count}-${filler}`, null, null).id;
        const put = db.prepare("INSERT INTO entries(thread,n,kind,ts,author_kind,author,text,at,card,options) VALUES (?,?,?,?,?,?,?,?,?,?)");
        const card = JSON.stringify({ type: "options", options: [{ label: "yes" }] });
        let n = 0;
        const add = (kind: string, author: string, text: string, at: number, value: string | null = null, options: string | null = null) => {
          n++;
          put.run(thread, n, kind, `${n}`, author, author === "person" ? "p" : "a", text, at, value, options);
          return n;
        };
        for (let i = 0; i < count; i++) add(filler, "agent", "old", 1, card);
        // The first person after a card already answered it before the requested window.
        add("message", "person", "old answer", 50);
        add("message", "person", "late follow-up", 120);
        add("message", "agent", "bad card", 1, "not-json");
        add("message", "person", "bad answer", 110);
        add("message", "agent", "superseded", 1, null, '["yes"]');
        add("message", "agent", "latest", 1, card);
        add("message", "person", "latest answer", 105);
        add("message", "agent", "edited", 1, card);
        add("edit", "agent", "edit", 1, card);
        add("message", "person", "edited answer", 100);
        add("message", "agent", "legacy", 1, null, '["yes"]');
        add("message", "person", "legacy answer", 130);
        const closed = add("message", "agent", "closed", 1, card);
        db.prepare("INSERT INTO closed_cards (thread,n,viewer,at) VALUES (?,?,?,?)").run(thread, closed, "p", 140);
        add("message", "person", "after close", 140);
        const whole = store.answersSince(100).filter((a) => a.question.thread === thread);
        // The whole-station read is ordered by answer time; the scoped read has always followed card order.
        const ordered = [...whole.filter((a) => a.answer !== null).sort((a, b) => a.question.n - b.question.n),
          ...whole.filter((a) => a.answer === null)];
        const scoped = answersSince(makeStore(db, "."), 100, [thread]);
        const pairs = (answers: typeof whole) => answers.map((a) => [a.question.text, a.answer?.text ?? null]);
        assert.deepEqual(pairs(ordered), [["latest", "latest answer"], ["edited", "edited answer"], ["legacy", "legacy answer"], ["closed", null]]);
        assert.deepEqual(scoped, ordered, `${count} prior ${filler} entries`);
      } finally { store.close(); }
    }
  }
});
