// A chat whose runtime the station does not have (station sessions/actor.ts `runtimeMissing`): the person's message,
// waiting, and still.fail's notice with installing it under it (core views.ts `installView`), in each state it has.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, RuntimeInstall } from "../src/core/shapes.ts";

export type InstallStory = "missing" | "installing" | "failed" | "installed" | "member";

const INSTALL: Record<InstallStory, RuntimeInstall> = {
  missing: { runtime: "dsh", state: "missing", action: "安装 DeepSeek Harness" },
  installing: { runtime: "dsh", state: "installing", text: "正在安装 DeepSeek Harness", percent: 42 },
  failed: { runtime: "dsh", state: "failed", text: "安装失败：npm ERR! code EACCES", action: "重试安装" },
  installed: { runtime: "dsh", state: "installed", text: "已安装 DeepSeek Harness" },
  member: { runtime: "dsh", state: "missing", text: "需由 workspace 的 owner 或管理员安装" },
};

/** The person's question and the notice after it, at the end of the chat on show. */
function withNotice(chat: ChatView, story: InstallStory): ChatView {
  const mine = [...chat.messages].reverse().find((m) => m.authorKind === "person");
  if (!mine || chat.messages.some((m) => m.runtime)) return chat;
  const seq = (chat.messages.at(-1)?.seq ?? 0) + 1;
  const ts = Number(chat.messages.at(-1)?.ts ?? mine.ts);
  const { followed: _f, joined: _j, ...base } = mine;
  const asked: ChatMessage = { ...base, seq, ts: `${ts + 30}`, text: "有没有什么下载抖音视频的方案", quotes: [], attachments: [], mine: true, waiting: story !== "installed" };
  const notice: ChatMessage = {
    ...base, seq: seq + 1, ts: `${ts + 31}`, authorKind: "ember", author: "ember", mine: false, system: true, waiting: false, quotes: [], attachments: [],
    by: { name: "still.fail" },
    text: "⚠️ 无法启动 agent：此 station 尚未安装 DeepSeek Harness", runtime: "dsh", install: INSTALL[story],
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
