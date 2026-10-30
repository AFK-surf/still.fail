// The record of what the connections do (record.ts): its lines' form, and nothing built while it is off.
import assert from "node:assert/strict";
import { test } from "node:test";
import { dialLine, record, recording, said, stationTag, type Recording } from "../src/record.ts";

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
