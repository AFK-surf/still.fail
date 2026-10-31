// What the site says, in Chinese (its page at /) and in English (its page at /en/: site/en/index.html). The page is
// built to HTML in each (prerender.tsx); the browser takes over the one it is on (main.tsx, by the root's lang).
import { createContext, useContext } from "react";

export type SiteLang = "zh" | "en";

const ZH = {
  download: "下载", open: "打开", androidQr: "下载 Android 版的二维码", androidScan: "扫码下载 Android 版",
  /** The downloads (Site.tsx Downloads): its title, every app in a line, and the button for the device the page is on. */
  downloads: {
    title: "下载 still.fail",
    main: { mac: "下载 Mac 版", windows: "下载 Windows 版", android: "下载 Android 版", other: "打开网页版" },
    all: "全部版本", web: "网页版",
  },
  /** What it works with (Site.tsx Works): the agents it runs, and where they are directed from. */
  works: {
    title: "接上你在用的",
    agents: "Agent",
    from: "在这些地方指挥",
    places: { app: "still.fail（手机、电脑、网页）", slack: "Slack", feishu: "飞书" },
  },
  /** What a visitor asks first (Site.tsx Questions), each with its answer. */
  questionsTitle: "常见问题",
  questions: [
    { q: "和直接在终端里用 Claude Code 有什么不同？", a: "终端里的 agent 只能坐在那台电脑前用。still.fail 把你每台电脑上的 agent 放到一处：在手机、Slack 或飞书里随时交代和查看，看每台电脑的负载，密钥在 agent 使用前由你批准。agent 本身不变。" },
    { q: "要付费吗？", a: "目前免费，免费版限制 workspace 和成员数量。agent 用的是你自己的订阅账号或 API 密钥。" },
    { q: "代码和对话会传到云端吗？", a: "不会。对话、文件和记录保存在你的电脑上，云端只负责账号和中继。中继只转发加密数据，看不到内容。" },
    { q: "电脑要一直开着吗？", a: "agent 在你的电脑上运行，所以电脑要开着、联网。still.fail station 随登录启动，不用开着窗口。" },
    { q: "不在同一个网络里，能连上吗？", a: "能。设备之间先直接连接，连不通时经加密中继转发，不用配置端口、VPN 或内网穿透。" },
    { q: "会影响我的 agent 账号吗？", a: "still.fail 运行的是这些 agent 的官方命令行，和你在终端里用它们一样，不修改它们，也不绕过它们的限制。" },
    { q: "哪些电脑能加入？", a: "Mac、Windows 和 Linux。在电脑上运行一条命令，它就成为 workspace 里的一台 station。" },
    { q: "iPhone 和 iPad 能用吗？", a: "App 即将上线，现在可以用网页版，添加到主屏幕后像 App 一样打开。" },
    { q: "开源吗？", a: "开源，采用 MIT 许可，代码在 GitHub。" },
  ],
  /** What the last release brought (Site.tsx Shipped): its number and day, how many new, better and fixed, and its
   *  first new things (in Chinese only: the notes are). */
  shipped: {
    title: "每晚更新",
    when: (version: string, date: string) => `${version} · ${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`,
    counts: (c: { fresh: number; better: number; fixed: number }) => [c.fresh && `${c.fresh} 项新功能`, c.better && `${c.better} 项改进`, c.fixed && `${c.fixed} 项修复`].filter(Boolean).join(" · "),
    lines: true,
  },
  /** The page's last word: its title again, and the ways in. */
  closing: "One devices.",
  other: "English", otherHref: "/en/",
  title: "One devices.",
  start: "开始使用",
  scenesTitle: "能用来做什么",
  /** What it is for, each by what it does (`soon`: not yet), shown on the phone's app at its page (`at`: its path in
   *  the workspace, or "chat": its chat), as it opens there (featurePage). */
  scenes: [
    { title: "Agent", text: "Claude Code、Codex 等 agent 在你的电脑上运行，用手机、Slack 或飞书指挥", soon: false, at: "chat" },
    { title: "资源管理", text: "每台的 CPU、内存、磁盘和文件都在一处，任务按负载排队", soon: false, at: "s/local/overview" },
    { title: "密钥管理", text: "订阅账号（Profile）和 API 密钥集中保存，agent 使用前由你在手机上批准", soon: false, at: "settings/vault" },
    { title: "IoT", text: "摄像头、传感器和家里的设备，也连进来", soon: true, at: "" },
  ],
  soon: "即将支持",
  /** The demo's machines as it names them (demo/station.ts; demo/english.ts in English). */
  machines: ["笔记本", "Studio", "Mini", "服务器"],
  phoneTitle: "still.fail 手机版",
  install: ["一条命令", "加入一台电脑"],
  installSteps: ["→ 下载 still.fail station · 加入 workspace「Acme」", "→ 注册为登录启动的服务", "✓ station 已上线"],
  web: "网页版", terms: "服务条款", privacy: "隐私政策", trademark: "商标", legal: "",
  theme: { label: "主题", system: "跟随系统", light: "浅色", dark: "深色" },
};

const EN: typeof ZH = {
  download: "Download", open: "Open", androidQr: "A code to scan for the Android app", androidScan: "Scan for Android",
  downloads: {
    title: "Download still.fail",
    main: { mac: "Download for Mac", windows: "Download for Windows", android: "Download for Android", other: "Open the web app" },
    all: "Every version", web: "Web app",
  },
  works: {
    title: "Works with what you use",
    agents: "Agents",
    from: "Direct them from",
    places: { app: "still.fail (phone, computer, web)", slack: "Slack", feishu: "Feishu" },
  },
  questionsTitle: "Questions",
  questions: [
    { q: "How is it different from Claude Code in a terminal?", a: "An agent in a terminal is used at that computer. still.fail puts the agents on all your computers in one place: direct and follow them from your phone, Slack or Feishu, see each computer's load, and approve a key before an agent uses it. The agents themselves are unchanged." },
    { q: "Does it cost anything?", a: "It's free for now. The free plan limits workspaces and members. Agents use your own subscriptions or API keys." },
    { q: "Do my code and chats go to the cloud?", a: "No. Chats, files and history stay on your computers; the cloud only handles accounts and relays. A relay passes on encrypted data it can't read." },
    { q: "Does my computer have to stay on?", a: "Agents run on your computer, so it has to be on and online. The still.fail station starts at login; no window needs to stay open." },
    { q: "Does it work across networks?", a: "Yes. Devices connect directly, and through an encrypted relay when they can't. No ports, VPN or tunnels to set up." },
    { q: "Does it affect my agent accounts?", a: "still.fail runs each agent's official command-line tool, the same as you would in a terminal, without changing it or working around its limits." },
    { q: "Which computers can join?", a: "Mac, Windows and Linux. Run one command on a computer and it becomes a station in your workspace." },
    { q: "Can I use it on an iPhone or iPad?", a: "The app is coming. Until then, use the web app; added to the home screen, it opens like an app." },
    { q: "Is it open source?", a: "Yes, under the MIT license. The code is on GitHub." },
  ],
  shipped: {
    title: "Shipped every night",
    when: (version: string, date: string) => `${version} · ${new Date(`${date}T00:00:00Z`).toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })}`,
    counts: (c: { fresh: number; better: number; fixed: number }) => [c.fresh && `${c.fresh} new`, c.better && `${c.better} improved`, c.fixed && `${c.fixed} fixed`].filter(Boolean).join(" · "),
    lines: false,
  },
  closing: "One devices.",
  other: "中文", otherHref: "/",
  title: "One devices.",
  start: "Get started",
  scenesTitle: "What it's for",
  scenes: [
    { title: "Agents", text: "Claude Code, Codex and other agents run on your computers; direct them from your phone, Slack or Feishu", soon: false, at: "chat" },
    { title: "Resources", text: "Every device's CPU, memory, disk and files in one place; tasks queue by load", soon: false, at: "s/local/overview" },
    { title: "Keys", text: "Subscriptions (Profiles) and API keys kept in one place; an agent uses one only once you approve it on your phone", soon: false, at: "settings/vault" },
    { title: "IoT", text: "Cameras, sensors and things at home, joined in too", soon: true, at: "" },
  ],
  soon: "Coming",
  machines: ["Laptop", "Studio", "Mini", "Server"],
  phoneTitle: "still.fail on a phone",
  install: ["One command", "adds a computer"],
  installSteps: ["→ Downloading still.fail station · joining workspace “Acme”", "→ Registering it to start at login", "✓ Station online"],
  web: "Web app", terms: "Terms", privacy: "Privacy", trademark: "Trademark", legal: "/en",
  theme: { label: "Theme", system: "System", light: "Light", dark: "Dark" },
};

export const WORDS: Record<SiteLang, typeof ZH> = { zh: ZH, en: EN };

/**
 * The page of a phone showing what it is for (a scene's `at`): the phone's app opened there, built to HTML with the site
 * (web/site-prerender.mjs) and nothing more, no script: a picture of it, as the phone shows it (the phone's rules go
 * by the screen's width, which in its frame is a phone's), not one more app run on the page's thread (../picture.ts).
 */
export const featurePage = (at: string) => `phone-${at.replaceAll("/", "-")}`;

export const SiteLangContext = createContext<SiteLang>("zh");

/** The site's words in the page's language. */
export function useSay(): typeof ZH {
  return WORDS[useContext(SiteLangContext)];
}

/** The page's language. */
export function useSiteLang(): SiteLang {
  return useContext(SiteLangContext);
}
