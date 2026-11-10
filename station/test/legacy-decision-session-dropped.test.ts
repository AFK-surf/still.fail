import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { overview } from "../src/api/overview.ts";
import { DecisionSessionsUnavailable, decisionSessionIndexStep, decisionSessionRepairStep,
  installDecisionSessionIndex } from "../src/store/legacy-decision-session.ts";
import { decisionTimeIndexStep } from "../src/store/legacy-decision-time.ts";
import { buildLegacyEntryLookups } from "../src/store/legacy-said-builder.ts";
import { Store } from "../src/store/store.ts";

for (const mode of ["native", "shared", "separate"] as const) test(
  `a missing ${mode} session lookup does not scan unrelated decisions`, () => {
    const visits: number[] = [];
    for (const unrelated of [80, 800]) {
      const dir = mkdtempSync(join(tmpdir(), "decision-session-dropped-"));
      const path = join(dir, "station.db"), first = Store.open(path);
      try {
        const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
        put.run("mine", 1, '{"mine":true}');
        for (let n = 0; n < unrelated; n++) put.run("other", 2, '{}');
        if (mode !== "native") first.db.exec("DROP INDEX decision_checks_session");
        if (mode === "shared") first.db.exec("DROP INDEX decision_checks_lately");
      } finally { first.close(); }

      const store = Store.open(path);
      try {
        if (mode === "shared") while (!decisionTimeIndexStep(store.db).done) { /* prepare */ }
        if (mode === "separate") while (!decisionSessionIndexStep(store.db).done) { /* prepare */ }
        store.db.exec(`DROP INDEX ${mode === "native" ? "decision_checks_session"
          : mode === "shared" ? "legacy_decision_time_by_session" : "legacy_decision_session_by_session"}`);
        let visited = 0;
        store.db.function("visit_unindexed_session", (session) => { visited++; return session; });
        const descriptor = Object.getOwnPropertyDescriptor(DatabaseSync.prototype, "prepare")!;
        const wrapped = new Proxy(descriptor.value as DatabaseSync["prepare"], {
          apply(target, receiver, args) {
            if (typeof args[0] === "string" && /^SELECT result FROM decision_checks\b/.test(args[0]))
              args[0] = args[0].replace("session = ?", "visit_unindexed_session(session) = ?");
            return Reflect.apply(target, receiver, args);
          },
        });
        Object.defineProperty(DatabaseSync.prototype, "prepare", { ...descriptor, value: wrapped });
        try {
          try { assert.deepEqual(store.lastDecision("mine"), { mine: true }); }
          catch (error) { if (!(error instanceof DecisionSessionsUnavailable)) throw error; }
        } finally { Object.defineProperty(DatabaseSync.prototype, "prepare", descriptor); }
        visits.push(visited);
      } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
    }
    assert.ok(visits[1]! <= 65 && visits[1]! <= visits[0]! + 2,
      `unrelated source decisions visited: ${visits.join(", ")}`);
  },
);

for (const mode of ["native", "shared", "separate"] as const) test(
  `a removed ${mode} session lookup can be rebuilt after handover`, { timeout: 5000 }, async () => {
    const dir = mkdtempSync(join(tmpdir(), "decision-session-repair-"));
    const path = join(dir, "station.db"), first = Store.open(path);
    try {
      const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
      put.run("mine", 1, '{"original":true}');
      for (let n = 0; n < 130; n++) put.run("other", 2, '{}');
      if (mode !== "native") first.db.exec("DROP INDEX decision_checks_session");
      if (mode === "shared") first.db.exec("DROP INDEX decision_checks_lately");
    } finally { first.close(); }

    const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
    if (mode === "shared") while (!decisionTimeIndexStep(store.db).done) { /* prepare */ }
    if (mode === "separate") while (!decisionSessionIndexStep(store.db).done) { /* prepare */ }
    const oldWrite = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    const previous = Promise.withResolvers<void>();
    const builder = buildLegacyEntryLookups(store, previous.promise);
    store.waitForDecisionSessions = () => builder.waitForDecisionSessions();
    try {
      store.db.exec(`DROP INDEX ${mode === "native" ? "decision_checks_session"
        : mode === "shared" ? "legacy_decision_time_by_session" : "legacy_decision_session_by_session"}`);
      assert.equal(store.decisionSessionsReady(), false);
      assert.throws(() => store.lastDecision("mine"), DecisionSessionsUnavailable);
      let finished = false;
      const waiting = store.prepareDecisionSessions().then(() => { finished = true; });
      await new Promise<void>((resolve) => setImmediate(resolve));
      assert.equal(finished, false, "the old process has not handed over");
      oldWrite.run("mine", 3, '{"later":true}');
      for (let n = 0; n < 65; n++) oldWrite.run("other", 4, '{}');
      previous.resolve();
      await waiting;
      assert.equal(finished, true);
      assert.deepEqual(store.lastDecision("mine"), { later: true });
      assert.equal(store.lastDecision("absent"), null);
    } finally {
      previous.resolve();
      await builder.close();
      old.close();
      store.close();
      rmSync(dir, { recursive: true, force: true });
    }
  },
);

test("an old store reopens when its separate session lookup was removed", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-reopen-"));
  const path = join(dir, "station.db"), first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('other',?,'{}')");
    for (let n = 0; n < 130; n++) put.run(n);
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const old = Store.open(path);
  try {
    while (!decisionSessionIndexStep(old.db).done) { /* prepare */ }
    old.db.exec("DROP INDEX legacy_decision_session_by_session");
  } finally { old.close(); }
  let reopened: Store | null = null;
  try { reopened = Store.open(path); }
  finally { reopened?.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a missing time lookup does not hide a missing session lookup", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
    const put = store.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 100, '{"mine":true}');
    for (let n = 0; n < 130; n++) put.run("other", 100, "{}");
    store.db.exec("DROP INDEX decision_checks_lately; DROP INDEX decision_checks_session");
    // No time or session index is available, so reading every other session is not a bounded fallback.
    assert.throws(() => store.latestDecisionsSince(50, { workspace: "mine", home: false }), DecisionSessionsUnavailable);
  } finally { store.close(); }
});

test("an overview resumes after its session index is removed", { timeout: 5000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-dropped-overview-")), path = join(dir, "station.db");
  const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  const previous = Promise.withResolvers<void>(), requested = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  store.waitForDecisionSessions = () => { requested.resolve(); return builder.waitForDecisionSessions(); };
  const viewer = { sub: "s", email: "p@example.test", name: "P", role: "admin" as const,
    workspace: "mine", device: "d", home: false };
  const accounts: any = { profilesView: () => [], loginsView: () => [], apiProviders: () => [], machineLogins: () => [],
    decisionModels: () => [], automaticDecisionsView: () => ({ recent: [] }) };
  const hub: any = { processes: () => [], config: () => ({ dataDir: dir }) };
  const deps = { store, hub, accounts, cloud: { state: null } as any, config: () => ({ connects: [] }) };
  try {
    store.insertSession({ key: "mine", ws: "mine", connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/work", token: "mine", createdAt: 1, lastActiveAt: 1 });
    const put = old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", Date.now(), '{"result":{"selected":"before"}}');
    for (let n = 0; n < 130; n++) put.run("other", Date.now(), "{}");
    old.exec("DROP INDEX decision_checks_session");
    const first = overview(deps, viewer, "en");
    const second = overview(deps, viewer, "en");
    await requested.promise;
    let finished = false;
    void first.then(() => { finished = true; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(finished, false);
    put.run("mine", Date.now(), '{"result":{"selected":"landed"}}');
    for (let n = 0; n < 65; n++) put.run("other", Date.now(), "{}");
    previous.resolve();
    for (const result of await Promise.all([first, second]) as any[]) {
      assert.equal(result.automaticDecisions.policy.checked, 1);
      assert.equal(result.automaticDecisions.policy.options.find((option: any) => option.id === "landed").count, 1);
    }
  } finally {
    previous.resolve(); await builder.close(); old.close(); store.close(); rmSync(dir, { recursive: true, force: true });
  }
});

test("a failed handover settles a later repair request", { timeout: 3000 }, async () => {
  const store = Store.open(":memory:"), previous = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const put = store.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('other',?,'{}')");
    for (let n = 0; n < 130; n++) put.run(n);
    previous.reject(new Error("handover failed"));
    await new Promise<void>((resolve) => setImmediate(resolve));
    store.db.exec("DROP INDEX decision_checks_session");
    const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error("repair kept waiting after handover failed")), 1000); });
    assert.equal(await Promise.race([builder.waitForDecisionSessions(), timeout]), false);
  } finally {
    if (timer) clearTimeout(timer);
    await builder.close(); store.close();
  }
});

test("a session lookup can be repaired after its repair index is removed", { timeout: 5000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-repair-again-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 1, '{"mine":true}');
    for (let n = 0; n < 130; n++) put.run("other", 2, "{}");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path);
  while (!decisionSessionIndexStep(store.db).done) { /* prepare */ }
  const builder = buildLegacyEntryLookups(store, Promise.resolve());
  store.waitForDecisionSessions = () => builder.waitForDecisionSessions();
  try {
    store.db.exec("DROP INDEX legacy_decision_session_by_session");
    await store.prepareDecisionSessions();
    assert.deepEqual(store.lastDecision("mine"), { mine: true });
    store.db.exec("DROP INDEX legacy_decision_session_repair_by_session");
    assert.equal(store.decisionSessionsReady(), false);
    await store.prepareDecisionSessions();
    assert.deepEqual(store.lastDecision("mine"), { mine: true });
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a repair index can be cleaned in bounded batches, rolled back and resumed after reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-clean-reopen-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 1, '{"first":true}');
    for (let n = 0; n < 130; n++) put.run("other", 2, "{}");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  let store = Store.open(path);
  const old = new DatabaseSync(path, { timeout: 5000 });
  try {
    while (!decisionSessionIndexStep(store.db).done) { /* prepare */ }
    store.db.exec("DROP INDEX legacy_decision_session_by_session");
    installDecisionSessionIndex(store.db);
    while (!decisionSessionRepairStep(store.db).done) { /* prepare */ }
    store.db.exec("DROP INDEX legacy_decision_session_repair_by_session");
    installDecisionSessionIndex(store.db);
    assert.equal(store.db.prepare("SELECT complete FROM legacy_decision_session_repair_meta").get()?.complete, 2);
    store.db.exec(`CREATE TRIGGER repair_test_abort BEFORE DELETE ON legacy_decision_session_repair
      BEGIN SELECT RAISE(ABORT, 'injected'); END`);
    assert.throws(() => decisionSessionRepairStep(store.db, 7), /injected/);
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM legacy_decision_session_repair").get()?.n, 131);
    store.db.exec("DROP TRIGGER repair_test_abort");
    assert.deepEqual(decisionSessionRepairStep(store.db, 7), { done: false, visited: 7 });
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM legacy_decision_session_repair").get()?.n, 124);
    old.prepare("UPDATE decision_checks SET session='mine',result=? WHERE id=2").run('{"changed":true}');
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('mine',3,?)").run('{"during":true}');
    store.close();
    store = Store.open(path);
    assert.equal(store.decisionSessionsReady(), false);
    let steps = 0;
    while (store.db.prepare("SELECT complete FROM legacy_decision_session_repair_meta").get()?.complete === 2) {
      const step = decisionSessionRepairStep(store.db, 7);
      assert.ok(step.visited <= 7);
      assert.ok(++steps < 100);
    }
    old.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES('mine',4,?)").run('{"after":true}');
    let step;
    do {
      step = decisionSessionRepairStep(store.db, 7);
      assert.ok(step.visited <= 7);
      assert.ok(++steps < 100);
    } while (!step.done);
    assert.deepEqual(store.lastDecision("mine"), { after: true });
    assert.deepEqual(
      store.db.prepare("SELECT id,session FROM legacy_decision_session_repair ORDER BY id").all(),
      store.db.prepare("SELECT id,session FROM decision_checks ORDER BY id").all(),
    );
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a waiting reader recovers if its session index is removed during handover", { timeout: 5000 }, async () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-drop-waiting-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 1, '{"mine":true}');
    for (let n = 0; n < 130; n++) put.run("other", 2, "{}");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path), previous = Promise.withResolvers<void>();
  const builder = buildLegacyEntryLookups(store, previous.promise);
  store.waitForDecisionSessions = () => builder.waitForDecisionSessions();
  try {
    const waiting = store.prepareDecisionSessions();
    void waiting.catch(() => {});
    store.db.exec("DROP INDEX legacy_decision_session_by_session");
    // The next wait probe must discover that the in-progress lookup has disappeared.
    const deadline = Date.now() + 2000;
    while (!store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='legacy_decision_session_repair_by_session'").get()) {
      if (Date.now() > deadline) throw new Error("the missing lookup was not repaired while the reader waited");
      await new Promise<void>((resolve) => setTimeout(resolve, 25));
    }
    previous.resolve();
    await waiting;
    assert.deepEqual(store.lastDecision("mine"), { mine: true });
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a reader sees a replacement finished by another opener after its snapshot ends", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-replacement-snapshot-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 1, '{"mine":true}');
    for (let n = 0; n < 130; n++) put.run("other", 2, "{}");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const store = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  try {
    store.db.exec("BEGIN");
    assert.equal(store.decisionSessionsReady(), false);
    old.exec("DROP INDEX legacy_decision_session_by_session");
    installDecisionSessionIndex(old);
    while (!decisionSessionRepairStep(old).done) { /* the other opener prepares the replacement */ }
    assert.equal(store.decisionSessionsReady(), false);
    assert.throws(() => store.lastDecision("mine"), DecisionSessionsUnavailable);
    store.db.exec("COMMIT");
    // No extra readiness call tells this connection that the new lookup was published.
    assert.deepEqual(store.lastDecision("mine"), { mine: true });
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a reader keeps its old snapshot while a removed repair index is rebuilt", () => {
  const dir = mkdtempSync(join(tmpdir(), "decision-session-repair-snapshot-")), path = join(dir, "station.db");
  const first = Store.open(path);
  try {
    const put = first.db.prepare("INSERT INTO decision_checks(session,created_at,result) VALUES(?,?,?)");
    put.run("mine", 1, '{"before":true}');
    for (let n = 0; n < 130; n++) put.run("other", 2, "{}");
    first.db.exec("DROP INDEX decision_checks_session");
  } finally { first.close(); }
  const setup = Store.open(path);
  try {
    while (!decisionSessionIndexStep(setup.db).done) { /* prepare */ }
    setup.db.exec("DROP INDEX legacy_decision_session_by_session");
    installDecisionSessionIndex(setup.db);
    while (!decisionSessionRepairStep(setup.db).done) { /* prepare repair */ }
  } finally { setup.close(); }
  const reader = Store.open(path), old = new DatabaseSync(path, { timeout: 5000 });
  try {
    reader.db.exec("BEGIN");
    assert.deepEqual(reader.lastDecision("mine"), { before: true });
    old.exec("DROP INDEX legacy_decision_session_repair_by_session");
    installDecisionSessionIndex(old);
    old.prepare("UPDATE decision_checks SET result=? WHERE id=1").run('{"after":true}');
    while (!decisionSessionRepairStep(old, 7).done) { /* clean and prepare again */ }
    assert.deepEqual(reader.lastDecision("mine"), { before: true });
    reader.db.exec("COMMIT");
    assert.deepEqual(reader.lastDecision("mine"), { after: true });
  } finally { old.close(); reader.close(); rmSync(dir, { recursive: true, force: true }); }
});
