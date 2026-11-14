// Only what newly happens while a chat is watched comes in (a message's `said`, attend.ts): one its station's stream
// told as it happened while the chat showed here. What a resumed stream tells again of what came meanwhile (its link
// came back, a core started again from where the one before kept it) was said before it was shown, and is caught up on;
// so is what came while the chat was out of view. The station's clock ahead of the device's or behind it changes none
// of it (link.ts, `stillfail-head`).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Core } from "../src/core.ts";
import { HostWire } from "../src/station/wire.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, entry, started } from "./station-fixture.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const S = "ws/st";
const RUN = "abcdef";

async function watched(skew: number) {
  const s = await started(base(), 0, undefined, (f) => {
    f.gate.marks = true;
    f.gate.resumes = true;
  });
  let core: Core = s.core;
  // A message made now by the station's clock (`skew` from the device's), at its place `n` in the station's log.
  const said = (seq: number, n: number) => s.push("thread", { id: 7, entries: [{ ...entry(seq, `m${seq}`), at: s.host.nowMs() + skew }] }, `${RUN}.${n}`);
  let values = new Map();
  let ui = 0;
  const open = async () => {
    ui = core.connect();
    values = new Map();
    subscribe(core, ui, 1, { topic: "chat", station: S, thread: 7, session: null });
    call(core, ui, 2, "client.focus", { visible: true, focused: true, chat: { station: S, thread: 7 } });
    await s.host.time.pass(500, 10);
  };
  const shown = async () => {
    await s.host.time.pass(500, 10);
    apply(s.host, values);
    const messages: J[] = v(values, 1).messages;
    return { seqs: messages.map((m) => m.seq), said: messages.filter((m) => m.said === true).map((m) => m.seq) };
  };
  try {
    await open();
    assert.deepEqual((await shown()).said, [], "what it held as it opened is not said");

    // (a) Told live while it shows.
    said(4, 10);
    assert.deepEqual(await shown(), { seqs: [1, 2, 3, 4], said: [4] }, "(a) told live");

    // (b) Its link drops while it shows; 5 and 6 are said meanwhile, told again as the stream resumes; 7 after.
    s.end();
    s.gate.head = `${RUN}.12`;
    await s.host.time.pass(3_000, 50);
    assert.ok(s.streams.at(-1)!.path.includes(`since=${RUN}.10`), s.streams.at(-1)!.path);
    said(5, 11);
    said(6, 12);
    said(7, 13);
    assert.deepEqual(await shown(), { seqs: [1, 2, 3, 4, 5, 6, 7], said: [4, 7] }, "(b) told again on resuming: caught up on");

    // Out of view (the app away) and back: what came meanwhile is not said; what comes after is.
    call(core, ui, 3, "client.focus", { visible: false, focused: false });
    said(8, 14);
    await s.host.time.pass(500, 10);
    call(core, ui, 4, "client.focus", { visible: true, focused: true });
    assert.deepEqual((await shown()).said, [], "what came while it was out of view");
    said(9, 15);
    assert.deepEqual((await shown()).said, [9], "told live after it came back into view");

    // (c) The core started again, where its stream was kept; 10 and 11 said meanwhile, told again as it resumes.
    await run(core.inner.data.written);
    assert.equal(core.inner.data.record("heard", S), `${RUN}.15`);
    core.close();
    await s.host.settle();
    s.gate.head = `${RUN}.17`;
    core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
    await open();
    assert.ok(s.streams.at(-1)!.path.includes(`since=${RUN}.15`), s.streams.at(-1)!.path);
    said(10, 16);
    said(11, 17);
    assert.deepEqual(await shown(), { seqs: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], said: [] }, "(c) told again after a restart: none said");
    said(12, 18);
    assert.deepEqual((await shown()).said, [12], "(c) told live after it");
  } finally {
    core.close();
    s.core.close();
  }
}

test("a_message_told_live_while_its_chat_shows_comes_in_one_told_again_as_the_stream_resumes_does_not", () => watched(0));
// (d) The station's clock minutes ahead of the device's, and behind it.
test("the_station_clock_ahead_changes_nothing_of_what_comes_in", () => watched(5 * 60_000));
test("the_station_clock_behind_changes_nothing_of_what_comes_in", () => watched(-5 * 60_000));
