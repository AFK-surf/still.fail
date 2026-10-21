// A chat whose runtime the station does not have (station sessions/actor.ts `runtimeMissing`), as the core puts it
// (present.ts `installView`, views.ts `blockedUnder`): said under the viewer's message that waits for it, with installing it, in each
// state it has; one with none of the viewer's waiting stays a notice. And a turn that failed, the red pill, with reporting
// it where the station takes bug reports (views.ts `reportable`). And SuperGrok's sign-in on a station without Grok Build
// (core forms.ts `profileView`): installing it first.
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { ApiProvider, ChatMessage, ChatView, ProfileFlowView, RuntimeInstall } from "../src/core/shapes.ts";

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

/** The add-profile picker on a station that runs Cursor, and Devin with `devin` (core forms.ts `groups`): each last of the
 *  makers, its plan alone (no key), and its variables by hand among the rest. */
export function cursorPickDemo(devin = false): DemoExtension {
  type Tile = ApiProvider;
  const tile = (id: string, name: string, over: Partial<Tile>): Tile => ({
    id, name, group: "labs", mark: id, kind: "api-provider", hasKey: true, hasPlan: false, endpointRequired: false, protocols: [], keyOptional: false, uses: [], usesText: "", ...over,
  });
  const env = (runtime: string, label: string): Tile => ({
    id: `env-${runtime}`, name: `环境变量（${label}）`, group: "local", kind: "env", hasKey: false, hasPlan: false, runtime, endpointRequired: false, protocols: [], keyOptional: true, uses: [runtime], usesText: label,
  });
  const view: ProfileFlowView = {
    step: "pick", station: "", title: "选择服务商", hint: "订阅和 API key 都在这里添加，选择服务商开始", choices: [], showEndpoint: false, endpoint: "", protocols: [], regions: [],
    showKey: false, key: "", keyLabel: "", canSubmit: false, pending: false, submitLabel: "", usesLine: "",
    groups: [
      { id: "labs", title: "模型厂商", providers: [
        tile("openai", "OpenAI", { hasPlan: true, runtime: "codex", uses: ["codex", "dsh"], usesText: "Codex · DeepSeek Harness" }),
        tile("anthropic", "Anthropic", { hasPlan: true, runtime: "claude", uses: ["claude", "dsh"], usesText: "Claude Code · DeepSeek Harness" }),
        tile("deepseek", "DeepSeek", { uses: ["claude", "dsh", "decision"], usesText: "Claude Code · DeepSeek Harness · 自动决策" }),
        tile("cursor", "Cursor", { hasKey: false, hasPlan: true, runtime: "cursor", uses: ["cursor"], usesText: "Cursor" }),
        ...(devin ? [tile("devin", "Devin", { hasKey: false, hasPlan: true, runtime: "devin", uses: ["devin"], usesText: "Devin" })] : []),
      ] },
      { id: "local", title: "本地", providers: [env("claude", "Claude Code"), env("codex", "Codex"), env("dsh", "DeepSeek Harness"), env("cursor", "Cursor"), ...(devin ? [env("devin", "Devin")] : [])] },
    ],
  };
  return {
    topic: (t) => (t.topic === "profileFlow" ? { ...view, station: String(t.station) } : undefined),
    call: (name) => (name.startsWith("profile.flow.") ? {} : undefined),
  };
}

/** The add-profile pages at Kimi's tile, where the station signs Kimi Code in (core forms.ts): its plan or the open
 *  platform's key, as OpenAI's tile has ChatGPT's plan beside its key. */
export function kimiMethodDemo(): DemoExtension {
  const view: ProfileFlowView = {
    step: "method", station: "", title: "连接 Kimi", hint: "", choices: [
      { id: "plan", title: "订阅 · Kimi Code", hint: "Kimi Code 会员，用于运行 Claude Code。用 Kimi 账号登录一次。" },
      { id: "key", title: "API key", hint: "使用 Kimi 的 API key，按量计费" },
    ],
    showEndpoint: false, endpoint: "", protocols: [], regions: [], showKey: false, key: "", keyLabel: "", canSubmit: false, pending: false, submitLabel: "", usesLine: "", groups: [],
    tile: { id: "moonshotai", name: "Kimi", group: "labs", mark: "kimi", kind: "api-provider", hasKey: true, hasPlan: true, endpointRequired: false, protocols: [], keyOptional: false, uses: ["claude", "decision"], usesText: "Claude Code · 自动决策" },
  };
  return {
    topic: (t) => (t.topic === "profileFlow" ? { ...view, station: String(t.station) } : undefined),
    call: (name) => (name.startsWith("profile.flow.") ? {} : undefined),
  };
}
