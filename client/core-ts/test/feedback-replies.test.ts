// The still.fail team's replies on a chat's bug reports (feedback-replies.ts): read from still.fail cloud with the
// person's sign-in as its events socket opens and as it says they changed, shown in that chat alone, answered as
// the person.
import assert from "node:assert/strict";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { Core } from "../src/core.ts";
import { chatFeedback } from "../src/feedback-replies.ts";
import { holdLanguage } from "../src/i18n.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { account, answers, apply, call, nowS, subscribe, v } from "./helpers.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

const report = (number: number, session: string, replies: J[], station = "st") => ({ id: `FB${number}`, number, title: `报告 ${number}`, station, session, thread: null, replies });
const team = (id: string, text: string, at = 1_790_000_000) => ({ id, from: "team", name: "", text, created_at: at });

test("a chat shows only its own reports the team replied on, the team's latest first line on its card", () => {
  const kept = {
    feedback: [
      report(12, "chat:c-1", [team("r1", "能发一下日志吗？\n谢谢"), { id: "r2", from: "person", name: "阿一", text: "好的", created_at: 1_790_000_100 }, team("r3", "\n  收到，已修复。  ")]),
      report(11, "chat:c-2", [team("r4", "别的对话的")]),
      report(10, "chat:c-1", [team("r5", "另一个站的")], "other"),
      report(9, "chat:c-1", [{ id: "r6", from: "agent", name: "", text: "只有 agent 回过", created_at: 1 }]),
    ],
  };
  const shown = chatFeedback(kept, "w1/st", "chat:c-1", 1_790_000_200_000, 0);
  assert.deepEqual(shown.reports.map((r: J) => [r.label, r.workspace, r.heading, r.latest, r.latestId, r.dismissed]), [["FB-12", "w1", "still.fail 团队回复了 FB-12", "收到，已修复。", "r3", false]]);
  assert.equal(chatFeedback(kept, "w1/st", "chat:c-1", 1_790_000_200_000, 0, "", { FB12: "r3" }).reports[0].dismissed, true);
  assert.equal(chatFeedback(kept, "w1/st", "chat:c-1", 1_790_000_200_000, 0, "", { FB12: "r1" }).reports[0].dismissed, false, "a newer team reply brings it back");
  assert.deepEqual(shown.reports[0].replies.map((r: J) => [r.from, r.who, r.text]), [
    ["team", "still.fail 团队", "能发一下日志吗？\n谢谢"],
    ["person", "阿一", "好的"],
    ["team", "still.fail 团队", "\n  收到，已修复。  "],
  ]);
  assert.deepEqual(chatFeedback(undefined, "w1/st", "chat:c-1", 0, 0), { reports: [] });
});

test("the replies are read as the events socket opens and as the cloud says they changed; a person answers as themselves", async () => {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a1", "r", nowS(host) + 3600)]);
  let kept: J = { feedback: [] };
  const posted: J[] = [];
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { user: { sub: "s1" }, workspaces: [{ id: "w1", name: "W" }], invitations: [], relay_url: "https://relay.test" });
    if (path === "/v1/workspaces/w1") return jsonResponse(200, { id: "w1", stations: [{ id: "st", name: "一号", online: false }] });
    if (path === "/v1/workspaces/w1/feedback" && req.method === "GET") return jsonResponse(200, kept);
    if (path === "/v1/workspaces/w1/feedback/FB12/reply" && req.method === "POST") {
      const body = JSON.parse(new TextDecoder().decode(req.body!));
      posted.push(body);
      kept = { feedback: [report(12, "chat:c-1", [...kept.feedback[0].replies, { id: "r9", from: "person", name: "阿一", text: body.text, created_at: 1_790_000_300 }])] };
      return jsonResponse(200, { id: "r9" });
    }
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chatFeedback", station: "w1/st", session: "chat:c-1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { reports: [] });
  const reads = () => host.requests.filter((r) => r.url.endsWith("/v1/workspaces/w1/feedback")).length;
  assert.equal(reads(), 1, "read as the socket opened");

  // The team replies: the cloud says so, and it is read again, shown in its chat.
  kept = { feedback: [report(12, "chat:c-1", [team("r1", "能发一下日志吗？")])] };
  host.socketSend("/v1/events", '{"type":"feedback","workspace":"w1"}');
  await host.settle();
  apply(host, values);
  assert.equal(reads(), 2);
  assert.deepEqual(v(values, 1).reports.map((r: J) => [r.label, r.account, r.latest, r.replies.length]), [["FB-12", "s1", "能发一下日志吗？", 1]]);
  // Another workspace's word is not this one's.
  host.socketSend("/v1/events", '{"type":"feedback","workspace":"w9"}');
  await host.settle();
  assert.equal(reads(), 2);

  // The person answers in the app: as themselves, and what it holds read again.
  call(core, ui, 2, "workspace.feedbackReply", { account: "s1", workspace: "w1", id: "FB12", text: "昨天下午三点" });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.ok(answers(emitted, 2) && "ok" in answers(emitted, 2)!, JSON.stringify(answers(emitted, 2)));
  host.emitted.push(...emitted);
  apply(host, values);
  assert.deepEqual(posted, [{ text: "昨天下午三点" }]);
  assert.ok(host.requests.some((r) => r.url.endsWith("/feedback/FB12/reply") && r.headers.some(([k, val]) => k === "authorization" && val === "Bearer a1")));
  assert.deepEqual(v(values, 1).reports[0].replies.map((r: J) => [r.from, r.who, r.text]), [["team", "still.fail 团队", "能发一下日志吗？"], ["person", "阿一", "昨天下午三点"]]);
  assert.equal(v(values, 1).reports[0].dismissed, false);

  // Dismissed on this device up to r1: kept across restarts and person replies, shown again when the team replies anew.
  call(core, ui, 3, "feedback.dismiss", { workspace: "w1", id: "FB12", reply: "r1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).reports[0].latestId, v(values, 1).reports[0].dismissed], ["r1", true]);
  core.close();

  const core2 = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui2 = core2.connect();
  const values2 = new Map();
  subscribe(core2, ui2, 1, { topic: "chatFeedback", station: "w1/st", session: "chat:c-1" });
  await host.settle();
  apply(host, values2);
  assert.deepEqual([v(values2, 1).reports[0].latestId, v(values2, 1).reports[0].dismissed], ["r1", true], "persisted in the workspace's database");

  kept = { feedback: [report(12, "chat:c-1", [...kept.feedback[0].replies, team("r10", "查到了，0.1.8701 已修。")])] };
  host.socketSend("/v1/events", '{"type":"feedback","workspace":"w1"}');
  await host.settle();
  apply(host, values2);
  assert.deepEqual([v(values2, 1).reports[0].latestId, v(values2, 1).reports[0].dismissed, v(values2, 1).reports[0].latest], ["r10", false, "查到了，0.1.8701 已修。"]);
  core2.close();
});
