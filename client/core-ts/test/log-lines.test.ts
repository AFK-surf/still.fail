// A job's log's lines numbered as it grows (src/log-lines.ts): each line keeps its number from one time the station
// says the log to the next, those new count on from them.
import assert from "node:assert/strict";
import { test } from "node:test";
import { firstNumber, linesOf, logged } from "../src/log-lines.ts";

const E = "\u001b";
/// The lines of `text` as said before, its first numbered `from`.
const was = (text: string, from: number) => ({ from, lines: linesOf(text) });
/// The number the first of `text`'s lines has after `old`.
const first = (old: { from: number; lines: ReturnType<typeof linesOf> } | null, text: string) => firstNumber(old, linesOf(text));

test("the first read numbers its lines from 0", () => {
  assert.equal(first(null, "a\nb\nc"), 0);
  assert.deepEqual(logged(undefined, "a\nb", 5), { text: "a\nb", outputAt: 5, from: 0 });
});

test("lines appended keep the numbers of those before and count on from them, one or several at once", () => {
  assert.equal(first(was("a\nb\nc", 7), "a\nb\nc\nd"), 7);
  assert.equal(first(was("a\nb\nc", 7), "a\nb\nc\nd\ne\nf"), 7);
  // (the same said again: nothing moves)
  assert.equal(first(was("a\nb\nc", 7), "a\nb\nc"), 7);
});

test("at its most, the first lines gone: those left keep their numbers", () => {
  assert.equal(first(was("a\nb\nc", 7), "b\nc\nd"), 8);
  assert.equal(first(was("a\nb\nc", 7), "c\nd\ne"), 9);
  // (in colour: by its runs, the codes done)
  const line = (k: number) => `${E}[2m${k}${E}[22m ${E}[32m✔${E}[39m test ${k}`;
  const log = (from: number, to: number) => Array.from({ length: to - from }, (_, i) => line(from + i)).join("\n");
  assert.equal(first(was(log(0, 300), 40), log(1, 301)), 41);
});

test("the last line written again or finished keeps its number", () => {
  // (a progress bar written again in place: \r)
  assert.equal(first(was("build\n[==   ] 40%", 3), "build\n[==   ] 40%\r[=====] 100%"), 3);
  // (a line not ended yet, ended since, and one more under it)
  assert.equal(first(was("build\ntesting", 3), "build\ntesting ok\nnext"), 3);
  // (at its most too: the last line alone left of what was said, finished)
  assert.equal(first(was("a\nb\ntest", 3), "testing ok\nx\ny"), 5);
  // (rewritten all through, that line alone overlapping: not the same line)
  assert.equal(first(was("a\nb\n40%", 3), "100%\nx\ny"), 6);
});

test("the station's read beginning inside a line: what is left of it keeps that line's number", () => {
  // (its last 64 KB from wherever they begin: the first line cut, a character cut through U+FFFD)
  assert.equal(first(was("first line\nsecond line\nthird", 10), "nd line\nthird\nfourth"), 11);
  assert.equal(first(was("first line\n中文第二行\nthird", 10), "�文第二行\nthird\nfourth"), 11);
  assert.equal(first(was(`${E}[31mred line${E}[0m\nb\nc`, 10), "d line\nb\nc\nd"), 10);
});

test("nothing in common: the log begun again or all of it new, numbered on from the last", () => {
  assert.equal(first(was("a\nb\nc", 7), "x\ny"), 10);
  assert.equal(first(was("a\nb\nc", 7), ""), 10);
});

test("repeated lines alike: the most of them kept", () => {
  assert.equal(first(was("x\nx\nx", 0), "x\nx\nx\nx"), 0);
  assert.equal(first(was("x\ny\nx\ny", 0), "x\ny\nx\ny\nx"), 0);
  // (at its most, a pair gone and a pair come: as alike as before, nothing moved)
  assert.equal(first(was("x\ny\nx\ny", 0), "x\ny\nx\ny"), 0);
});

test("an empty log has no lines; what follows it begins where it would have", () => {
  assert.deepEqual(linesOf(""), []);
  assert.equal(first(was("", 4), "a\nb"), 4);
  assert.equal(first(was("a", 4), ""), 5);
});

test("what the link keeps: kept before numbers (no `from`) taken as from 0", () => {
  assert.deepEqual(logged({ text: "a\nb", outputAt: 1 }, "b\nc", 2), { text: "b\nc", outputAt: 2, from: 1 });
  assert.deepEqual(logged({ text: "a\nb", outputAt: 1, from: 9 }, "a\nb\nc", 2), { text: "a\nb\nc", outputAt: 2, from: 9 });
  assert.deepEqual(logged(null, "a", null), { text: "a", outputAt: null, from: 0 });
});
