// Where a device is in a station's log of events (src/station/cursor.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Cursor } from "../src/station/cursor.ts";

test("a_cursor_is_the_furthest_id_heard_of_a_run_written_down_as_it_moves", () => {
  const c = new Cursor();
  assert.equal(c.since, null);
  assert.equal(c.toKeep(), null);
  assert.equal(c.restored, false);
  c.heard("1f2e3d4c.9");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.toKeep(), "1f2e3d4c.9");
  assert.equal(c.toKeep(), null, "as last written");
  // Streams overlap as one takes over: an id below the furthest heard moves nothing; what is no id either.
  c.heard("1f2e3d4c.4");
  c.heard("not an id");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.toKeep(), null);
  // The station started anew: its run's ids, however low.
  c.heard("0a0a0a0a.2");
  assert.equal(c.since, "0a0a0a0a.2");
  assert.equal(c.toKeep(), "0a0a0a0a.2");
});

test("a_cursor_goes_on_from_what_a_core_before_wrote_down", () => {
  const c = new Cursor("1f2e3d4c.9");
  assert.equal(c.since, "1f2e3d4c.9");
  assert.equal(c.restored, true);
  assert.equal(c.toKeep(), null, "written already");
  // Nothing written down, or nothing an id: it starts afresh.
  assert.equal(new Cursor(null).restored, false);
  assert.equal(new Cursor("gibberish").since, null);
});
