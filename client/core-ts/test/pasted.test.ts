// Words pasted into what is written (src/pasted.ts) and the references in it (src/refLinks.ts refAt, markBefore,
// marksIn, pastedRefs), as every client reads them.
import assert from "node:assert/strict";
import { test } from "node:test";
import { pasted, PASTE_RESTORE_LIMIT, PASTE_THRESHOLD } from "../src/pasted.ts";
import { markBefore, marksIn, pastedRefs, refAt } from "../src/refLinks.ts";
import { wordsAnswer } from "../src/words.ts";

test("long_words_pasted_go_as_a_file_that_says_how_they_begin_and_how_many", () => {
  assert.deepEqual(pasted("短的"), { file: false, info: null });
  const long = `  第一行\n${"字".repeat(PASTE_THRESHOLD)}`;
  const p = pasted(long);
  assert.equal(p.file, true);
  assert.equal(p.info?.preview, "第一行");
  assert.equal(p.info?.characters, long.length);
  assert.equal(p.info?.text, long);
  assert.equal(pasted("x".repeat(PASTE_RESTORE_LIMIT + 1)).info?.text, undefined);
});

test("at_words_ask_for_a_chat_and_a_mark_goes_whole", () => {
  assert.deepEqual(refAt("看 @修登", 5), { start: 2, query: "修登" });
  assert.deepEqual(refAt("@", 1), { start: 0, query: "" });
  assert.equal(refAt("a@b", 3), null);
  assert.equal(refAt("看 @修 登", 6), null);
  assert.equal(markBefore("看 @[修登录]", 8), 2);
  assert.equal(markBefore("看 @[修登录] ", 9), null);
  assert.deepEqual(marksIn("看 @[修登录] 和 @[x]"), [{ start: 2, end: 8, title: "修登录" }, { start: 11, end: 15, title: "x" }]);
});

test("a_chats_link_pasted_as_copied_is_a_reference_when_it_is_of_this_workspace", () => {
  const text = "看 [修登录](https://app.still.fail/o/ws/st/k1) 和 [别处](https://app.still.fail/o/other/st/k2)";
  assert.deepEqual(pastedRefs(text, "ws/st9"), [{ start: 2, end: 42, title: "修登录", station: "ws/st", id: "k1", history: "" }]);
  // A station of no workspace takes none.
  assert.deepEqual(pastedRefs(text, "st9"), []);
});

test("clients_without_the_js_ask_the_same_reading_and_the_bound_a_paste_goes_as_a_file_from", () => {
  assert.deepEqual(wordsAnswer("paste.info", "", 0, ""), { file: false, info: null, threshold: PASTE_THRESHOLD });
  assert.deepEqual(wordsAnswer("ref.at", "看 @首", 4, ""), { at: { start: 2, query: "首" } });
  assert.deepEqual(wordsAnswer("ref.marks", "@[甲] 和 @[乙]", 0, ""), { marks: marksIn("@[甲] 和 @[乙]") });
});
