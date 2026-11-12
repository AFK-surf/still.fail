// feedback_reply: the agent's answer on a report, when the person asks for it. The team's replies are never given to
// an agent (the app shows them to people; cloud/test/feedback.test.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { feedbackTools } from "../src/tools/feedback.ts";
import type { Store } from "../src/store/store.ts";

test("feedback_reply sends the agent's answer on FB-n with its session, and says so", async () => {
  const store = { getSession: (key: string) => (key === "s1" ? { key } : null) } as unknown as Store;
  const sent: unknown[] = [];
  const tool = feedbackTools(store, () => null, () => null, () => async (body) => (sent.push(body), { id: "01" })).find((t) => t.name === "feedback_reply")!;
  assert.equal(await tool.run("s1", { number: 12, text: " Here is the log. " }), "Sent to the still.fail team as a reply on FB-12.");
  assert.deepEqual(sent, [{ number: 12, text: "Here is the log.", session: "s1" }]);
  await assert.rejects(tool.run("s1", { number: 12, text: " " }), /text/);
  await assert.rejects(tool.run("s1", { number: "x", text: "hi" }), /number/);
  const notFound = feedbackTools(store, () => null, () => null, () => async () => { throw new Error("still.fail cloud answered 404: {\"error\":\"feedback_not_found\"}"); }).find((t) => t.name === "feedback_reply")!;
  await assert.rejects(notFound.run("s1", { number: 99, text: "hi" }), /FB-99 is not a report this station sent/);
  const offline = feedbackTools(store, () => null, () => null, () => null).find((t) => t.name === "feedback_reply")!;
  await assert.rejects(offline.run("s1", { number: 12, text: "hi" }), /not connected to still.fail cloud/);
});

test("no tool or notice of the station's carries the team's replies", async () => {
  const tools = feedbackTools({ getSession: () => null } as unknown as Store, () => null, () => null);
  assert.deepEqual(tools.map((t) => t.name), ["feedback_send", "feedback_reply"]);
  const module = await import("../src/tools/feedback.ts");
  assert.ok(!("tellReplies" in module) && !("replyNotice" in module));
});
