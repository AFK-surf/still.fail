// A folder of the drive shown, kept as it is on the station's disk: the station tells each change on a stream
// (GET /drive/watch as events), and the folder is read again then, never on a timer; a stream opened again reads it
// for what changed meanwhile.
import assert from "node:assert/strict";
import { test } from "node:test";
import { STREAM_IDLE_MS } from "../src/station/link.ts";
import { subscribe } from "./helpers.ts";
import { started, stationReplies } from "./station-fixture.ts";

const ST = "ws/st";
const ROOT = "/Users/a/Movies";
const WATCH = `/drive/watch?root=${encodeURIComponent(ROOT)}&path=`;

test("a shown folder is read again as its station tells it changed, and not while nothing changes", async () => {
  const s = await started(undefined, 0, undefined, (s) => s.told.set(WATCH, { queues: new Set(), asked: 0 }));
  stationReplies(s.host, (req) => (req.url.includes("/admin/api/drive/list?") ? { path: "", entries: [], truncated: false } : undefined));
  const lists = () => s.host.requests.filter((r) => r.url.includes("/admin/api/drive/list?")).length;
  const feed = s.told.get(WATCH)!;
  subscribe(s.core, s.core.connect(), 1, { topic: "drive", station: ST, root: ROOT, path: "" });
  await s.host.time.pass(100, 10);
  assert.equal(feed.asked, 1);
  assert.equal(lists(), 1, "read as it is shown");
  // (within the station's own stream's idle time: past it, this fixture's quiet station is linked afresh, and what is
  // shown read with it)
  await s.host.time.pass(STREAM_IDLE_MS - 1_000, 1_000);
  assert.equal(lists(), 1, "nothing read while nothing changes");
  assert.equal(feed.asked, 1, "one stream");
  s.tell(WATCH, "changed", {});
  await s.host.time.pass(100, 10);
  assert.equal(lists(), 2, "read again as it changed");
  await s.core.close();
});
