// The Feishu connect (docs/feishu.md) in each state its pages have: the new-connect wizard's platform step and its
// Feishu path as the core puts it (forms.ts `ConnectFlows`, the QR code by qr.ts), and a Feishu connect's page, up or
// failing. The wizard's calls answer at once and change nothing (the stories show states, not what follows).
import { qr } from "../../client/core-ts/src/qr.ts";
import type { DemoExtension } from "../src/demo/mount.tsx";
import type { Connect, ConnectFeishuFlow, ConnectFlowView, ConnectsView } from "../src/core/shapes.ts";

export type FeishuStep = "platform" | "old" | "bind" | "way" | "scan" | "expired" | "made" | "made-failed" | "app" | "app-verified" | "app-wrong";

const URL = "https://accounts.feishu.cn/oauth/v1/app/verify?flow_id=7f3c2a91d4e8b6f0&name=still.fail&addons=H4sIAAAAAAAAA6tWKkktLlGyUlAqzs9NVdJRKkotLs1JUbJSMjQ0rgUAyHw-_xwAAAA";

function feishu(step: FeishuStep): ConnectFeishuFlow {
  const base: ConnectFeishuFlow = {
    way: step === "app" || step === "app-verified" || step === "app-wrong" ? "app" : "scan", appId: "", appSecret: "", lark: false, canVerify: false,
    verified: false, errors: [], failed: false, creating: false,
  };
  const registration = (state: string) => ({ id: "r1", url: URL, expiresAt: 1_792_000_600_000, state });
  switch (step) {
    case "scan": return { ...base, registration: registration("waiting"), qr: qr(URL)!, stateText: "使用飞书扫描二维码，按提示创建机器人" };
    case "expired": return { ...base, registration: registration("expired"), stateText: "二维码已过期", failed: true };
    case "made": return { ...base, registration: { ...registration("done"), appId: "cli_a7f3c2a91d4e8", domain: "feishu" }, stateText: "机器人已创建，正在添加连接", creating: true };
    case "made-failed": return { ...base, registration: { ...registration("done"), appId: "cli_a7f3c2a91d4e8", domain: "feishu" }, stateText: "机器人已创建，添加连接失败", error: "无法获取 tenant_access_token：app_ticket 尚未推送" };
    case "app": return { ...base, appId: "cli_a7f3c2a91d4e8", appSecret: "xxxxxxxx", canVerify: true };
    case "app-wrong": return { ...base, appId: "cli_a7f3c2a91d4e8", appSecret: "xxxxxxxx", canVerify: true, errors: ["App Secret 无效（code 10014）"] };
    case "app-verified": return { ...base, appId: "cli_a7f3c2a91d4e8", appSecret: "xxxxxxxx", canVerify: true, verified: true, identity: { botName: "Codex 机器人", tenant: { key: "t1", name: "Acme 中国" } } };
    default: return base;
  }
}

const STEP: Record<FeishuStep, [string, string, number, string]> = {
  platform: ["platform", "选择平台", 1, "close"],
  old: ["platform", "选择平台", 1, "close"],
  bind: ["feishuBind", "绑定模型", 2, "platform"],
  way: ["feishuWay", "创建飞书机器人", 3, "feishuBind"],
  scan: ["feishuScan", "扫码创建", 4, "feishuWay"],
  expired: ["feishuScan", "扫码创建", 4, "feishuWay"],
  made: ["feishuScan", "扫码创建", 4, "feishuWay"],
  "made-failed": ["feishuScan", "扫码创建", 4, "feishuWay"],
  app: ["feishuApp", "使用已有应用", 4, "feishuWay"],
  "app-wrong": ["feishuApp", "使用已有应用", 4, "feishuWay"],
  "app-verified": ["feishuApp", "使用已有应用", 4, "feishuWay"],
};

function flowView(step: FeishuStep, mobile: boolean): ConnectFlowView {
  const [at, title, number, back] = STEP[step];
  return {
    step: at, title, back, number, total: step === "platform" || step === "old" ? 5 : 4, mobile, adding: false,
    settings: { name: "still.fail", displayName: "still.fail", description: "", longDescription: "", backgroundColor: "#F3E3D3", groups: {} },
    config: "", configReady: false, mode: "multi-session", requireMention: true, gettingToken: false, noProfile: false, canMake: false,
    canCreate: true, teams: [], ...(step === "platform" || step === "old" ? {} : { platform: "feishu" }),
    platforms: step === "old" ? ["slack"] : ["slack", "feishu"], feishu: feishu(step),
  };
}

/** The new-connect wizard at `step` (on a phone: `mobile`, its steps a screen each). */
export function feishuFlowDemo(step: FeishuStep, mobile = false): DemoExtension {
  return {
    topic: (t) => (t.topic === "connectFlow" ? flowView(step, mobile) : t.topic === "slackTokens" ? { appToken: "", botToken: "", errors: [], ready: false } : undefined),
    call: (name) => (name.startsWith("connect.flow.") || name.startsWith("slack.tokens.") ? {} : undefined),
  };
}

/** A Feishu connect, shaped as the core presents it: up, or failing to connect. */
function feishuConnect(failing: boolean): Connect {
  return {
    id: "codex-bot", name: "Codex 机器人", team: "Acme 中国", enabled: true, kind: "feishu", mode: "multi-session", requireMention: true,
    bind: { runtime: "claude", model: "claude-opus-5-5", effort: "medium", profile: "machine-claude" },
    slack: { appToken: "", botToken: "" },
    feishu: { appId: "cli_a7f3c2a91d4e8", appSecret: "a7f3••••••••c2e1", domain: "feishu", console: "https://open.feishu.cn/app/cli_a7f3c2a91d4e8" },
    connection: failing
      ? { state: "error", error: "无法建立长连接：应用未开启长连接接收事件（code 1000040345）" }
      : { state: "connected", botUserId: "ou_7d8a6e6df7621556ce0d21922b676706", workspace: { team: "Acme 中国", teamId: "t1", url: "", botUserId: "ou_7d8a6e6df7621556ce0d21922b676706", botName: "Codex 机器人" } },
    createdBy: { id: "lin@acme.dev", name: "林晓", shown: { name: "林晓", display: "林晓", mine: false } }, sessions: 3,
    statusText: failing ? "出错" : "在线", presence: failing ? "error" : "online", modeText: "多会话", modeShort: "多会话", runtimeText: "Claude Code", runText: "Claude Code · Opus 5.5 · medium", modelName: "Opus 5.5",
  };
}

/** The connects with a Feishu one beside the Slack one (its page opened by its name). */
export function feishuConnectDemo(failing = false): DemoExtension {
  return {
    then: (t, value) => {
      if (t.topic !== "connects" || !value || typeof value !== "object") return undefined;
      const v = value as ConnectsView;
      const station = v.items[0]?.station ?? "";
      return { ...v, items: [...v.items, { station, stationName: "Studio", connect: feishuConnect(failing), sessions: [], candidates: [], running: 0 }] };
    },
  };
}
