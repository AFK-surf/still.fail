// Writes libs/base/src/wire/sse_made_test.mbt: streams of an event stream's text, and beside each the events the
// device base's reader in TypeScript gives for it (client/core-ts/src/sse.ts, run here as it is, by Node: so with the
// WHATWG's TextDecoder). The reader in MoonBit (libs/base/src/wire/sse.mbt) reads as that one does, to the byte, and
// they stay two (the core is not switched to the one in MoonBit: the user, 2026-11-14), so this is what holds one to
// the other: the base's tests feed each stream whole, a byte at a time and cut in two, natively and on js.
// `--check` fails when the file is not what the streams below and that reader make (scripts/check.sh runs it for a
// change to either reader or to this): a change to what the reader in TypeScript gives fails here until the cases
// are made again, and they then fail the base's tests until the reader in MoonBit gives the same.
//
// The streams are written out by kind (KINDS), and some more are put together of the same pieces by a generator
// seeded here, so that the file is the same each time it is made.
//
//   node scripts/mb-base-sse.ts [--check]
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SseParser } from "../client/core-ts/src/sse.ts";

const FROM = "client/core-ts/src/sse.ts";
const out = fileURLToPath(new URL("../libs/base/src/wire/sse_made_test.mbt", import.meta.url));

const encoder = new TextEncoder();
/// The bytes of the parts one after another: a string's as UTF-8, bytes as they are.
function stream(...parts: (string | readonly number[])[]): Uint8Array {
  return Uint8Array.from(parts.flatMap((part) => (typeof part === "string" ? [...encoder.encode(part)] : part)));
}
const char = String.fromCodePoint;

/// A byte order mark.
const MARK = [0xef, 0xbb, 0xbf];
/// What JavaScript's `trim` takes off (ECMAScript's WhiteSpace and LineTerminator) but the two a line cannot end
/// with here: LF, which ends it, and CR, which is dropped before.
const BLANK = [0x09, 0x0b, 0x0c, 0x20, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff];
/// Bytes that are no UTF-8, of each kind (a byte that continues nothing, an overlong form, a surrogate, past
/// U+10FFFF, a byte UTF-8 never has, a sequence cut short after each of its bytes), and a few that are, beside them.
const NOT_UTF8: number[][] = [
  [0x80], [0xbf], [0xc0, 0x80], [0xc1, 0xbf], [0xc2], [0xe0, 0x80, 0x80], [0xe0, 0xa0], [0xe6, 0x95], [0xed, 0xa0, 0x80], [0xed, 0xb0, 0x80],
  [0xed, 0xa0, 0x80, 0xed, 0xb0, 0x80], [0xf0, 0x80, 0x80, 0x80], [0xf0, 0x9f], [0xf0, 0x9f, 0x98], [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80],
  [0xf8, 0x88, 0x80, 0x80, 0x80], [0xff], [0xfe], [0xef, 0xbf, 0xbe], [0xef, 0xbf, 0xbf], [0xe2, 0x80], [0xe2, 0x80, 0xa8], [0xc2, 0xa0], [0xc2, 0x85], [0xe2],
  [0xf0], [0xf4, 0x8f, 0xbf, 0xbf], [0xf1, 0x80, 0x80], [0xe0, 0x9f, 0xbf], [0xf0, 0x8f, 0xbf, 0xbf], [0xf4, 0x8f], [0xc2, 0xc2, 0xa0], [0xe1, 0x80, 0xe1, 0x80, 0x80],
];

/// The streams, by kind: a kind is one test of the file made.
const KINDS: [kind: string, streams: Uint8Array[]][] = [
  [
    "a field with no space, with spaces alone, with no colon, with nothing; several of one; what is no field",
    [
      "data:\n\n", "data: \n\n", "data:  \n\n", "data:   \n\n", "data\n\n", "data:x\n\n", "data:  x \n\n", "data:\ndata:\n\n", "data: a\ndata:\ndata: b\n\n",
      "data: one\ndata: two\ndata: three\n\n", "id:\n\n", "id: \n\n", "id:   \n\n", "id\n\n", "id:7\n\n", "id:7\ndata:\n\n", "id: a\nid: b\n\n", "id: a\nid:\ndata: x\n\n",
      "event:\n\n", "event: \n\n", "event:x\n\n", "event:\ndata:x\n\n", "event:   \ndata:x\n\n", "event: a\nevent: b\ndata: x\n\n", "event: a b \ndata: x\n\n",
      "event:  e \ndata: x\n\n", "event: e\nid: 1\ndata: x\n\n", "data: x\nid: 1\nevent: e\n\n", "Data: x\n\n", " data: x\n\n", "data : x\n\n", "data:x:y\n\n", ":comment\n\n",
      ": a comment\nid: 4\n\n", "retry: 5\ndata: x\n\n", "retry: 5\n\n", "data: a\u0000b\n\n", "id: \u0000\n\n", "event:\u0000\ndata:\u0000\n\n", "\u0000data: x\n\n",
    ].map((text) => stream(text)),
  ],
  [
    "blank lines before, between and after blocks; a block that is not ended",
    ["\n\n", "\n\n\n\n", "\n\n\n", "\ndata: x\n\n", "\n\n\ndata: x\n\n", "data: x\n\n\n\n", "data: x\n\n\ndata: y\n\n", "data: x\n", "data: x\n\ndata: y", "data: x\n\nid: 2\n"].map((text) => stream(text)),
  ],
  [
    "what JavaScript's trim takes off, at both ends of a name, an id and data; and what it does not",
    [
      ...BLANK.map((c) => stream(`event:${char(c)}n${char(c)}\nid:${char(c)}i${char(c)}\ndata:${char(c)}d${char(c)}\n\nid:${char(c)}\n\n`)),
      // (no white space to JavaScript: a Mongolian vowel separator, a next line, a zero width space, two separators)
      ...["id:᠎\n\n", "id: ᠎\n\n", "id: \u0085\n\n", "id: ​\n\n", "id: \u001c\u001f\n\n", "event: \u0085a​᠎ \ndata: 1\n\n"].map((text) => stream(text)),
      stream("event: \t 　a b  ﻿ \nid:   7   \ndata:  x 　\n\n"),
    ],
  ],
  [
    "characters of 2, 3 and 4 bytes, in a name, an id and data",
    [
      "id: é\n\n", "id:长\n\n", "id:\u{1f600}\n\n", "data:é\n\n", "data: 长长\n\n", "data:\u{1f600}\n\n", "event:\u{1f600}\ndata: \u{1f600}\n\n",
      "id: \u{1f600} 　\n\n", "event: \u{1f600}x\u{1f600}\t\nid:\u{1f600}\n\n", "event: é长\u{1f600}\nid: \u{1f600}长é\ndata: {\"text\":\"整理é\u{1f600}\"}\n\n",
    ].map((text) => stream(text)),
  ],
  [
    "CRs: after a line, alone, in runs, in a field's name, for a blank line",
    ["data: x\r\n\r\n", "data: x\r\r\n\r\n", "data: x\n\r\n", "data: x\rdata: y\r\r", "\r\r\r", "\r\n\r\n", "data: a\rb\n\n", "da\rta: x\n\n", "\rdata: x\n\r\n\r", "event: e\r\nid: 1\r\ndata: x\r\n\r\ndata: y\r\n\r\n", "id: 1\r\n\r", "data: x\n\r\r\r\ndata: y\n\n"].map(
      (text) => stream(text),
    ),
  ],
  [
    "a byte order mark: at a stream's head, at a later block's, in a line, twice, cut short, with CRs in it",
    [
      stream(MARK, "data: x\n\n"), stream(MARK, MARK, "data: x\n\n"), stream("data: x\n\n", MARK, "event: e\ndata: y\n\n"), stream(MARK, "id: 1\n\n"), stream(MARK, "\n\n"),
      stream("data: ", MARK, "x\n\n"), stream("id:", MARK, "\n\n"), stream("event:", MARK, "\ndata:x\n\n"), stream("id: 3", MARK, "\n\n"), stream(MARK, "\ndata: x\n\n"),
      stream("\n", MARK, "data: x\n\n"), stream("data: a\n", MARK, "data: b\n\n"), stream([0xef, 0xbb], "data: x\n\n"), stream([0xef], "data: x\n\n"),
      stream(MARK, [0xef, 0xbb], "\ndata: x\n\n"), stream([0xff, 0xfe], "data: x\n\n"), stream(MARK, "\r\ndata: x\r\n\r\n"), stream([0xef, 13, 0xbb, 13, 0xbf], "data: x\n\n"),
      stream([0xef, 0xbb, 13, 0xbf], "id: 1\n\n"),
    ],
  ],
  [
    "bytes that are no UTF-8, of each kind: in data, at a block's end, at its head, in an id and a name, twice",
    NOT_UTF8.flatMap((bad) => [
      stream("data: a", bad, "b\n\n"),
      stream("data: a", bad, "\n\ndata: z\n\n"),
      stream(bad, "data: a\n\n", bad, "\n\n"),
      stream("id:", bad, "\n\nevent:", bad, " \ndata:", bad, "\n\n"),
      stream("data: ", bad, bad, "\n\n"),
    ]),
  ],
];

// Put together at random, of the pieces above: 1 to 30 of them a stream.
let seed = 99;
const below = (n: number) => {
  seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
  return (seed >>> 8) % n;
};
const one = <T>(of: readonly T[]): T => of[below(of.length)]!;
const PIECES: (() => string | readonly number[])[] = [
  () => one(["data:", "data: ", "id:", "id: ", "event:", "event: ", ":", "data", "", " ", "x"]),
  () => one(["\n", "\n", "\n\n", "\n\n", "\r\n", "\r", "\r\n\r\n"]),
  () => char(one(BLANK)),
  () => one(NOT_UTF8),
  () => MARK,
  () => one(["a", "长", "\u{1f600}", "\u0000", "é", "1f2e.3", "᠎", "​", "\u0085"]),
];
const RANDOM = 120;
KINDS.push(["streams put together at random of the same pieces", Array.from({ length: RANDOM }, () => stream(...Array.from({ length: 1 + below(30) }, () => one(PIECES)())))]);

// ── what the reader in TypeScript gives ──

type Events = [string, string, string?][];
/// What the reader gives for `bytes` fed in the chunks `cuts` cut it into.
function read(bytes: Uint8Array, cuts: number[]): Events {
  const reader = new SseParser();
  const events: Events = [];
  let at = 0;
  for (const cut of [...cuts, bytes.length]) {
    events.push(...reader.feed(bytes.subarray(at, cut)));
    at = cut;
  }
  return events;
}

/// A MoonBit literal of bytes and of a string: what prints in ASCII as it is, the rest by its number.
const escapes = new Map([["\n", "\\n"], ["\r", "\\r"], ["\t", "\\t"], ['"', '\\"'], ["\\", "\\\\"]]);
const plain = (code: number) => code >= 0x20 && code < 0x7f;
const bytesOf = (bytes: Uint8Array) => `b"${Array.from(bytes, (b) => escapes.get(char(b)) ?? (plain(b) ? char(b) : `\\x${b.toString(16).padStart(2, "0")}`)).join("")}"`;
const stringOf = (text: string) => `"${Array.from(text, (c) => escapes.get(c) ?? (plain(c.codePointAt(0)!) ? c : `\\u{${c.codePointAt(0)!.toString(16)}}`)).join("")}"`;

let made = `// Made by scripts/mb-base-sse.ts: do not edit. Each case is a stream and the events the device base's reader in
// TypeScript (${FROM}, run by Node, with the WHATWG's TextDecoder) gives for it. The reader here is
// to give the same, the stream fed whole, a byte at a time and cut in two (\`fed\`: wire_test.mbt), on each target. A
// reading meant to change is changed in both readers; a stream is added in the script; then this is made again:
// node scripts/mb-base-sse.ts.

///|
/// \`stream\` reads as \`want\` however it is fed; \`n\` says which case did not.
fn made(n : Int, stream : Bytes, want : Array[@wire.Event]) -> Unit raise {
  let ways : Array[(String, Array[Int])] = [
    ("whole", []),
    ("a byte at a time", Array::makei(stream.length() - 1, i => i + 1)),
    ("cut in two", [stream.length() / 2]),
  ]
  for way in ways {
    if fed(stream, way.1) != want {
      fail("case \\{n}, fed \\{way.0}: \\{stream}")
    }
  }
}
`;
const seen = new Set<string>();
let n = 0;
for (const [kind, streams] of KINDS) {
  made += `\n///|\ntest ${stringOf(`made: ${kind}`)} {\n`;
  for (const bytes of streams) {
    const key = bytes.join();
    if (bytes.length === 0 || seen.has(key)) continue;
    seen.add(key);
    const want = read(bytes, []);
    // (the reader in TypeScript itself reads a stream the same however it is cut: else it is no case)
    for (const cuts of [Array.from({ length: bytes.length - 1 }, (_, i) => i + 1), [bytes.length >> 1]]) {
      if (JSON.stringify(read(bytes, cuts)) !== JSON.stringify(want)) throw new Error(`${FROM} reads ${bytesOf(bytes)} otherwise cut at ${cuts.join()}`);
    }
    const events = want.map(([name, data, id]) => `{ name: ${stringOf(name)}, data: ${stringOf(data)}, id: ${id === undefined ? "None" : `Some(${stringOf(id)})`} }`);
    made += `  made(${++n}, ${bytesOf(bytes)}, [${events.join(", ")}])\n`;
  }
  made += "}\n";
}

if (process.argv.includes("--check")) {
  let was = "";
  try { was = readFileSync(out, "utf8"); } catch {}
  if (was !== made) { console.error(`not what ${FROM} gives for the streams of scripts/mb-base-sse.ts: ${out} — run node scripts/mb-base-sse.ts, and where the base's tests then fail, the reader in MoonBit (libs/base/src/wire/sse.mbt) is to read as the one in TypeScript`); process.exit(1); }
} else {
  writeFileSync(out, made);
  console.log(`${n} cases`);
}
