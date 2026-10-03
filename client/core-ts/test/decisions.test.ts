// client/core/src/decisions.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import * as d from "../src/decisions.ts";
import { holdLanguage } from "../src/i18n.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const shape = (ty: string, v: unknown) => assert.ok("ok" in conform(ty, v), JSON.stringify(conform(ty, v)));

function decision(seq: number, dismissed: boolean): J {
  const v: J = {
    seq,
    options: [{ label: "按今天累计", detail: "重连不清零", recommended: true }, { label: " 先不改 " }, { label: "" }, { label: "改成本次", detail: " " }],
    message: { seq, ts: "9.000002", text: "**「共」改成按今天累计吗？**\n细节：重连、换中继不清零", authorName: "Claude" },
    before: [],
  };
  if (dismissed) v.dismissed = true;
  return v;
}

function textCard(seq: number): J {
  return { seq, card: { type: "text", placeholder: " sk_test_… " }, message: { seq, ts: "9.000003", text: "Stripe 的测试 key 是多少？", authorName: "Claude" }, before: [] };
}

test("only_the_assignee_gets_a_card_but_anyone_can_answer_in_chat", () => {
  const c = textCard(5);
  c.card.assignee = "owner@x.com";
  const row: J = { mine: true, card: c };
  assert.notEqual(d.forViewer(row, { email: "OWNER@x.com" }), null);
  assert.equal(d.forViewer(row, { email: "helper@x.com" }), null);
  assert.notEqual(d.reply(d.ofRow(row), "I can help", false), null);
  assert.equal(d.forViewer({ mine: true, card: textCard(6) }, { email: "owner@x.com" }), null);
  const dismissed = structuredClone(row);
  dismissed.card.dismissed = true;
  assert.equal(d.forViewer(dismissed, { email: "owner@x.com" }), null);
  const card = structuredClone(c.card);
  d.labelAssignee(card, { email: "helper@x.com" }, [{ email: "owner@x.com", name: "小王" }], null);
  assert.equal(card.assigneeText, "需要小王决策");
  d.labelAssignee(card, { email: "owner@x.com" }, [], null);
  assert.equal(d.cardShown(card).assigneeText, "需要你决策");
  const old: J = { type: "text" };
  d.labelAssignee(old, null, [], null);
  assert.equal(old.assigneeText, "尚未指定决策人");
});

test("a_card_no_one_was_assigned_is_its_starters", () => {
  const starter = { id: "owner@x.com", name: "小王", email: "owner@x.com", via: "cloud" };
  const row: J = { card: textCard(6), creator: starter };
  assert.notEqual(d.forViewer(row, { email: "owner@x.com" }), null);
  assert.equal(d.forViewer(row, { email: "helper@x.com" }), null);
  const assigned = structuredClone(row);
  assigned.card.card.assignee = "helper@x.com";
  assert.equal(d.forViewer(assigned, { email: "owner@x.com" }), null);
  assert.notEqual(d.forViewer(assigned, { email: "helper@x.com" }), null);
  const card: J = { type: "text" };
  d.labelAssignee(card, { email: "helper@x.com" }, [], starter);
  assert.equal(card.assigneeText, "需要小王决策");
  d.labelAssignee(card, { email: "owner@x.com" }, [], starter);
  assert.equal(card.assigneeText, "需要你决策");
});

test("a_need_without_a_card_is_asked_as_a_text_card", () => {
  const starter = { id: "owner@x.com", email: "owner@x.com" };
  const need = { seq: 8, message: { seq: 8, ts: "9.000008", text: "要 Stripe 的测试 key", authorName: "Claude" }, before: [] };
  const row: J = { need, creator: starter };
  const asked = d.forViewer(row, { email: "owner@x.com" });
  assert.deepEqual([asked.seq, d.kind(asked.card)], [8, "text"]);
  assert.notEqual(d.reply(asked, "sk_test_1", false), null);
  assert.equal(d.forViewer(row, { email: "helper@x.com" }), null);
  assert.ok(!d.waits(row));
  const both = { need, card: textCard(6), creator: starter };
  assert.equal(d.asked(both)?.seq, 6);
  const dismissed = structuredClone(row);
  dismissed.need.dismissed = true;
  assert.equal(d.forViewer(dismissed, { email: "owner@x.com" }), null);
  assert.notEqual(d.asked(dismissed), null, "still answered in its chat");
});

test("options_show_the_recommended_one_last", () => {
  const shown = d.optionsShown(decision(4, false).options);
  assert.deepEqual(shown, [{ label: "先不改" }, { label: "改成本次" }, { label: "按今天累计", detail: "重连不清零", recommended: true }]);
  for (const o of shown) shape("DecisionOption", o);
  assert.deepEqual(d.optionsShown(null), []);
});

test("the_list_asks_with_the_agents_need_else_the_whole_first_line", () => {
  const long = `**${"字".repeat(50)}**\n细节`;
  const agent = (need: string, about: number | null) => ({
    lastTurn: { declared: "block", ending: "need_help", outcome: "completed", need, about: about === null ? null : { thread: 3, seq: about } },
  });
  const row = (agents: J[]) => ({ thread: 3, agents });
  assert.equal(d.asks(row([agent("选统计口径", 7)]), 7, long), "选统计口径");
  assert.equal(d.asks(row([agent("选统计口径", null)]), 7, long), "选统计口径");
  assert.equal(d.asks(row([agent("选统计口径", 5)]), 7, long), "字".repeat(50), "a need about another post");
  assert.equal(d.asks(row([agent("  ", 7)]), 7, long), "字".repeat(50));
  assert.equal(d.asks(row([]), 7, ""), "奏");
});

test("a_cards_line_is_its_whole_first_line", () => {
  assert.equal(d.line("**「共」改成按今天累计吗？**\n细节"), "奏 · 「共」改成按今天累计吗？");
  assert.equal(d.line("\n\n## 选哪个"), "奏 · 选哪个");
  const long = "字".repeat(50);
  assert.equal(d.line(long), `奏 · ${long}`);
  assert.equal(d.line(""), "奏");
});

test("a_rows_card_is_read_from_its_card_else_its_decision", () => {
  assert.equal(d.kind(d.ofRow({ decision: decision(4, false) }).card), "options");
  const row = { decision: decision(4, false), card: textCard(5) };
  assert.deepEqual([d.ofRow(row).seq, d.kind(d.ofRow(row).card)], [5, "text"]);
  assert.equal(d.ofRow({ card: null, decision: null }), null);
  assert.deepEqual(d.ofMessage({ options: [{ label: "A" }] }), { type: "options", options: [{ label: "A" }] });
  assert.deepEqual(d.ofMessage({ card: { type: "text" } }), { type: "text" });
  assert.equal(d.ofMessage({ options: [] }), null);
  assert.deepEqual(d.cardShown({ type: "text", placeholder: " sk_… " }), { type: "text", placeholder: "sk_…" });
  shape("MessageCard", d.cardShown(d.ofMessage({ options: [{ label: "A" }] })));
});

test("a_row_with_a_card_says_so_and_is_marked_wait_until_dismissed", () => {
  let row: J = { state: "run", unread: true, decision: decision(4, false) };
  d.presentRow(row);
  assert.equal(row.tone, "wait");
  assert.equal(row.decision.text, "奏 · 「共」改成按今天累计吗？");
  assert.equal(row.decision.options[2].label, "按今天累计");
  assert.equal(row.decision.card.type, "options");
  assert.equal(row.decision.message, undefined);
  shape("RowDecision", row.decision);
  assert.equal(d.ofRow(row)?.seq, 4);
  row = { state: null, card: textCard(6) };
  d.presentRow(row);
  assert.deepEqual([row.card, row.decision.options, row.decision.card], [undefined, [], { type: "text", placeholder: "sk_test_…" }]);
  assert.equal(row.tone, "wait");
  row = { state: null, unread: false, decision: decision(4, true) };
  d.presentRow(row);
  assert.deepEqual([row.tone, row.decision.text, row.decision.dismissed], [undefined, undefined, true]);
  row = { state: null, unread: true, decision: decision(4, true) };
  d.presentRow(row);
  assert.equal(row.tone, "done");
  assert.equal(d.tone({ state: "block" }), "wait");
  assert.equal(d.tone({ state: "failed", decision: decision(4, false) }), "alert");
  assert.equal(d.tone({ state: "run", decision: decision(4, false) }), "wait");
  assert.equal(d.tone({ state: "run" }), "busy");
  assert.equal(d.tone({ state: null, unread: true }), "done");
  assert.equal(d.tone({ state: null }), null);
  row = { state: null, decision: null };
  d.presentRow(row);
  assert.deepEqual([row.decision, row.tone], [undefined, undefined]);
});

const said = (seq: number, kind: string, text: string): J => ({ seq, ts: `9.00000${seq}`, authorKind: kind, text, quotes: [], mine: false, by: { name: kind === "person" ? "林晓" : "Claude" } });
const askedMsg = (seq: number): J => ({ ...said(seq, "agent", "选哪个？"), options: [{ label: "A", recommended: true }, { label: "B" }] });
const typed = (seq: number): J => ({ ...said(seq, "agent", "key？"), card: { type: "text", placeholder: "sk_" } });

test("cards_in_a_chat_say_whether_they_wait_and_who_answered_how", () => {
  let messages: J[] = [said(1, "person", "做吧"), askedMsg(2), said(3, "agent", "顺便说下进度")];
  d.inMessages(messages, [2, true]);
  assert.deepEqual(messages[1].decision, { resolved: false, dismissed: true });
  assert.deepEqual(messages[1].options, [{ label: "B" }, { label: "A", recommended: true }]);
  assert.deepEqual(messages[1].card, { type: "options", options: [{ label: "B" }, { label: "A", recommended: true }] });
  assert.equal(messages[0].decision, undefined);
  const pick = said(3, "person", " B ");
  pick.quotes = [{ author: "Claude", text: "选哪个？", ts: "9.000002", role: "agent" }];
  messages = [askedMsg(2), pick];
  d.inMessages(messages, null);
  assert.deepEqual(messages[0].decision, { resolved: true, answeredBy: "林晓", chosen: "B", text: "林晓 选了「B」" });
  shape("MessageDecision", messages[0].decision);
  const mine = said(3, "person", "都不要");
  mine.mine = true;
  messages = [askedMsg(2), mine];
  d.inMessages(messages, null);
  assert.equal(messages[0].decision.text, "你 回复了");
  messages = [askedMsg(2), said(3, "person", "A")];
  d.inMessages(messages, null);
  assert.equal(messages[0].decision.chosen, undefined);
  messages = [askedMsg(2), said(3, "agent", "进度"), typed(4)];
  d.inMessages(messages, undefined);
  assert.deepEqual(messages[0].decision, { resolved: true, text: "已换成新的问题" });
  assert.deepEqual(messages[2].decision, { resolved: false });
  assert.deepEqual([messages[2].card, messages[2].options], [{ type: "text", placeholder: "sk_" }, undefined]);
  messages = [typed(2), said(3, "person", "sk_test_1")];
  d.inMessages(messages, null);
  assert.deepEqual(messages[0].decision, { resolved: true, answeredBy: "林晓", text: "林晓 回复了" });
});

test("a_picked_option_or_a_written_answer_quotes_the_post", () => {
  const c = d.ofRow({ decision: decision(4, false) });
  const [text, quotes] = d.answer(c, "先不改")!;
  assert.equal(text, "先不改");
  assert.deepEqual(quotes, [{ author: "Claude", text: "**「共」改成按今天累计吗？**\n细节：重连、换中继不清零", comment: "", role: "agent", ts: "9.000002" }]);
  assert.equal(d.answer(c, "别的"), null);
  const [text2, quotes2] = d.reply(c, "  先调间距\n颜色不动  ", false)!;
  assert.equal(text2, "先调间距\n颜色不动");
  assert.equal(quotes2[0].ts, "9.000002");
  assert.equal(d.reply(c, " ", false), null);
  assert.equal(d.reply(c, "", true)![0], "");
  assert.equal(d.reply({ card: { type: "date" } }, "明天", false), null);
  const tc = textCard(5);
  const [text3, quotes3] = d.reply(tc, "  sk_test_123 ", false)!;
  assert.deepEqual([text3, quotes3[0].ts], ["sk_test_123", "9.000003"]);
  assert.equal(d.reply(tc, " ", false), null);
  assert.equal(d.answer(tc, "sk"), null, "a text card has no options");
});

test("the_page_puts_those_set_aside_last", () => {
  const items: [string, number, number | null][] = [["c", 3, 20], ["a", 5, null], ["d", 1, 10], ["b", 2, null]];
  d.order(items);
  assert.deepEqual(items.map((i) => i[0]), ["b", "a", "d", "c"]);
  const prefs = { decisionsDeferred: { [d.deferralKey("w/s", 7, 4)]: 12 } };
  assert.equal(d.deferredAt(prefs, "w/s", 7, 4), 12);
  assert.equal(d.deferredAt(prefs, "w/s", 7, 5), null);
});
