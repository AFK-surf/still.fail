// What the site says, in Chinese (its page at /) and in English (its page at /en/: site/en/index.html). The page is
// built to HTML in each (prerender.tsx); the browser takes over the one it is on (main.tsx, by the root's lang).
import { createContext, useContext } from "react";

export type SiteLang = "zh" | "en";

const ZH = {
  download: "下载", open: "打开", appleSilicon: "Apple 芯片", downloadGo: "下载 →", androidQr: "下载 Android 版的二维码", androidScan: "扫码下载",
  /** The downloads (Site.tsx Downloads): its title, the button for the device the page is on, and each app. */
  downloads: {
    title: "下载 still.fail",
    main: { mac: "下载 Mac 版", windows: "下载 Windows 版", android: "下载 Android 版", other: "打开网页版" },
    phones: "iPhone 和 iPad", phonesNote: "App 即将上线，现在可以用网页版", openWeb: "打开网页版 →", apk: "下载 APK →",
  },
  other: "English", otherHref: "/en/",
  title: "One devices.",
  start: "开始使用",
  filmTitle: "在手机上交代，在电脑上做完",
  soundOn: "打开声音", soundOff: "关闭声音",
  scenesTitle: "能用来做什么",
  /** What it is for, each by what it does (`soon`: not yet), shown on the phone's app at its page (`at`: its path in
   *  the workspace, or "chat": its chat, the story played). */
  scenes: [
    { title: "Agent", text: "Claude Code 和 Codex 在你的电脑上运行，用手机、Slack 或飞书指挥", soon: false, at: "chat" },
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
  download: "Download", open: "Open", appleSilicon: "Apple silicon", downloadGo: "Download →", androidQr: "A code to scan for the Android app", androidScan: "Scan to download",
  downloads: {
    title: "Download still.fail",
    main: { mac: "Download for Mac", windows: "Download for Windows", android: "Download for Android", other: "Open the web app" },
    phones: "iPhone and iPad", phonesNote: "The app is coming; use the web app for now", openWeb: "Open the web app →", apk: "Download the APK →",
  },
  other: "中文", otherHref: "/",
  title: "One devices.",
  start: "Get started",
  filmTitle: "Asked on a phone, done on a computer",
  soundOn: "Turn sound on", soundOff: "Turn sound off",
  scenesTitle: "What it's for",
  scenes: [
    { title: "Agents", text: "Claude Code and Codex run on your computers; direct them from your phone, Slack or Feishu", soon: false, at: "chat" },
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
