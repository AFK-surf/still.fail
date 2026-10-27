// What still.fail uses of a station's machine (the `stationResources` topic, station/sync.ts `resourcesWatch`): told by
// the station as it looks, on a stream of its own, while shown and a page of the app is in view; asked again and again
// of a station from before.
import assert from "node:assert/strict";
import { test } from "node:test";
import { RESOURCES_EVERY_MS } from "../src/station/sync.ts";
import { apply, call, subscribe } from "./helpers.ts";
import { base, started } from "./station-fixture.ts";

const S = "ws/st";
const asks = (s: Awaited<ReturnType<typeof started>>) => s.host.requests.filter((r) => r.url.endsWith("/admin/api/resources")).length;

test("resources_are_told_on_one_stream_while_shown_and_none_is_held_while_no_page_is_in_view", async () => {
  const s = await started(base(), 0, undefined, (s) => s.told.set("/resources", { queues: new Set(), asked: 0 }));
  const feed = s.told.get("/resources")!;
  const ui = s.core.connect();
  const values = new Map<number, unknown>();
  subscribe(s.core, ui, 1, { topic: "stationResources", station: S });
  await s.host.time.pass(100, 10);
  assert.equal(feed.asked, 1);
  s.tell("/resources", "resources", { at: 1, groups: [] });
  await s.host.time.pass(100, 10);
  apply(s.host, values);
  assert.deepEqual(values.get(1), { at: 1, groups: [] });
  // (a station telling tells each look, every few seconds: quiet for longer, it is taken for gone)
  s.tell("/resources", "resources", { at: 2, groups: [] });
  await s.host.time.pass(3 * RESOURCES_EVERY_MS, 100);
  apply(s.host, values);
  assert.deepEqual(values.get(1), { at: 2, groups: [] });
  assert.equal(feed.asked, 1, "one stream, not asked again");
  // no page in view: the stream let go, nothing asked meanwhile; in view again, followed again
  call(s.core, ui, 2, "client.focus", { visible: false });
  await s.host.time.pass(100, 10);
  assert.equal(feed.queues.size, 0);
  await s.host.time.pass(10 * RESOURCES_EVERY_MS, 100);
  assert.equal(feed.asked, 1);
  call(s.core, ui, 3, "client.focus", { visible: true });
  await s.host.time.pass(RESOURCES_EVERY_MS + 100, 100);
  assert.equal(feed.asked, 2);
  assert.equal(feed.queues.size, 1);
  await s.core.close();
});

test("a_station_from_before_answers_resources_whole_and_is_asked_again_every_few_seconds_while_shown", async () => {
  const s = await started({ ...base(), "GET /resources": { at: 1, groups: [] } });
  const ui = s.core.connect();
  const values = new Map<number, unknown>();
  subscribe(s.core, ui, 1, { topic: "stationResources", station: S });
  await s.host.time.pass(100, 10);
  apply(s.host, values);
  assert.deepEqual(values.get(1), { at: 1, groups: [] });
  const first = asks(s);
  await s.host.time.pass(3 * RESOURCES_EVERY_MS, 100);
  assert.equal(asks(s) - first, 3);
  await s.core.close();
});
