// Catching up after the app was away (station/sync.ts `#catching`): the chats' list says it is syncing while a station
// has yet to say what changed, then how many chats are left to bring the latest of, and nothing once all is here.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Core } from "../src/core.ts";
import { t } from "../src/i18n.ts";
import type { HttpResponse } from "../src/host.ts";
import { HostWire } from "../src/station/wire.ts";
import { jsonResponse } from "../src/testing.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, entries, started, stationLater, threadView } from "./station-fixture.ts";

/// The station read once with its chat at 120, the app let go, the chat said on to 125 meanwhile.
async function away() {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  answers["GET /chats"] = [{ id: "7", session: "k1", thread: 7, title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null }];
  const first = await started(answers);
  await run(first.core.inner.data.written);
  first.core.close();
  answers["GET /threads"] = [threadView(7, 125, 120, 5)];
  // (its history read a request a read: each as the station takes its time with it, `stationLater`)
  first.batches.on = false;
  return first;
}

const said = (url: string) => {
  const query = /\/threads\/7\/entries\?(.*)$/.exec(url)?.[1];
  if (query === undefined) return null;
  const q = new URLSearchParams(query);
  const from = q.has("after") ? Number(q.get("after")) + 1 : Number(q.get("from") ?? 76);
  return entries(from, Number(q.get("to") ?? 125));
};

test("the_chats_say_they_are_syncing_until_what_came_while_away_is_here", async () => {
  const { host } = await away();
  const asked: (() => void)[] = [];
  // (its chats' summaries answered once let go)
  const lists = host.hold("/admin/api/changed/threads");
  stationLater(host, (req) => {
    const brought = said(req.url);
    if (brought === null) return undefined;
    return new Promise<HttpResponse>((answer) => asked.push(() => answer(jsonResponse(200, { last: 125, entries: brought }))));
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  try {
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chats", scope: "ws", mine: false });
    await host.time.pass(500, 10);
    apply(host, values);
    // What changed not known yet: syncing, with no count.
    assert.equal(v(values, 1).days.length, 1, "the chats held show meanwhile");
    assert.equal(v(values, 1).syncing, t("core-views.station.syncing"));
    // Known: one chat left.
    lists();
    await host.time.pass(500, 10);
    apply(host, values);
    assert.equal(v(values, 1).syncing, t("core-views.station.syncing_left", { n: 1 }));
    // Its latest here: nothing to say.
    while (asked.length > 0) {
      for (const answer of asked.splice(0)) answer();
      await host.time.pass(200, 10);
    }
    apply(host, values);
    assert.equal(core.inner.data.logSpan("entry", "ws/st", "7")?.max, 125);
    assert.equal(v(values, 1).syncing ?? null, null);
  } finally {
    core.close();
  }
});

test("a_chat_whose_latest_cannot_be_brought_now_is_not_waited_on", async () => {
  const { host } = await away();
  stationLater(host, (req) => (said(req.url) === null ? undefined : Promise.resolve(jsonResponse(403, { error: "no" }))));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  try {
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chats", scope: "ws", mine: false });
    await host.time.pass(2000, 10);
    apply(host, values);
    assert.equal(core.inner.data.logSpan("entry", "ws/st", "7")?.max, 120, "still behind");
    assert.equal(v(values, 1).syncing ?? null, null);
  } finally {
    core.close();
  }
});

test("a_station_whose_stream_went_is_not_said_to_be_syncing_until_it_is_back", async () => {
  const s = await away();
  const asked: (() => void)[] = [];
  stationLater(s.host, (req) => {
    const brought = said(req.url);
    if (brought === null) return undefined;
    return new Promise<HttpResponse>((answer) => asked.push(() => answer(jsonResponse(200, { last: 125, entries: brought }))));
  });
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
  try {
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chats", scope: "ws", mine: false });
    await s.host.time.pass(500, 10);
    apply(s.host, values);
    assert.equal(v(values, 1).syncing, t("core-views.station.syncing_left", { n: 1 }));
    // Its stream gone: the list says it is coming back (`trouble`), not that it syncs.
    s.end();
    await s.host.time.pass(100, 10);
    apply(s.host, values);
    assert.equal(v(values, 1).syncing ?? null, null);
    // Back, and read afresh: still one left, until it is here.
    await s.host.time.pass(2500, 50);
    apply(s.host, values);
    assert.equal(v(values, 1).syncing, t("core-views.station.syncing_left", { n: 1 }));
    while (asked.length > 0) {
      for (const answer of asked.splice(0)) answer();
      await s.host.time.pass(200, 10);
    }
    apply(s.host, values);
    assert.equal(v(values, 1).syncing ?? null, null);
  } finally {
    core.close();
  }
});
