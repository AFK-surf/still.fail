import assert from "node:assert/strict";
import { test } from "node:test";
import { openJobAction } from "../web/src/open-job-action.ts";

test("a long-running row stops its job, simulator, or remote view with the right operation", () => {
  const job = { station: "w/st", id: "j1" };
  assert.deepEqual(openJobAction(job), { call: "job.stop", params: { station: "w/st", id: "j1" }, word: null });
  assert.deepEqual(openJobAction({ ...job, id: "screen:simulator:A", stop: { call: "screen.close", screen: "simulator:A", word: "关闭" } }), {
    call: "screen.close", params: { station: "w/st", screen: "simulator:A" }, word: "关闭",
  });
  assert.deepEqual(openJobAction({ ...job, id: "view:desktop/v1", stop: { call: "screen.endView", screen: "desktop", view: "v1", word: "断开" } }), {
    call: "screen.endView", params: { station: "w/st", screen: "desktop", view: "v1" }, word: "断开",
  });
  assert.equal(openJobAction({ ...job, stop: { call: "screen.close", screen: "", word: "关闭" } }), null);
  assert.equal(openJobAction({ ...job, stop: { call: "screen.endView", screen: "desktop", word: "断开" } }), null);
  assert.equal(openJobAction({ ...job, stop: { call: "unexpected", screen: "desktop", word: "停止" } }), null);
});
