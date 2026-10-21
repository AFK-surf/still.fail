// A command's output as a terminal shows it (src/terminal.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { terminal } from "../src/terminal.ts";

const E = "\u001b";

test("plain output stays as it is, with no runs", () => {
  assert.deepEqual(terminal("a\n\tb\n"), { text: "a\n\tb\n" });
  assert.deepEqual(terminal(""), { text: "" });
});

test("xmake's colours: runs of one style, the codes gone", () => {
  const out = terminal(`${E}[0m${E}[38;5;2;1m[  0%]:${E}[0m ${E}[38;5;5;1m<engine>${E}[0m ${E}[0mgenerating x.cpp${E}[0m\nnext`);
  assert.equal(out.text, "[  0%]: <engine> generating x.cpp\nnext");
  assert.deepEqual(out.runs, [
    { text: "[  0%]:", fg: "2", bold: true },
    { text: " " },
    { text: "<engine>", fg: "5", bold: true },
    { text: " generating x.cpp\nnext" },
  ]);
});

test("the 16 colours by number, the other 256 and true colour as #rrggbb, each reset alone", () => {
  const out = terminal(`${E}[31;42mA${E}[91;103mB${E}[38;5;196mC${E}[38;5;244mD${E}[38;2;1;2;3mE${E}[38:2::255:128:0mF${E}[39;49mG${E}[3;4;2mH${E}[22;23;24mI`);
  assert.equal(out.text, "ABCDEFGHI");
  assert.deepEqual(out.runs, [
    { text: "A", fg: "1", bg: "2" },
    { text: "B", fg: "9", bg: "11" },
    { text: "C", fg: "#ff0000", bg: "11" },
    { text: "D", fg: "#808080", bg: "11" },
    { text: "E", fg: "#010203", bg: "11" },
    { text: "F", fg: "#ff8000", bg: "11" },
    { text: "G" },
    { text: "H", dim: true, italic: true, underline: true },
    { text: "I" },
  ]);
});

test("\\r and \\b write over the line, erasing in it is done", () => {
  assert.equal(terminal("  0%\r 50%\r100%\ndone").text, "100%\ndone");
  assert.equal(terminal("abcdef\rxy").text, "xycdef");
  assert.equal(terminal(`abcdef\r${E}[2Kxy`).text, "xy");
  assert.equal(terminal(`abcdef\rxy${E}[K`).text, "xy");
  assert.equal(terminal(`abcdef\b\b${E}[1K`).text, "     f");
  assert.equal(terminal("ab\b\bcd").text, "cd");
  // A line written from where a shorter one ended.
  assert.equal(terminal(`ab\r${E}[4C`).text, "ab");
});

test("other sequences and control characters are dropped", () => {
  // Cursor moves, private modes, a window title, a hyperlink (its text kept), a charset, a bell.
  const out = terminal(`${E}[?25l${E}[2J${E}[H${E}]0;title\u0007${E}]8;;https://x.test${E}\\link${E}]8;;${E}\\ ${E}(Bok\u0007\u0000`);
  assert.deepEqual(out, { text: "link ok" });
  // Cut off at the end.
  assert.deepEqual(terminal(`done${E}[38;5`), { text: "done" });
  assert.deepEqual(terminal(`done${E}`), { text: "done" });
});
