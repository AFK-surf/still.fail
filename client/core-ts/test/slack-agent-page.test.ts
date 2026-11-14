import assert from "node:assert/strict";
import { test } from "node:test";
import type { HttpResponse } from "../src/host.ts";
import { jsonResponse } from "../src/testing.ts";
import { apply, subscribe, v } from "./helpers.ts";
import { base, session, started, stationLater } from "./station-fixture.ts";

// An agent that has only been in Slack (no chat of its own here): its page is what it heard and said there, read from
// its history. Opened on a device that holds none of that history, behind a station's many other agents whose
// histories the sync brings in the background: its own history comes first, and till it is here the page is not said
// to be empty.
test("a_slack_agents_page_brings_its_history_first_and_is_not_empty_meanwhile", async () => {
  const answers = base();
  const others = Array.from({ length: 60 }, (_, i) => `o${i}`);
  answers["GET /sessions"] = [...others.map((k) => ({ ...session(k), lastActiveAt: 1000 })), session("k1")];
  for (const k of others) answers[`GET /sessions/${k}`] = { session: session(k), threads: [], turns: [], jobs: [] };
  const prompt = `<message via="slack" connect="c1" you="Bot (<@UB>)" thread="C1/100.0" from="Ann (U1)" ts="100.0">\nhello there\n</message>`;
  const items = [{ at: "2026-11-11T08:00:00.000Z", kind: "user", text: prompt }];
  answers["GET /threads"] = [];
  // Every history but k1's waits, as a station far away answers a long sweep: k1's is answered once asked.
  const asked: string[] = [];
  const s = await started(answers, 0, undefined, (f) => {
    f.batches.on = false;
    stationLater(f.host, (req) => {
      const m = /\/sessions\/([^/?]+)\/timeline/.exec(req.url);
      if (m === null) return undefined;
      asked.push(m[1]!);
      if (m[1] === "k1") return Promise.resolve(jsonResponse(200, { start: 0, entries: items }));
      return new Promise<HttpResponse>(() => {});
    });
  });
  try {
    const ui = s.core.connect();
    const values = new Map();
    subscribe(s.core, ui, 2, { topic: "chat", station: "ws/st", session: "k1" });
    await s.host.time.pass(100, 10);
    apply(s.host, values);
    const shown = v(values, 2);
    assert.ok(asked.includes("k1"), `its history asked, before the others' answered (asked: ${asked.join(",")})`);
    assert.deepEqual(shown?.elsewhere?.map((e: { text: string }) => e.text), ["hello there"]);
  } finally { s.core.close(); }
});
