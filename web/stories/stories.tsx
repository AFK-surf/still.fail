// Each story: a part of the app in one state, on made-up data (data.ts, the site's demo core). People open them in the
// gallery (`pnpm stories`); test/browser/stories.mjs opens every one, takes its steps and measures it (docs/ui-panels.md).
// A story is the whole app (`app`, the site's demo, the steps taking it to the state) or one part drawn alone (`render`).
// A new part of the app gets a story here, and so is measured.
import { useEffect, useState, type ReactNode } from "react";
import { SystemBubbles } from "../src/SystemBubbles.tsx";
import { DecisionOptions } from "../src/Decisions.tsx";
import { StationUpdate } from "../src/StationUpdate.tsx";
import { Reader } from "@stillfail/ui/viewer/Reader.tsx";
import { Tile } from "../src/pages/Notifications.tsx";
import { PermissionRow } from "../src/pages/Permissions.tsx";
import { Player } from "@stillfail/ui/viewer/Player.tsx";
import { driveFile } from "../src/drive/viewerFile.ts";
import { DrivePreview } from "../src/mobile/Drive.tsx";
import { FilePreview } from "../src/FilePreview.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { ComposerExtras, FileCard, MessageFileCard, MineBubble, MineMessage } from "../src/Chat.tsx";
import type { Draft, Pending } from "../src/draft.ts";
import * as composerCss from "../src/styles/composer.css.ts";
import * as conversationCss from "../src/styles/conversation.css.ts";
import { MdView, Prose } from "../src/Prose.tsx";
import {
  AgentMark, Button, Choices, Confirm, CopyCommand, Dialog, Empty, Field, IconButton, Menu, ModelLogo, PanelButton, PanelGroup,
  PanelHead, PanelIconButton, PanelRow, PanelText, Pill, Progress, RuntimeTags, Section, Segmented, Select, Spinner, StatusDot, StatusText,
  Switch, SwitchRow, Tip, WaitLine, WaitPill, Waiting,
} from "../src/ui.tsx";
import { Archive, Bell, Close, Copy, Download, Edit, Folder, Plus, Refresh, Search, Trash } from "@stillfail/ui/icons.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { AT, apk, clips, CODE_COLOURS, MATH, folder, HISTORY, JOIN_REFUSED, JOINABLE, LOGINS, loginsView, MEMBERSHIPS, note, NOTE, novel, picture, SCREENS, TABLE, VIEWER_LOGIN } from "./data.ts";
import { LoginCard, LoginsSection } from "../src/MachineLogins.tsx";
import * as pagesCss from "../src/styles/pages.css.ts";
import { HELD, type DemoExtension } from "../src/demo/mount.tsx";
import { shown as fontsShown } from "../../client/core-ts/src/fonts.ts";
import type { ChatMessage, ChatView, DownloadShown, ShareInView, StationView } from "../src/core/shapes.ts";
import { stamp } from "../src/demo/fixtures.ts";
import { markdown } from "../../client/core-ts/src/markdown.ts";
import type { Shared } from "../src/shareIn.ts";
import { ScreenViewer } from "../src/screen/ScreenViewer.tsx";
import { OUTDATED, SCREENS_LACKING, adbLinksDemo, screenLinksDemo, screensDemo, simulatorLinkDemo, type ViewStory } from "./screens.ts";
import { LONG_COMMAND, libraryDemo, vaultDemo } from "./vault.ts";
import { filesDemo, TRANSFERS } from "./files.ts";
import { cursorPickDemo, installDemo, installFlowDemo, kimiMethodDemo } from "./install.ts";
import { ADD, pickModelsDemo } from "./pickModels.ts";
import { permissionsDemo } from "./permissions.ts";
import { agentEnvDemo } from "./agent-env.ts";
import { softwareDemo } from "./software.ts";
import { lockDemo } from "./lock.ts";
import { thingsDemo } from "./things.ts";
import { shareImageDemo } from "./publish.ts";
import { feishuConnectDemo, feishuFlowDemo } from "./feishu.ts";
import { relaysDemo } from "./relays.ts";
import { ccDemo, relayDemo, TWO_BOTS } from "./relay.ts";
import { Console } from "../src/admin/console.tsx";
import { ACCOUNT } from "../src/demo/station.ts";
import { ModelTriple } from "../src/ModelTriple.tsx";
import { ModelList } from "../src/mobile/History.tsx";
import { ChatRowsSample } from "../src/Sidebar.tsx";
import { PriceTables, SAMPLE_USAGE } from "../src/Usage.tsx";
import type { Picking } from "../src/pick.ts";
import type { ModelOption, PickView } from "../src/core/shapes.ts";
import CLIP_URL from "./assets/story-clip.mp4?url";
import TALL_CLIP_URL from "./assets/story-clip-tall.mp4?url";
import PICTURE_URL from "./assets/story-picture.png?url";

/**
 * What takes a story to its state, as the tests do it (Playwright's selectors); shown beside it in the gallery. `hold`:
 * a finger held on the middle of it as long as a long press, then lifted. A step's `move` comes first: what the pointer
 * wakes (a playing video's controls, gone again once it rests) is pressed before it has rested.
 */
export interface Step { click?: string; rightClick?: string; hover?: string; key?: string; move?: [number, number]; text?: string; hold?: string }
export interface Story {
  id: string;
  group: string;
  title: string;
  /** The whole app (the site's demo), taken to the state by its steps. */
  app?: boolean;
  /** One part, drawn alone. */
  render?: () => ReactNode;
  steps?: Step[];
  /** In a phone's window (wide by default). */
  phone?: boolean;
  /** In a browser of this phone's or tablet's system (its name for itself and its platform, as the page reads them):
   *  what draws the system itself (通知's preview) draws that one. The browser's own by default. */
  system?: "android" | "ios" | "ipad";
  /** Shows the changelog's news (the notices' bubble). */
  news?: boolean;
  /** Its chat's messages carry files (data.ts SENT): pictures and files' cards. */
  files?: boolean;
  /** A file its chat's agent names in a message, read for its card (data.ts PEEK), or not to be found. */
  peek?: "file" | "missing";
  /** What it adds to the demo's core, asked before everything else (topics and calls of its own state). */
  demo?: DemoExtension;
  /** Something another app shares, waiting to be sent as the app opens (../src/shareIn.ts): its sheet or panel up. */
  share?: Shared;
}

const at = (name: string) => ({ ...AT, path: name });
/** To 设置 › 密钥: the wide screen's settings, the phone's (from its chat, back to the list). */
const toVault: Step[] = [{ click: '[aria-label="设置"]' }, { text: "密钥" }];
/** To the wide screen's station page, at one of its parts (StationPage.tsx). */
const toStation = (part: "设置" | "软件与设备"): Step[] => [{ click: '[aria-label^="Station"]' }, { click: `[aria-label="显示"] button:has-text("${part}")` }];
/** To a station's page on the phone (settings › Station › the demo's one). */
const toPhoneStation: Step[] = [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { text: "Studio" }];
const toPhoneVault: Step[] = [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "密钥" }];

/** Fonts chosen on this device (client/core-ts/src/fonts.ts): each place a face of its own. */
const chosenFonts: DemoExtension = (() => {
  const choice = { ui: "noto-serif-sc", text: "lxgw-wenkai", code: "maple-mono" };
  return { topic: (t) => (t.topic === "prefs" ? { fonts: choice, faces: fontsShown(choice) } : undefined) };
})();

/** The demo with stations of other workspaces to add (`list`), or one that refuses to join (none to add: no choice). */
const joining = (kind: "list" | "error"): DemoExtension => ({
  topic: (t) => (t.topic === "joinable" ? JOINABLE : undefined),
  call: (name) => (name === "station.join" ? (kind === "error" ? Promise.reject(new Error(JOIN_REFUSED)) : { joined: null }) : undefined),
});
/** An agent's history in turns (data.ts HISTORY), for whichever agent's is opened. */
const historyTurns: DemoExtension = { topic: (t) => (t.topic === "history" ? HISTORY : undefined) };
/** A workspace with no station yet (its first station's page), with stations of other workspaces to add. */
const firstJoining: DemoExtension = {
  topic: (t) => (t.topic === "joinable" ? JOINABLE : t.topic === "stations" ? [] : undefined),
  call: (name) => (name === "station.join" ? { joined: null } : undefined),
};
/** The demo's station in Lab too, its profile open to Lab (`on`) or not: the profile's page offers the switch. */
const profileFor = (on: boolean): DemoExtension => ({
  topic: (t) => (t.topic === "memberships" ? MEMBERSHIPS : undefined),
  then: (t, value) => {
    if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
    const o = value as { profiles: Record<string, unknown>[] };
    return { ...o, profiles: o.profiles.map((p) => ({ ...p, workspaces: on ? ["lab"] : [] })) };
  },
});
/** The demo's profile as an API provider's, which does not list its models: one more is named by hand under those enabled. */
const addModel: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
    const o = value as { profiles: Record<string, unknown>[] };
    return { ...o, profiles: o.profiles.map((p) => ({ ...p, canAddModel: true })) };
  },
};
/** A profile list entry's profile and its title as the core makes it (views/profiles.ts: a subscription by its email). */
const titled = (profile: Record<string, unknown>) => ({ profile, title: String(profile.email ?? profile.name ?? "") });
/** Hermes' ACP catalog on an environment profile, before any model is enabled. */
const hermesModels: DemoExtension = {
  then: (t, value) => {
    if (!value || typeof value !== "object") return undefined;
    const shown = (p: Record<string, unknown>) => ({
      ...p, name: "Hermes Agent", runtime: "hermes", runtimes: ["hermes"], machine: false,
      access: { kind: "env" }, model: null, models: [], quota: null, login: null, env: [],
      canAddModel: true, available: ["openai-api:smoke-model", "openrouter:anthropic/claude-sonnet-4.6"],
      names: {"openai-api:smoke-model":"openai-api:smoke-model", "openrouter:anthropic/claude-sonnet-4.6":"Sonnet 4.6"},
      makers: {}, series: [{name:"Sonnet",models:["openrouter:anthropic/claude-sonnet-4.6"]},{name:"其他",models:["openai-api:smoke-model"]}],
      modelsText: "已启用 0 / 2 个模型", modelsReading: false, checkText: "可用", checkTone: "green", checkLine: "2 个模型", trouble: null,
      kindText: "自定义环境变量", providerName: null, loginCommand: "",
      home: "/Users/lin/.stillfail/homes/hermes", check: { state: "ok", detail: "可用，2 个模型", checkedAt: Date.now(), models: ["openai-api:smoke-model", "openrouter:anthropic/claude-sonnet-4.6"] },
    });
    if (t.topic === "overview") {
      const o = value as {profiles: Record<string,unknown>[]};
      return {...o, profiles: o.profiles.map(shown)};
    }
    if (t.topic === "profiles") {
      const o = value as {items: Record<string,unknown>[]};
      return {...o, items: o.items.map(e => ({...e, group: "key", groupTitle: "其他", title: "Hermes Agent", profile: shown(e.profile as Record<string,unknown>)}))};
    }
    return undefined;
  },
};
/** The demo's profile as an OpenCode Go one on an OpenCode account (accounts/console.ts): signed in, or being signed in
 *  again (`signingIn`: the device code is up). */
const openCode = (signingIn: boolean): DemoExtension => ({
  then: (t, value) => {
    if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
    const o = value as { profiles: Record<string, unknown>[] };
    const at = Date.UTC(2026, 9, 18, 3, 0);
    const login = { profile: "machine-claude", runtime: "claude", provider: "opencode", state: "needs_approval", url: "https://opencode.ai/console/device?user_code=WXYZ-1234&client_id=still.fail", userCode: "WXYZ-1234", startedAt: at, expiresAt: at + 600_000 };
    return {
      ...o,
      profiles: o.profiles.map((p) => ({
        ...p, machine: false, runtimes: ["claude", "codex", "dsh"], loginCommand: "", providerName: undefined,
        access: { kind: "opencode-go", key: "st_4a…3f9c", login: true },
        // Its check and allowance as they would be for it, not the demo's Claude account's.
        quota: null, trouble: null,
        ...(signingIn
          ? { login, check: { ...(p.check as object), state: "login", detail: "OpenCode 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber" }
          : { login: null, check: { ...(p.check as object), state: "ok", detail: "可用，29 个模型" }, checkText: "可用", checkTone: "green" }),
      })),
    };
  },
});
/** The demo's profile as a Kimi Code one on a Kimi account (accounts/kimi.ts), being signed in again: its device code. */
const kimiCode: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
    const o = value as { profiles: Record<string, unknown>[] };
    const at = Date.UTC(2026, 9, 21, 3, 0);
    const login = { profile: "machine-claude", runtime: "claude", provider: "kimi", state: "needs_approval", url: "https://www.kimi.com/code/authorize_device?user_code=UXP8-IJXV", userCode: "UXP8-IJXV", startedAt: at, expiresAt: at + 1_800_000 };
    return {
      ...o,
      profiles: o.profiles.map((p) => ({
        ...p, machine: false, runtimes: ["claude"], loginCommand: "", providerName: "Kimi Code", providerMark: "kimi",
        access: { kind: "api-provider", key: "", provider: "kimi-code", login: true },
        quota: null, trouble: null, login,
        check: { ...(p.check as object), state: "login", detail: "Kimi 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber",
      })),
    };
  },
};
/** The demo's profile as a Claude subscription being signed in again: Claude's page is up and its code is pasted back;
 * `inStation`, where the station's own browser can open it too (docs/remote-login.md). */
const claudeSigningIn = (inStation = false): DemoExtension => ({
  then: (t, value) => {
    if (t.topic !== "overview" || !value || typeof value !== "object") return undefined;
    const o = value as { profiles: Record<string, unknown>[] };
    const at = Date.UTC(2026, 9, 19, 3, 0);
    const login = { profile: "machine-claude", runtime: "claude", state: "needs_code", url: "https://claude.ai/oauth/authorize?code=true&client_id=still.fail", startedAt: at, expiresAt: at + 600_000, ...(inStation ? { browser: true } : {}) };
    return {
      ...o,
      profiles: o.profiles.map((p) => ({
        ...p, machine: false, access: { kind: "subscription", key: "" }, quota: null, trouble: null,
        login, check: { ...(p.check as object), state: "login", detail: "Claude 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber",
      })),
    };
  },
});
const claudeSignIn = claudeSigningIn();
/** The workspace's list with an account of each kind, a section each, its mark before its title. */
const everyKind: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "profiles" || !value || typeof value !== "object") return undefined;
    const v = value as { items: Record<string, unknown>[] };
    const e = v.items[0]!;
    const p = e.profile as Record<string, unknown>;
    const as = (id: string, group: string, groupTitle: string, profile: Record<string, unknown>) => ({ ...e, key: `${String(e.key)}-${id}`, group, groupTitle, profile: { ...p, id, ...profile } });
    return {
      ...v,
      items: [
        ...v.items,
        as("codex", "chatgpt", "ChatGPT 订阅", { name: "lin@acme.dev", runtime: "codex", runtimes: ["codex"], quota: null }),
        as("grok", "grok", "SuperGrok 订阅", { name: "lin@acme.dev", runtime: "grok", runtimes: ["grok"], quota: null }),
        // Signed in to an account rather than given a key: its vendor's subscription.
        as("kimi", "kimi", "Kimi Code 订阅", { name: "Kimi Code", runtime: undefined, runtimes: ["claude"], access: { kind: "api-provider", provider: "kimi-code", key: "", login: true }, providerMark: "kimi", quota: null }),
        as("go", "opencode", "OpenCode Go 订阅", { name: "lin@acme.dev", runtime: undefined, runtimes: ["claude", "codex", "dsh"], access: { kind: "opencode-go", key: "st_4a…3f9c", login: true }, quota: null }),
        as("cursor", "cursor", "Cursor 订阅", { name: "lin@acme.dev", runtime: "cursor", runtimes: ["cursor"], quota: null }),
        as("devin", "devin", "Devin 订阅", { name: "lin@acme.dev", runtime: "devin", runtimes: ["devin"], quota: null }),
        // A key with an allowance of several windows: they take a line of their own, under its name and where it is.
        as("key", "key", "API Key", { name: "OpenRouter", access: { kind: "api-provider", key: "sk-or…9f2c" }, providerMark: "openrouter", quota: { checkedAt: 0, state: "ok", windows: [
          { label: "5 小时", mark: "5H", left: 100, level: "ok", usedPercent: 0 },
          { label: "每周", mark: "W", left: 64, level: "ok", usedPercent: 36 },
          { label: "每月", mark: "M", left: 8, level: "red", usedPercent: 92 },
        ] } }),
      ],
    };
  },
};
/** The demo's profile as a SuperGrok subscription (Grok Build's): signed in, or being signed in again (`signingIn`: xAI's
 *  device code is up). The workspace's list has it under its own kind too. */
const superGrok = (signingIn: boolean): DemoExtension => {
  const at = Date.UTC(2026, 9, 19, 3, 0);
  const login = { profile: "machine-claude", runtime: "grok", state: "needs_approval", url: "https://accounts.x.ai/device?user_code=QRST-5678", userCode: "QRST-5678", startedAt: at, expiresAt: at + 600_000 };
  const models = ["grok-4.3", "grok-code-fast-2"];
  const grok = (p: Record<string, unknown>) => ({
    ...p, machine: false, runtime: "grok", runtimes: ["grok"], loginCommand: "grok login --device-auth", providerName: undefined,
    access: { kind: "subscription", key: "" }, quota: null, trouble: null,
    models, available: models, modelsText: "已启用 2 / 2 个模型", series: [{ name: "Grok", models }],
    makers: Object.fromEntries(models.map((m) => [m, { id: "xai", name: "xAI" }])), names: { "grok-4.3": "Grok 4.3", "grok-code-fast-2": "Grok Code Fast 2" },
    ...(signingIn
      ? { login, check: { checkedAt: 0, state: "login", detail: "Grok 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber" }
      : { login: null, check: { checkedAt: 0, state: "ok", detail: "已登录", models }, checkText: "可用", checkTone: "green" }),
  });
  return {
    then: (t, value) => {
      if (!value || typeof value !== "object") return undefined;
      if (t.topic === "overview") {
        const o = value as { profiles: Record<string, unknown>[] };
        return { ...o, profiles: o.profiles.map(grok) };
      }
      if (t.topic === "profiles") {
        const v = value as { items: Record<string, unknown>[] };
        return { ...v, items: v.items.map((e) => ({ ...e, group: "grok", groupTitle: "SuperGrok 订阅", ...titled(grok(e.profile as Record<string, unknown>)) })) };
      }
      return undefined;
    },
  };
};
/** The demo's profile as a Cursor subscription: signed in, or being signed in again (`signingIn`: Cursor's page is up, with
 *  no code; it is only confirmed there). The workspace's list has it under its own kind too. */
const cursorAccount = (signingIn: boolean): DemoExtension => {
  const at = Date.UTC(2026, 9, 20, 3, 0);
  const login = { profile: "machine-claude", runtime: "cursor", state: "needs_approval", url: "https://cursor.com/loginDeepControl?challenge=Xq7…&uuid=5b1e…&mode=login", userCode: null, startedAt: at, expiresAt: at + 600_000 };
  const models = ["composer-2", "gpt-5.5"];
  const cursor = (p: Record<string, unknown>) => ({
    ...p, machine: false, runtime: "cursor", runtimes: ["cursor"], loginCommand: undefined, providerName: undefined,
    access: { kind: "subscription", key: "" }, quota: { state: "unavailable", windows: [], checkedAt: at }, trouble: null,
    models, available: models, modelsText: "已启用 2 / 2 个模型", series: [{ name: "Composer", models: ["composer-2"] }, { name: "GPT", models: ["gpt-5.5"] }],
    makers: { "composer-2": { id: "cursor", name: "Cursor" }, "gpt-5.5": { id: "openai", name: "OpenAI" } }, names: { "composer-2": "Composer 2", "gpt-5.5": "GPT-5.5" },
    ...(signingIn
      ? { login, check: { checkedAt: 0, state: "login", detail: "Cursor 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber" }
      : { login: null, check: { checkedAt: 0, state: "ok", detail: "已登录", models }, checkText: "可用", checkTone: "green" }),
  });
  return {
    then: (t, value) => {
      if (!value || typeof value !== "object") return undefined;
      if (t.topic === "overview") {
        const o = value as { profiles: Record<string, unknown>[] };
        return { ...o, profiles: o.profiles.map(cursor) };
      }
      if (t.topic === "profiles") {
        const v = value as { items: Record<string, unknown>[] };
        return { ...v, items: v.items.map((e) => ({ ...e, group: "cursor", groupTitle: "Cursor 订阅", ...titled(cursor(e.profile as Record<string, unknown>)) })) };
      }
      return undefined;
    },
  };
};
/** The demo's profile as a Devin subscription: signed in, or being signed in again (`signingIn`: Devin's page is up; the code
 *  it shows once signed in is pasted back, as Claude's). The workspace's list has it under its own kind too. */
const devinAccount = (signingIn: boolean): DemoExtension => {
  const at = Date.UTC(2026, 9, 21, 3, 0);
  const login = { profile: "machine-claude", runtime: "devin", state: "needs_code", url: "https://app.devin.ai/auth/cli/continue?state=4b1e…&code_challenge=Qx2…&code_challenge_method=S256&cli_pkce_marker=1", startedAt: at, expiresAt: at + 600_000 };
  const models = ["swe-2", "claude-opus-5-5"];
  const devin = (p: Record<string, unknown>) => ({
    ...p, machine: false, runtime: "devin", runtimes: ["devin"], loginCommand: undefined, providerName: undefined,
    access: { kind: "subscription", key: "" }, quota: { state: "unavailable", windows: [], checkedAt: at }, trouble: null,
    models, available: models, modelsText: "已启用 2 / 2 个模型", series: [{ name: "SWE", models: ["swe-2"] }, { name: "Claude", models: ["claude-opus-5-5"] }],
    makers: { "swe-2": { id: "devin", name: "Cognition" }, "claude-opus-5-5": { id: "anthropic", name: "Anthropic" } }, names: { "swe-2": "SWE-2", "claude-opus-5-5": "Claude Opus 5.5" },
    ...(signingIn
      ? { login, check: { checkedAt: 0, state: "login", detail: "Devin 登录已失效", models: null }, checkText: "需要登录", checkTone: "amber" }
      : { login: null, check: { checkedAt: 0, state: "ok", detail: "已登录", models }, checkText: "可用", checkTone: "green" }),
  });
  return {
    then: (t, value) => {
      if (!value || typeof value !== "object") return undefined;
      if (t.topic === "overview") {
        const o = value as { profiles: Record<string, unknown>[] };
        return { ...o, profiles: o.profiles.map(devin) };
      }
      if (t.topic === "profiles") {
        const v = value as { items: Record<string, unknown>[] };
        return { ...v, items: v.items.map((e) => ({ ...e, group: "devin", groupTitle: "Devin 订阅", ...titled(devin(e.profile as Record<string, unknown>)) })) };
      }
      return undefined;
    },
  };
};
/** A new chat on a station this workspace joined that has no profile open to it (the core's `blocked: shared`). */
const notShared: DemoExtension = {
  then: (t, value) => (t.topic === "newChat" && value && typeof value === "object"
    ? { ...(value as object), blocked: "shared", problem: "Studio 属于 Lab，其 Profile 尚未对此 workspace 开放：在 Profile 页开启「同时用于 Acme」" }
    : undefined),
};
/** The demo's station in Lab too (the core's `memberships`), and, with `joined`, Lab's Mini1 in this workspace. */
const memberships = (joined = false): DemoExtension => ({
  topic: (t) => (t.topic === "memberships" ? MEMBERSHIPS : undefined),
  then: (t, value) => {
    if (!joined || t.topic !== "stations" || !Array.isArray(value)) return undefined;
    const first = value[0] as Record<string, unknown>;
    return [...value, { ...first, station: "demo/mini1", id: "mini1", name: "Mini1", emoji: undefined, icon: "glyph:dice-1", joined: true, home: "Lab" }];
  },
});
/** Lab's Mini1 joined to this workspace, which it takes none of the members of for a security mode (the core's `blocked`). */
const blockedJoined: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "stations" || !Array.isArray(value)) return undefined;
    const first = value[0] as StationView;
    const why = "此 workspace 在此 station 加入后才开启安全模式，它不再接受此 workspace 的成员：请将它从此 workspace 移除后重新添加";
    const { overview: _, host: __, ...rest } = first;
    return [...value, { ...rest, station: "demo/mini1", id: "mini1", name: "Mini1", emoji: undefined, icon: "glyph:dice-1", joined: true, home: "Lab", online: false,
      summary: "安全模式未放行", blocked: why, link: { state: "offline", cause: "lock", message: why } }];
  },
};
/** Several of these at once: the first that answers a topic or call, each `then` over the last's value. */
const together = (...all: DemoExtension[]): DemoExtension => ({
  topic: (t) => { for (const e of all) { const v = e.topic?.(t); if (v !== undefined) return v; } return undefined; },
  then: (t, value) => { let changed: unknown; for (const e of all) { const v = e.then?.(t, changed ?? value); if (v !== undefined) changed = v; } return changed; },
  call: (name, params) => { for (const e of all) { const v = e.call?.(name, params); if (v !== undefined) return v; } return undefined; },
  stream: (name, params, emit, signal) => { for (const e of all) { const v = e.stream?.(name, params, emit, signal); if (v !== undefined) return v; } return undefined; },
});
/** A Mac station with everything its page shows: screens, grants missing, logins, variables, search, its context, two workspaces. */
const fullStation = (): DemoExtension => together(
  permissionsDemo("missing", screensDemo()), agentEnvDemo("set"), logins(), memberships(),
  { then: (t, value) => (t.topic === "stations" && Array.isArray(value)
    ? (value as StationView[]).map((s) => (s.overview ? { ...s, overview: { ...s.overview, search: { files: "spotlight", personal: false }, context: { afreshWhenCold: false }, network: { congestion: "cubic" } } } : s))
    : undefined) },
);
/** One of the demo station's screens seen, its view going as `story` says (screens.ts), alone on the window; `h264`: in
 * H.264 where the browser encodes it. */
const screenView = (story: ViewStory, phone = false, h264 = false, screen = "desktop"): Pick<Story, "render" | "demo"> => ({
  demo: screensDemo(story, undefined, h264),
  render: () => stage(<ScreenViewer station="demo/local" screen={screen} backLabel="返回" onBack={noop} onWindow={phone ? undefined : noop} phone={phone} />),
});
/** A simulator booted on the demo station (an iPhone's home screen), seen as `screenView`'s. */
const SIMULATOR = "simulator:8A1704F6-57D2-40B0-A330-B98038CB17C3";
/** With a mouse, the pointer brought to the bar at the top. */
const toTheBar: Step[] = [{ move: [640, 20] }];
/** A chat row of the demo's, the made-up ones copied from (kept from its first view, whatever is typed later). */
let shareRowLike: ShareInView["items"][number] | undefined;
/** What the share stories share: a video's link, with the title its app gave it. */
const SHARED: Shared = { source: "https://www.youtube.com/watch?v=8pDqJVdNa44", title: "在家用旧电脑搭一台 NAS：从零到能用", popup: false };
/** More chats than the demo has, for a list long enough to search (the sheet offers it from six). */
const MORE_CHATS = ["NAS 和下载", "NAS 备份到 B2", "周报：十月第三周", "官网首屏改版", "Android 分享进来", "发版 0.1.2500"];
/**
 * Where it can go, in a state of its own: `kept`, the third chat the one youtube.com's links went to last (first);
 * `new`, three stations up for a new chat; `none`, no chat and no station; `loading`, the chats not known yet;
 * `search`, more chats than the demo has, enough to search.
 */
const sharing = (state: "kept" | "new" | "none" | "loading" | "search"): Pick<Story, "demo" | "share"> => ({
  share: SHARED,
  demo: {
    then: (t, value) => {
      if (t.topic !== "shareIn" || !value) return undefined;
      const v = value as ShareInView;
      // As the core has them: the link's site known at once, whatever else is.
      const site = v.site ? { site: v.site } : {};
      if (state === "loading") return { ...site, items: [], stations: [], loading: true } satisfies ShareInView;
      if (state === "none") return { ...site, items: [], stations: [], loading: false, note: "还没有能发到的 chat，也没有在线的 station" } satisfies ShareInView;
      if (state === "new") {
        return { ...v, newOn: "demo/local", stations: [{ station: "demo/local", name: "Studio" }, { station: "demo/mini1", name: "Mini1" }, { station: "demo/mba", name: "MacBook Air" }] } satisfies ShareInView;
      }
      if (state === "search") {
        // Its own chats, then these: those the words find while searching (the demo's own are found already).
        shareRowLike ??= v.items[0];
        const { last: _, ...like } = shareRowLike ?? { last: undefined };
        const q = String(t.query ?? "").trim().toLowerCase();
        const more = shareRowLike ? MORE_CHATS.map((title, i) => ({ ...(like as ShareInView["items"][number]), id: `more-${i}`, session: `more-${i}`, title }))
          .filter((r) => !q || r.title.toLowerCase().includes(q)) : [];
        return { ...v, items: [...v.items, ...more] } satisfies ShareInView;
      }
      const k = v.items[2] ?? v.items[0]!;
      return { ...v, items: [k, ...v.items.filter((i) => i !== k)], kept: { station: k.station, id: k.id, text: "youtube.com 的链接上次发到这里" } } satisfies ShareInView;
    },
  },
});
/**
 * The demo's station's logins (data.ts LOGINS, docs/remote-login.md): `canLogin` false as a read-only member sees them,
 * `canRelay` false as a web page has them (no callback taken), `old` a station from before them; `card`, the chat's
 * first agent message carrying that login's card.
 */
const logins = ({ canLogin = true, canRelay = true, old = false, card, listed }: { canLogin?: boolean; canRelay?: boolean; old?: boolean; card?: string; listed?: string[] } = {}): DemoExtension => ({
  topic: (t) => t.topic === "machineLogins" ? (old ? { ...loginsView(), supported: false, logins: [] } : loginsView(canLogin, canRelay, listed))
    : t.topic === "machineLogin" ? (canLogin ? LOGINS[t.id] ?? null : t.id === "device" ? VIEWER_LOGIN : LOGINS[t.id] ?? null)
    : t.topic === "machineLoginScreen" ? SCREENS[t.id] ?? null
    : undefined,
  call: (name) => (name.startsWith("machineLogin.") ? null : undefined),
  then: (t, value) => {
    if (!card || t.topic !== "chat" || !value) return undefined;
    const chat = value as { messages: { authorKind: string; card?: unknown }[] };
    const first = chat.messages.findIndex((m) => m.authorKind === "agent");
    return { ...chat, messages: chat.messages.map((m, i) => (i === first ? { ...m, card: { type: "login", login: card } } : m)) };
  },
});
/** The viewer's three messages sent one after another at the chat's end: close together, the time under the last only
 *  (`followed`, `joined`). */
const followed: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "chat" || !value) return undefined;
    const chat = value as ChatView;
    const last = chat.messages.at(-1);
    if (!last) return undefined;
    const start = Date.now() - 3 * 60_000;
    const said: ChatMessage[] = ["首页的图换成新的", "按钮颜色也跟着改", "改完发我看看"].map((text, i) => {
      const at = start + i * 40_000;
      return {
        seq: last.seq + 1 + i, thread: last.thread, ts: `${at / 1000}`, authorKind: "person", author: "local", authorName: "你", text, attachments: [], quotes: [],
        createdAt: at, mine: true, system: false, by: { name: "你" }, waiting: false, time: { createdAt: stamp(at) }, ...(i < 2 ? { followed: true } : {}), ...(i > 0 ? { joined: true } : {}),
      };
    });
    return { ...chat, messages: [...chat.messages, ...said] };
  },
};
/** Its agent at rest, its prompt cache over (the core's `cacheCold`): said over the composer, with 换新上下文. */
const cacheCold: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "chat" || !value) return undefined;
    const chat = value as ChatView;
    const session = chat.agents[0]?.session.key;
    return session ? { ...chat, cacheCold: { session, text: "缓存已过期，接着聊约需 $1.49" } } : undefined;
  },
};
/** Its agent's prompt cache over and its station down: two notices over the composer, one over the other. */
const coldOffline: DemoExtension = {
  then: (t, value) => {
    const cold = cacheCold.then?.(t, value);
    return cold ? { ...(cold as ChatView), offline: true } : undefined;
  },
};
/** The chat archived: its notice over the composer, with 还原对话. */
const archivedChat: DemoExtension = {
  then: (t, value) => t.topic === "chat" && value ? { ...(value as ChatView), archived: true } : undefined,
};
/** What the chat's agent and another chat's wrote each other: not in the chat (only its bar's button says how many,
 *  the core's `letters`), read in their own tab or sheet (`chatLetters`, Letters.tsx); with `open`, that tab open. */
const letters: DemoExtension = {
  topic: (t) => {
    if (t.topic !== "chatLetters") return undefined;
    const start = Date.now() - 6 * 60_000;
    const at = (i: number) => start + i * 50_000;
    const link = "https://app.still.fail/o/w/s/ember%3Ac-4dbf0d0c6e";
    const theirs = (chat: string, from: string) => ({ name: `「${chat}」的 agent`, from, maker: ANTHROPIC });
    const mbui = "https://app.still.fail/o/w/s/ember%3Ac-06ffb79643";
    const ours = { name: "Opus 5.5", maker: ANTHROPIC, runtime: "claude" as const };
    const letter = (i: number, way: "in" | "out", text: string, by = theirs("BFT 备份尺寸分析", link)): ChatMessage => ({
      seq: 100 + i, thread: Number(t.thread), ts: `${at(i) / 1000}`, attachments: [], quotes: [], createdAt: at(i), waiting: false, time: { createdAt: stamp(at(i)) },
      authorKind: "agent", author: way === "in" ? "peer/ember:c-9" : "ember:c-1", text, md: markdown(text), mine: false, system: false, by: way === "in" ? by : ours, way,
    });
    return {
      title: "备份改成 zstd",
      whole: true,
      chats: [
        { key: mbui, title: "接手监督 mbui", link: mbui, last: "测试版 4521 已出，你这边的 #1108 等它跑完再合", lastActiveAt: at(3), time: { lastActiveAt: stamp(at(3)) }, letters: [
          letter(3, "in", "测试版 **4521** 已出，你这边的 #1108 等它跑完再合", theirs("接手监督 mbui", mbui)),
        ] },
        { key: link, title: "BFT 备份尺寸分析", link, last: "补充一点：macOS 自带的 /usr/bin/tar 能直接解 zstd，guest 里不用另装", lastActiveAt: at(2), time: { lastActiveAt: stamp(at(2)) }, letters: [
          letter(0, "in", "用户让精简备份并改用 zstd。我没有 host2 的权限，改好的两个脚本放在 `~/bft/backup/`，麻烦替换一下"),
          letter(1, "out", "已替换，**今晚 02:00** 那份会按新脚本出"),
          letter(2, "in", "补充一点：macOS 自带的 `/usr/bin/tar` 能直接解 zstd，guest 里不用另装"),
        ] },
      ],
    };
  },
  then: (t, value) => {
    if (t.topic !== "chat" || !value) return undefined;
    return { ...(value as ChatView), letters: 4 };
  },
};
/** The chat's services and background jobs (the `chatJobs` view): a web service up and a task that ended, so the title
 *  bar's button for them is there (it is not while there are none). */
const someJobs: DemoExtension = {
  topic: (t) => {
    if (t.topic !== "chatJobs") return undefined;
    const now = Date.now();
    return {
      jobs: [
        { id: "j1", name: "dev server", state: "running", port: 5173, startedAt: now - 20 * 60_000, tone: "up", service: true, open: true, current: true, word: "运行中", meta: [{ text: ":5173" }], age: "20 分钟" },
        { id: "j2", name: "pnpm test", state: "exited", exitCode: 0, startedAt: now - 9 * 60_000, endedAt: now - 7 * 60_000, tone: "off", ended: true, word: "已结束", meta: [{ text: "2 分钟" }], age: "9 分钟前" },
      ],
      servicesNote: "1 个运行中", jobsNote: "", current: 1, ended: 1, clear: ["c1"], allText: "全部 2 个", clearText: "清除已结束的", hiddenText: "",
    };
  },
};
/** A message sent while the chat's station updates: it waits for the update to finish, saying so under it
 *  (`Outgoing.waits`), and the chat's head says the station is updating. */
const sentUpdating: DemoExtension = {
  then: (t, value) => {
    if (t.topic !== "chat" || !value) return undefined;
    const chat = value as ChatView;
    const at = Date.now() - 20_000;
    return {
      ...chat,
      outbox: [{ id: "o-updating", text: "更新完把首页的图换成新的", attachments: [], quotes: [], createdAt: at, state: "sending", time: { createdAt: stamp(at) }, waits: "station 正在更新，完成后发送" }],
      stationUpdate: { tone: "busy", label: "更新中", text: "「Studio」正在更新", station: "Studio", detail: "正在等待 station 重新连接；消息仍在发送，连接恢复后自动继续", from: "0.1.3640", to: "0.1.3650", open: false, canUpdate: false, dismissible: false },
    };
  },
};
/** One login's card, as an agent's message has it. */
const loginCard = (id: string, padding?: number) => loginCards([id], padding);
/** A chat's login cards, one for each login, as an agent's message has them. */
const loginCards = (ids: string[], padding = 40) => () => stage(
  <div style={{ display: "grid", alignContent: "start", gap: 4, padding, maxWidth: 720 }}>{ids.map((id) => <LoginCard key={id} station="demo/local" id={id} />)}</div>,
);
/** The station page's 登录, as the page lays it out. */
const loginsSection = () => stage(<div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><LoginsSection station="demo/local" /></div>);
const ANTHROPIC = { id: "anthropic", name: "Anthropic" };
const OPENAI = { id: "openai", name: "OpenAI" };
const noop = () => undefined;

/** The sidebar's chats not come yet: still read from Studio (`reading`), or Studio not reachable (`failing`). */
const chatsWaiting = (state: "reading" | "failing"): DemoExtension => ({
  then: (t, value) => (t.topic !== "chats" || !value ? undefined : {
    ...(value as object), days: [],
    note: state === "reading" ? { reading: true, text: "正在从 Studio 读取对话", failing: [], empty: false }
      : { reading: false, failing: [{ station: "demo/local", text: "无法连接 Studio", message: "station 离线" }], empty: false },
  }),
});
/** Lab's Mini1 in this workspace, not reached: the bell's Station line, its mark by its name (the core's `trouble`);
 * Studio with an emoji, by its name where it is named. */
const stationDown: DemoExtension = together(memberships(true), {
  then: (t, value) => t.topic === "stations" && Array.isArray(value)
    ? value.map((s: Record<string, unknown>) => (s.station === "demo/local" ? { ...s, emoji: "🖥️" } : s))
    : t.topic !== "chats" || !value ? undefined
    : { ...(value as object), trouble: { text: "无法连接「Mini1」", state: "error", retry: false, station: "demo/mini1" } },
});
/** What the core is still reading (topics `names`): never answered, their pages waiting. */
const held = (...names: string[]): DemoExtension => ({ topic: (t) => (names.includes(t.topic) ? HELD : undefined) });
/** 用量 not come yet: its stations still read. */
const usageWaiting: DemoExtension = {
  then: (t, value) => (t.topic !== "usage" || !value ? undefined : { ...(value as object), empty: true, wait: { reading: true, text: "正在从 Studio 读取用量", failing: [], empty: false } }),
};

/** The admin console as the demo's account, the admin. */
const adminConsole = () => stage(<Console account={ACCOUNT} />);
/** To its 中继 (on the phone, from the sidebar its "/" is). */
const toRelays: Step[] = [{ click: 'a[href="/relays"]' }];
/** A part drawn alone on the app's ground, the whole window its room. */
const stage = (node: ReactNode) => <div style={{ position: "relative", width: "100%", height: "100vh", overflow: "hidden", background: vars.canvas, color: vars.text }}>{node}</div>;
/** A model control on ccvm with the workspace's models (docs/station-share.md 借用): its own, one borrowed from Studio,
 *  two only Studio has; `picked` one of those, so the panel's foot borrows it (`borrowing`: its dialog up). */
function borrowPick(picked: boolean): Picking {
  const option = (model: string, name: string, family: string, runtime: "claude" | "codex" | "dsh", more: Partial<ModelOption> = {}): ModelOption =>
    ({ model, name, family, ids: [model], runtimes: [runtime], efforts: { [runtime]: ["low", "medium", "high"] }, accounts: { [runtime]: [] }, ...more }) as ModelOption;
  const options: ModelOption[] = [
    option("claude-opus-5-5", "Opus 5.5", "Opus", "claude", { availability: "here" }),
    option("kimi-k3", "Kimi K3", "Kimi", "dsh", { availability: "borrowed", fromText: "借自 Studio", fromStation: { name: "Studio", emoji: "🖥️" } }),
    option("gpt-6-astra", "GPT-6 Astra", "GPT", "codex", { availability: "borrowable", fromText: "在 Mini1 上", fromStation: { name: "Mini1" } }),
    option("deepseek-v4-pro", "DeepSeek V4 Pro", "DeepSeek", "dsh", { availability: "borrowable", fromText: "在 Studio 上", fromStation: { name: "Studio", emoji: "🖥️" } }),
  ];
  const value = { model: "claude-opus-5-5", runtime: "claude" as const };
  const draft = picked ? { model: "deepseek-v4-pro", runtime: "dsh" as const } : value;
  const view = {
    options, runtimeFixed: false, value, valueOption: options[0], draft, option: draft.model, runtimes: [], efforts: ["low", "medium", "high"], accounts: [],
    who: "账号", autoNote: "额度用完或登录失效时自动切换", changed: picked, was: [], becomes: [], modelText: "", accountText: "自动分配", accountNote: "", accountWarn: false, saveText: "",
    ...(picked ? { borrow: {
      note: "此 station 还不能用 DeepSeek V4 Pro", title: "向 Studio 借用 zuozijian1994@gmail.com", action: "借用账号", allowed: true,
      lines: [
        "此 station 尚无可运行 DeepSeek V4 Pro 的账号。借用后，Studio 会把 Profile「zuozijian1994@gmail.com」分享给此 station，此 station 上的对话可以用它运行。",
        "此 station 会保存一份副本，Studio 离线时仍可使用。",
        "不同 station 的环境可能不同（已安装的运行时和工具、网络、文件），借用前请确认此 station 能正常使用这个账号。",
      ],
    } } : {}),
  } as unknown as PickView;
  return { view, set: noop, save: () => Promise.resolve({ saved: false }), borrow: () => new Promise(() => {}) };
}
/** The phone's list of models (mobile/History.tsx ModelList, as a chat's run settings show it), with the workspace's. */
const phoneModels = () => stage(<div style={{ width: 390, height: "100%", display: "flex", flexDirection: "column" }}><ModelList models={borrowPick(false).view!.options} runtime="claude" picked="deepseek-v4-pro" onPick={noop} /></div>);
const borrowStory = (picked: boolean) => stage(<div style={{ padding: 32 }}><ModelTriple pick={borrowPick(picked)} onConfirm={noop} /></div>);

/** Parts side by side on a page of the app: sections of them, each named. */
const sheet = (sections: [string, ReactNode][]) => stage(
  <div style={{ display: "grid", alignContent: "start", gap: 20, padding: 32, maxWidth: 880, overflowY: "auto", height: "100%", boxSizing: "border-box" }}>
    {sections.map(([title, body]) => <Section key={title} title={title}><div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12 }}>{body}</div></Section>)}
  </div>,
);
/** A small panel as it opens, drawn in place (controls.css.ts popover). */
const panel = (body: ReactNode, card = false) => (
  <div className={card ? `${controlsCss.popover} ${controlsCss.panelCard}` : controlsCss.popover} style={{ position: "static", width: 280, animation: "none" }}>{body}</div>
);

function SwitchDemo({ start, busy, disabled }: { start: boolean; busy?: boolean; disabled?: boolean }) {
  const [on, setOn] = useState(start);
  return <Switch checked={on} onChange={setOn} busy={busy} disabled={disabled} label="开关" />;
}
function SegmentedDemo({ n }: { n: 2 | 3 }) {
  const options = n === 2 ? [{ value: "a", label: "宋体" }, { value: "b", label: "黑体" }] : [{ value: "a", label: "跟随系统" }, { value: "b", label: "浅色" }, { value: "c", label: "深色" }];
  const [v, setV] = useState("a");
  return <Segmented label="选项" options={options} value={v} onChange={setV} />;
}
function SelectDemo() {
  const [v, setV] = useState("opus");
  return <div style={{ width: 240 }}><Select label="模型" value={v} onChange={setV} options={[{ value: "opus", label: "Opus 5.5", hint: "最强" }, { value: "sonnet", label: "Sonnet 5.5" }, { value: "haiku", label: "Haiku 4.5", hint: "最快" }]} /></div>;
}
function ChoicesDemo() {
  const [v, setV] = useState<string>("all");
  return <div style={{ width: 420 }}><Choices label="范围" value={v} onChange={setV} options={[{ value: "all", title: "全部会话", description: "workspace 里所有人的对话" }, { value: "mine", title: "我参与的", description: "只看自己发起或参与的" }]} /></div>;
}
/** What can wait in a composer to be sent, each kind once: a page's mark with its note, a file up, one going up, one
 * that failed, one named by its path, a folder named by its path, pasted words, a folder of the station going as a zip,
 * a link shared in (with its title, and without), a picture. */
function ComposerCards() {
  const ref = (path: string, dir = false, mode: "path" | "file" = "path") => ({ station: "demo/studio", stationName: "Studio", path, dir, mode });
  const files: Pending[] = [
    { id: "1", name: "合同-2026Q4.pdf", size: 1_468_006, done: { name: "合同-2026Q4.pdf", path: "/u/a.pdf", size: 1_468_006 }, error: null },
    { id: "2", name: "export-1013.csv", size: 22_528_000, sent: 9_000_000, done: null, error: null },
    { id: "3", name: "build.log", size: 4096, done: null, error: "station 无响应" },
    { id: "4", name: "发版录屏 1014.mp4", size: 50_541_773, done: null, error: null, ref: ref("/Users/lin/Downloads/发版录屏 1014.mp4") },
    { id: "5", name: "设计稿", size: 0, done: null, error: null, ref: ref("/Users/lin/Downloads/设计稿", true) },
    { id: "6", name: "pasted.txt", size: 5120, done: { name: "pasted.txt", path: "/u/p.txt", size: 5120 }, error: null, pasted: { preview: "error: connect ECONNREFUSED 127.0.0.1:5432 at TCPConnectWrap", characters: 5120, text: "error: connect ECONNREFUSED…" } },
    { id: "7", name: "acme", size: 0, sent: 0, done: null, error: null, ref: ref("/Users/lin/code/acme", true, "file") },
    // A link shared in (docs/share-in.md): a card as a file's, never under way; one with no title by its address.
    { id: "8", name: "在家用旧电脑搭一台 NAS：从零到能用，三块硬盘、一个周末", size: 0, done: null, error: null, link: { url: "https://www.youtube.com/watch?v=8pDqJVdNa44", title: "在家用旧电脑搭一台 NAS：从零到能用，三块硬盘、一个周末", site: "youtube.com" } },
    { id: "9", name: "https://b23.tv/x1Yz", size: 0, done: null, error: null, link: { url: "https://b23.tv/x1Yz" } },
    { id: "10", name: "story-picture.png", size: 182_000, done: { name: "story-picture.png", path: "/u/story-picture.png", size: 182_000 }, error: null, preview: PICTURE_URL },
  ];
  const quotes = [{ id: "q1", author: "定价页 · 1", role: "page", text: "「专业版 ¥99/月」这一行", comment: "改成按年付的价格，月付放到下面" }];
  const draft = { quotes, files, text: "", starting: false, asFiles: false, remove: noop, setMode: noop, setAsFiles: noop, add: noop, setText: noop, unquote: noop, comment: noop } as unknown as Draft;
  return (
    <div style={{ padding: 40, maxWidth: 820 }}>
      <form className={composerCss.composerBox} data-multiline="" style={{ display: "flex" }}>
        <ComposerExtras draft={draft} focusQuote={null} onFocused={noop} onDone={noop} />
      </form>
    </div>
  );
}

/** A message sent while its file still goes up: the file says how far it has gone, as it did in the composer. */
function OutboxUpload() {
  return (
    <div style={{ padding: 40, maxWidth: 820 }}>
      <MineMessage data-role="person">
        <MineBubble text="帮我看看是否正常" />
        <FileCard file={{ name: "Trace-20261017T025130.json.gz", size: 38_400_000 }} pending sent={16_777_216} />
      </MineMessage>
      {/* As it counts, what follows the number stands still: one, two and three digits alike. */}
      <MineMessage data-role="person">
        <FileCard file={{ name: "Trace-20261017T025130.json.gz", size: 38_400_000 }} pending sent={2_000_000} />
        <FileCard file={{ name: "Trace-20261017T025130.json.gz", size: 38_400_000 }} pending sent={38_400_000} />
      </MineMessage>
    </div>
  );
}

/** A chat's file the core downloads (chatDownloads.ts): how far on its card, its sheet filling as an upload's does; one
 * that failed, why. */
function FileDownloads() {
  const size = 52_428_800;
  const of = (state: DownloadShown["state"], loaded: number, statusText: string): DownloadShown =>
    ({ id: `s|k|${state}`, station: "s", key: "k", name: "dist.zip", title: "dist.zip", size, loaded, progress: loaded / size, state, active: state !== "failed", statusText, startedAt: 0 });
  const file = { name: "dist.zip", size, path: "work/dist.zip" };
  return (
    <div style={{ padding: 40, maxWidth: 820, display: "grid", gap: 12, justifyItems: "start" }}>
      {[null, of("going", 22_020_096, "正在下载 42% · 50 MB"), of("waiting", 10_485_760, "等待连接 station · 20%"), of("failed", 0, "下载失败：无法连接 station")].map((d) => (
        <MessageFileCard key={d?.state ?? "none"} file={file} download={d} onOpen={noop} onCancel={noop} onRetry={noop} />
      ))}
    </div>
  );
}

/** A chat's file opened (its preview), from what is here already: it opens in the viewer of its kind. */
function AttachmentDemo({ name, url, type }: { name: string; url: string; type: string }) {
  const [local, setLocal] = useState<{ blob: Blob; url: string } | null>(null);
  useEffect(() => {
    let live = true;
    void fetch(url).then((r) => r.blob()).then((b) => { if (live) { const blob = new Blob([b], { type }); setLocal({ blob, url: URL.createObjectURL(blob) }); } });
    return () => { live = false; };
  }, [url, type]);
  return local ? <FilePreview open onClose={noop} sessionKey="" file={{ name, path: `draft:${name}`, size: local.blob.size }} local={local} /> : null;
}
const NOTE_URL = URL.createObjectURL(new Blob([NOTE], { type: "text/markdown" }));

function ToastDemo({ text }: { text: string }) {
  const toast = useToast();
  useEffect(() => { toast(text); }, [toast, text]);
  return null;
}

export const stories: Story[] = [
  // ── controls ──
  {
    id: "control-buttons", group: "基础控件", title: "按钮",
    render: () => sheet([
      ["按钮", <>
        <Button variant="primary">主要</Button><Button>次要</Button><Button variant="ghost">幽灵</Button>
        <Button variant="danger">危险</Button><Button variant="danger-solid">删除</Button>
        <Button variant="primary" icon={Plus}>带图标</Button><Button busy>处理中</Button><Button disabled>不可用</Button>
      </>],
      ["图标按钮", <>
        <IconButton label="刷新" icon={Refresh} /><IconButton label="搜索" icon={Search} /><IconButton label="编辑" icon={Edit} />
        <IconButton label="删除" icon={Trash} /><IconButton label="处理中" icon={Download} busy /><IconButton label="失败" icon={Download} failed="未连接" />
      </>],
      ["小面板按钮", <>
        <PanelButton tone="accent">看看</PanelButton><PanelButton>普通</PanelButton><PanelButton tone="quiet">次要</PanelButton>
        <PanelButton tone="filled">现在更新</PanelButton><PanelIconButton label="关闭"><Close size={14} /></PanelIconButton>
      </>],
    ]),
  },
  { id: "control-buttons-hover", group: "基础控件", title: "按钮 · 悬停", render: () => sheet([["按钮", <><Button variant="ghost">幽灵</Button><IconButton label="刷新" icon={Refresh} /><PanelButton tone="accent">看看</PanelButton></>]]), steps: [{ hover: "text=幽灵" }] },
  {
    id: "control-fields", group: "基础控件", title: "输入框",
    render: () => sheet([
      ["单行", <div style={{ display: "grid", gap: 12, width: 360 }}>
        <Field label="名字" hint="会显示在侧栏和对话里"><input className={controlsCss.input} defaultValue="Studio" /></Field>
        <Field label="地址" error="这个地址打不开"><input className={controlsCss.input} defaultValue="http://127.0.0.1:3000" /></Field>
        <Field label="空的"><input className={controlsCss.input} placeholder="还没填" /></Field>
      </div>],
      ["多行", <div style={{ width: 420 }}><Field label="说明"><textarea className={controlsCss.input} rows={3} defaultValue={"归档建议：\n超过 7 天没有新消息、也没有在跑的任务"} /></Field></div>],
    ]),
  },
  { id: "control-fields-focus", group: "基础控件", title: "输入框 · 聚焦", render: () => sheet([["单行", <div style={{ width: 360 }}><Field label="名字"><input className={controlsCss.input} defaultValue="Studio" /></Field></div>]]), steps: [{ click: "input" }] },
  { id: "control-segmented", group: "基础控件", title: "分段控件", render: () => sheet([["两项", <SegmentedDemo n={2} />], ["三项", <SegmentedDemo n={3} />]]) },
  { id: "control-choices", group: "基础控件", title: "选项卡片", render: () => sheet([["单选", <ChoicesDemo />]]) },
  {
    id: "control-switches", group: "基础控件", title: "开关",
    render: () => sheet([
      ["开关", <><SwitchDemo start /><SwitchDemo start={false} /><SwitchDemo start busy /><SwitchDemo start={false} disabled /></>],
      ["带说明", <div style={{ width: 420 }}><SwitchRow title="自动归档" description="超过 7 天没动静的对话移到归档" checked onChange={noop} /></div>],
    ]),
  },
  { id: "control-select", group: "基础控件", title: "下拉框", render: () => sheet([["下拉", <SelectDemo />]]) },
  { id: "control-select-open", group: "基础控件", title: "下拉框 · 展开", render: () => sheet([["下拉", <SelectDemo />]]), steps: [{ click: '[role="combobox"]' }] },
  { id: "control-menu-open", group: "基础控件", title: "「…」菜单", render: () => sheet([["菜单", <Menu items={[{ label: "重命名", icon: Edit, onSelect: noop }, { label: "复制链接", icon: Copy, onSelect: noop }, "separator", { label: "归档", icon: Archive, onSelect: noop }, { label: "删除", icon: Trash, danger: true, onSelect: noop }]} />]]), steps: [{ click: '[aria-label="更多操作"]' }] },
  { id: "control-tip", group: "基础控件", title: "提示", render: () => sheet([["提示", <Tip label="新建对话"><IconButton label="新建对话" icon={Plus} /></Tip>]]), steps: [{ hover: '[aria-label="新建对话"]' }] },
  {
    id: "control-marks", group: "基础控件", title: "标签、状态和标记",
    render: () => sheet([
      ["标签", <><Pill>普通</Pill><Pill tone="green">在线</Pill><Pill tone="blue">进行中</Pill><Pill tone="amber">等待</Pill><Pill tone="red">失败</Pill><Pill tone="accent">强调</Pill></>],
      ["状态", <><StatusDot state="online" label="在线" /><StatusDot state="busy" label="忙" /><StatusDot state="error" label="出错" /><StatusDot state="offline" label="离线" /><StatusText text="已连接 · 3 分钟前" /></>],
      ["模型和运行时", <><ModelLogo maker={ANTHROPIC} runtime="claude" size={20} /><ModelLogo maker={OPENAI} runtime="codex" size={20} /><ModelLogo maker={null} runtime="dsh" size={20} /><ModelLogo maker={null} runtime="grok" size={20} /><ModelLogo maker={null} runtime="cursor" size={20} /><ModelLogo maker={null} runtime="devin" size={20} /><AgentMark maker={ANTHROPIC} runtime="claude" badge={undefined} size={28} /><RuntimeTags runtimes={["claude", "codex", "dsh", "grok", "cursor", "devin"]} /></>],
    ]),
  },
  {
    id: "control-states", group: "基础控件", title: "等待、空和命令",
    render: () => sheet([
      ["列表第一次读取", <div style={{ width: 420 }}><Waiting text="正在读取会话" sample={<ChatRowsSample lead="agents" />} /></div>],
      ["设置页第一次读取", <div style={{ width: 420 }}><Waiting sample={<PriceTables view={SAMPLE_USAGE} />} /></div>],
      ["一节内容", <WaitLine text="正在读取配置" />],
      ["胶囊", <><WaitPill text="正在连接 Studio" /><WaitPill text="无法连接 MBA" error /></>],
      ["进度", <div style={{ display: "grid", gap: 12, width: 240 }}><Progress part={0.4} /><Progress part={null} /></div>],
      ["空", <div style={{ width: 420 }}><Empty>还没有对话</Empty></div>],
      ["命令", <div style={{ width: 520 }}><CopyCommand text="curl -fsSL https://still.fail/install.sh | sh" /></div>],
    ]),
  },
  {
    id: "control-panel-parts", group: "基础控件", title: "小面板部件",
    render: () => sheet([
      ["列表", panel(<>
        <PanelHead title="自定义侧边条" note="拖动换位置，点 − 拿掉" />
        <PanelGroup label="对话列表"><PanelRow icon={<Folder size={18} />} label="文件" end={<Plus size={16} />} onClick={noop} /><PanelRow icon={<Archive size={18} />} label="已归档" end={<Plus size={16} />} onClick={noop} /></PanelGroup>
      </>)],
      ["卡片", panel(<><PanelText><b>Studio</b> 有新版本</PanelText><PanelText>更新时会重启 station，正在跑的 agent 会接着跑。</PanelText></>, true)],
    ]),
  },

  { id: "composer-cards", group: "对话", title: "输入框里的附件", render: () => stage(<ComposerCards />) },
  { id: "math", group: "对话", title: "数学公式 · 行内与独立", render: () => stage(<div className={conversationCss.markdown} style={{ maxWidth: 720, width: "100%", padding: 24 }}><Prose>{MATH}</Prose></div>) },
  { id: "code-colours", group: "对话", title: "代码块 · 各语言的颜色", render: () => stage(<div className={conversationCss.markdown} style={{ maxWidth: 720, padding: 24 }}><MdView md={CODE_COLOURS.md} source={CODE_COLOURS.text} /></div>) },
  // A table's copy key on a row of its own over it, its menu open (docs/ui-panels.md 复制表格).
  { id: "table-copy", group: "对话", title: "表格 · 复制", render: () => stage(<div className={conversationCss.markdown} style={{ maxWidth: 720, padding: 24 }}><MdView md={TABLE.md} source={TABLE.text} /></div>), steps: [{ click: '[aria-label="复制表格"]' }] },
  { id: "outbox-upload", group: "对话", title: "发出后还在上传的附件", render: () => stage(<OutboxUpload />) },
  { id: "file-downloads", group: "对话", title: "下载中的附件", render: () => stage(<FileDownloads />) },
  { id: "runtime-missing", group: "对话", title: "缺少运行时 · 安装", app: true, demo: installDemo("missing") },
  { id: "runtime-installing", group: "对话", title: "缺少运行时 · 正在安装", app: true, demo: installDemo("installing") },
  { id: "runtime-install-failed", group: "对话", title: "缺少运行时 · 安装失败", app: true, demo: installDemo("failed") },
  { id: "runtime-missing-member", group: "对话", title: "缺少运行时 · 成员", app: true, demo: installDemo("member") },
  { id: "runtime-missing-notice", group: "对话", title: "缺少运行时 · 别人的消息", app: true, demo: installDemo("notice") },
  { id: "phone-runtime-missing", group: "对话", title: "手机 · 缺少运行时 · 安装", app: true, phone: true, demo: installDemo("missing") },
  { id: "turn-failed-report", group: "对话", title: "本轮出错 · 上报", app: true, demo: installDemo("report") },
  { id: "phone-turn-failed-report", group: "对话", title: "手机 · 本轮出错 · 上报", app: true, phone: true, demo: installDemo("report") },
  { id: "turn-failed-report-ask", group: "对话", title: "本轮出错 · 上报 · 确认", app: true, demo: installDemo("report"), steps: [{ text: "上报" }] },

  // ── dialogs and toasts ──
  { id: "dialog", group: "弹窗", title: "弹窗", render: () => stage(<Dialog open title="添加 station" description="在要接入的机器上运行这条命令。" onClose={noop} footer={<><Button variant="ghost">取消</Button><Button variant="primary">完成</Button></>}><CopyCommand text="curl -fsSL https://still.fail/install.sh | sh" /></Dialog>) },
  { id: "dialog-wide", group: "弹窗", title: "弹窗 · 宽", render: () => stage(<Dialog open wide title="分享对话" onClose={noop} footer={<Button variant="primary">完成</Button>}><Choices label="范围" value="all" onChange={noop} options={[{ value: "all", title: "全部", description: "workspace 里的所有人" }, { value: "mine", title: "只给我", description: "只有自己能看" }]} /></Dialog>) },
  { id: "dialog-confirm", group: "弹窗", title: "确认", render: () => stage(<Confirm open title="删除「设计稿」？" description="文件夹和里面的文件都会删除，不能恢复。" action="删除" onConfirm={noop} onClose={noop} />) },
  { id: "dialog-confirm-error", group: "弹窗", title: "确认 · 失败", render: () => stage(<Confirm open title="归档这个对话？" description="归档后有新消息会自动恢复。" action="归档" onConfirm={noop} onClose={noop} error="station 无响应" />) },
  { id: "toast", group: "弹窗", title: "toast", render: () => stage(<ToastDemo text="已复制链接" />) },
  { id: "toast-long", group: "弹窗", title: "toast · 长", render: () => stage(<ToastDemo text="没能上传：http://127.0.0.1:4760/upload 返回 413，文件超过了 station 允许的大小（200 MB）" />) },

  // ── the app (the site's demo) ──
  { id: "app-chat", group: "应用", title: "对话页", app: true },
  { id: "app-chat-files", group: "应用", title: "对话 · 消息里的附件", app: true, files: true },
  { id: "app-chat-followed", group: "应用", title: "对话 · 连发几条", app: true, demo: followed },
  { id: "app-chat-cache-cold", group: "应用", title: "对话 · 缓存已过期", app: true, demo: cacheCold },
  { id: "phone-chat-cache-cold", group: "手机", title: "对话 · 缓存已过期", app: true, phone: true, demo: cacheCold },
  { id: "app-chat-cold-offline", group: "应用", title: "对话 · 缓存已过期，station 连不上", app: true, demo: coldOffline },
  { id: "phone-chat-cold-offline", group: "手机", title: "对话 · 缓存已过期，station 连不上", app: true, phone: true, demo: coldOffline },
  { id: "app-chat-archived", group: "应用", title: "对话 · 已归档", app: true, demo: archivedChat },
  { id: "phone-chat-archived", group: "手机", title: "对话 · 已归档", app: true, phone: true, demo: archivedChat },
  { id: "phone-chat-followed", group: "手机", title: "对话 · 连发几条", app: true, phone: true, demo: followed },
  // A chat shared as a picture: its messages as the chat's list draws them (the visitor's in their bubble, a vault
  // request as its card), its files to tick.
  { id: "app-chat-share-image", group: "应用", title: "对话 · 分享图片", app: true, demo: shareImageDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=分享图片" }] },
  { id: "phone-chat-share-image", group: "手机", title: "对话 · 分享图片", app: true, phone: true, demo: shareImageDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=分享图片" }] },
  { id: "app-chat-letters-entry", group: "应用", title: "对话 · agent 往来的入口（对话信息里）", app: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "app-chat-letters", group: "应用", title: "对话 · agent 往来", app: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }] },
  { id: "app-chat-letters-open", group: "应用", title: "对话 · agent 往来 · 打开一个对话的", app: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }, { click: "text=BFT 备份尺寸分析" }] },
  { id: "app-chat-things-entry", group: "应用", title: "对话 · 对话信息里的 PR 和「图片、文件和链接」", app: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "app-chat-things", group: "应用", title: "对话 · 图片、文件和链接", app: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }] },
  { id: "app-chat-things-pulls", group: "应用", title: "对话 · 图片、文件和链接 · PR", app: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }, { click: '[role="radio"]:has-text("PR")' }] },
  { id: "app-chat-things-hover", group: "应用", title: "对话 · 图片、文件和链接 · PR 悬停", app: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }, { click: '[role="radio"]:has-text("PR")' }, { hover: "text=首页列表按天分组 >> nth=0" }] },
  { id: "app-chat-things-menu", group: "应用", title: "对话 · 图片、文件和链接 · 右键菜单", app: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }, { rightClick: '[class*="tile"] >> nth=0' }] },
  { id: "phone-chat-things-entry", group: "手机", title: "对话 · 对话信息里的 PR 和「图片、文件和链接」", app: true, phone: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "phone-chat-things", group: "手机", title: "对话 · 图片、文件和链接", app: true, phone: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }] },
  { id: "phone-chat-things-pulls", group: "手机", title: "对话 · 图片、文件和链接 · PR", app: true, phone: true, demo: thingsDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=图片、文件和链接" }, { click: '[role="radio"]:has-text("PR")' }] },
  { id: "phone-chat-letters-info", group: "手机", title: "对话 · agent 往来的入口（对话信息里）", app: true, phone: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "phone-chat-letters", group: "手机", title: "对话 · agent 往来", app: true, phone: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }] },
  { id: "phone-chat-letters-open", group: "手机", title: "对话 · agent 往来 · 打开一个对话的", app: true, phone: true, demo: letters, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }, { click: "text=BFT 备份尺寸分析" }] },
  { id: "app-chat-sent-updating", group: "应用", title: "对话 · station 更新时发出的消息", app: true, demo: sentUpdating },
  { id: "phone-chat-sent-updating", group: "手机", title: "对话 · station 更新时发出的消息", app: true, phone: true, demo: sentUpdating },
  { id: "phone-chat-files", group: "手机", title: "对话 · 消息里的附件", app: true, phone: true, files: true },
  { id: "app-chat-history", group: "应用", title: "执行历史", app: true, steps: [{ click: '[aria-label$="的执行历史"]' }] },
  { id: "app-chat-history-turns", group: "应用", title: "执行历史 · 一轮一轮", app: true, steps: [{ click: '[aria-label$="的执行历史"]' }], demo: historyTurns },
  { id: "app-chat-side", group: "应用", title: "对话 · 侧栏打开", app: true, steps: [{ click: '[aria-label="打开侧栏"]' }] },
  // A tab's × pointed at, behind and in front: the tab stays lit, the × a step more (docs/ui-panels.md 悬停).
  { id: "app-chat-side-tab-close", group: "应用", title: "对话 · 侧栏标签的 × 悬停", app: true, demo: letters, steps: [{ click: '[aria-label$="的执行历史"]' }, { click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }, { hover: '[class*="sideTabWrap"]:first-child [class*="sideTabClose"]' }] },
  { id: "app-chat-side-front-close", group: "应用", title: "对话 · 侧栏当前标签的 × 悬停", app: true, demo: letters, steps: [{ click: '[aria-label$="的执行历史"]' }, { click: '[aria-label="对话信息"]' }, { click: "text=agent 往来" }, { hover: '[class*="sideTabWrap"]:last-child [class*="sideTabClose"]' }] },
  { id: "app-chat-relay", group: "应用", title: "对话 · 接力到频道", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }] },
  { id: "app-chat-cc", group: "应用", title: "对话 · 抄送", app: true, demo: ccDemo() },
  { id: "app-chat-cc-on", group: "应用", title: "对话 · 抄送 · 勾了一个", app: true, demo: ccDemo([21]) },
  { id: "app-chat-cc-open", group: "应用", title: "对话 · 抄送 · 写字时", app: true, demo: ccDemo(), steps: [{ click: "textarea" }] },
  { id: "app-chat-cc-open-on", group: "应用", title: "对话 · 抄送 · 写字时勾了一个", app: true, demo: ccDemo([21]), steps: [{ click: "textarea" }] },
  { id: "app-chat-cc-menu", group: "应用", title: "对话 · 抄送 · 选到哪", app: true, demo: ccDemo([21]), steps: [{ click: "textarea" }, { click: "text=抄送" }] },
  { id: "phone-chat-cc-on", group: "手机", title: "对话 · 抄送 · 勾了一个", app: true, phone: true, demo: ccDemo([21]) },
  { id: "app-chat-relay-picked", group: "应用", title: "对话 · 接力到频道 · 选中一个", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { text: "#cue-dev" }] },
  // The note's `@`: the people of the place picked in a popover under it, the first chosen; ↓ the next.
  { id: "app-chat-relay-mention", group: "应用", title: "对话 · 接力到频道 · 附言里 @", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { text: "#cue-dev" }, { key: "@" }] },
  { id: "app-chat-relay-mention-down", group: "应用", title: "对话 · 接力到频道 · 附言里 @ · ↓", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { text: "#cue-dev" }, { key: "@" }, { key: "j" }, { key: "ArrowDown" }] },
  { id: "app-chat-relay-all", group: "应用", title: "对话 · 接力到频道 · 显示全部", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { text: "显示全部 10 个" }] },
  { id: "app-chat-relay-bot", group: "应用", title: "对话 · 接力到频道 · 换一个 bot", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { click: '[aria-label="用哪个 bot"] button:nth-child(2)' }] },
  { id: "app-chat-relay-search", group: "应用", title: "对话 · 接力到频道 · 搜索", app: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }, { click: '[aria-label="搜索频道或群"]' }, { key: "d" }] },
  { id: "app-chat-relay-none", group: "应用", title: "对话 · 接力到频道 · 没有连接", app: true, demo: relayDemo([]), steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=接力到频道…" }] },
  { id: "app-sidebar-folded", group: "应用", title: "侧栏收起", app: true, steps: [{ click: '[aria-label="对话"]' }] },
  { id: "app-sidebar-peek", group: "应用", title: "侧栏收起后临时展开", app: true, steps: [{ click: '[aria-label="对话"]' }, { hover: '[aria-label="对话"]' }, { move: [150, 60] }] },
  { id: "app-new-chat", group: "应用", title: "新建对话", app: true, steps: [{ text: "新建对话" }] },
  { id: "app-new-chat-files", group: "应用", title: "新建对话 · Station 文件", app: true, steps: [{ text: "新建对话" }, { click: '[aria-label="Station 文件"]' }, { text: "Downloads" }] },
  { id: "app-new-chat-files-added", group: "应用", title: "新建对话 · Station 文件 · 发路径", app: true, steps: [{ text: "新建对话" }, { click: '[aria-label="Station 文件"]' }, { text: "Downloads" }, { rightClick: "button:has-text(\"发版录屏 1014.mp4\")" }, { text: "添加到消息" }] },
  { id: "app-todo", group: "应用", title: "待处理", app: true, steps: [{ click: '[aria-label="待处理"]' }] },
  { id: "app-todo-station-down", group: "应用", title: "待处理 · station 连不上", app: true, demo: stationDown, steps: [{ click: '[aria-label="待处理"]' }] },
  { id: "app-files", group: "应用", title: "文件", app: true, steps: [{ click: '[aria-label="文件"]' }] },
  { id: "app-files-home", group: "应用", title: "文件 · 主目录", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }] },
  { id: "app-files-deep", group: "应用", title: "文件 · 分栏", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { text: "code" }, { text: "acme" }, { text: "web" }] },
  { id: "app-files-columns-hover", group: "应用", title: "文件 · 分栏 · 悬停展开的文件夹", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { text: "code" }, { text: "acme" }, { text: "web" }, { hover: 'button:has-text("acme")' }] },
  { id: "app-files-column-edge", group: "应用", title: "文件 · 分栏 · 调整栏宽", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { text: "code" }, { text: "acme" }, { text: "web" }, { hover: '[role="separator"][aria-label="调整栏宽"]' }] },
  { id: "app-files-tree", group: "应用", title: "文件 · 文件树", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { click: '[aria-label="文件树"]' }, { text: "code" }, { key: "ArrowRight" }, { key: "ArrowRight" }, { key: "ArrowRight" }, { key: "ArrowRight" }, { key: "ArrowDown" }, { key: "ArrowRight" }] },
  { id: "app-files-list", group: "应用", title: "文件 · 列表", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { click: '[aria-label="列表"]' }] },
  { id: "app-files-row-menu", group: "应用", title: "文件 · 文件夹右键", app: true, steps: [{ click: '[aria-label="文件"]' }, { text: "主目录" }, { rightClick: "button:has-text(\"Movies\")" }] },
  { id: "app-files-stations", group: "应用", title: "文件 · 两台 station", app: true, demo: filesDemo(), steps: [{ click: '[aria-label="文件"]' }, { text: "Studio" }, { click: '[aria-label="展开 MBA"]' }] },
  { id: "app-files-tabs", group: "应用", title: "文件 · 多标签", app: true, demo: filesDemo(), steps: [{ click: '[aria-label="文件"]' }, { text: "Studio" }, { click: '[aria-label="新标签"]' }, { text: "MBA" }] },
  { id: "app-files-split", group: "应用", title: "文件 · 左右分栏", app: true, demo: filesDemo(), steps: [{ click: '[aria-label="文件"]' }, { text: "Studio" }, { text: "Downloads" }, { click: '[aria-label="左右分栏"]' }, { text: "MBA" }, { text: "项目" }] },
  { id: "app-files-transfers", group: "应用", title: "文件 · 传输", app: true, demo: filesDemo(TRANSFERS), steps: [{ click: '[aria-label="文件"]' }, { text: "Studio" }, { click: 'button:has-text("个传输")' }] },
  { id: "app-chat-files", group: "应用", title: "对话 · Station 文件", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }] },
  { id: "app-chat-files-folder", group: "应用", title: "对话 · Station 文件 · 文件夹", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }, { text: "Downloads" }] },
  { id: "app-chat-files-tree", group: "应用", title: "对话 · Station 文件 · 文件树", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }, { click: '[aria-label="文件树"]' }, { text: "code" }, { key: "ArrowRight" }, { key: "ArrowRight" }, { key: "ArrowRight" }] },
  { id: "app-chat-files-menu", group: "应用", title: "对话 · Station 文件 · 右键", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }, { text: "Downloads" }, { rightClick: "button:has-text(\"login-375.png\")" }] },
  { id: "app-chat-files-added", group: "应用", title: "对话 · Station 文件 · 发路径", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }, { text: "Downloads" }, { rightClick: "button:has-text(\"发版录屏 1014.mp4\")" }, { text: "添加到消息" }] },
  { id: "app-chat-files-card", group: "应用", title: "对话 · 文件卡片悬停", app: true, steps: [{ click: '[aria-label="对话信息"]' }, { click: "text=Station 文件" }, { text: "Downloads" }, { rightClick: "button:has-text(\"发版录屏 1014.mp4\")" }, { text: "添加到消息" }, { hover: "text=Studio · 路径" }] },
  { id: "app-station", group: "应用", title: "station", app: true, steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-station-mark", group: "应用", title: "station · 选图标", app: true, steps: [{ click: '[aria-label^="Station"]' }, { click: '[aria-label^="为 Studio 选择图标"]' }] },
  { id: "app-station-workspaces", group: "应用", title: "station · 在几个 workspace 里", app: true, demo: memberships(), steps: toStation("设置") },
  { id: "app-station-joined", group: "应用", title: "station · 从别的 workspace 加入的", app: true, demo: memberships(true), steps: [{ click: '[aria-label^="Station"]' }, { text: "Mini1" }] },
  { id: "app-station-blocked", group: "应用", title: "station · 安全模式未放行", app: true, demo: blockedJoined, steps: [{ click: '[aria-label^="Station"]' }, { text: "Mini1" }] },
  { id: "phone-station-blocked", group: "应用", title: "手机 · station · 安全模式未放行", app: true, phone: true, demo: blockedJoined, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { text: "Mini1" }] },
  { id: "app-station-add-existing", group: "应用", title: "添加 station · 已有的", app: true, demo: joining("list"), steps: [{ click: '[aria-label^="Station"]' }, { text: "添加 station" }, { text: "已有的 station" }] },
  { id: "app-first-station-existing", group: "应用", title: "第一台 station · 也可加已有的", app: true, demo: firstJoining },
  { id: "app-first-station-existing-open", group: "应用", title: "第一台 station · 选已有的", app: true, demo: firstJoining, steps: [{ text: "添加其他 workspace 的 station" }] },
  { id: "app-station-add-existing-error", group: "应用", title: "添加 station · 加入失败", app: true, demo: joining("error"), steps: [{ click: '[aria-label^="Station"]' }, { text: "添加 station" }, { text: "已有的 station" }, { text: "添加到此 workspace" }] },
  { id: "app-profile", group: "应用", title: "Profile", app: true, steps: [{ click: '[aria-label="Profile"]' }] },
  { id: "app-profile-workspaces", group: "应用", title: "Profile · 也给加入的 workspace 用", app: true, demo: profileFor(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-workspaces-on", group: "应用", title: "Profile · 已开放给加入的 workspace", app: true, demo: profileFor(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-add-model", group: "应用", title: "Profile · 按名称添加模型", app: true, demo: addModel, steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-hermes-models", group: "应用", title: "Hermes · 读取模型和按名称添加", app: true, demo: hermesModels, steps: [{ click: '[aria-label="Profile"]' }, { text: "Hermes Agent" }] },
  { id: "app-profile-opencode", group: "应用", title: "Profile · OpenCode Go 账号登录", app: true, demo: openCode(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-opencode-signing-in", group: "应用", title: "Profile · OpenCode Go 重新登录（设备码）", app: true, demo: openCode(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-kimi-signing-in", group: "应用", title: "Profile · Kimi Code 重新登录（设备码）", app: true, demo: kimiCode, steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-supergrok", group: "应用", title: "Profile · SuperGrok 订阅（Grok Build）", app: true, demo: superGrok(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-claude-signing-in", group: "应用", title: "Profile · Claude 订阅重新登录（贴回代码）", app: true, demo: claudeSignIn, steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-claude-signing-in-station", group: "应用", title: "Profile · Claude 订阅重新登录 · 「其他方式」打开", app: true, demo: claudeSigningIn(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }, { click: '[aria-label="其他方式"]' }] },
  { id: "app-profile-add-install", group: "应用", title: "添加 Profile · SuperGrok · 先安装 Grok Build", app: true, demo: installFlowDemo("missing"), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-add-installing", group: "应用", title: "添加 Profile · SuperGrok · 正在安装 Grok Build", app: true, demo: installFlowDemo("installing"), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-supergrok-signing-in", group: "应用", title: "Profile · SuperGrok 重新登录（设备码）", app: true, demo: superGrok(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-add-kimi", group: "应用", title: "添加 Profile · Kimi：订阅 Kimi Code 或 API key", app: true, demo: kimiMethodDemo(), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-add-cursor", group: "应用", title: "添加 Profile · 选择服务商（Cursor 只有订阅）", app: true, demo: cursorPickDemo(), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-cursor", group: "应用", title: "Profile · Cursor 订阅", app: true, demo: cursorAccount(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-cursor-signing-in", group: "应用", title: "Profile · Cursor 重新登录（无代码，打开页面确认）", app: true, demo: cursorAccount(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-pick-models-reading", group: "应用", title: "添加 Profile · 选择模型 · 正在读取", app: true, demo: pickModelsDemo(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }, { text: ADD }] },
  { id: "app-profile-pick-models", group: "应用", title: "添加 Profile · 选择模型", app: true, demo: pickModelsDemo(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }, { text: ADD }] },
  { id: "app-profile-add-devin", group: "应用", title: "添加 Profile · 选择服务商（Cursor、Devin 只有订阅）", app: true, demo: cursorPickDemo(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-add-hermes", group: "应用", title: "添加 Profile · Hermes Agent · 环境变量", app: true, demo: cursorPickDemo(true, true), steps: [{ click: '[aria-label="Profile"]' }, { text: "添加 Profile" }] },
  { id: "app-profile-devin", group: "应用", title: "Profile · Devin 订阅", app: true, demo: devinAccount(false), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "app-profile-devin-signing-in", group: "应用", title: "Profile · Devin 重新登录（贴回代码）", app: true, demo: devinAccount(true), steps: [{ click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "pick-workspace-models", group: "选模型", title: "模型 · 本机、借用的、可借用的", render: () => borrowStory(false), steps: [{ click: "text=Opus 5.5" }] },
  { id: "pick-borrow", group: "选模型", title: "模型 · 选了别的 station 的，借用", render: () => borrowStory(true), steps: [{ click: "text=Opus 5.5" }] },
  { id: "pick-phone-models", group: "选模型", title: "手机 · 模型列表（本机、借用的、可借用的）", phone: true, render: phoneModels },
  { id: "pick-borrow-confirm", group: "选模型", title: "模型 · 借用前再次确认", render: () => borrowStory(true), steps: [{ click: "text=Opus 5.5" }, { click: "text=借用账号" }] },
  { id: "app-new-chat-not-shared", group: "应用", title: "新建对话 · 加入的 station 没有开放的 Profile", app: true, demo: notShared, steps: [{ text: "新建对话" }] },
  { id: "app-connects", group: "应用", title: "连接", app: true, steps: [{ click: '[aria-label="连接"]' }] },
  { id: "app-connect-platform", group: "连接", title: "添加连接 · 选平台", app: true, demo: feishuFlowDemo("platform"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-platform-old", group: "连接", title: "添加连接 · 选平台 · station 尚无飞书", app: true, demo: feishuFlowDemo("old"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-bind", group: "连接", title: "添加连接 · 飞书 · 绑定模型", app: true, demo: feishuFlowDemo("bind"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-way", group: "连接", title: "添加连接 · 飞书 · 创建方式", app: true, demo: feishuFlowDemo("way"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-scan", group: "连接", title: "添加连接 · 飞书 · 扫码等待", app: true, demo: feishuFlowDemo("scan"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-expired", group: "连接", title: "添加连接 · 飞书 · 二维码过期", app: true, demo: feishuFlowDemo("expired"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-made", group: "连接", title: "添加连接 · 飞书 · 已创建，正在添加", app: true, demo: feishuFlowDemo("made"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-made-failed", group: "连接", title: "添加连接 · 飞书 · 已创建，添加失败", app: true, demo: feishuFlowDemo("made-failed"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-app", group: "连接", title: "添加连接 · 飞书 · 已有应用", app: true, demo: feishuFlowDemo("app"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-app-wrong", group: "连接", title: "添加连接 · 飞书 · 已有应用 · 验证失败", app: true, demo: feishuFlowDemo("app-wrong"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "app-connect-app-verified", group: "连接", title: "添加连接 · 飞书 · 已有应用 · 已验证", app: true, demo: feishuFlowDemo("app-verified"), steps: [{ click: '[aria-label="连接"]' }, { text: "添加连接" }] },
  { id: "phone-connect-platform", group: "连接", title: "手机 · 添加连接 · 选平台", app: true, phone: true, demo: feishuFlowDemo("platform", true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: '[aria-label="添加连接"]' }] },
  { id: "phone-connect-way", group: "连接", title: "手机 · 添加连接 · 飞书 · 创建方式", app: true, phone: true, demo: feishuFlowDemo("way", true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: '[aria-label="添加连接"]' }] },
  { id: "phone-connect-scan", group: "连接", title: "手机 · 添加连接 · 飞书 · 扫码等待", app: true, phone: true, demo: feishuFlowDemo("scan", true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: '[aria-label="添加连接"]' }] },
  { id: "phone-connect-expired", group: "连接", title: "手机 · 添加连接 · 飞书 · 二维码过期", app: true, phone: true, demo: feishuFlowDemo("expired", true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: '[aria-label="添加连接"]' }] },
  { id: "phone-connect-app-verified", group: "连接", title: "手机 · 添加连接 · 飞书 · 已有应用 · 已验证", app: true, phone: true, demo: feishuFlowDemo("app-verified", true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: '[aria-label="添加连接"]' }] },
  { id: "app-connects-feishu", group: "连接", title: "连接列表 · 含飞书", app: true, demo: feishuConnectDemo(), steps: [{ click: '[aria-label="连接"]' }] },
  { id: "app-connect-feishu", group: "连接", title: "飞书连接 · 已连接", app: true, demo: feishuConnectDemo(), steps: [{ click: '[aria-label="连接"]' }, { click: "text=Codex 机器人" }] },
  { id: "app-connect-feishu-error", group: "连接", title: "飞书连接 · 出错", app: true, demo: feishuConnectDemo(true), steps: [{ click: '[aria-label="连接"]' }, { click: "text=Codex 机器人" }] },
  { id: "phone-connect-feishu", group: "连接", title: "手机 · 飞书连接 · 已连接", app: true, phone: true, demo: feishuConnectDemo(), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "连接" }, { click: "text=Codex 机器人" }] },
  { id: "app-usage", group: "应用", title: "用量", app: true, steps: [{ click: '[aria-label="用量"]' }] },

  // ── waiting (docs/ui-panels.md「等待」): a list or page read the first time, a row or button at work ──
  { id: "app-waiting-chats", group: "等待", title: "侧栏 · 正在读取对话", app: true, demo: chatsWaiting("reading") },
  { id: "app-waiting-failing", group: "等待", title: "侧栏 · station 无法连接", app: true, demo: chatsWaiting("failing") },
  { id: "app-waiting-usage", group: "等待", title: "设置页 · 正在读取用量", app: true, demo: usageWaiting, steps: [{ click: '[aria-label="用量"]' }] },
  { id: "app-waiting-chat", group: "等待", title: "对话 · 正在读取消息", app: true, demo: held("chat") },
  { id: "app-waiting-memory", group: "等待", title: "设置页 · 正在读取记忆", app: true, demo: held("memory"), steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }] },
  { id: "phone-waiting-chats", group: "等待", title: "手机 · 首页 · 正在读取对话", app: true, phone: true, demo: chatsWaiting("reading"), steps: [{ click: '[aria-label="返回"]' }] },
  { id: "phone-waiting-chat", group: "等待", title: "手机 · 对话 · 正在读取消息", app: true, phone: true, demo: held("chat") },
  { id: "phone-waiting-memory", group: "等待", title: "手机 · 记忆 · 正在读取", app: true, phone: true, demo: held("memory"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }] },
  { id: "phone-waiting-stations", group: "等待", title: "手机 · Station · 正在读取", app: true, phone: true, demo: held("stations"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }] },
  { id: "app-waiting-stations", group: "等待", title: "设置页 · Station · 正在读取", app: true, demo: held("stations"), steps: [{ click: '[aria-label="设置"]' }, { text: "Station" }] },
  { id: "app-waiting-devices", group: "等待", title: "设置页 · 账号 · 正在读取已登录设备", app: true, demo: held("loginSessions"), steps: [{ click: '[aria-label="设置"]' }] },
  { id: "app-waiting-workspace", group: "等待", title: "设置页 · Workspace · 正在读取", app: true, demo: held("workspace"), steps: [{ click: '[aria-label="设置"]' }, { text: "Acme" }] },
  { id: "app-waiting-profiles", group: "等待", title: "Profile · 正在读取", app: true, demo: held("profiles"), steps: [{ click: '[aria-label="Profile"]' }] },
  { id: "phone-waiting-profiles", group: "等待", title: "手机 · Profile · 正在读取", app: true, phone: true, demo: held("profiles"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Profile" }] },
  {
    id: "control-busy", group: "等待", title: "做事中的按钮和行",
    render: () => sheet([
      ["按钮", <><Button variant="primary" busy>保存</Button><Button busy>重新连接</Button><Button variant="danger-solid" busy>删除</Button><IconButton label="刷新" icon={Refresh} busy /></>],
      ["开关", <><SwitchDemo start busy /><Switch checked onChange={noop} small busy label="小开关" /></>],
      ["行尾", <div style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12, color: vars.muted }}>正在保存<Spinner inline /></div>],
    ]),
  },
  { id: "app-share", group: "应用", title: "分享进来 · 上次那个 chat 在最前", app: true, ...sharing("kept") },
  { id: "app-share-opened", group: "应用", title: "分享进来 · 点了之后的 chat", app: true, ...sharing("kept"), steps: [{ click: 'button:has-text("youtube.com 的链接上次发到这里")' }] },
  { id: "app-share-new-chat", group: "应用", title: "分享进来 · 新 chat，几台 station", app: true, ...sharing("new") },
  { id: "app-share-none", group: "应用", title: "分享进来 · 没有 chat 也没有 station", app: true, ...sharing("none") },
  { id: "app-share-loading", group: "应用", title: "分享进来 · 正在读取", app: true, ...sharing("loading") },
  { id: "app-share-search", group: "应用", title: "分享进来 · 搜索 chat", app: true, ...sharing("search"), steps: [{ text: "搜索" }, { key: "N" }, { key: "A" }, { key: "S" }] },

  // ── a station's logins (docs/remote-login.md) ──
  { id: "logins-section", group: "登录", title: "station 页 · 登录（进行中和做过的）", render: loginsSection, demo: logins() },
  { id: "logins-section-under-way", group: "登录", title: "station 页 · 登录（一个进行中）", render: loginsSection, demo: logins({ listed: ["device"] }) },
  { id: "logins-section-marked", group: "登录", title: "station 页 · 链接指到的那张卡片", render: () => stage(<div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><LoginsSection station="demo/local" marked="device" /></div>), demo: logins({ listed: ["device", "done"] }) },
  { id: "logins-section-readonly", group: "登录", title: "station 页 · 只读成员", render: loginsSection, demo: logins({ canLogin: false }) },
  { id: "app-station-logins", group: "登录", title: "station 页 · 在页面里", app: true, demo: logins(), steps: toStation("设置") },
  { id: "login-card-loopback", group: "登录", title: "卡片 · 回环（桌面）", render: loginCard("loopback"), demo: logins() },
  { id: "login-card-loopback-web", group: "登录", title: "卡片 · 回环（网页）", render: loginCard("loopback"), demo: logins({ canRelay: false }) },
  { id: "login-card-loopback-listening", group: "登录", title: "卡片 · 回环 · 等浏览器回来", render: loginCard("listening"), demo: logins() },
  { id: "login-card-loopback-taken", group: "登录", title: "卡片 · 回环 · 本机端口被占用", render: loginCard("taken"), demo: logins() },
  { id: "login-card-device", group: "登录", title: "卡片 · 设备码", render: loginCard("device"), demo: logins() },
  { id: "login-card-in-station", group: "登录", title: "卡片 · 回环 · 也能在 station 的浏览器里做（桌面）", render: loginCard("inStation"), demo: logins() },
  { id: "login-card-in-station-web", group: "登录", title: "卡片 · 回环 · 网页：在 station 的浏览器里做", render: loginCard("inStation"), demo: logins({ canRelay: false }) },
  { id: "login-card-in-station-more", group: "登录", title: "卡片 · 回环 · 「其他方式」打开", render: loginCard("inStation"), demo: logins(), steps: [{ click: "[data-login-more]" }] },
  { id: "login-card-in-station-taken", group: "登录", title: "卡片 · 回环 · 本机端口被占：在 station 的浏览器里做", render: loginCard("inStationTaken"), demo: logins() },
  { id: "login-card-in-station-open", group: "登录", title: "卡片 · 回环 · station 浏览器的标签页开着", render: loginCard("inStationOpen"), demo: logins(), steps: [{ click: "[data-login-more]" }] },
  { id: "login-card-paste", group: "登录", title: "卡片 · 打开网址，再贴回页面给的码", render: loginCard("paste"), demo: logins() },
  { id: "login-card-paste-phone", group: "登录", title: "卡片 · 贴码 · 手机", phone: true, render: loginCard("paste", 12), demo: logins() },
  { id: "login-card-checking", group: "登录", title: "卡片 · 码已贴回，正在确认", render: loginCard("checking"), demo: logins() },
  { id: "login-card-checking-phone", group: "登录", title: "卡片 · 码已贴回，正在确认 · 手机", phone: true, render: loginCard("checking", 12), demo: logins() },
  { id: "login-card-question", group: "登录", title: "卡片 · agent 在回答命令的问题", render: loginCard("question"), demo: logins() },
  { id: "logins-section-past", group: "登录", title: "station 页 · 登录（只有做过的）", render: loginsSection, demo: logins({ listed: ["done", "failed", "cancelled"] }) },
  { id: "login-card-open", group: "登录", title: "卡片 · 打开网址", render: loginCard("open"), demo: logins() },
  { id: "login-card-done", group: "登录", title: "卡片 · 已登录", render: loginCard("done"), demo: logins() },
  { id: "login-card-failed", group: "登录", title: "卡片 · 失败", render: loginCard("failed"), demo: logins() },
  { id: "login-card-timeout", group: "登录", title: "卡片 · 超时", render: loginCard("timeout"), demo: logins() },
  { id: "login-card-code-copied", group: "登录", title: "卡片 · 设备码 · 点码复制之后", render: loginCard("device"), demo: logins(), steps: [{ click: "[data-login-code]" }] },
  { id: "login-card-code-copied-phone", group: "登录", title: "卡片 · 设备码 · 点码复制之后 · 手机", phone: true, render: loginCard("device", 12), demo: logins(), steps: [{ click: "[data-login-code]" }] },
  { id: "login-card-question-phone", group: "登录", title: "卡片 · agent 在回答命令的问题 · 手机", phone: true, render: loginCard("question", 12), demo: logins() },
  { id: "login-card-device-phone", group: "登录", title: "卡片 · 设备码 · 手机", phone: true, render: loginCard("device", 12), demo: logins() },
  { id: "login-card-failed-phone", group: "登录", title: "卡片 · 失败 · 手机", phone: true, render: loginCard("failed", 12), demo: logins() },
  { id: "login-card-cancelled", group: "登录", title: "卡片 · 已取消", render: loginCard("cancelled"), demo: logins() },
  { id: "login-card-done-phone", group: "登录", title: "卡片 · 已登录 · 手机", phone: true, render: loginCard("done", 12), demo: logins() },
  { id: "login-card-cancelled-phone", group: "登录", title: "卡片 · 已取消 · 手机", phone: true, render: loginCard("cancelled", 12), demo: logins() },
  { id: "app-chat-login-card-done", group: "登录", title: "对话 · 登录结束后的卡片", app: true, demo: logins({ card: "done" }) },
  { id: "phone-chat-login-card-done", group: "登录", title: "手机 · 对话里登录结束后的卡片", app: true, phone: true, demo: logins({ card: "done" }) },
  { id: "login-card-readonly", group: "登录", title: "卡片 · 只读成员", render: loginCard("device"), demo: logins({ canLogin: false }) },
  { id: "login-cards", group: "登录", title: "对话里的卡片", render: loginCards(["question", "device", "loopback", "open", "done", "failed", "cancelled"]), demo: logins() },
  { id: "login-cards-phone", group: "登录", title: "对话里的卡片 · 手机宽度（按钮仍一排）", phone: true, render: loginCards(["device", "loopback", "open", "listening"], 12), demo: logins() },
  { id: "login-cards-web", group: "登录", title: "对话里的卡片 · 网页", render: loginCards(["loopback", "device"]), demo: logins({ canRelay: false }) },
  { id: "app-chat-login-card", group: "登录", title: "对话 · 登录卡片", app: true, demo: logins({ card: "device" }) },
  { id: "phone-chat-login-card", group: "登录", title: "手机 · 对话里的卡片", app: true, phone: true, demo: logins({ card: "device" }) },

  // ── settings ──
  { id: "settings-appearance", group: "设置", title: "外观", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "外观" }] },
  { id: "phone-settings", group: "设置", title: "手机 · 设置（账号、workspace 两张卡，各组带图标）", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }] },
  { id: "phone-settings-about", group: "设置", title: "手机 · 关于（更新日志、使用统计、条款）", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "关于" }] },
  { id: "phone-settings-appearance", group: "设置", title: "手机 · 外观", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "外观" }] },
  { id: "settings-appearance-fonts", group: "设置", title: "外观 · 字体已选（思源宋体、霞鹜文楷、Maple Mono）", app: true, demo: chosenFonts, steps: [{ click: '[aria-label="设置"]' }, { text: "外观" }] },
  { id: "settings-appearance-fonts-text", group: "设置", title: "外观 · 字体 · 正文，指着思源宋体（预览里先试）", app: true, demo: chosenFonts, steps: [{ click: '[aria-label="设置"]' }, { text: "外观" }, { click: '[aria-label="字体"] button:has-text("正文")' }, { hover: 'button[aria-pressed]:has-text("思源宋体")' }] },
  { id: "phone-settings-fonts", group: "设置", title: "手机 · 外观 › 字体", app: true, phone: true, demo: chosenFonts, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "外观" }, { text: "字体" }] },
  { id: "app-chat-fonts", group: "设置", title: "对话 · 字体已选（思源宋体、霞鹜文楷、Maple Mono）", app: true, demo: chosenFonts },
  { id: "settings-notifications", group: "设置", title: "通知", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "通知" }] },
  { id: "settings-notifications-type", group: "设置", title: "通知 · 展开一个类别", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "通知" }, { click: 'button:has-text("有人发言")' }] },
  { id: "settings-notifications-ipad", group: "设置", title: "通知 · iPad 的浏览器（预览是一台平板，没有红点）", app: true, system: "ipad", steps: [{ click: '[aria-label="设置"]' }, { text: "通知" }] },
  {
    id: "settings-notifications-refused", group: "设置", title: "通知 · 系统没允许",
    render: () => stage(<div style={{ display: "grid", gap: 10, padding: 32, maxWidth: 720 }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 10 }}>
        <Tile way="banner" on={false} action="在系统设置中开启" onChange={noop} /><Tile way="badge" on onChange={noop} />
      </div>
    </div>),
  },
  // (not a row of the settings' list: 通知's page asks for it; ⌘K finds it)
  { id: "settings-permissions", group: "设置", title: "权限", app: true, steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }, { key: "p" }, { key: "e" }, { key: "r" }, { key: "m" }, { key: "i" }, { key: "s" }, { key: "Enter" }] },
  {
    id: "settings-permissions-states", group: "设置", title: "权限 · 各种状态",
    render: () => stage(<div style={{ display: "grid", gap: 10, padding: 32, maxWidth: 720 }}>
      {(["granted", "default", "denied", "unknown"] as const).map((state) => (
        <PermissionRow key={state} icon={Bell} name="通知" purpose="需要你决定、出错或有人发消息时显示横幅" without="未授权时：无法显示横幅，红点不受影响"
          where="系统设置 → 通知 → still.fail → 允许通知" state={state} onAllow={noop} onOpen={noop} />
      ))}
    </div>),
  },
  { id: "settings-changelog", group: "设置", title: "更新日志", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "关于" }, { text: "更新日志" }] },
  { id: "settings-about", group: "设置", title: "关于", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "关于" }] },
  // (the settings come to the account's page, their list's first row's)
  { id: "settings-account-delete", group: "设置", title: "账号 · 注销", app: true, steps: [{ click: '[aria-label="设置"]' }, { click: 'button:has-text("注销")' }] },
  { id: "phone-me", group: "设置", title: "手机 · 账号", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "you@acme.dev" }] },
  { id: "phone-me-delete", group: "设置", title: "手机 · 账号 · 注销", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "you@acme.dev" }, { text: "注销账号" }] },
  { id: "settings-archive", group: "设置", title: "归档", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "归档" }] },
  { id: "settings-decisions", group: "设置", title: "自动决策", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "自动决策" }] },
  { id: "settings-memory", group: "设置", title: "记忆", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }] },
  { id: "settings-memory-station", group: "设置", title: "记忆 · Studio", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }] },
  { id: "settings-memory-skill", group: "设置", title: "记忆 · 项目", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }, { text: "acme-web" }] },
  { id: "settings-memory-global", group: "设置", title: "记忆 · 全局", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }, { text: "合并" }] },
  { id: "settings-workspace", group: "设置", title: "Workspace", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "Acme" }] },
  { id: "settings-workspace-member", group: "设置", title: "Workspace · 成员的角色和移出", app: true, steps: [{ click: '[aria-label="设置"]' }, { text: "Acme" }, { text: "陈默" }] },
  { id: "phone-workspace", group: "设置", title: "手机 · Workspace", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Acme" }] },
  { id: "settings-security", group: "设置", title: "安全 · 此 workspace 没有安全模式（设置的目录里不列）", app: true, steps: [{ click: '[aria-label="设置"]' }] },
  { id: "settings-security-on", group: "设置", title: "安全 · 已开启", app: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }] },
  { id: "settings-security-turn-off", group: "设置", title: "安全 · 关闭安全模式", app: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }, { click: 'button:has-text("关闭安全模式")' }] },
  { id: "settings-security-turn-off-typed", group: "设置", title: "安全 · 关闭安全模式 · 已输入名称", app: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }, { click: 'button:has-text("关闭安全模式")' }, { key: "A" }, { key: "c" }, { key: "m" }, { key: "e" }] },
  { id: "settings-security-remove", group: "设置", title: "安全 · 移除设备", app: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }, { click: 'button:has-text("移除")' }] },
  { id: "settings-security-no-stations", group: "设置", title: "安全 · 暂无 station", app: true, demo: lockDemo("noStations"), steps: [{ click: '[aria-label="设置"]' }, { text: "安全" }] },
  { id: "security-waiting", group: "设置", title: "安全 · 等待批准此设备", app: true, demo: lockDemo("waiting") },
  { id: "security-waiting-finding", group: "设置", title: "安全 · 正在联系受信任设备", app: true, demo: lockDemo("finding") },
  { id: "security-waiting-code", group: "设置", title: "安全 · 输入受信任设备上的安全码", app: true, demo: lockDemo("code") },
  { id: "security-waiting-code-typed", group: "设置", title: "安全 · 安全码输入到一半", app: true, demo: lockDemo("code"), steps: [{ click: '[aria-label="输入你的受信任设备上显示的安全码"]' }, { key: "4" }, { key: "8" }, { key: "2" }, { key: "9" }] },
  { id: "security-waiting-wrong", group: "设置", title: "安全 · 安全码不对", app: true, demo: lockDemo("wrong") },
  { id: "security-waiting-none", group: "设置", title: "安全 · 未找到在线的受信任设备", app: true, demo: lockDemo("none") },
  { id: "security-waiting-failed", group: "设置", title: "安全 · 批准请求未能提交", app: true, demo: lockDemo("failed") },
  { id: "phone-security-waiting", group: "设置", title: "手机 · 安全 · 等待批准此设备（顶栏可切换 workspace）", app: true, phone: true, demo: lockDemo("waiting") },
  { id: "phone-security-waiting-failed", group: "设置", title: "手机 · 安全 · 批准请求未能提交", app: true, phone: true, demo: lockDemo("failed") },
  { id: "security-prompt-two-workspaces", group: "设置", title: "安全 · 新设备请求批准（显示安全码）", app: true, demo: lockDemo("prompt") },
  { id: "phone-security-prompt-two-workspaces", group: "设置", title: "手机 · 安全 · 新设备请求批准（显示安全码）", app: true, phone: true, demo: lockDemo("prompt") },
  { id: "phone-security-waiting-code", group: "设置", title: "手机 · 安全 · 输入受信任设备上的安全码", app: true, phone: true, demo: lockDemo("code") },
  { id: "phone-security-waiting-code-typed", group: "设置", title: "手机 · 安全 · 安全码输入到一半", app: true, phone: true, demo: lockDemo("code"), steps: [{ click: '[aria-label="输入你的受信任设备上显示的安全码"]' }, { key: "4" }, { key: "8" }, { key: "2" }, { key: "9" }] },
  { id: "phone-security-waiting-wrong", group: "设置", title: "手机 · 安全 · 安全码不对", app: true, phone: true, demo: lockDemo("wrong") },
  { id: "phone-settings-security-on", group: "设置", title: "手机 · 安全 · 已开启", app: true, phone: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "安全" }] },
  { id: "phone-settings-security-remove", group: "设置", title: "手机 · 安全 · 移除设备", app: true, phone: true, demo: lockDemo("on"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "安全" }, { click: 'button:has-text("移除")' }] },
  { id: "phone-settings-security-no-stations", group: "设置", title: "手机 · 安全 · 暂无 station", app: true, phone: true, demo: lockDemo("noStations"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "安全" }] },

  // ── the vault (docs/vault.md) ──
  { id: "vault-web", group: "密钥", title: "网页只看名字", app: true, demo: vaultDemo("web"), steps: toVault },
  { id: "vault-no-lock", group: "密钥", title: "先打开安全模式", app: true, demo: vaultDemo("noLock"), steps: toVault },
  { id: "vault-unconfirmed", group: "密钥", title: "此设备尚未确认", app: true, demo: vaultDemo("unconfirmed"), steps: toVault },
  { id: "vault-off", group: "密钥", title: "尚未开启", app: true, demo: vaultDemo("off"), steps: toVault },
  { id: "vault-words", group: "密钥", title: "恢复码", app: true, demo: vaultDemo("off"), steps: [...toVault, { text: "开启密钥库" }] },
  { id: "vault-on", group: "密钥", title: "等你批准的和库的设置", app: true, demo: vaultDemo("waiting"), steps: toVault },
  { id: "vault-all", group: "密钥", title: "全部密钥", app: true, demo: vaultDemo("waiting"), steps: [...toVault, { text: "全部密钥" }] },
  { id: "vault-all-accounts", group: "密钥", title: "全部密钥 · 订阅和 API Key 展开", app: true, demo: vaultDemo("waiting"), steps: [...toVault, { text: "全部密钥" }, { text: "订阅和 API Key" }] },
  { id: "vault-all-locked", group: "密钥", title: "全部密钥 · 锁着", app: true, demo: vaultDemo("locked"), steps: [...toVault, { text: "全部密钥" }] },
  { id: "vault-lasts", group: "密钥", title: "默认最长授权", app: true, demo: vaultDemo("on"), steps: [...toVault, { text: "默认最长授权" }] },
  { id: "vault-locked", group: "密钥", title: "锁着 · 新设备尚无钥匙", app: true, demo: vaultDemo("locked"), steps: toVault },
  { id: "vault-not-keyed", group: "密钥", title: "此设备尚无钥匙", app: true, demo: vaultDemo("notKeyed"), steps: toVault },
  { id: "vault-recover", group: "密钥", title: "用恢复码找回", app: true, demo: vaultDemo("notKeyed"), steps: [...toVault, { text: "使用恢复码" }] },
  { id: "vault-item", group: "密钥", title: "打开一条", app: true, demo: vaultDemo("on"), steps: [...toVault, { text: "全部密钥" }, { text: "GitHub token" }] },
  { id: "vault-editor", group: "密钥", title: "添加", app: true, demo: vaultDemo("on"), steps: [...toVault, { text: "全部密钥" }, { click: 'main button:has-text("添加")' }, { click: 'button:has-text("GitHub、Cloudflare")' }] },
  { id: "vault-editor-agent", group: "密钥", title: "编辑 · agent 可申请", app: true, demo: vaultDemo("on"), steps: [...toVault, { text: "全部密钥" }, { text: "GitHub token" }, { text: "编辑" }] },
  { id: "vault-card", group: "密钥", title: "对话里的申请", app: true, demo: vaultDemo("waiting", true) },
  { id: "vault-card-web", group: "密钥", title: "对话里的申请 · 网页", app: true, demo: vaultDemo("web", true) },
  { id: "vault-card-hour", group: "密钥", title: "对话里的申请 · 最长 1 小时的条目", app: true, demo: vaultDemo("waiting", { lasts: "hour" }) },
  { id: "vault-card-granted", group: "密钥", title: "对话里的申请 · 已批准", app: true, demo: vaultDemo("on", { status: "granted", scope: "chat" }) },
  { id: "vault-card-denied", group: "密钥", title: "对话里的申请 · 长命令 · 已拒绝", app: true, demo: vaultDemo("on", { status: "denied", command: LONG_COMMAND }) },
  { id: "vault-save-card", group: "密钥", title: "agent 申请存入", app: true, demo: vaultDemo("waiting", { save: true }) },
  { id: "vault-save-card-off", group: "密钥", title: "agent 申请存入 · 密钥库尚未开启", app: true, demo: vaultDemo("off", { save: true }) },
  { id: "vault-save-card-kept", group: "密钥", title: "agent 申请存入 · 已存入", app: true, demo: vaultDemo("on", { save: true, status: "granted" }) },
  { id: "vault-typed-card", group: "密钥", title: "agent 请你填入密钥", app: true, demo: vaultDemo("waiting", { typed: true }) },
  { id: "vault-card-long", group: "密钥", title: "对话里的申请 · 长命令", app: true, demo: vaultDemo("waiting", { command: LONG_COMMAND }) },
  { id: "phone-vault-web", group: "密钥", title: "手机 · 网页只看名字", app: true, phone: true, demo: vaultDemo("web"), steps: toPhoneVault },
  { id: "phone-vault-no-lock", group: "密钥", title: "手机 · 先打开安全模式", app: true, phone: true, demo: vaultDemo("noLock"), steps: toPhoneVault },
  { id: "phone-vault-off", group: "密钥", title: "手机 · 尚未开启", app: true, phone: true, demo: vaultDemo("off"), steps: toPhoneVault },
  { id: "phone-vault-words", group: "密钥", title: "手机 · 恢复码", app: true, phone: true, demo: vaultDemo("off"), steps: [...toPhoneVault, { text: "开启密钥库" }] },
  { id: "phone-vault-on", group: "密钥", title: "手机 · 等你批准的和库的设置", app: true, phone: true, demo: vaultDemo("waiting"), steps: toPhoneVault },
  { id: "phone-vault-all", group: "密钥", title: "手机 · 全部密钥", app: true, phone: true, demo: vaultDemo("waiting"), steps: [...toPhoneVault, { text: "全部密钥" }] },
  { id: "phone-vault-all-accounts", group: "密钥", title: "手机 · 全部密钥 · 订阅和 API Key 展开", app: true, phone: true, demo: vaultDemo("waiting"), steps: [...toPhoneVault, { text: "全部密钥" }, { text: "订阅和 API Key" }] },
  { id: "phone-vault-all-locked", group: "密钥", title: "手机 · 全部密钥 · 锁着", app: true, phone: true, demo: vaultDemo("locked"), steps: [...toPhoneVault, { text: "全部密钥" }] },
  { id: "phone-vault-lasts", group: "密钥", title: "手机 · 默认最长授权", app: true, phone: true, demo: vaultDemo("on"), steps: [...toPhoneVault, { text: "默认最长授权" }] },
  { id: "phone-vault-locked", group: "密钥", title: "手机 · 锁着", app: true, phone: true, demo: vaultDemo("locked"), steps: toPhoneVault },
  { id: "phone-vault-not-keyed", group: "密钥", title: "手机 · 此设备尚无钥匙", app: true, phone: true, demo: vaultDemo("notKeyed"), steps: toPhoneVault },
  { id: "phone-vault-recover", group: "密钥", title: "手机 · 用恢复码找回", app: true, phone: true, demo: vaultDemo("notKeyed"), steps: [...toPhoneVault, { text: "使用恢复码" }] },
  { id: "phone-vault-item", group: "密钥", title: "手机 · 打开一条", app: true, phone: true, demo: vaultDemo("on"), steps: [...toPhoneVault, { text: "全部密钥" }, { text: "GitHub token" }] },
  { id: "phone-vault-editor", group: "密钥", title: "手机 · 添加", app: true, phone: true, demo: vaultDemo("on"), steps: [...toPhoneVault, { text: "全部密钥" }, { click: '[aria-label="添加"]' }, { text: "GitHub、Cloudflare 等服务的 API token" }] },
  { id: "phone-vault-editor-agent", group: "密钥", title: "手机 · 编辑 · agent 可申请", app: true, phone: true, demo: vaultDemo("on"), steps: [...toPhoneVault, { text: "全部密钥" }, { text: "GitHub token" }, { click: '[aria-label="编辑"]' }] },
  { id: "phone-vault-card", group: "密钥", title: "手机 · 对话里的申请", app: true, phone: true, demo: vaultDemo("waiting", true) },
  // ── the library: the profiles' accounts and the secrets in one place (docs/vault.md 一个库) ──
  { id: "lib-plain", group: "密钥", title: "库 · 未加锁", app: true, demo: libraryDemo(false), steps: toVault },
  { id: "lib-plain-item", group: "密钥", title: "库 · 未加锁 · 一条 token", app: true, demo: libraryDemo(false), steps: [...toVault, { text: "全部密钥" }, { text: "GitHub token" }] },
  { id: "lib-sealed", group: "密钥", title: "库 · 已加锁", app: true, demo: libraryDemo(true), steps: toVault },
  { id: "lib-migrate", group: "密钥", title: "库 · 开启安全模式后待加密", app: true, demo: libraryDemo(true, 2), steps: toVault },
  { id: "phone-lib-migrate", group: "密钥", title: "手机 · 库 · 开启安全模式后待加密", app: true, phone: true, demo: libraryDemo(true, 2), steps: toPhoneVault },
  { id: "lib-add", group: "密钥", title: "库 · 添加", app: true, demo: libraryDemo(false), steps: [...toVault, { text: "全部密钥" }, { click: 'main button:has-text("添加")' }] },
  { id: "lib-add-token", group: "密钥", title: "库 · 未加锁时添加 token", app: true, demo: libraryDemo(false), steps: [...toVault, { text: "全部密钥" }, { click: 'main button:has-text("添加")' }, { click: 'button:has-text("GitHub、Cloudflare")' }] },
  { id: "phone-lib-plain", group: "密钥", title: "手机 · 库 · 未加锁", app: true, phone: true, demo: libraryDemo(false), steps: toPhoneVault },
  { id: "phone-lib-item", group: "密钥", title: "手机 · 库 · 未加锁 · 一条 token", app: true, phone: true, demo: libraryDemo(false), steps: [...toPhoneVault, { text: "全部密钥" }, { text: "GitHub token" }] },
  { id: "phone-lib-sealed", group: "密钥", title: "手机 · 库 · 已加锁", app: true, phone: true, demo: libraryDemo(true), steps: toPhoneVault },
  { id: "phone-lib-add", group: "密钥", title: "手机 · 库 · 添加", app: true, phone: true, demo: libraryDemo(false), steps: [...toPhoneVault, { text: "全部密钥" }, { click: '[aria-label="添加"]' }] },
  { id: "phone-vault-card-web", group: "密钥", title: "手机 · 对话里的申请 · 网页", app: true, phone: true, demo: vaultDemo("web", true) },

  // ── small panels (docs/ui-panels.md) ──
  { id: "panel-filter", group: "小面板", title: "筛选菜单", app: true, steps: [{ click: '[aria-label^="筛选会话"]' }] },
  { id: "panel-chat-info", group: "小面板", title: "对话信息", app: true, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "panel-jobs", group: "小面板", title: "服务和后台任务", app: true, demo: someJobs, steps: [{ click: '[aria-label="服务和后台任务"]' }] },
  { id: "panel-workspace", group: "小面板", title: "workspace 菜单", app: true, steps: [{ click: '[aria-label="新建 workspace、添加账号"]' }] },
  { id: "panel-rail-menu", group: "小面板", title: "侧边条右键菜单", app: true, steps: [{ rightClick: '[aria-label="文件"]' }] },
  { id: "panel-rail-adder", group: "小面板", title: "侧边条自定义", app: true, steps: [{ rightClick: '[aria-label="文件"]' }, { text: "自定义侧边条" }] },
  { id: "panel-chat-menu", group: "小面板", title: "对话右键菜单", app: true, steps: [{ rightClick: "a:has-text(\"订单导出支持 CSV\")" }] },
  { id: "panel-file-card", group: "小面板", title: "消息里的文件卡片", app: true, peek: "file", steps: [{ move: [1, 1] }, { hover: 'button[class*="fileChip"]' }] },
  { id: "panel-file-card-missing", group: "小面板", title: "消息里的文件卡片 · 找不到", app: true, peek: "missing", steps: [{ move: [1, 1] }, { hover: 'button[class*="fileChip"]' }] },
  { id: "panel-station-card", group: "小面板", title: "station 卡片", app: true, steps: [{ move: [1, 1] }, { hover: "header >> text=/Studio|这台机器/" }] },
  { id: "panel-switcher", group: "小面板", title: "⌘K", app: true, steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }] },
  { id: "panel-switcher-relay", group: "小面板", title: "⌘K · 接力到频道", app: true, demo: relayDemo(), steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }, { key: "r" }, { key: "e" }, { key: "l" }, { key: "a" }] },
  { id: "panel-switcher-search", group: "小面板", title: "⌘K · 搜索", app: true, steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }, { key: "c" }, { key: "s" }, { key: "v" }] },
  { id: "panel-switcher-kind", group: "小面板", title: "⌘K · 一类结果", app: true, steps: [{ click: "textarea" }, { key: "ControlOrMeta+k" }, { key: "c" }, { key: "s" }, { key: "v" }, { click: "text=查看更多" }] },
  {
    id: "panel-station-update", group: "小面板", title: "station 更新",
    render: () => stage(<div style={{ padding: 24 }}><StationUpdate station="local" notice={{
      tone: "update", text: "Studio 有新版本", label: "有新版本", station: "Studio", detail: "更新时会重启 station，正在跑的 agent 会接着跑",
      from: "0.1.2790", to: "0.1.2925", version: "0.1.2925", canUpdate: true, dismissible: true, open: true,
    }} /></div>),
  },
  {
    id: "panel-station-updating", group: "小面板", title: "station 更新 · 进行中",
    render: () => stage(<div style={{ padding: 24 }}><StationUpdate station="local" notice={{
      tone: "busy", text: "Studio 正在更新", label: "正在更新", station: "Studio", detail: "下载新版本", percent: 42, from: "0.1.2790", to: "0.1.2925", open: true,
    }} /></div>),
  },
  {
    id: "card-decision", group: "页面卡片", title: "决策选项", render: () => stage(<div style={{ padding: 32, width: 560 }}>
      <DecisionOptions station="demo/local" thread={1} seq={1} options={[
        { label: "A. 只改这一张卡片", detail: "其他页面先不动" },
        { label: "B. 出一份页面卡片的规范", detail: "所有页面里的卡片按它来，测试也按它量", recommended: true },
      ]} />
    </div>),
  },
  { id: "panel-bubble", group: "小面板", title: "通知气泡", news: true, render: () => stage(<SystemBubbles scope="demo" />) },
  { id: "panel-bubble-hover", group: "小面板", title: "通知气泡 · 悬停按钮", news: true, render: () => stage(<SystemBubbles scope="demo" />), steps: [{ hover: "text=查看" }] },

  // ── files ──
  { id: "reader-txt", group: "文件", title: "阅读器 · 小说", render: () => stage(<Reader file={driveFile(at(novel.name), novel)} markdown={false} backLabel="下载" onBack={noop} />) },
  { id: "reader-contents", group: "文件", title: "阅读器 · 目录", render: () => stage(<Reader file={driveFile(at(novel.name), novel)} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="目录"]' }] },
  { id: "reader-find", group: "文件", title: "阅读器 · 搜索", render: () => stage(<Reader file={driveFile(at(novel.name), novel)} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="搜索"]' }] },
  { id: "reader-layout", group: "文件", title: "阅读器 · 排版", render: () => stage(<Reader file={driveFile(at(novel.name), novel)} markdown={false} backLabel="下载" onBack={noop} />), steps: [{ click: '[aria-label="排版"]' }] },
  { id: "reader-md", group: "文件", title: "阅读器 · Markdown", render: () => stage(<Reader file={driveFile(at(note.name), note)} markdown backLabel="下载" onBack={noop} />) },
  { id: "reader-phone", group: "文件", title: "阅读器 · 手机", phone: true, render: () => stage(<Reader file={driveFile(at(novel.name), novel)} markdown={false} backLabel="下载" onBack={noop} />) },
  { id: "player", group: "文件", title: "播放器", render: () => stage(<Player file={driveFile(at(clips[0]!.name), clips[0]!)} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />), steps: [{ move: [640, 400] }] },
  { id: "player-list", group: "文件", title: "播放器 · 选集", render: () => stage(<Player file={driveFile(at(clips[0]!.name), clips[0]!)} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />), steps: [{ move: [640, 400], click: '[aria-label="选集"]' }, { move: [500, 400] }] },
  { id: "player-phone", group: "文件", title: "播放器 · 手机", phone: true, render: () => stage(<Player file={driveFile(at(clips[0]!.name), clips[0]!)} siblings={folder} backLabel="下载" onBack={noop} onGo={noop} />) },
  { id: "attachment-md", group: "文件", title: "附件 · Markdown", render: () => stage(<AttachmentDemo name="orders-慢查询.md" url={NOTE_URL} type="text/markdown" />) },
  { id: "attachment-video", group: "文件", title: "附件 · 视频", render: () => stage(<AttachmentDemo name="发版录屏 1014.mp4" url={CLIP_URL} type="video/mp4" />), steps: [{ move: [640, 400] }] },
  // Playing, the pointer on its timeline: its controls, the time where it points.
  { id: "attachment-video-controls", group: "文件", title: "附件 · 视频 · 控件", render: () => stage(<AttachmentDemo name="发版录屏 1014.mp4" url={CLIP_URL} type="video/mp4" />), steps: [{ move: [640, 400], hover: '[role=slider][aria-label="位置"]' }] },
  // Paused: looked at closely, its frames' keys, the frame's time to the millisecond, which of how many, the camera.
  { id: "attachment-video-paused", group: "文件", title: "附件 · 视频 · 暂停逐帧", render: () => stage(<AttachmentDemo name="发版录屏 1014.mp4" url={CLIP_URL} type="video/mp4" />), steps: [{ move: [640, 400] }, { key: "k" }, { click: '[aria-label="下一帧"]' }, { hover: 'canvas[aria-label^="第"]' }] },
  { id: "attachment-video-phone", group: "文件", title: "附件 · 视频 · 手机", phone: true, render: () => stage(<AttachmentDemo name="发版录屏 1014.mp4" url={CLIP_URL} type="video/mp4" />) },
  // A phone's recording, taller than the window is: all of it in the window, not cut off at the top and the bottom.
  { id: "attachment-video-tall", group: "文件", title: "附件 · 竖屏视频", render: () => stage(<AttachmentDemo name="手机录屏 1017.mp4" url={TALL_CLIP_URL} type="video/mp4" />), steps: [{ move: [640, 400] }] },
  { id: "attachment-picture", group: "文件", title: "附件 · 图片", render: () => stage(<AttachmentDemo name="login-375.png" url={PICTURE_URL} type="image/png" />), steps: [{ move: [640, 400] }] },
  { id: "preview-picture", group: "文件", title: "图片预览", render: () => stage(<DrivePreview at={at(picture.name)} entries={folder} entry={picture} onClose={noop} />), steps: [{ move: [640, 400] }] },
  { id: "preview-unshown", group: "文件", title: "预览 · 不能预览的文件", render: () => stage(<DrivePreview at={at(apk.name)} entries={[...folder, apk]} entry={apk} onClose={noop} />), steps: [{ move: [640, 400] }] },
  { id: "preview-unshown-phone", group: "文件", title: "预览 · 不能预览的文件 · 手机", phone: true, render: () => stage(<DrivePreview at={at(apk.name)} entries={[...folder, apk]} entry={apk} onClose={noop} />) },

  // ── a station's screens (docs/remote-screens.md) ──
  { id: "screen-connecting", group: "屏幕", title: "屏幕 · 连接中", ...screenView("connecting") },
  { id: "screen-live", group: "屏幕", title: "屏幕 · 控制", ...screenView("live"), steps: toTheBar },
  { id: "screen-live-h264", group: "屏幕", title: "屏幕 · 控制 · H.264", ...screenView("live", false, true), steps: toTheBar },
  { id: "screen-read-only", group: "屏幕", title: "屏幕 · 只读成员只能看", ...screenView("readOnly"), steps: toTheBar },
  { id: "screen-undrivable", group: "屏幕", title: "屏幕 · station 没有辅助功能权限", ...screenView("undrivable"), steps: toTheBar },
  { id: "screen-agent-driving", group: "屏幕", title: "屏幕 · Agent 正在控制", ...screenView("agent") },
  { id: "screen-agent-driving-phone", group: "屏幕", title: "屏幕 · Agent 正在控制 · 手机", phone: true, ...screenView("agent", true) },
  { id: "screen-taken-over", group: "屏幕", title: "屏幕 · 接管之后", ...screenView("agent"), steps: [{ click: 'button:has-text("接管")' }, ...toTheBar] },
  { id: "screen-reconnecting", group: "屏幕", title: "屏幕 · 重新连接", ...screenView("reconnecting") },
  { id: "screen-ended", group: "屏幕", title: "屏幕 · 结束了", ...screenView("ended") },
  { id: "screen-outdated", group: "屏幕", title: "屏幕 · station 要更新", ...screenView("outdated") },
  { id: "screen-gone", group: "屏幕", title: "屏幕 · 不在了", ...screenView("gone") },
  { id: "screen-denied", group: "屏幕", title: "屏幕 · 没有权限", ...screenView("denied") },
  { id: "screen-failed", group: "屏幕", title: "屏幕 · 没连上", ...screenView("failed") },
  { id: "screen-phone", group: "屏幕", title: "屏幕 · 手机", phone: true, ...screenView("live", true) },
  { id: "screen-simulator", group: "屏幕", title: "屏幕 · iOS 模拟器", ...screenView("live", false, false, SIMULATOR), steps: [{ hover: '[aria-label="多任务"]' }] },
  { id: "screen-simulator-phone", group: "屏幕", title: "屏幕 · iOS 模拟器 · 手机", phone: true, ...screenView("live", true, false, SIMULATOR) },
  { id: "screen-stats", group: "屏幕", title: "屏幕 · 连接统计（采集方式、硬编）", ...screenView("live", false, true), steps: [...toTheBar, { click: '[aria-label="连接"]' }] },
  { id: "screen-scale", group: "屏幕", title: "屏幕 · Windows · 控制中心 › 缩放", ...screenView("windows"), steps: [...toTheBar, { click: 'button:has-text("控制中心")' }, { click: '[role="menuitem"]:has-text("缩放")' }] },
  { id: "screen-phone-scale", group: "屏幕", title: "屏幕 · Windows · 手机 · 缩放", phone: true, ...screenView("windows", true), steps: [{ click: '[aria-label="缩放"]' }] },
  { id: "screen-phone-full", group: "屏幕", title: "屏幕 · 手机 · 全屏", phone: true, ...screenView("live", true), steps: [{ click: '[aria-label="全屏"]' }] },
  { id: "screen-phone-full-tools", group: "屏幕", title: "屏幕 · 手机 · 全屏 · 工具", phone: true, ...screenView("live", true), steps: [{ click: '[aria-label="全屏"]' }, { click: '[aria-label="工具"]' }] },
  { id: "screen-phone-command", group: "屏幕", title: "屏幕 · 手机 · 按住 ⌘", phone: true, ...screenView("live", true), steps: [{ click: '[aria-label="Command"]' }] },
  // Measured once the note is up: it comes with the stream's first clipboard event, at no set time.
  { id: "screen-copied", group: "屏幕", title: "屏幕 · 远端复制了（浏览器没让直接写剪贴板）", ...screenView("copied"), steps: [{ hover: '[role="status"]:has(button)' }] },
  { id: "screen-dragging", group: "屏幕", title: "屏幕 · 拖文件进来", ...screenView("dragging") },
  { id: "screen-sending", group: "屏幕", title: "屏幕 · 文件发送中", ...screenView("sending") },
  { id: "screen-sent", group: "屏幕", title: "屏幕 · 文件已发到那台机器", ...screenView("sent"), steps: toTheBar },
  { id: "screen-sent-phone", group: "屏幕", title: "屏幕 · 文件已发到那台机器 · 手机", phone: true, ...screenView("sent", true) },
  { id: "app-station-screens", group: "屏幕", title: "station · 屏幕", app: true, demo: screensDemo(), steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-station-screens-lacking", group: "屏幕", title: "station · 屏幕 · 缺权限", app: true, demo: screensDemo("live", SCREENS_LACKING), steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-station-screens-outdated", group: "屏幕", title: "station · 屏幕 · 要更新", app: true, demo: screensDemo("live", OUTDATED), steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-screen", group: "屏幕", title: "station · 打开屏幕", app: true, demo: screensDemo(), steps: [{ click: '[aria-label^="Station"]' }, { click: 'a[href$="/screen/desktop"]' }, ...toTheBar] },
  { id: "app-screen-tab-menu", group: "屏幕", title: "station · 浏览器标签页 · 控制中心", app: true, demo: screensDemo(), steps: [{ click: '[aria-label^="Station"]' }, { click: 'a[href$="/screen/browser%3A7F3A9C"]' }, { click: 'button:has-text("控制中心")' }] },
  { id: "app-chat-screen-links", group: "屏幕", title: "对话里的屏幕链接", app: true, demo: screenLinksDemo },
  { id: "phone-chat-screen-links", group: "屏幕", title: "手机 · 对话里的屏幕链接", app: true, phone: true, demo: screenLinksDemo },
  { id: "app-chat-simulator-link", group: "屏幕", title: "对话里的模拟器链接 · 在侧边打开", app: true, demo: simulatorLinkDemo, steps: [{ hover: 'text=iOS 模拟器 · 1179×2556' }] },
  { id: "app-chat-simulator-side", group: "屏幕", title: "模拟器在对话侧边", app: true, demo: simulatorLinkDemo, steps: [{ hover: 'a[href*="simulator"]' }, { click: '[aria-label="在侧边打开"]' }] },
  { id: "app-chat-adb-link", group: "屏幕", title: "对话里的共享调试链接", app: true, demo: adbLinksDemo(false) },
  { id: "phone-chat-adb-link", group: "屏幕", title: "手机 · 对话里的共享调试链接（已共享）", app: true, phone: true, demo: adbLinksDemo(true) },
  { id: "phone-station-screens", group: "屏幕", title: "手机 · station 的屏幕", app: true, phone: true, demo: screensDemo(), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { text: "Studio" }] },
  // ── a Mac station's grants to still.fail Helper (docs/remote-screens.md "Grants") ──
  { id: "app-station-permissions", group: "权限", title: "station · 权限 · 都已允许", app: true, demo: permissionsDemo("granted"), steps: toStation("设置") },
  { id: "app-station-permissions-missing", group: "权限", title: "station · 权限 · 缺几项", app: true, demo: permissionsDemo("missing"), steps: toStation("设置") },
  { id: "app-station-permissions-asking", group: "权限", title: "station · 权限 · 申请中（可远程点）", app: true, demo: permissionsDemo("asking"), steps: toStation("设置") },
  { id: "app-station-permissions-asking-there", group: "权限", title: "station · 权限 · 申请中（要去那台 Mac）", app: true, demo: permissionsDemo("askingThere"), steps: toStation("设置") },
  // Asked for where the screen can be driven: one tap, and the desktop opens with the window up on it.
  { id: "app-station-permissions-requested", group: "权限", title: "station · 权限 · 申请后打开屏幕", app: true, demo: permissionsDemo("missing", screensDemo()), steps: [...toStation("设置"), { click: '[aria-label="申请「桌面」"]' }, ...toTheBar] },
  { id: "app-station-permissions-read-only", group: "权限", title: "station · 权限 · 只读成员", app: true, demo: permissionsDemo("readOnly"), steps: toStation("设置") },
  { id: "app-station-permissions-none", group: "权限", title: "station · 权限 · 不是 Mac（不显示）", app: true, demo: permissionsDemo("none"), steps: toStation("设置") },
  { id: "phone-station-permissions", group: "权限", title: "手机 · station · 权限 · 都已允许", app: true, phone: true, demo: permissionsDemo("granted"), steps: toPhoneStation },
  { id: "phone-station-permissions-missing", group: "权限", title: "手机 · station · 权限 · 缺几项", app: true, phone: true, demo: permissionsDemo("missing"), steps: toPhoneStation },
  { id: "phone-station-permissions-asking", group: "权限", title: "手机 · station · 权限 · 申请中（可远程点）", app: true, phone: true, demo: permissionsDemo("asking"), steps: toPhoneStation },
  { id: "phone-station-permissions-asking-there", group: "权限", title: "手机 · station · 权限 · 申请中（要去那台 Mac）", app: true, phone: true, demo: permissionsDemo("askingThere"), steps: toPhoneStation },
  { id: "phone-station-permissions-requested", group: "权限", title: "手机 · station · 权限 · 申请后打开屏幕", app: true, phone: true, demo: permissionsDemo("missing", screensDemo()), steps: [...toPhoneStation, { click: '[aria-label="申请「桌面」"]' }] },
  { id: "phone-station-permissions-read-only", group: "权限", title: "手机 · station · 权限 · 只读成员", app: true, phone: true, demo: permissionsDemo("readOnly"), steps: toPhoneStation },
  { id: "phone-station-permissions-none", group: "权限", title: "手机 · station · 权限 · 不是 Mac（不显示）", app: true, phone: true, demo: permissionsDemo("none"), steps: toPhoneStation },
  // The variables what a station starts for its agents runs with (docs/agent-env.md): set, none yet, and edited on a phone.
  { id: "app-station-full", group: "应用", title: "station · 什么都有的 Mac", app: true, demo: fullStation(), steps: [{ click: '[aria-label^="Station"]' }] },
  { id: "app-station-full-settings", group: "应用", title: "station · 什么都有的 Mac · 设置", app: true, demo: fullStation(), steps: toStation("设置") },
  { id: "app-station-network", group: "应用", title: "station · 高级网络设置", app: true, demo: fullStation(), steps: [...toStation("设置"), { click: 'button:has-text("高级网络设置")' }] },
  { id: "app-station-network-select", group: "应用", title: "station · 算法选择", app: true, demo: fullStation(), steps: [...toStation("设置"), { click: 'button:has-text("高级网络设置")' }, { click: '[role="combobox"][aria-label="拥塞控制算法"]' }] },
  { id: "app-station-full-machine", group: "应用", title: "station · 什么都有的 Mac · 软件与设备", app: true, demo: fullStation(), steps: toStation("软件与设备") },
  { id: "app-station-software", group: "设置", title: "station · 软件与更新 · 都能安装", app: true, demo: softwareDemo("installable"), steps: toStation("软件与设备") },
  { id: "app-station-software-no-npm", group: "设置", title: "station · 软件与更新 · 没有 npm、无法安装 Node", app: true, demo: softwareDemo("noNpm"), steps: toStation("软件与设备") },
  { id: "app-station-agent-env", group: "设置", title: "station · Agent 环境变量", app: true, demo: agentEnvDemo("set"), steps: toStation("设置") },
  { id: "app-station-agent-env-empty", group: "设置", title: "station · Agent 环境变量 · 暂无", app: true, demo: agentEnvDemo("empty"), steps: toStation("设置") },
  { id: "app-station-agent-env-wrong", group: "设置", title: "station · Agent 环境变量 · 有错的行", app: true, demo: agentEnvDemo("wrong"), steps: toStation("设置") },
  { id: "phone-station-agent-env", group: "设置", title: "手机 · station · Agent 环境变量", app: true, phone: true, demo: agentEnvDemo("set"), steps: toPhoneStation },
  { id: "phone-station-agent-env-edit", group: "设置", title: "手机 · station · Agent 环境变量 · 编辑", app: true, phone: true, demo: agentEnvDemo("wrong"), steps: [...toPhoneStation, { text: "编辑变量" }] },
  { id: "phone-screen", group: "屏幕", title: "手机 · 打开屏幕", app: true, phone: true, demo: screensDemo(), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { text: "Studio" }, { text: "登录 · GitHub" }] },

  // ── the phone ──
  { id: "phone-chat", group: "手机", title: "对话", app: true, phone: true },
  { id: "phone-station-files", group: "手机", title: "对话 · Station 文件", app: true, phone: true, steps: [{ click: '[aria-label="添加文件"]' }, { text: "Station 文件" }, { text: "主目录" }, { text: "Downloads" }, { text: "login-375.png" }] },
  { id: "phone-station-file-card", group: "手机", title: "对话 · Station 文件的卡片", app: true, phone: true, steps: [{ click: '[aria-label="添加文件"]' }, { text: "Station 文件" }, { text: "下载" }, { text: "login-375.png" }, { text: "添加 1 个" }, { click: "[data-card]" }] },
  { id: "phone-chat-station", group: "手机", title: "对话 · station 卡片", app: true, phone: true, steps: [{ click: '[aria-label$="的名片"]' }, { text: "Station" }] },
  { id: "phone-chat-pick", group: "手机", title: "对话 · 选取一段", app: true, phone: true, steps: [{ hold: '[data-role="agent"][data-ts] li' }] },
  { id: "phone-home", group: "手机", title: "首页", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }] },
  { id: "phone-share", group: "手机", title: "分享进来 · 上次那个 chat 在最前", app: true, phone: true, ...sharing("kept") },
  { id: "phone-share-opened", group: "手机", title: "分享进来 · 点了之后的 chat", app: true, phone: true, ...sharing("kept"), steps: [{ click: 'button:has-text("youtube.com 的链接上次发到这里")' }] },
  { id: "phone-share-new-chat", group: "手机", title: "分享进来 · 新 chat，几台 station", app: true, phone: true, ...sharing("new") },
  { id: "phone-share-none", group: "手机", title: "分享进来 · 没有 chat 也没有 station", app: true, phone: true, ...sharing("none") },
  { id: "phone-share-loading", group: "手机", title: "分享进来 · 正在读取", app: true, phone: true, ...sharing("loading") },
  { id: "phone-share-search", group: "手机", title: "分享进来 · 搜索 chat", app: true, phone: true, ...sharing("search"), steps: [{ text: "搜索" }, { key: "N" }, { key: "A" }, { key: "S" }] },
  { id: "phone-search", group: "手机", title: "搜索全部内容", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { text: "搜索全部内容" }, { key: "c" }, { key: "s" }, { key: "v" }] },
  { id: "phone-share-search-none", group: "手机", title: "分享进来 · 搜索没找到", app: true, phone: true, ...sharing("search"), steps: [{ text: "搜索" }, { key: "z" }, { key: "z" }] },
  { id: "phone-agent", group: "手机", title: "agent 名片", app: true, phone: true, steps: [{ click: '[aria-label$="的名片"]' }] },
  { id: "phone-chat-history-turns", group: "手机", title: "执行历史 · 一轮一轮", app: true, phone: true, steps: [{ click: '[aria-label$="的名片"]' }, { text: "历史" }], demo: historyTurns },
  { id: "phone-chat-history-steps", group: "手机", title: "执行历史 · 展开的一组", app: true, phone: true, steps: [{ click: '[aria-label$="的名片"]' }, { text: "历史" }, { text: "读取 Win11 上 pnpm shot 的输出 · 共 8 项" }], demo: historyTurns },
  { id: "phone-chat-info", group: "手机", title: "对话信息", app: true, phone: true, steps: [{ click: '[aria-label="对话信息"]' }] },
  { id: "phone-chat-relay-one", group: "手机", title: "对话 · 接力到频道 · 只有一个 bot", app: true, phone: true, demo: relayDemo(TWO_BOTS.slice(0, 1)), steps: [{ click: '[aria-label="对话信息"]' }, { text: "接力到频道…" }] },
  { id: "phone-chat-relay-two-bots", group: "手机", title: "对话 · 接力到频道 · 一个 workspace 两个 bot（选中这个对话的）", app: true, phone: true, demo: relayDemo(TWO_BOTS), steps: [{ click: '[aria-label="对话信息"]' }, { text: "接力到频道…" }] },
  { id: "phone-chat-relay", group: "手机", title: "对话 · 接力到频道", app: true, phone: true, demo: relayDemo(), steps: [{ click: '[aria-label="对话信息"]' }, { text: "接力到频道…" }, { text: "#cue-dev" }] },
  { id: "phone-files", group: "手机", title: "文件", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="文件"]' }] },
  { id: "phone-profile", group: "手机", title: "Profile", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }] },
  { id: "phone-profile-kinds", group: "手机", title: "Profile · 各类账号（分组带标记）", app: true, phone: true, demo: everyKind, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }] },
  { id: "phone-memory", group: "手机", title: "记忆", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }] },
  { id: "phone-memory-skill", group: "手机", title: "记忆 · 项目", app: true, phone: true, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "记忆" }, { text: "Studio" }, { text: "acme-web" }] },
  { id: "phone-profile-add-install", group: "手机", title: "添加 Profile · SuperGrok · 先安装 Grok Build", app: true, phone: true, demo: installFlowDemo("missing"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }] },
  { id: "phone-profile-workspaces", group: "手机", title: "Profile · 也给加入的 workspace 用", app: true, phone: true, demo: profileFor(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-opencode-signing-in", group: "手机", title: "Profile · OpenCode Go 重新登录（设备码）", app: true, phone: true, demo: openCode(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-kimi-signing-in", group: "手机", title: "Profile · Kimi Code 重新登录（设备码）", app: true, phone: true, demo: kimiCode, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-supergrok", group: "手机", title: "Profile · SuperGrok 订阅（Grok Build）", app: true, phone: true, demo: superGrok(false), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-claude-signing-in", group: "手机", title: "Profile · Claude 订阅重新登录（贴回代码）", app: true, phone: true, demo: claudeSignIn, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-claude-signing-in-station", group: "手机", title: "Profile · Claude 订阅重新登录 ·「其他方式」打开", app: true, phone: true, demo: claudeSigningIn(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }, { click: '[aria-label="其他方式"]' }] },
  { id: "phone-profile-supergrok-signing-in", group: "手机", title: "Profile · SuperGrok 重新登录（设备码）", app: true, phone: true, demo: superGrok(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-add-kimi", group: "手机", title: "添加 Profile · Kimi：订阅 Kimi Code 或 API key", app: true, phone: true, demo: kimiMethodDemo(), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }] },
  { id: "phone-profile-add-cursor", group: "手机", title: "添加 Profile · 选择服务商（Cursor 只有订阅）", app: true, phone: true, demo: cursorPickDemo(), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }] },
  { id: "phone-profile-cursor-signing-in", group: "手机", title: "Profile · Cursor 重新登录（无代码，打开页面确认）", app: true, phone: true, demo: cursorAccount(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-profile-pick-models-reading", group: "手机", title: "添加 Profile · 选择模型 · 正在读取", app: true, phone: true, demo: pickModelsDemo(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }, { text: ADD }] },
  { id: "phone-profile-pick-models", group: "手机", title: "添加 Profile · 选择模型", app: true, phone: true, demo: pickModelsDemo(false), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }, { text: ADD }] },
  { id: "phone-profile-add-devin", group: "手机", title: "添加 Profile · 选择服务商（Cursor、Devin 只有订阅）", app: true, phone: true, demo: cursorPickDemo(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { click: '[aria-label="添加 Profile"]' }] },
  { id: "phone-profile-devin-signing-in", group: "手机", title: "Profile · Devin 重新登录（贴回代码）", app: true, phone: true, demo: devinAccount(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="Profile"]' }, { text: "lin@acme.dev" }] },
  { id: "phone-new-chat-not-shared", group: "手机", title: "新建对话 · 加入的 station 没有开放的 Profile", app: true, phone: true, demo: notShared, steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="新建对话"]' }] },
  { id: "phone-station-add-existing", group: "手机", title: "添加 station · 已有的", app: true, phone: true, demo: joining("list"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { click: '[aria-label="添加 station"]' }, { text: "已有的 station" }] },
  { id: "phone-station-add-existing-done", group: "手机", title: "添加 station · 已加入", app: true, phone: true, demo: joining("list"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { click: '[aria-label="添加 station"]' }, { text: "已有的 station" }, { text: "添加到此 workspace" }] },
  { id: "phone-station-add-existing-error", group: "手机", title: "添加 station · 加入失败", app: true, phone: true, demo: joining("error"), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { click: '[aria-label="添加 station"]' }, { text: "已有的 station" }, { text: "添加到此 workspace" }] },
  { id: "phone-station-workspaces", group: "手机", title: "station · 在几个 workspace 里", app: true, phone: true, demo: memberships(true), steps: [{ click: '[aria-label="返回"]' }, { click: '[aria-label="设置"]' }, { text: "Station" }, { text: "Studio" }] },
  // The admin console (admin.still.fail), its sidebar beside the page: from the overview to 中继.
  { id: "admin-relays", group: "管理后台", title: "中继 · 24 小时", render: adminConsole, demo: relaysDemo("normal"), steps: toRelays },
  { id: "admin-relays-week", group: "管理后台", title: "中继 · 7 天", render: adminConsole, demo: relaysDemo("normal"), steps: [...toRelays, { text: "7 天" }] },
  { id: "admin-relays-old", group: "管理后台", title: "中继 · 旧 cloud 没有数据（404）", render: adminConsole, demo: relaysDemo("old"), steps: toRelays },
  { id: "phone-admin-relays", group: "手机", title: "管理后台 · 中继", render: adminConsole, phone: true, demo: relaysDemo("normal"), steps: toRelays },
];
