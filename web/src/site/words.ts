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
    { q: "要付费吗？", a: "目前免费，有使用额度（workspace、成员和 station 的数量）。agent 用的是你自己的订阅账号或 API 密钥。" },
    { q: "代码和对话会传到云端吗？", a: "不会。对话、文件和记录保存在你的电脑上，云端只负责账号和中继。中继只转发加密数据，看不到内容。" },
    { q: "电脑要一直开着吗？", a: "agent 在你的电脑上运行，所以电脑要开着、联网。still.fail station 随登录启动，不用开着窗口。" },
    { q: "不在同一个网络里，能连上吗？", a: "能。设备之间先直接连接，连不通时经加密中继转发，不用配置端口、VPN 或内网穿透。" },
    { q: "会影响我的 agent 账号吗？", a: "still.fail 运行的是这些 agent 的官方命令行，和你在终端里用它们一样，不修改它们，也不绕过它们的限制。" },
    { q: "哪些电脑能加入？", a: "Mac、Windows 和 Linux。在电脑上运行一条命令，它就成为 workspace 里的一台 station。" },
    { q: "iPhone 和 iPad 能用吗？", a: "App 即将上线，现在可以用网页版，添加到主屏幕后像 App 一样打开。" },
    { q: "开源吗？", a: "开源，采用 MIT 许可，代码在 GitHub。" },
  ],
  other: "English", otherHref: "/en/",
  title: "One devices.",
  start: "开始使用",
  filmTitle: "在手机上交代，在电脑上做完",
  soundOn: "打开声音", soundOff: "关闭声音",
  scenesTitle: "能用来做什么",
  /** What it is for, each by what it does (`soon`: not yet), shown on the phone's app at its page (`at`: its path in
   *  the workspace, or "chat": its chat, the story played). */
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
    { q: "Does it cost anything?", a: "It's free for now, within limits on workspaces, members and stations. Agents use your own subscriptions or API keys." },
    { q: "Do my code and chats go to the cloud?", a: "No. Chats, files and history stay on your computers; the cloud only handles accounts and relays. A relay passes on encrypted data it can't read." },
    { q: "Does my computer have to stay on?", a: "Agents run on your computer, so it has to be on and online. The still.fail station starts at login; no window needs to stay open." },
    { q: "Does it work across networks?", a: "Yes. Devices connect directly, and through an encrypted relay when they can't. No ports, VPN or tunnels to set up." },
    { q: "Does it affect my agent accounts?", a: "still.fail runs each agent's official command-line tool, the same as you would in a terminal, without changing it or working around its limits." },
    { q: "Which computers can join?", a: "Mac, Windows and Linux. Run one command on a computer and it becomes a station in your workspace." },
    { q: "Can I use it on an iPhone or iPad?", a: "The app is coming. Until then, use the web app; added to the home screen, it opens like an app." },
    { q: "Is it open source?", a: "Yes, under the MIT license. The code is on GitHub." },
  ],
  other: "中文", otherHref: "/",
  title: "One devices.",
  start: "Get started",
  filmTitle: "Asked on a phone, done on a computer",
  soundOn: "Turn sound on", soundOff: "Turn sound off",
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

export const SiteLangContext = createContext<SiteLang>("zh");

/** The site's words in the page's language. */
export function useSay(): typeof ZH {
  return WORDS[useContext(SiteLangContext)];
}

/** The page's language. */
export function useSiteLang(): SiteLang {
  return useContext(SiteLangContext);
}
