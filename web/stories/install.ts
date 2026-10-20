// A chat whose runtime the station does not have (station sessions/actor.ts `runtimeMissing`), as the core puts it
// (present.ts `installView`, views.ts `blockedUnder`): said under the viewer's message that waits for it, with installing it, in each
// state it has; one with none of the viewer's waiting stays a notice. And a turn that failed, the red pill, with reporting
// it where the station takes bug reports (views.ts `reportable`). And SuperGrok's sign-in on a station without Grok Build
// (core forms.ts `profileView`): installing it first.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ChatMessage, ChatView, ProfileFlowView, RuntimeInstall } from "../src/core/shapes.ts";

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

/** The add-profile pages at SuperGrok's sign-in on a station without Grok Build: installing it (`missing`) or under way. */
export function installFlowDemo(state: "missing" | "installing"): DemoExtension {
  const install: RuntimeInstall = state === "missing"
    ? { runtime: "grok", state: "missing", title: "此 station 尚未安装 Grok Build", action: "安装" }
    : { runtime: "grok", state: "installing", title: "正在安装 Grok Build", percent: 42 };
  const view: ProfileFlowView = {
    step: "connect", station: "", title: "连接 xAI", hint: "", groups: [], method: "plan", choices: [], showEndpoint: false, endpoint: "", protocols: [], regions: [],
    showKey: false, key: "", keyLabel: "", canSubmit: false, pending: false, submitLabel: "", usesLine: "添加后可用于：Grok Build", install,
    tile: { id: "xai", name: "xAI", group: "labs", mark: "xai", kind: "api-provider", hasKey: true, hasPlan: true, runtime: "grok", endpointRequired: false, protocols: [], keyOptional: false, uses: ["codex", "grok"], usesText: "Codex · Grok Build" },
  };
  return {
    topic: (t) => (t.topic === "profileFlow" ? { ...view, station: String(t.station) } : undefined),
    // The page's edits and installing answer at once, the page as it was (the stories show states, not what follows).
    call: (name) => (name.startsWith("profile.flow.") || name === "software.update" ? {} : undefined),
  };
}
