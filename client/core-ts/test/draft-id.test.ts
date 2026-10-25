// A draft's own name (DraftView.id): the core gives it, keeps it with the draft across restarts, and gives another
// once the draft is sent or put back empty; what goes up from a draft is named by it (the station gives back an upload
// it finished within the hour by its id), so the same file in the next message, or in another new chat, is another.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { SOON_MS } from "../src/data.ts";
import { HostWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { answers, call, signIn } from "./helpers.ts";

async function setup() {
  const host = new FakeHost();
  signIn(host);
  host.onFetch((request) => {
    const path = new URL(request.url).pathname;
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: null });
    // Both stations belong to this account: normal retention must keep their drafts across restarts.
    if (path === "/v1/workspaces/ws") return jsonResponse(200, {
      id: "ws",
      stations: ["st", "other"].map((id) => ({ id, name: id, online: false, last_seen: null })),
    });
    return jsonResponse(404, { error: "not_found" });
  });
  const open = () => Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  let core = await open();
  await host.time.pass(500);
  let ui = core.connect();
  let id = 0;
  return {
    get core() { return core; },
    async ask(name: "draft.get" | "draft.put", params: unknown) {
      const at = ++id;
      call(core, ui, at, name, params);
      await host.settle();
      const answer = answers(host.takeEmitted(), at);
      assert.ok(answer && "ok" in answer, `${name} did not succeed: ${JSON.stringify(answer)}`);
      return answer.ok as any;
    },
    async restart() {
      await host.time.pass(SOON_MS + 50);
      await host.settle();
      await Effect.runPromise(core.inner.data.written);
      core.close();
      host.takeEmitted();
      core = await open();
      ui = core.connect();
    },
    close() { core.close(); },
  };
}

const draft = { text: "写到一半", quotes: [], files: [{ name: "a.png", path: "/u/a.png", size: 3 }] };
const blank = { text: "", quotes: [], files: [] };

test("a_draft_has_a_name_from_the_core_kept_with_it_across_a_restart", async () => {
  const t = await setup();
  try {
    const first = (await t.ask("draft.get", { key: "ws/st:ember:a" })).id;
    // the core's name for it: `draft-` and hex (never sent up as it is: the app hashes it into an upload's id)
    assert.match(first, /^draft-[0-9a-f]+$/);
    assert.match(first, /^[A-Za-z0-9_-]{8,64}$/);
    // written to: the same draft, whatever the page says its name is
    assert.equal((await t.ask("draft.put", { key: "ws/st:ember:a", ...draft })).id, first);
    assert.equal((await t.ask("draft.put", { key: "ws/st:ember:a", ...draft, text: "再写一点", id: "not-its-name" })).id, first);
    await t.restart();
    assert.equal((await t.ask("draft.get", { key: "ws/st:ember:a" })).id, first);
  } finally { t.close(); }
});

test("sent_or_put_back_empty_the_next_draft_is_another", async () => {
  const t = await setup();
  try {
    const first = (await t.ask("draft.put", { key: "ws/st:ember:a", ...draft })).id;
    // the page sent it and emptied it
    const next = (await t.ask("draft.put", { key: "ws/st:ember:a", ...blank })).id;
    assert.notEqual(next, first);
    assert.equal((await t.ask("draft.get", { key: "ws/st:ember:a" })).id, next);
    // written to again: still the next one
    assert.equal((await t.ask("draft.put", { key: "ws/st:ember:a", ...draft })).id, next);
    // a new chat's, sent (its chat made), then another new chat on the same station: another draft
    const fresh = (await t.ask("draft.put", { key: "new:ws", ...draft })).id;
    const after = (await t.ask("draft.put", { key: "new:ws", ...blank })).id;
    assert.notEqual(after, fresh);
    // another chat's draft is another draft
    assert.notEqual((await t.ask("draft.get", { key: "ws/st:ember:b" })).id, next);
  } finally { t.close(); }
});

test("taken_to_send_the_next_is_another_and_put_back_it_is_the_one_taken", async () => {
  const t = await setup();
  try {
    const key = "ws/st:ember:a";
    const first = (await t.ask("draft.put", { key, ...draft })).id;
    const composers = t.core.inner.composers;
    composers.take(key);
    const next = (await t.ask("draft.get", { key })).id;
    assert.notEqual(next, first);
    composers.restore(key, "没发出去", false);
    assert.equal((await t.ask("draft.get", { key })).id, first);
  } finally { t.close(); }
});
