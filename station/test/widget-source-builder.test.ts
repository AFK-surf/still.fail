import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { test } from "node:test";
import { WidgetSourcesBuilder } from "../src/read/widget-sources-builder.ts";
import { installWidgetSources, widgetSourcesReady, widgetSourcesStep } from "../src/store/widget-sources.ts";
import { Store } from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function oldThreads(store: Store): [number, number] {
  const db = store.db;
  const first = store.openThread("ember", "CHAT", "old-first", null, null).id;
  const second = store.openThread("ember", "CHAT", "old-second", null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,author_kind,author,at,attachments)
    VALUES(?,?,'message','agent','wanted',?,?)`);
  const files = (name: string) => JSON.stringify([{ path: "/w/pick.html", name }]);
  db.exec("BEGIN");
  put.run(first, 1, 1, files("first.html"));
  for (let n = 2; n <= 513; n++) put.run(first, n, n, "[]");
  put.run(second, 1, 1000, files("second.html"));
  db.exec("COMMIT");
  const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'widget_source_%' AND type IN ('trigger','table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type))
    db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
  installWidgetSources(db);
  return [first, second];
}

test("widget source preparation waits for handover and lets a short thread finish first", async () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-sources-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = new WidgetSourcesBuilder(path, { previousGone: previous.promise });
  try {
    const [long, short] = oldThreads(store);
    let longReady = false;
    const one = builder.ready([long]).then(() => { longReady = true; });
    const two = builder.ready([short]);
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(widgetSourcesReady(store.db, short), false);
    assert.equal(store.db.prepare("SELECT count(*) AS n FROM widget_source_scopes").get()?.n, 0);
    previous.resolve();
    await two;
    assert.equal(widgetSourcesReady(store.db, short), true);
    assert.equal(longReady, false);
    await one;
    assert.equal(widgetSourcesReady(store.db, long), true);
  } finally { previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("cancelling one widget source request leaves another waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-sources-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const previous = Promise.withResolvers<void>(), cancel = new AbortController();
  const builder = new WidgetSourcesBuilder(path, { previousGone: previous.promise });
  try {
    const [thread] = oldThreads(store);
    const stopped = builder.ready([thread], cancel.signal);
    const kept = builder.ready([thread]);
    cancel.abort();
    await assert.rejects(stopped, /read cancelled/);
    previous.resolve();
    await kept;
    assert.equal(widgetSourcesReady(store.db, thread), true);
  } finally { cancel.abort(); previous.resolve(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a stopped widget source worker resumes the requested thread", async () => {
  const dir = mkdtempSync(join(tmpdir(), "widget-worker-"));
  const path = join(dir, "stillfail.db"), store = Store.open(path);
  const file = join(dir, "worker.mjs"), marker = join(dir, "exited");
  const real = new URL("../src/read/widget-sources-worker.ts", import.meta.url).href;
  writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
  const builder = new WidgetSourcesBuilder(path, {}, pathToFileURL(file));
  try {
    const [, thread] = oldThreads(store);
    await builder.ready([thread]);
    assert.ok(existsSync(marker));
    assert.equal(widgetSourcesReady(store.db, thread), true);
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("delivery prepares old widget sources again if membership changes while it waits", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "wanted", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "wanted", createdAt: 1, lastActiveAt: 1 });
    const [first, second] = oldThreads(rig.store);
    rig.store.joinThread(first, "wanted", "ember");
    rig.store.putWidgetState("wanted", "/w/pick.html", "{}", "blue");
    const calls: number[][] = [];
    rig.hub.prepareWidgetSources = async (threads) => {
      calls.push([...threads]);
      if (calls.length === 1) rig.store.joinThread(second, "wanted", "ember");
      for (const thread of threads) while (!widgetSourcesStep(rig.store.db, thread).done) {}
    };
    const actor = rig.hub.actor(rig.session("wanted"));
    const [text, widgets] = await (actor as any).format([]) as [string, [string, string][]];
    assert.deepEqual(calls, [[first], [second]]);
    assert.ok(text.includes("second.html"));
    assert.deepEqual(widgets, [["/w/pick.html", "blue"]]);
  } finally { await rig.close(); }
});

test("a failed widget preparation leaves the model untold", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "wanted", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "wanted", createdAt: 1, lastActiveAt: 1 });
    const [thread] = oldThreads(rig.store);
    rig.store.joinThread(thread, "wanted", "ember");
    rig.store.putWidgetState("wanted", "/w/pick.html", "{}", "blue");
    rig.hub.prepareWidgetSources = async () => { throw new Error("preparation failed"); };
    const actor = rig.hub.actor(rig.session("wanted"));
    await assert.rejects((actor as any).format([]), /preparation failed/);
    assert.equal(rig.store.db.prepare("SELECT told_at FROM widget_states WHERE session='wanted'").get()?.told_at, null);
  } finally { await rig.close(); }
});
