// A text/event-stream split into events as chunks arrive (src/station/sse.ts), however the stream is cut.
import assert from "node:assert/strict";
import { test } from "node:test";
import { SseParser } from "../src/station/sse.ts";

const bytes = (s: string) => new TextEncoder().encode(s);

/// The events of `stream` fed in chunks cut at `cuts` (byte offsets, ascending).
function fed(stream: Uint8Array, cuts: number[]): [string, string, string?][] {
  const p = new SseParser();
  const out: [string, string, string?][] = [];
  let at = 0;
  for (const c of [...cuts, stream.length]) {
    out.push(...p.feed(stream.subarray(at, c)));
    at = c;
  }
  return out;
}

const STREAM =
  'event: entry\nid: 1f2e.1\ndata: {"text":"整理发布清单"}\n\n' +
  "data: one\ndata: two\n\n" +
  "id: 1f2e.2\n\n" +
  ': a comment\nevent: state\r\ndata:{"busy":true}\r\n\r\n' +
  'event: entry\nid: 1f2e.3\ndata: {"text":"' + "长".repeat(3000) + '"}\n\n';

const WANT: [string, string, string?][] = [
  ["entry", '{"text":"整理发布清单"}', "1f2e.1"],
  ["message", "one\ntwo"],
  ["", "", "1f2e.2"],
  ["state", '{"busy":true}'],
  ["entry", '{"text":"' + "长".repeat(3000) + '"}', "1f2e.3"],
];

test("a_stream_in_one_chunk_is_its_events_in_order", () => {
  assert.deepEqual(fed(bytes(STREAM), []), WANT);
});

test("a_stream_cut_anywhere_is_the_same_events_a_byte_at_a_time_too", () => {
  const s = bytes(STREAM);
  assert.deepEqual(fed(s, Array.from({ length: s.length - 1 }, (_, i) => i + 1)), WANT);
  // between the two newlines that end a block, and inside a character of three bytes
  const blank = s.indexOf(10, s.indexOf(10) + 1);
  for (let at = 1; at < s.length; at += 7) assert.deepEqual(fed(s, [at]), WANT, `cut at ${at}`);
  assert.deepEqual(fed(s, [blank + 1]), WANT);
});

test("a_stream_cut_at_random_is_the_same_events_as_it_grows_past_the_buffer", () => {
  const s = bytes(STREAM.repeat(20));
  const want = Array.from({ length: 20 }, () => WANT).flat();
  let seed = 7;
  for (let run = 0; run < 30; run++) {
    const cuts: number[] = [];
    let at = 0;
    for (;;) {
      seed = (seed * 1103515245 + 12345) % 2 ** 31;
      at += 1 + (seed % 5000);
      if (at >= s.length) break;
      cuts.push(at);
    }
    assert.deepEqual(fed(s, cuts), want, `run ${run}`);
  }
});

test("what_is_not_a_whole_block_yet_waits_for_the_rest", () => {
  const p = new SseParser();
  assert.deepEqual(p.feed(bytes("event: entry\ndata: {")), []);
  assert.deepEqual(p.feed(bytes('"a":1}\n')), []);
  assert.deepEqual(p.feed(bytes("\n")), [["entry", '{"a":1}']]);
  assert.deepEqual(p.feed(bytes("")), []);
});
