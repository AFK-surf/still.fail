// The record of what the connections do (record.ts): its lines' form, and nothing built while it is off.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dialLine, record, recordDht, recording, said, stationTag, type Recording } from "../src/record.ts";

test("a_dial_is_one_line_its_stages_from_its_start", () => {
  assert.equal(
    dialLine({ n: 3, station: "a".repeat(64), via: "relay:euc1-1.relay.still.fail", onto: 12, credential: 40.4, dialled: 812, openBi: 830, sent: 831, total: 850, outcome: "ok" }),
    "#3 aaaaaaaa via=relay:euc1-1.relay.still.fail onto=12ms credential=40ms dialled=812ms openBi=830ms sent=831ms total=850ms -> ok",
  );
  // stages not reached said so
  assert.equal(
    dialLine({ n: 4, station: "b".repeat(64), via: "main", onto: 5, credential: 30, dialled: -1, openBi: -1, sent: -1, total: 10000, outcome: "no-answer" }),
    "#4 bbbbbbbb via=main onto=5ms credential=30ms dialled=- openBi=- sent=- total=10000ms -> no-answer",
  );
});

test("a_station_is_named_by_its_ids_first_8_its_workspaces_first_6_before", () => {
  assert.equal(stationTag("01M65NKSJK5DHHFS26R3JJ46ZH/af9f844d7bcec35052cc"), "01M65N/af9f844d");
  assert.equal(stationTag("af9f844d7bcec35052cc"), "af9f844d");
});

test("a_failure_is_said_on_one_line_at_most_120_long", () => {
  assert.equal(said("timed\n  out"), "timed out");
  assert.equal(said("x".repeat(200)).length, 118);
});

test("off_nothing_is_built", () => {
  const lines: string[] = [];
  let on = false;
  const host: Recording = { recorder: { on: () => on, line: (l) => lines.push(l) } };
  let built = 0;
  record(host, "conn dial", () => (built++, "x"));
  assert.equal(recording(host), false);
  assert.equal(built, 0);
  on = true;
  record(host, "conn dial", () => (built++, "x"));
  assert.deepEqual(lines, ["conn dial: x"]);
  // a host that keeps none
  assert.equal(recording({}), false);
});

test("the_dht_s_lines_recorded_each_with_how_long_before_kept_until_off_and_off_told_once", () => {
  let on = true;
  let now = 10_000;
  const lines: string[] = [];
  const host = { recorder: { on: () => on, line: (l: string) => lines.push(l) }, nowMs: () => now };
  const keeps: boolean[] = [];
  let next: { at: number; text: string }[] = [{ at: 9_988, text: "dht#3 read failed #1: NotConnected, next read in 50ms" }, { at: 9_990, text: "dht#3 lookup d70ccd13 asked" }];
  const dht = {
    dhtSaid: (keep: boolean) => {
      keeps.push(keep);
      const said = { lines: next, dropped: next.length > 0 ? 2 : 0 };
      next = [];
      return said;
    },
  };
  recordDht(host, dht);
  assert.deepEqual(lines, [
    "dht: dht#3 read failed #1: NotConnected, next read in 50ms (12ms before)",
    "dht: dht#3 lookup d70ccd13 asked (10ms before)",
    "dht: 2 line(s) dropped for want of room",
  ]);
  // each station's tick: one take between them within `every`
  now += 1_000;
  recordDht(host, dht, 5_000);
  recordDht(host, dht, 5_000);
  assert.deepEqual(keeps, [true]);
  // back after ten minutes away (nothing taken meanwhile): what the socket said as it came back, at once
  now += 600_000;
  next = [{ at: now - 3, text: "dht#3 read failed #1: NotConnected, next read in 50ms" }];
  recordDht(host, dht);
  assert.equal(lines.at(-2), "dht: dht#3 read failed #1: NotConnected, next read in 50ms (3ms before)");
  // off: told once to keep none
  on = false;
  recordDht(host, dht);
  recordDht(host, dht, 5_000);
  assert.deepEqual(keeps, [true, true, false]);
  // a host whose endpoints look nothing up on the DHT
  recordDht(host, {});
});
