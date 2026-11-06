import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { IrohStream } from "../src/iroh.ts";
import { Lines } from "../src/mesh.ts";
import { utf8 } from "../src/util.ts";
import { run } from "./run.ts";

function stream(chunks: Uint8Array[]): IrohStream {
  return {
    read: () => Effect.sync(() => chunks.shift() ?? null),
    write: () => Effect.void,
    finish: () => Effect.void,
    stopped: () => Effect.succeed(null),
    reset: () => {},
  };
}

test("line size is bounded for whole and fragmented reads", async () => {
  const long = utf8(`${"a".repeat(64 * 1024 + 1)}\n`);
  for (const chunks of [[long], [long.slice(0, 4096), long.slice(4096, -1), long.slice(-1)]]) {
    await assert.rejects(run(new Lines(stream(chunks)).next()), { code: "mesh" });
  }
});

test("a longer permitted line preserves subsequent lines and the body", async () => {
  const value = "你".repeat(30_000), bytes = utf8(`${value}\nnext\nbody`);
  const chunks: Uint8Array[] = [];
  for (let i = 0; i < bytes.length; i += 8192) chunks.push(bytes.slice(i, i + 8192));
  const lines = new Lines(stream(chunks));
  assert.equal(await run(lines.next(bytes.length)), value);
  assert.equal(await run(lines.next()), "next");
  assert.equal(new TextDecoder().decode(lines.carry), "body");
});
