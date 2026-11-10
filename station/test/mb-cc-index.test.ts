// The MoonBit builder of the sessions' copy destinations, chat names and latest conversations (station/mb, src/cc)
// prepares them as `CcIndexPreparation`, `SessionChatPreparation` and `prepareLatestThreadStep` do: the same old
// memberships, slice by slice, give the same answers and the same tables, also when a shared chat changes and its
// change is distributed to every session in it.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { CcIndexBuilder } from "../src/read/cc-index-builder.ts";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { CcIndexPreparation, ccSessionReady, installCcIndex } from "../src/store/cc-thread-index.ts";
import { latestThreadReady, prepareLatestThreadStep } from "../src/store/latest-thread-index.ts";
import { SessionChatPreparation, sessionChatReady } from "../src/store/session-chat-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// Old memberships: a session in 300 chats, another in 4 (two of them shared with the first), one in none; messages
/// in some chats, one of them internal.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-cc-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const key of ["long", "short", "none"]) store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
    workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
  const thread = db.prepare("INSERT INTO threads(surface,channel,thread_ts,created_at) VALUES(?,'C',?,?)");
  const member = db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES(?,?,'slack',?)");
  const say = db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,1,'message','person','me','x',?)");
  const threads: number[] = [];
  db.exec("BEGIN");
  for (let n = 0; n < 300; n++) {
    const id = Number(thread.run(n === 7 ? "stillfail" : "slack:one", `long-${n}`, n).lastInsertRowid);
    member.run(id, "long", n);
    if (n % 3 === 0) say.run(id, 1000 + n);
    if (n === 5 || n === 9) member.run(id, "short", n);
    threads.push(id);
  }
  for (let n = 0; n < 2; n++) member.run(Number(thread.run("slack:two", `short-${n}`, 500 + n).lastInsertRowid), "short", 500 + n);
  db.exec("COMMIT");
  installCcIndex(db);
  return { dir, path, store, threads, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT session, scan_after, scan_end, complete FROM cc_sessions ORDER BY session"),
    all("SELECT * FROM cc_session_rows ORDER BY session, thread"),
    all("SELECT session, thread FROM cc_session_dirty ORDER BY session, thread"),
    all("SELECT thread, after_session, through_session FROM cc_order_dispatch ORDER BY thread"),
    all("SELECT * FROM cc_order_turn"),
    all("SELECT * FROM session_chat_scopes ORDER BY session"),
    all("SELECT * FROM session_chat_rows ORDER BY session, thread"),
    all("SELECT * FROM latest_thread_scopes ORDER BY session"),
    all("SELECT * FROM latest_thread_rows ORDER BY session, member_rowid"),
    all("SELECT * FROM latest_thread_members ORDER BY thread, session"),
  ].join("\n");
}

test("the MoonBit builder prepares destinations, names and latest conversations as the TypeScript does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "cc-index", "--db", mb.path]);
  const cc = new CcIndexPreparation(), names = new SessionChatPreparation();
  const ask = async (message: { session: string; name?: true; latest?: true }) => {
    const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
    builder.postMessage(message);
    const ours = await answered;
    assert.equal(ours.error, undefined);
    const options = { existingSession: true };
    const theirs = message.latest ? prepareLatestThreadStep(ts.store.db, message.session, 64, options).done
      : message.name ? names.step(ts.store.db, message.session, 64, options).done : cc.step(ts.store.db, message.session).done;
    return { mb: ours.done, ts: theirs };
  };
  const finish = async (message: { session: string; name?: true; latest?: true }, steps: { mb: boolean; ts: boolean }[]) => {
    for (let i = 0; i < 40; i++) { const s = await ask(message); steps.push(s); if (s.mb) return; }
    assert.fail(`not done: ${JSON.stringify(message)}`);
  };
  try {
    const steps: { mb: boolean; ts: boolean }[] = [];
    for (const session of ["short", "long", "none", "gone"]) await finish({ session }, steps);
    assert.equal(tables(mb.store), tables(ts.store), "after the destinations");
    // a shared chat gets a message and the long session leaves a chat: distributed, then settled
    for (const f of [ts, mb]) {
      f.store.db.prepare("INSERT INTO entries(thread,n,kind,author_kind,author,text,at) VALUES(?,2,'message','person','me','y',9999)").run(f.threads[5]);
      f.store.db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='long'").run(f.threads[12]);
    }
    for (const session of ["short", "long"]) await finish({ session }, steps);
    for (const session of ["short", "long"]) await finish({ session, name: true }, steps);
    for (const session of ["short", "long", "gone"]) await finish({ session, latest: true }, steps);
    assert.ok(steps.length >= 20, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(tables(mb.store), tables(ts.store), "after the change and the names and latest conversations");
    for (const session of ["short", "long"]) {
      assert.equal(ccSessionReady(mb.store.db, session), true);
      assert.equal(sessionChatReady(mb.store.db, session), true);
      assert.equal(latestThreadReady(mb.store.db, session), true);
    }
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("the station's copy destination builder prepares what it is asked through the MoonBit builder", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const builder = new CcIndexBuilder(f.path, {});
  try {
    await builder.ready(["long", "short"]);
    await builder.readyNames(["long"]);
    await builder.readyLatest(["short"]);
    assert.equal(ccSessionReady(f.store.db, "long"), true);
    assert.equal(sessionChatReady(f.store.db, "long"), true);
    assert.equal(latestThreadReady(f.store.db, "short"), true);
  } finally {
    await builder.close();
    f.close();
  }
});
