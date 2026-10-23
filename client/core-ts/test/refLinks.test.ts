// still.fail's links as what is written names them (src/refLinks.ts), as every client reads them.
import assert from "node:assert/strict";
import { test } from "node:test";
import { adbOfLink, chatOfLink, copiedRef, isChatLink, REF_LINK, REF_MARK, screenOfLink, shareLink, splitBy, stationOfLink } from "../src/refLinks.ts";

const runs = (text: string, pattern: RegExp) => splitBy(text, pattern).map((p) => (typeof p === "string" ? p : [...p]));

test("references_are_found_as_the_composer_holds_them_and_as_they_are_sent", () => {
  assert.deepEqual(runs("看 @[修登录] 和 @[x]", REF_MARK), ["看 ", ["@[修登录]", "修登录"], " 和 ", ["@[x]", "x"]]);
  assert.deepEqual(runs("没有引用", REF_MARK), ["没有引用"]);
  const sent = "see [Fix](https://app.still.fail/w/ws/s/st/chats/7) and [Other](https://app.still.fail/o/ws/st/k1).";
  assert.deepEqual(runs(sent, REF_LINK), [
    "see ",
    ["[Fix](https://app.still.fail/w/ws/s/st/chats/7)", "Fix", "https://app.still.fail/w/ws/s/st/chats/7"],
    " and ",
    ["[Other](https://app.still.fail/o/ws/st/k1)", "Other", "https://app.still.fail/o/ws/st/k1"],
    ".",
  ]);
  // A link to anything else is words.
  assert.deepEqual(runs("[x](https://example.com/a)", REF_LINK), ["[x](https://example.com/a)"]);
});

test("a_chats_link_is_its_page_or_its_still_fail_link", () => {
  assert.equal(isChatLink("/w/ws/s/st/chats/7"), true);
  assert.equal(isChatLink("https://app.still.fail/w/ws/s/st/chats/7/?history=k2"), true);
  assert.equal(isChatLink("https://app.still.fail/o/ws/st/k1?history=k2"), true);
  assert.equal(isChatLink("https://app.still.fail/o/ws/st"), false);
  assert.equal(isChatLink("https://example.com/chats/"), false);
  assert.equal(isChatLink(undefined), false);
});

test("a_chat_is_given_away_by_its_still_fail_link_or_else_its_page", () => {
  const item = { station: "ws/st", session: "ds:C1 x", id: "7" };
  const at = { cloud: "https://app.still.fail/", here: "http://localhost:5173", root: "/w/ws/s/st/" };
  assert.equal(shareLink(item, at), "https://app.still.fail/o/ws/st/ds%3AC1%20x");
  assert.equal(shareLink(item, at, { key: "k 2", entry: 3 }), "https://app.still.fail/o/ws/st/ds%3AC1%20x?history=k%202&entry=3");
  assert.equal(shareLink(item, at, { key: "k2" }), "https://app.still.fail/o/ws/st/ds%3AC1%20x?history=k2");
  // No cloud known, or a station of no workspace: its page here.
  assert.equal(shareLink(item, { ...at, cloud: null }), "http://localhost:5173/w/ws/s/st/chats/7");
  assert.equal(shareLink({ ...item, station: "st", id: "a b" }, { ...at, here: null }), "/w/ws/s/st/chats/a%20b");
});

test("a_link_copied_says_its_title_on_one_line_as_a_reference_is_sent", () => {
  assert.deepEqual(copiedRef("修 [登录]\n问题", "L"), { shown: "修  登录  问题", plain: "[修  登录  问题](L)" });
  assert.deepEqual(copiedRef(" \n", "https://a/o/w/s/k"), { shown: "https://a/o/w/s/k", plain: "[https://a/o/w/s/k](https://a/o/w/s/k)" });
  assert.equal(Array.from(copiedRef("字".repeat(200), "L").shown).length, 120);
});

test("the_chat_station_screen_or_shared_debugging_a_link_names", () => {
  assert.deepEqual(chatOfLink("https://app.still.fail/o/ws/st/ds%3Ak?history=k2&entry=5"), { station: "ws/st", id: "ds:k", history: "?history=k2&entry=5" });
  assert.deepEqual(chatOfLink("https://app.still.fail/w/ws/s/st/chats/7/"), { station: "ws/st", id: "7", history: "" });
  assert.equal(chatOfLink("https://x.com/chats/7"), null);
  assert.equal(chatOfLink("/w/ws/s/st/chats/%E0%A4%A"), null);
  assert.equal(stationOfLink("https://app.still.fail/o/ws/st/k"), "ws/st");
  assert.equal(stationOfLink("/w/ws/s/st/chats/7"), "ws/st");
  assert.equal(stationOfLink("https://x.com/a"), null);
  assert.deepEqual(screenOfLink("https://app.still.fail/w/ws/s/st/screen/s%201"), { station: "ws/st", screen: "s 1" });
  assert.deepEqual(screenOfLink("/w/ws/s/st/screen/1/"), { station: "ws/st", screen: "1" });
  assert.equal(screenOfLink("/w/ws/s/st/screen"), null);
  assert.equal(adbOfLink("/w/ws/s/st/adb"), "ws/st");
  assert.equal(adbOfLink("https://app.still.fail/w/w%20s/s/st/adb/"), "w s/st");
  assert.equal(adbOfLink("/w/ws/s/st/adb/x"), null);
});
