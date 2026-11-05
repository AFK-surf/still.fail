// The lock's rules as rules/ (MoonBit) has them, against the TypeScript they are to replace (lock-form.ts, the
// stations' lowerRole): the same text for the same value, byte for byte, the test vectors and seeded random values
// (unicode, control characters, lone surrogates, nesting, numbers a lock refuses).
import assert from "node:assert/strict";
import { test } from "node:test";
import { canonical, entryText } from "../src/lock-form.ts";
import { lowerRole } from "../../../station/src/cloud/lock.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";

const ours = (f: () => string) => {
  try {
    return f();
  } catch (e) {
    return `!${(e as Error).message}`;
  }
};

function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    let x = (s += 0x6d2b79f5);
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

function value(r: () => number, depth: number): unknown {
  const pick = Math.floor(r() * (depth > 3 ? 5 : 8));
  const chars = ["a", "é", "名", "😀", "\u0000", "\n", "\t", '"', "\\", "\u001f", " ", "\ud800", "\udfff", "/", "\u007f", " "];
  const text = () => Array.from({ length: Math.floor(r() * 6) }, () => chars[Math.floor(r() * chars.length)]).join("");
  switch (pick) {
    case 0: return null;
    case 1: return r() < 0.5;
    case 2: return text();
    case 3: return [0, 1, -1, 1700000000, 9007199254740991, -9007199254740991, 2 ** 53, 1.5, -0][Math.floor(r() * 9)];
    case 4: return Math.floor((r() - 0.5) * 1e12);
    case 5: return Array.from({ length: Math.floor(r() * 4) }, () => value(r, depth + 1));
    default: return Object.fromEntries(Array.from({ length: Math.floor(r() * 4) }, () => [text() || "k", value(r, depth + 1)]));
  }
}

test("canonical: the MoonBit rules write what lock-form.ts writes, for the vectors and 5000 random values", () => {
  const vector = { v: 1, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字", exp: 1702592000 } };
  assert.equal(rules.entry_text_of(vector), entryText(vector));
  const r = rng(7);
  for (let i = 0; i < 5000; i++) {
    const v = value(r, 0);
    const text = JSON.stringify(v);
    const theirs = rules.canonical_of(JSON.parse(text));
    const mine = ours(() => canonical(JSON.parse(text)));
    assert.equal(theirs.startsWith("!"), mine.startsWith("!"), `${text}: ${theirs} / ${mine}`);
    if (!mine.startsWith("!")) assert.equal(theirs, mine, text);
  }
});

test("lowerRole: the MoonBit rules' as the stations'", () => {
  const roles = ["owner", "admin", "member", "viewer", "nobody"];
  for (const a of roles) for (const b of roles) assert.equal(rules.lower_role(a, b), lowerRole(a, b), `${a} ${b}`);
});
