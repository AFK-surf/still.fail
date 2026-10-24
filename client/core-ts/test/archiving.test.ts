// How a station archives on its own, as 设置 › 归档 says it (present.ts archiving).
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { archiving } from "../src/present.ts";

holdLanguage();

const decided = (on: boolean) => ({ settings: { completion: { enabled: on, model: "m1" } }, models: [{ id: "m1", name: "Haiku 5" }] });

test("a_station_set_to_go_by_its_review_while_it_is_off_says_nothing_goes", () => {
  const v = archiving({ days: 3, slackDays: 0, reviewed: true, canEdit: true }, decided(false));
  assert.deepEqual([v.mode, v.reviewOn, v.stalled], ["reviewed", false, true]);
  assert.notEqual(v.lineText, v.summaryText);
  // what the way chosen does, and that its review is off
  assert.ok(v.modeNote.length > 0);
  const on = archiving({ days: 3, slackDays: 0, reviewed: true, canEdit: true }, decided(true));
  assert.deepEqual([on.stalled, on.lineText === on.summaryText], [false, true]);
  assert.ok(on.reviewText.includes("Haiku 5"));
});

test("each_way_to_archive_says_what_choosing_it_saves", () => {
  const v = archiving({ days: 7, slackDays: 3, reviewed: false, canEdit: true }, decided(false));
  assert.deepEqual(v.modes.map((m: any) => [m.mode, m.days, m.reviewed, m.allowed]), [["off", 0, false, true], ["idle", 7, false, true], ["reviewed", 7, true, false]]);
  const off = archiving({ days: 0, slackDays: 0, reviewed: false, canEdit: true }, decided(true));
  assert.deepEqual(off.modes.map((m: any) => [m.days, m.allowed]), [[0, true], [1, true], [1, true]]);
  assert.equal(off.daysOfferedText.length, off.daysOffered.length);
});
