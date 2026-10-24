// What the settings say of the workspace as a whole (views/settings.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { settingsView } from "../src/views/settings.ts";

holdLanguage();

const station = (id: string, completion: unknown) => ({ id, station: `w/${id}`, name: id.toUpperCase(), online: true, overview: { automaticDecisions: { settings: { completion } } } });

test("the_automatic_decisions_say_how_many_stations_have_them_on", () => {
  const on = settingsView([station("a", { enabled: true }), station("b", { enabled: false }), station("c", { enabled: true }), { id: "d", station: "w/d" }]);
  assert.deepEqual([on.decisionsOn, on.decisionsText], [2, "2 台 station 已启用"]);
  const off = settingsView([station("a", { enabled: false }), { id: "b", station: "w/b", overview: {} }]);
  assert.deepEqual([off.decisionsOn, off.decisionsText], [0, "未启用"]);
  assert.equal(settingsView([]).decisionsText, "未启用");
});

test("the_hint_by_review_says_what_the_stations_reviews_mean", () => {
  const some = settingsView([station("a", { enabled: true }), station("b", { enabled: false }), { id: "c", station: "w/c", name: "C", online: false }]);
  assert.deepEqual([some.hintNoReview, some.hintReviewText.includes("A"), some.hintReviewText.includes("B")], [false, true, true]);
  const none = settingsView([station("a", { enabled: false })]);
  assert.equal(none.hintNoReview, true);
  assert.notEqual(none.hintReviewText, "");
  assert.deepEqual([settingsView([station("a", { enabled: true })]).hintReviewText, settingsView([]).hintReviewText], ["", ""]);
});
