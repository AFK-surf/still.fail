// The MoonBit builder of the widgets' sources (station/mb, src/widgets) prepares an old thread's messages as
// `widgetSourcesStep` does: the same messages, batch by batch, give the same answers and the same tables.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { WidgetSourcesBuilder } from "../src/read/widget-sources-builder.ts";
import { installWidgetSources, widgetSourcesReady, widgetSourcesStep } from "../src/store/widget-sources.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose messages are from before the widgets' index: a long thread (600 messages, some with
/// files, some with malformed attachments, some letters, and entries that are not messages) and a short one.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-widget-sources-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  const long = store.openThread("ember", "CHAT", "old-long", null, null).id;
  const short = store.openThread("ember", "CHAT", "old-short", null, null).id;
  const put = db.prepare(`INSERT INTO entries(thread, n, kind, author_kind, author, at, attachments, letter)
    VALUES (?, ?, ?, 'agent', 'wanted', ?, ?, ?)`);
  const files = (n: number) => JSON.stringify([{ path: `/w/${n}.html`, name: `${n}.html` }, { path: `/w/${n}.png` }, { name: "no path" }]);
  db.exec("BEGIN");
  for (let n = 1; n <= 600; n++) {
    const attachments = n % 10 === 0 ? files(n) : n % 37 === 0 ? "not json" : n % 41 === 0 ? '["{bad"]' : "[]";
    put.run(long, n, n % 23 === 0 ? "status" : "message", n, attachments, n % 29 === 0 ? "letter" : null);
  }
  put.run(short, 1, "message", 1000, files(1), null);
  db.exec("COMMIT");
  const objects = db.prepare("SELECT type,name FROM sqlite_master WHERE name LIKE 'widget_source_%' AND type IN ('trigger','table')").all() as { type: string; name: string }[];
  for (const type of ["trigger", "table"] as const) for (const object of objects.filter((item) => item.type === type))
    db.exec(`DROP ${type.toUpperCase()} "${object.name.replaceAll('"', '""')}"`);
  installWidgetSources(db);
  return { dir, path, store, long, short, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT thread, n, slot, path, at, name FROM widget_source_rows ORDER BY thread, n, slot"),
    all("SELECT thread, n FROM widget_source_invalid ORDER BY thread, n"),
    all("SELECT thread, last_n, end_n, complete FROM widget_source_scopes ORDER BY thread"),
  ].join("\n");
}

test("the MoonBit builder prepares an old thread's widget sources batch by batch as widgetSourcesStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "widget-sources", "--db", mb.path]);
  try {
    const steps: { thread: number; ts: boolean; mb: boolean }[] = [];
    for (const thread of [mb.short, mb.long, 999]) {
      for (let i = 0; i < 10; i++) {
        const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ thread });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        steps.push({ thread, ts: widgetSourcesStep(ts.store.db, thread).done, mb: ours.done });
        if (ours.done) break;
      }
    }
    assert.ok(steps.filter((s) => s.thread === mb.long).length >= 4, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(tables(mb.store), tables(ts.store));
    assert.ok((mb.store.db.prepare("SELECT count(*) AS n FROM widget_source_rows").get() as { n: number }).n > 100);
    assert.ok((mb.store.db.prepare("SELECT count(*) AS n FROM widget_source_invalid").get() as { n: number }).n > 10);
    for (const thread of [mb.short, mb.long]) assert.equal(widgetSourcesReady(mb.store.db, thread), true);
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's widget source builder finishes what it is asked", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new WidgetSourcesBuilder(f.path, {});
  try {
    await builder.ready([f.long, f.short]);
    assert.equal(widgetSourcesReady(f.store.db, f.long), true);
    assert.equal(widgetSourcesReady(f.store.db, f.short), true);
  } finally {
    await builder.close();
    f.close();
  }
});
