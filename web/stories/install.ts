// A chat whose runtime the station does not have (station sessions/actor.ts `runtimeMissing`), as the core puts it
// (views.ts `installView`, `blockedUnder`): said under the viewer's message that waits for it, with installing it, in each
// state it has; one with none of the viewer's waiting stays a notice. And a turn that failed, the red pill, with reporting
// it where the station takes bug reports (views.ts `reportable`).
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, RuntimeInstall } from "../src/core/shapes.ts";

export type InstallStory = "missing" | "installing" | "failed" | "member" | "notice" | "turn" | "report";

const MISSING = "此 station 尚未安装 DeepSeek Harness";
const INSTALL: Record<"missing" | "installing" | "failed" | "member" | "notice", RuntimeInstall> = {
  missing: { runtime: "dsh", state: "missing", title: MISSING, action: "安装" },
  installing: { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness", percent: 42 },
  failed: { runtime: "dsh", state: "failed", title: "无法安装 DeepSeek Harness", detail: "npm ERR! code EACCES: permission denied", action: "重试" },
  member: { runtime: "dsh", state: "missing", title: MISSING, note: "需由 workspace 的 owner 或管理员安装" },
  notice: { runtime: "dsh", state: "missing", title: MISSING, action: "安装" },
};

/** The person's question at the end of the chat on show, and what its runtime missing makes of it. */
function withStory(chat: ChatView, story: InstallStory): ChatView {
  const person = [...chat.messages].reverse().find((m) => m.authorKind === "person");
  if (!person || chat.messages.some((m) => m.text === ASKED)) return chat;
  const seq = (chat.messages.at(-1)?.seq ?? 0) + 1;
  const ts = Number(chat.messages.at(-1)?.ts ?? person.ts);
  const { followed: _f, joined: _j, ...base } = person;
  const mine = story !== "notice";
  const asked: ChatMessage = {
    ...base, seq, ts: `${ts + 30}`, text: ASKED, quotes: [], attachments: [], mine, waiting: true,
    ...(story !== "turn" && story !== "report" && story !== "notice" ? { blocked: INSTALL[story] } : {}),
  };
  const notice = (text: string, over: Partial<ChatMessage> = {}): ChatMessage => ({
    ...base, seq: seq + 1, ts: `${ts + 31}`, authorKind: "ember", author: "ember", mine: false, system: true, waiting: false, quotes: [], attachments: [],
    by: { name: "still.fail" }, text, ...over,
  });
  const after = story === "turn"
    ? [notice("⚠️ 本轮出错：API Error: 529 overloaded_error · the model is overloaded, try again in a moment")]
    : story === "report" ? [notice("⚠️ 本轮出错：workspace routing discovery timed out", { reportable: true }), notice("⚠️ 本轮出错：stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses), Transport error: network error", { seq: seq + 2, ts: `${ts + 32}`, reportable: true })]
    : story === "notice" ? [notice(`⚠️ 无法启动 agent：${MISSING}`, { runtime: "dsh", install: INSTALL.notice })] : [];
  return { ...chat, messages: [...chat.messages, asked, ...after] };
}
const ASKED = "有没有什么下载抖音视频的方案";

/** The demo with the chat on show in state `story`. */
export function installDemo(story: InstallStory): DemoExtension {
  return {
    then: (t, value) => (t.topic === "chat" && value && typeof value === "object" && "messages" in value ? withStory(value as ChatView, story) : undefined),
    // Installing answers at once, the page as it was (the stories show states, not what follows).
    call: (name) => (name === "software.update" ? {} : name === "chat.report" ? { number: 12 } : undefined),
  };
}
