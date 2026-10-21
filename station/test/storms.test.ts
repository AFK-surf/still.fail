// Connections trading only packets that carry nothing, thousands a second (src/mesh/storms.ts): said once, closed
// after STORM_SECONDS; a busy one carrying data, or a short burst, is left alone.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Fibers, liveClock } from "../src/ops/fibers.ts";
import { log } from "../src/ops/log.ts";
import type { Connection, Traffic } from "../src/mesh/native.ts";
import { STORM_CODE, STORM_SECONDS, Storms } from "../src/mesh/storms.ts";

/// A part's clock that stands where it is set and never wakes a wait: each second is a `look()` of the test's.
function standing() {
  let now = 1_000_000;
  const clock = { ...liveClock, currentTimeMillisUnsafe: () => now, sleep: () => Effect.never };
  return { fibers: new Fibers("mesh", clock), move: (ms: number) => void (now += ms) };
}

/// A connection whose counts the test moves on; `closed` what closed it.
function connection(withPackets = true) {
  const t: Traffic = withPackets
    ? { rxBytes: 0, txBytes: 0, rxPackets: 0, txPackets: 0, rxPings: 0, txPings: 0, rxAckRequests: 0, txAckRequests: 0, rxAcks: 0, txAcks: 0, rxData: 0, txData: 0 }
    : { rxBytes: 0, txBytes: 0 };
  const state = { closed: null as null | [number, string] };
  const conn = {
    remoteId: () => "ab".repeat(32),
    stats: () => ({ ...t }),
    paths: () => [{ selected: true, ip: "192.168.20.153:43112", rttMs: 9, txPackets: 0, lostPackets: 0 }],
    isClosed: () => state.closed !== null,
    close: (code: number, reason: string) => void (state.closed = [code, reason]),
  } as unknown as Connection;
  /// One second's traffic: `rx` packets in (pings and ACK requests), `tx` out (ACKs), `data` frames of data.
  const second = (rx: number, tx: number, data = 0) => {
    t.rxPackets! += rx;
    t.txPackets! += tx;
    t.rxPings! += rx;
    t.rxAckRequests! += rx;
    t.txAcks! += tx;
    t.rxData! += data;
  };
  return { conn, state, second };
}

function logged() {
  const lines: { msg: string; fields: Record<string, unknown> }[] = [];
  const { warn, info } = log;
  log.warn = (_target: string, msg: string, fields?: Record<string, unknown>) => void lines.push({ msg, fields: fields ?? {} });
  log.info = (_target: string, msg: string, fields?: Record<string, unknown>) => void lines.push({ msg, fields: fields ?? {} });
  return { lines, restore: () => Object.assign(log, { warn, info }) };
}

test("a connection trading only empty packets, thousands a second, is said once and closed after STORM_SECONDS", async () => {
  const { fibers, move } = standing();
  const storms = new Storms(fibers);
  const c = connection();
  storms.watch(c.conn);
  const { lines, restore } = logged();
  try {
    for (let s = 1; s < STORM_SECONDS; s++) {
      c.second(32_000, 16_000);
      move(1000);
      storms.look();
      assert.equal(c.state.closed, null, `still open after ${s} s`);
    }
    const said = lines.filter((l) => /is storming/.test(l.msg));
    assert.equal(said.length, 1, "said once, as it begins");
    assert.equal(said[0]!.fields.rxPackets, 32_000);
    assert.equal(said[0]!.fields.txAcks, 16_000);
    assert.match(String(said[0]!.fields.paths), /\*192\.168\.20\.153:43112 9ms/);
    c.second(32_000, 16_000);
    move(1000);
    storms.look();
    assert.deepEqual(c.state.closed, [STORM_CODE, "storm"]);
    assert.ok(lines.some((l) => /storming connection is closed/.test(l.msg)));
    // Closed: no longer looked at.
    c.second(32_000, 16_000);
    move(1000);
    storms.look();
    assert.equal(lines.filter((l) => /is storming/.test(l.msg)).length, 1);
  } finally {
    restore();
    await fibers.close();
  }
});

test("a busy connection carrying data, a short burst, and an addon without packet counts are left alone", async () => {
  const { fibers, move } = standing();
  const storms = new Storms(fibers);
  const busy = connection();
  const burst = connection();
  const old = connection(false);
  for (const c of [busy, burst, old]) storms.watch(c.conn);
  const { lines, restore } = logged();
  try {
    for (let s = 0; s < STORM_SECONDS * 3; s++) {
      // A screen's frames or a download: thousands of packets, many carrying data.
      busy.second(5000, 2500, 4000);
      // Empty packets for a few seconds at a time, then quiet: never long enough.
      if (s % 8 < STORM_SECONDS / 2) burst.second(5000, 2500);
      else burst.second(10, 5, 2);
      move(1000);
      storms.look();
    }
    assert.equal(busy.state.closed, null);
    assert.equal(burst.state.closed, null);
    assert.equal(old.state.closed, null);
    assert.equal(lines.filter((l) => /is storming/.test(l.msg)).length, 4, "the bursts said, each once");
    assert.ok(lines.some((l) => /storm is over/.test(l.msg)));
  } finally {
    restore();
    await fibers.close();
  }
});
