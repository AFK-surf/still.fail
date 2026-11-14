// A session's history read by the MoonBit reader (station/mb src/history's transcripts.mbt, src/readops/timeline.mbt;
// read/pool.ts HISTORY) as the worker reads it, on the same transcripts: `timeline` (pages before, after, between, in
// brief, in both languages, with every kind of number) and `transcriptState`; of a long Claude Code transcript with a
// line still being written, a history across a runtime change into Codex's code mode, one put away in segments, one put
// away before there were segments, one not written yet, none recorded. Each reads on from the other's marks on disk,
// as a transcript grows and as one is written anew, and what each writes there is what the other writes.
import assert from "node:assert/strict";
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { zstdCompressSync } from "node:zlib";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { seekTable } from "../src/read/packed.ts";
import { Readers } from "../src/read/pool.ts";
import { MARK_EVERY } from "../src/read/tail.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();
const at = "2026-10-24T00:00:00Z";
const said = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: at, message: { id, content: [{ type: "text", text }] } })}\n`;
const thought = (text: string, id: string) => `${JSON.stringify({ type: "assistant", timestamp: at, message: { id, content: [{ type: "thinking", thinking: text }] } })}\n`;
const call = (id: string, name: string, input: object) => `${JSON.stringify({ type: "assistant", timestamp: at, message: { id, content: [{ type: "tool_use", id, name, input }] } })}\n`;
const answer = (id: string, content: string, isError = false) => `${JSON.stringify({ type: "user", timestamp: at, message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content, is_error: isError }] } })}\n`;
const person = (text: string) => `${JSON.stringify({ type: "user", timestamp: at, message: { role: "user", content: text } })}\n`;
const item = (payload: object) => `${JSON.stringify({ type: "response_item", timestamp: at, payload })}\n`;

/// A long Claude Code transcript: calls and their answers (long, a post's, a failure), thoughts, words, a person, lines
/// that are no record; marks fall inside it.
function claudeLines(n: number, tag: string): string[] {
  const lines: string[] = [];
  for (let i = 0; i < n; i++) {
    const k = i % 9;
    if (k === 0) lines.push(call(`${tag}c${i}`, "Bash", { command: `echo ${"x".repeat(i % 700)}`, description: `Step ${i}` }));
    else if (k === 1) lines.push(answer(`${tag}c${i - 1}`, `out ${i} ${"y".repeat((i * 31) % 1500)}`, i % 4 === 1));
    else if (k === 2) lines.push(call(`${tag}p${i}`, "mcp__stillfail__chat_post", { to: "CHAT/1", text: `post ${i} ${"z".repeat(800)}` }));
    else if (k === 3) lines.push(answer(`${tag}p${i - 1}`, JSON.stringify({ ok: true, ts: `${i}.1`, extra: "w".repeat(900) })));
    else if (k === 4) lines.push(thought(`Thinking about it\n\n**Plan** ${i}\n${"t".repeat((i * 7) % 900)}`, `${tag}t${i}`));
    else if (k === 5) lines.push(person(`please ${i} 中文 ${"é".repeat(i % 50)}`));
    else if (k === 6) lines.push("not json at all\n", "\n", "{\"type\":\"progress\"}\r\n");
    else lines.push(said(`${i} ${"s".repeat((i * 37) % 3000)}`, `${tag}m${i}`));
  }
  return lines;
}

/// Codex's code mode: scripts that are only calls, scripts that do more (their calls answered by the script's output,
/// in the words of the language asked), plain calls and their output.
function codexLines(n: number): string[] {
  const lines = [`${JSON.stringify({ type: "session_meta", timestamp: at, payload: { id: "x-new" } })}\n`];
  for (let i = 0; i < n; i++) {
    lines.push(item({ type: "message", role: "assistant", content: [{ type: "output_text", text: `codex ${i}` }] }));
    lines.push(item({ type: "custom_tool_call", name: "exec", call_id: `s${i}`, input: `const a = await tools.exec_command({"cmd":"ls ${i}"}); const b = await tools.exec_command({"cmd":"pwd"}); console.log(a, b)` }));
    if (i % 3 !== 2) lines.push(item({ type: "custom_tool_call_output", call_id: `s${i}`, output: i % 2 ? "done" : "x\nProcess exited with code 2" }));
    lines.push(item({ type: "function_call", name: "shell", call_id: `f${i}`, arguments: JSON.stringify({ command: ["ls", `${i}`] }) }));
    lines.push(item({ type: "function_call_output", call_id: `f${i}`, output: `a b ${i}` }));
  }
  return lines;
}

/// A transcript put away in segments as the station puts one away (read/packed.ts), each ending at a line's end.
function packInSegments(path: string, lines: string[], segments: number) {
  const per = Math.ceil(lines.length / segments);
  const frames: { packed: number; size: number }[] = [];
  const bodies: Buffer[] = [];
  for (let i = 0; i < lines.length; i += per) {
    const raw = Buffer.from(lines.slice(i, i + per).join(""));
    const packed = zstdCompressSync(raw);
    bodies.push(packed);
    frames.push({ packed: packed.length, size: raw.length });
  }
  writeFileSync(`${path}.zst`, Buffer.concat([...bodies, seekTable(frames)]));
}

const put = (path: string, text: string) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };

test("the MoonBit reader reads a session's history as the worker does", { skip: binary === null ? "the MoonBit program is not built here" : false }, async () => {
  const data = mkdtempSync(join(tmpdir(), "mb-reader-timeline-"));
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  writeFileSync(join(data, "config.json"), JSON.stringify({ profiles: [{ id: "own", home: "homes/own" }] }));
  const session = (key: string, runtime: string, current: string | null, workspace: string) => {
    store.insertSession({ key, connect: "ember", runtime, profile: "own", workspace, token: key, createdAt: 1, lastActiveAt: 1, ws: null } as Parameters<Store["insertSession"]>[0]);
    if (current !== null) store.setRuntimeSessionId(key, current);
  };
  const claude = (slug: string, id: string) => join(data, "transcripts", "claude", slug, `${id}.jsonl`);
  // long: marks every MARK_EVERY entries, its last line still being written
  session("long", "claude", "c1", "/w/long");
  store.ranIn("long", "c1", "own");
  const long = claude("-w-long", "c1");
  // (and a stretch of outputs so long that a mark falls by MARK_BYTES before MARK_EVERY entries)
  const big = Array.from({ length: 60 }, (_, i) => [call(`b${i}`, "Bash", { command: "cat big" }), answer(`b${i}`, "B".repeat(30_000 + i))]).flat();
  const longLines = [...claudeLines(MARK_EVERY + 40, "l"), ...big, ...claudeLines(MARK_EVERY * 4, "m")];
  put(long, longLines.join("") + said("half", "h").slice(0, 30));
  // chain: a Claude Code runtime session, then Codex's
  session("chain", "claude", "c-old", "/w/chain");
  store.ranIn("chain", "c-old", "own");
  put(claude("-w-chain", "c-old"), claudeLines(40, "o").join(""));
  store.db.prepare("UPDATE sessions SET runtime = 'codex' WHERE key = 'chain'").run();
  store.setRuntimeSessionId("chain", "x-new");
  store.ranIn("chain", "x-new", "own");
  const rollout = join(data, "homes", "own", "sessions", "2026", "11", "09", "rollout-2026-11-09T00-00-00-x-new.jsonl");
  put(rollout, codexLines(120).join(""));
  // packed: put away in three segments; old: put away whole before there were segments
  session("packed", "claude", "c2", "/w/packed");
  store.ranIn("packed", "c2", "own");
  const packed = claude("-w-packed", "c2");
  mkdirSync(dirname(packed), { recursive: true });
  packInSegments(packed, claudeLines(MARK_EVERY * 2 + 90, "k"), 3);
  session("old", "claude", "c3", "/w/old");
  store.ranIn("old", "c3", "own");
  const old = claude("-w-old", "c3");
  mkdirSync(dirname(old), { recursive: true });
  writeFileSync(`${old}.zst`, zstdCompressSync(Buffer.from(claudeLines(MARK_EVERY + 30, "d").join(""))));
  // not written yet; none recorded
  session("unwritten", "claude", "c4", "/w/u");
  store.ranIn("unwritten", "c4", "own");
  session("fresh", "claude", null, "/w/f");
  // back: gone back to the runtime session it ran in first, which is read last
  session("back", "claude", "c5", "/w/back");
  store.ranIn("back", "c5", "own");
  put(claude("-w-back", "c5"), claudeLines(20, "f").join(""));
  store.setRuntimeSessionId("back", "c6");
  store.ranIn("back", "c6", "own");
  put(claude("-w-back", "c6"), claudeLines(25, "s").join(""));
  store.setRuntimeSessionId("back", "c5");
  const keys = ["long", "chain", "packed", "old", "unwritten", "fresh", "back", "missing"];

  const open: Readers[] = [];
  const readers = (mb: boolean) => {
    const r = new Readers(data, 1);
    open.push(r);
    r.mbReader = mb ? binary : null;
    return r;
  };
  const read = (r: Readers, op: string, args: unknown, lang: "zh" | "en" = "zh") => r.read(op, args, lang).then((t) => JSON.parse(t), (e: Error & { status?: number }) => ({ error: e.message, status: e.status }));
  const all = async (r: Readers) => {
    const out: unknown[] = [];
    for (const key of keys) {
      out.push(await read(r, "transcriptState", { key }));
      for (const lang of ["zh", "en", undefined] as const) {
        const pages: Record<string, unknown>[] = [
          {}, { before: "50", limit: "10" }, { before: "900", limit: "300", brief: "1" }, { limit: "0" }, { limit: "5000" }, { before: "1200", limit: "5000" }, { after: "0", limit: "5000" }, { before: "+12", limit: "007" },
          { before: "99999999999999999999999" }, { before: "abc", limit: "-3" }, { after: "0", limit: "5" }, { after: "260", brief: "1" },
          { after: "1000000" }, { from: "0", to: "9" }, { from: "250", to: "270", brief: "1" }, { from: "5", to: "2000" }, { from: "20" },
          { from: "40", to: "3" }, { from: "18446744073709551615", to: "18446744073709551615" }, { before: 5 }, { limit: 5 },
        ];
        for (const p of pages) out.push(await read(r, "timeline", { key, lang, ...p }, lang ?? "zh"));
      }
    }
    return out;
  };
  const marks = join(data, "transcript-marks");
  const kept = () => Object.fromEntries(readdirSync(marks).sort().map((f) => [f, JSON.parse(readFileSync(join(marks, f), "utf8"))]));
  const both = async (label: string) => {
    // each read first with nothing on disk, then the other going on from what it wrote there, in a reader of its own
    rmSync(marks, { recursive: true, force: true });
    const [w, p] = [readers(false), readers(true)];
    try {
      const worker = await all(w);
      const workerKept = kept();
      const fromWorker = await all(p);
      assert.deepEqual(fromWorker, worker, `${label}: the program from the worker's marks`);
      rmSync(marks, { recursive: true, force: true });
      const [p2, w2] = [readers(true), readers(false)];
      try {
        const program = await all(p2);
        assert.deepEqual(program, worker, `${label}: the program from nothing`);
        assert.deepEqual(kept(), workerKept, `${label}: what each keeps on disk`);
        assert.deepEqual(await all(w2), worker, `${label}: the worker from the program's marks`);
      } finally {
        p2.close(); w2.close();
      }
      return { w, p, worker };
    } catch (error) {
      w.close(); p.close();
      throw error;
    }
  };
  try {
    const first = await both("as written");
    const sign = JSON.stringify(first.worker);
    for (const s of ["\"brief\":true", "（结果在脚本的输出里）", "(Result is in the script output)", "codex 119", "post 2 ", "unknown session missing", "\"partial\":\"", "\"states\":null"])
      assert.ok(sign.includes(s), s);
    // Grown, the same readers going on from what they keep in memory: the line half written ends, more come.
    appendFileSync(long, said("half", "h").slice(30) + claudeLines(MARK_EVERY + 5, "g").join(""));
    appendFileSync(rollout, codexLines(7).join(""));
    assert.deepEqual(await all(first.p), await all(first.w), "grown");
    // Written anew, shorter, with more entries than a mark's worth: read again from its start, marked anew.
    writeFileSync(long, Array.from({ length: MARK_EVERY * 2 + 9 }, (_, i) => said(`n${i}`, `n${i}`)).join(""));
    assert.deepEqual(await all(first.p), await all(first.w), "written anew");
    first.w.close(); first.p.close();
    const again = await both("written anew");
    again.w.close(); again.p.close();
    // What a transcript has is what it was counted to have: a reader that starts again goes on from what is on disk,
    // not from a start read again (a line changed where it was, its length kept, is not read again).
    rmSync(marks, { recursive: true, force: true });
    const counted = readers(false);
    try {
      await all(counted);
      const text = readFileSync(long, "utf8");
      const first = text.slice(0, text.indexOf("\n"));
      writeFileSync(long, `${"x".repeat(Buffer.byteLength(first))}${text.slice(first.length)}`);
      const later = readers(true);
      try {
        assert.deepEqual(await all(later), await all(counted), "gone on from the marks on disk");
      } finally {
        later.close();
      }
    } finally {
      counted.close();
    }
  } finally {
    // (every reader, whatever failed: one left open keeps the test from ending)
    for (const r of open) r.close();
    store.close();
    rmSync(data, { recursive: true, force: true });
  }
});
