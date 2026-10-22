import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect } from "effect";
import { Core } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { started } from "./station-fixture.ts";

/// A draft as written, without the name the core gives it (its own test: draft-id.test.ts).
const noId = ({ id: _, ...d }: any) => d;

type J = any;

async function setup() {
  const t = await started();
  const ui = t.core.connect();
  const values = new Map<number, unknown>();
  const pending = t.core.inner.views.local.pendingNew("ws/st", {});
  const old = `ws/st:${pending}`;
  const key = "ws/st:ember:made";
  const settle = async () => { await t.host.time.pass(60); await t.host.settle(); apply(t.host, values); };
  const watch = async (id: number, draft: string) => { subscribe(t.core, ui, id, { topic: "composer", key: draft }); await settle(); };
  return { ...t, values, pending, old, key, settle, watch, composer: t.core.inner.composers,
    made: () => t.core.inner.views.local.pendingMade(pending, "ember:made", 9) };
}

test("late_aliases_join_live_edits_and_a_sent_draft_does_not_return_after_restart", async () => {
  const t = await setup();
  try {
    await t.watch(1, t.old);
    await t.watch(2, t.key);
    t.composer.text(t.old, "earlier draft");
    t.composer.text(t.key, "latest draft");
    t.composer.error(t.key, "keep this state");
    t.composer.starting(t.key, true);
    await t.host.time.pass(400);
    await t.settle();
    const rev = v(t.values, 2).rev;
    t.made();
    await t.settle();
    for (const sub of [1, 2]) {
      assert.equal(v(t.values, sub).text, "latest draft");
      assert.equal(v(t.values, sub).error, "keep this state");
      assert.equal(v(t.values, sub).starting, true);
      assert.ok(v(t.values, sub).rev > rev);
    }
    assert.equal(t.composer.take(t.key).text, "latest draft");
    await t.host.time.pass(400);
    await Effect.runPromise(t.core.inner.data.written);
    t.core.close();
    const again = await Core.create(t.host, { clock: t.host.time.clock, sample: 0, wire: () => new HostWire(t.host) });
    try {
      for (const key of [t.old, t.key]) assert.equal((again.inner.composers.value(key) as J).text, "");
    } finally { again.close(); }
  } finally { t.core.close(); }
});

test("a_late_empty_alias_subscription_is_told_of_the_existing_draft", async () => {
  const t = await setup();
  try {
    await t.watch(1, t.old);
    t.composer.text(t.old, "already written");
    await t.watch(2, t.key);
    assert.equal(v(t.values, 2).text, "");
    t.made();
    await t.settle();
    assert.equal(v(t.values, 1).text, "already written");
    assert.equal(v(t.values, 2).text, "already written");
  } finally { t.core.close(); }
});

test("upload_progress_does_not_outrank_a_later_edit_on_the_other_name", async () => {
  const t = await setup();
  const gate = Deferred.makeUnsafe<J, CoreError>();
  (t.core.inner.stations.requests as J).uploadName = () => Promise.resolve(null);
  (t.core.inner.stations.requests as J).uploadPart = () => Deferred.await(gate);
  try {
    t.composer.add(t.old, "ws/st", [{ id: "slow", name: "a.txt", size: 1, blob: new Blob(["a"]) }]);
    t.composer.text(t.key, "latest text");
    Deferred.doneUnsafe(gate, Effect.succeed({ have: 1, file: { name: "a.txt", size: 1, path: "/u/a.txt" } }));
    await t.settle();
    assert.equal((t.composer.value(t.old) as J).files[0].done.path, "/u/a.txt");
    t.made();
    assert.equal((t.composer.value(t.old) as J).text, "latest text");
    assert.equal((t.composer.value(t.key) as J).text, "latest text");
  } finally { t.core.close(); }
});

test("a_send_before_the_alias_is_known_can_still_restore_its_taken_draft", async () => {
  const t = await setup();
  try {
    t.composer.text(t.old, "earlier draft");
    t.composer.text(t.key, "sent draft");
    t.composer.take(t.key);
    t.made();
    assert.equal((t.composer.value(t.old) as J).text, "");
    t.composer.restore(t.old, "failed", false);
    assert.equal((t.composer.value(t.key) as J).text, "sent draft");
    assert.equal((t.composer.value(t.key) as J).error, "failed");
  } finally { t.core.close(); }
});

test("pending_aliases_and_cached_composers_do_not_cross_account_databases", async () => {
  const t = await setup();
  try {
    t.made();
    t.composer.text(t.old, "account A's draft");
    assert.equal((t.composer.value(t.key) as J).text, "account A's draft");
    await t.host.time.pass(400);
    await Effect.runPromise(t.core.inner.data.written);
    // Account A signs out; another account reaches the same workspace on this device.
    await Effect.runPromise(t.core.inner.data.accounts(["s2"]));
    t.core.inner.workspaces.setOwners(new Map([["ws", "s2"]]));
    assert.equal(t.core.inner.views.local.pendingKey("ws/st", "ember:made"), undefined);
    assert.equal(t.core.inner.views.local.pendingKey("ws/st", t.pending), undefined);
    for (const key of [t.key, t.old]) assert.equal((t.composer.value(key) as J).text, "");
    t.composer.text(t.key, "account B's draft");
    assert.equal((t.composer.value(t.old) as J).text, "");
    assert.equal((t.composer.value(t.key) as J).text, "account B's draft");
  } finally { t.core.close(); }
});

test("draft_snapshots_clear_whitespace_but_keep_quotes_or_uploaded_files_without_text", async () => {
  const t = await setup();
  try {
    const blank = { text: "", quotes: [], files: [] };
    t.composer.putDraft("ws/st", "new", { text: "  " });
    assert.deepEqual(noId(t.composer.readDraft("ws/st", "new")), blank);
    assert.equal((t.composer.value("new:ws/st") as J).text, "");
    const quote = { author: "agent", text: "quoted", comment: "" };
    t.composer.putDraft("ws/st", "new", { quotes: [quote] });
    assert.deepEqual(noId(t.composer.readDraft("ws/st", "new")), { ...blank, quotes: [quote] });
    const file = { name: "a.txt", path: "/u/a.txt", size: 1 };
    t.composer.putDraft("ws/st", "new", { files: [file] });
    assert.deepEqual(noId(t.composer.readDraft("ws/st", "new")), { ...blank, files: [file] });
  } finally { t.core.close(); }
});
