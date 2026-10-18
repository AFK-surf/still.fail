// A chat's failure notices (station sessions/actor.ts notice): a turn that failed, and a chat whose runtime the station
// does not have (`runtimeMissing`) with installing it (core views.ts `installView`) in each state it has. The person's
// message waits under them.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, RuntimeInstall } from "../src/core/shapes.ts";

export type InstallStory = "missing" | "installing" | "failed" | "installed" | "member" | "turn";

const INSTALL: Record<Exclude<InstallStory, "turn">, RuntimeInstall> = {
  missing: { runtime: "dsh", state: "missing", action: "安装" },
  installing: { runtime: "dsh", state: "installing", title: "正在安装 DeepSeek Harness", percent: 42 },
  failed: { runtime: "dsh", state: "failed", title: "无法安装 DeepSeek Harness", detail: "npm ERR! code EACCES: permission denied, mkdir '/usr/local/lib/node_modules/@deepseek-ai'", action: "重试" },
  installed: { runtime: "dsh", state: "installed", title: "已安装 DeepSeek Harness" },
  member: { runtime: "dsh", state: "missing", note: "需由 workspace 的 owner 或管理员安装" },
};

/** The person's question and the notice after it, at the end of the chat on show. */
function withNotice(chat: ChatView, story: InstallStory): ChatView {
  const mine = [...chat.messages].reverse().find((m) => m.authorKind === "person");
  if (!mine || chat.messages.some((m) => m.system && m.seq > mine.seq)) return chat;
  const seq = (chat.messages.at(-1)?.seq ?? 0) + 1;
  const ts = Number(chat.messages.at(-1)?.ts ?? mine.ts);
  const { followed: _f, joined: _j, ...base } = mine;
  const asked: ChatMessage = { ...base, seq, ts: `${ts + 30}`, text: "有没有什么下载抖音视频的方案", quotes: [], attachments: [], mine: true, waiting: story !== "installed" && story !== "turn" };
  const notice: ChatMessage = {
    ...base, seq: seq + 1, ts: `${ts + 31}`, authorKind: "ember", author: "ember", mine: false, system: true, waiting: false, quotes: [], attachments: [],
    by: { name: "still.fail" },
    ...(story === "turn"
      ? { text: "⚠️ 本轮出错：API Error: 529 overloaded_error · the model is overloaded, try again in a moment" }
      : { text: "⚠️ 无法启动 agent：此 station 尚未安装 DeepSeek Harness", runtime: "dsh", install: INSTALL[story] }),
  };
  return { ...chat, messages: [...chat.messages, asked, notice] };
}

/** The demo with the notice in state `story` in the chat on show. */
export function installDemo(story: InstallStory): DemoExtension {
  return {
    then: (t, value) => (t.topic === "chat" && value && typeof value === "object" && "messages" in value ? withNotice(value as ChatView, story) : undefined),
    // Installing answers at once, the page as it was (the stories show states, not what follows).
    call: (name) => (name === "software.update" ? {} : undefined),
  };
}
