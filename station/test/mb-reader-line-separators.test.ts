// A chat's text with U+2028 or U+2029 in it, read by the MoonBit reader as the worker reads it: node:readline, which
// the station reads the program's lines with, ends a line at either, so the program says them escaped
// (station/mb src/host `say`). Before, the answer that held one was cut in two and that read was never answered.
// The program's own line is read first, up to its newline: it answers either way, so a separator said raw fails the
// test there instead of leaving the read below waiting for good.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { test } from "node:test";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { Readers } from "../src/read/pool.ts";
import { Store, newMessage } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// The program's lines up to its `count`th newline, as bytes: what node:readline would cut further is left whole.
async function programLines(binary: string, data: string, ask: object, count: number): Promise<string[]> {
  const child = spawn(binary, ["--data", data, "--sep", sep], { stdio: ["pipe", "pipe", "inherit"] });
  const chunks: Buffer[] = [];
  child.stdin.write(`${JSON.stringify(ask)}\n`);
  for await (const chunk of child.stdout) {
    chunks.push(chunk as Buffer);
    if (Buffer.concat(chunks).toString("utf8").split("\n").length > count) break;
  }
  child.stdin.end();
  if (child.exitCode === null) { child.kill(); await once(child, "close"); }
  return Buffer.concat(chunks).toString("utf8").split("\n").slice(0, count);
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
    const [, said] = await programLines(binary!, data, { id: 1, op: "latestMessages", args: { thread, limit: 10 }, lang: "en", names: [], processes: [], clientKeys: [] }, 2);
    assert.ok(!said.includes("\u2028") && !said.includes("\u2029"), "the program said a line or paragraph separator raw, which node:readline ends a line at");
    assert.equal((JSON.parse(said) as { id: number }).id, 1);
    const [theirs, ours] = [await worker.read("latestMessages", { thread, limit: 10 }, "en"), await program.read("latestMessages", { thread, limit: 10 }, "en")];
    assert.deepEqual(JSON.parse(ours), JSON.parse(theirs));
    for (const text of texts) assert.ok(JSON.stringify(JSON.parse(ours)).includes(JSON.stringify(text).slice(1, -1)), text);
  } finally {
    worker.close(); program.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
