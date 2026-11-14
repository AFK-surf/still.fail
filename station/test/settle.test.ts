// What a hub test waits with (hub-fakes.ts `settle`): the loop's queued work and the disk's answers it waits on.
import assert from "node:assert/strict";
import { stat } from "node:fs/promises";
import { test } from "node:test";
import { settle } from "./hub-fakes.ts";

test("settle waits for the disk: file requests one after another, more of them than its turns, are all answered", async () => {
  // Each is asked as the one before is answered, a turn of the loop at least apart: 300 cannot be done in 100 turns.
  let answered = 0;
  const chain = (async () => {
    for (let i = 0; i < 300; i++) {
      await stat(import.meta.dirname);
      answered++;
    }
  })();
  await settle();
  assert.equal(answered, 300);
  await chain;
});

test("settle with nothing out is its turns of the loop, no more", async () => {
  let turns = 0;
  let going = true;
  const count = () => {
    if (!going) return;
    turns++;
    setImmediate(count);
  };
  setImmediate(count);
  await settle(7);
  going = false;
  assert.equal(turns, 7);
});
