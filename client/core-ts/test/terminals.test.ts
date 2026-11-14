// A station's terminals from the core (src/terminals.ts): what the calls take, the station's frames read as they come
// in pieces, the `terminals` topic made of what the station said. The view's stream end to end is the station's
// tests' (station/test/terminals.test.ts) and the app's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { FrameReader, KIND, frame, parseTerminal } from "../src/terminals.ts";

const station = "w1/s1";

test("a view asks its size, whether it types and takes it, where a new one opens", () => {
  const v = parseTerminal("terminal.view", { station, terminal: "new", view: "v1", cols: 80, rows: 24, taken: true, chat: "c1" });
  assert.deepEqual(v, { kind: "view", station, terminal: "new", view: "v1", ask: { cols: 80, rows: 24, control: true, taken: true, chat: "c1" } });
  assert.deepEqual(parseTerminal("terminal.view", { station, terminal: "term-1", view: "v1", cols: 80, rows: 24, control: false })?.kind, "view");
  assert.throws(() => parseTerminal("terminal.view", { station, terminal: "new", view: "v1", cols: 0, rows: 24 }));
  assert.throws(() => parseTerminal("terminal.view", { station, terminal: "new", view: "v1", cols: 80, rows: 9999 }));
  assert.equal(parseTerminal("terminal.end", { terminal: "term-1" }), null, "an operation's (ops.ts), not a view's");
});

test("what is typed comes as text or as bytes beside the call", () => {
  const typed = parseTerminal("terminal.input", { view: "v1", text: "ls\r" });
  assert.deepEqual(typed?.kind === "input" ? Buffer.from(typed.data).toString() : null, "ls\r");
  const bytes = parseTerminal("terminal.input", { view: "v1" }, new Uint8Array([0x1b, 0x5b, 0x41]));
  assert.deepEqual(bytes?.kind === "input" ? [...bytes.data] : null, [0x1b, 0x5b, 0x41]);
  assert.throws(() => parseTerminal("terminal.input", { view: "v1" }));
  assert.deepEqual(parseTerminal("terminal.resize", { view: "v1", cols: 100, rows: 30 }), { kind: "resize", view: "v1", cols: 100, rows: 30 });
  assert.deepEqual(parseTerminal("terminal.take", { view: "v1" }), { kind: "take", view: "v1" });
});

test("the station's frames are read whole however their bytes come", () => {
  const all = Buffer.concat([frame(KIND.screen, Buffer.from("\x1b[Hscreen")), frame(KIND.out, Buffer.from("more")), frame(KIND.state, Buffer.from('{"types":true}'))]);
  const reader = new FrameReader();
  const got: string[] = [];
  // a byte at a time: every frame cut anywhere
  for (const b of all) {
    reader.push(Uint8Array.of(b));
    for (let f = reader.next(); f !== null; f = reader.next()) got.push(`${f.kind}:${Buffer.from(f.payload).toString()}`);
  }
  assert.deepEqual(got, [`${KIND.screen}:\x1b[Hscreen`, `${KIND.out}:more`, `${KIND.state}:{"types":true}`]);
});
