import assert from "node:assert/strict";
import { test } from "node:test";
import { newSession, say } from "../src/sessions/lifecycle.ts";
import { Rig, settle } from "./hub-fakes.ts";

for (const [tool, kind] of [["chat_post", "all_done"], ["chat_state", "all_done"], ["chat_state", "waiting"]] as const) {
  test(`${tool} ${kind} identifies its about message without merging edits`, async () => {
    const r = new Rig();
    try {
      const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
      say(r.hub, thread.id, "ada@x.com", "please do this");
      await settle();
      const about = r.said(thread.id).at(-1)!;
      const original = r.store.messageAt;
      r.store.messageAt = () => { throw new Error("about unnecessarily merged its message"); };
      try {
        const state = kind === "all_done"
          ? { kind, done: "Finished the requested work" }
          : { kind, for: "The requested work", seconds: 60 };
        const args = tool === "chat_post"
          ? { ...state, about: about.ts, to: `CHAT/${thread.threadTs}`, text: "Here is the update" }
          : { ...state, about: about.ts };
        assert.match(await r.refused(key, tool, { ...args, about: "missing" }), /about must be the ts of a message/);
        const result = await r.call(key, tool, args);
        assert.match(result, /(?:Posted|Recorded state)/);
      } finally { r.store.messageAt = original; }
      r.claude.last().complete();
      await settle();
      assert.deepEqual(r.store.lastTurn(key)!.about, { thread: thread.id, seq: about.n, ts: about.ts });
    } finally { await r.close(); }
  });
}

for (const tool of ["chat_post", "chat_state"] as const) {
  test(`${tool} need_human checks the question's latest words`, async () => {
    const r = new Rig();
    try {
      const [key, thread] = newSession(r.hub, { runtime: "claude", createdBy: "ada@x.com" });
      say(r.hub, thread.id, "ada@x.com", "please do this");
      await settle();
      const to = `CHAT/${thread.threadTs}`;
      await r.call(key, "chat_post", { to, text: "May I continue?" });
      const question = r.said(thread.id).at(-1)!;
      r.store.editMessage(thread.surface, thread.channel, thread.threadTs, question.ts, "   ");
      const state = { kind: "need_human", need: "permission to continue", about: question.ts };
      const args = tool === "chat_post" ? { ...state, to, text: "Still waiting" } : state;
      assert.match(await r.refused(key, tool, args), /your visible question/);
    } finally { await r.close(); }
  });
}
