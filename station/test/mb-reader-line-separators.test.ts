// A chat's text with U+2028 or U+2029 in it, read by the MoonBit reader as the worker reads it. The program's answer
// is its head line and then its text's bytes, as many as the head says (mb-reader.ts `Said`): the text is never in a
// line, and a line ends at its newline alone. Before (2026-11-14), the answer was a line read by node:readline, which
// ends a line at either separator too: one that held one was cut in two and that read was never answered.
// The program's own output is read first, up to the body's end: it answers either way, so a body cut short or a head
// that says no length fails the test there instead of leaving the read below waiting for good.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { test } from "node:test";
import { Said, mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// What the program says for `ask`, its head and its body, read off its stdout as bytes.
async function programAnswer(binary: string, data: string, ask: object): Promise<{ head: string; body: Buffer }> {
  const child = spawn(binary, ["--data", data, "--sep", sep], { stdio: ["pipe", "pipe", "inherit"] });
  const chunks: Buffer[] = [];
  child.stdin.write(`${JSON.stringify(ask)}\n`);
  let answer: { head: string; body: Buffer } | null = null;
  for await (const chunk of child.stdout) {
    chunks.push(chunk as Buffer);
    const all = Buffer.concat(chunks);
    const first = all.indexOf(10), second = all.indexOf(10, first + 1);
    if (second < 0) continue;
    const head = all.subarray(first + 1, second).toString();
    const bytes = (JSON.parse(head) as { bytes?: number }).bytes;
    assert.equal(typeof bytes, "number", `the answer's head says no length: ${head.slice(0, 200)}`);
    if (all.length - second - 1 < bytes!) continue;
    answer = { head, body: all.subarray(second + 1, second + 1 + bytes!) };
    break;
  }
  child.stdin.end();
  if (child.exitCode === null) { child.kill(); await once(child, "close"); }
  assert.ok(answer !== null, "the program ended before its answer was whole");
  return answer;
}

test("a chat's text with a line or paragraph separator is read by the MoonBit reader as by the worker", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-line-separators-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const thread = store.openThread("ember", "CHAT", "c", "Line separated", null).id;
  const texts = ["one\u2028two", "para\u2029graph", "both \u2028\u2029 and \\u2028 written out", "plain"];
  texts.forEach((text, i) => store.insertMessage({ ...newMessage(thread, String(i + 1), "person", "p@x", text), at: (i + 1) * 10 } as ReturnType<typeof newMessage>));
  const worker = new Readers(data, 1);
  worker.mbReader = null;
  const program = new Readers(data, 1);
  program.mbReader = binary;
  try {
    const said = await programAnswer(binary!, data, { id: 1, op: "latestMessages", args: { thread, limit: 10 }, lang: "en", names: [], processes: [], clientKeys: [] });
    assert.equal((JSON.parse(said.head) as { id: number }).id, 1);
    assert.ok(said.body.toString().includes("one\u2028two"), "the body is the text's own bytes");
    const [theirs, ours] = [await worker.read("latestMessages", { thread, limit: 10 }, "en"), await program.read("latestMessages", { thread, limit: 10 }, "en")];
    assert.deepEqual(JSON.parse(ours), JSON.parse(theirs));
    for (const text of texts) assert.ok(JSON.stringify(JSON.parse(ours)).includes(JSON.stringify(text).slice(1, -1)), text);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});

test("a program's output is told a line at a time, a body after the line that says its length, however it comes in pieces", () => {
  const told: unknown[] = [];
  const body = Buffer.from('{"t":"a\u2028b\nc 中"}');
  const all = Buffer.concat([
    Buffer.from('{"ready":{}}\n\n{"id":1,"bytes":' + body.length + "}\n"), body,
    Buffer.from('{"id":2,"bytes":0}\n{"id":3,"text":"x\u2028y"}\n'),
  ]);
  // each way of cutting it in two, and a byte at a time
  for (let cut = 0; cut <= all.length; cut++) {
    told.length = 0;
    const said = new Said((s) => told.push(s));
    said.push(all.subarray(0, cut));
    said.push(all.subarray(cut));
    assert.deepEqual(told, [{ ready: {} }, { id: 1, body }, { id: 2, body: Buffer.alloc(0) }, { id: 3, text: "x\u2028y" }], `cut at ${cut}`);
  }
  told.length = 0;
  const said = new Said((s) => told.push(s));
  for (let i = 0; i < all.length; i++) said.push(all.subarray(i, i + 1));
  assert.equal(told.length, 4);
});
