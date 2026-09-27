import assert from "node:assert/strict";
import { createServer } from "node:http";
import { test } from "node:test";
import { listen, PortTaken } from "../src/ports.ts";

test("a usual port taken by something else gives way to a free one; a port the config names does not", async () => {
  const other = createServer();
  const taken = await listen(other, "127.0.0.1", 0, false, "x");
  const station = createServer();
  const got = await listen(station, "127.0.0.1", taken, false, "管理页");
  assert.notEqual(got, taken);
  assert.ok(got > 0);
  await assert.rejects(listen(createServer(), "127.0.0.1", taken, true, "管理页"), (e) => e instanceof PortTaken && /已被别的程序占用/.test(e.message));
  // Free, the usual one is used as it is.
  const free = createServer();
  const port = await listen(free, "127.0.0.1", 0, false, "x");
  await new Promise((r) => free.close(r));
  const again = createServer();
  assert.equal(await listen(again, "127.0.0.1", port, false, "x"), port);
  for (const s of [other, station, again]) s.close();
});
