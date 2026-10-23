// What the site says, in Chinese (its page at /) and in English (its page at /en/: site/en/index.html). The page is
// built to HTML in each (prerender.tsx); the browser takes over the one it is on (main.tsx, by the root's lang).
import { createContext, useContext } from "react";

export type SiteLang = "zh" | "en";

const ZH = {
  download: "下载", open: "打开", appleSilicon: "Apple 芯片", downloadGo: "下载 →", androidQr: "下载 Android 版的二维码", androidScan: "Android 扫码下载",
  other: "English", otherHref: "/en/",
  title: ["把你的设备", "连成一台电脑"],
  lede: "手机、笔记本、台式机和服务器直接相连。在其中任何一台上，都能打开另一台的文件，用它登录的订阅，让它跑任务。",
  start: "开始使用",
  steps: [
    { title: "设备两两直连", text: "数据不经服务器中转，连不上时才走加密中继" },
    { title: "像一台电脑一样用", text: "所有设备在同一个 still.fail 里，哪台的文件、订阅和任务都在这里" },
    { title: "手机上也一样", text: "在手机上打开，看到的是同样这几台设备" },
  ],
  /** The demo's machines as it names them (demo/station.ts; demo/english.ts in English). */
  machines: ["笔记本", "Studio", "Mini", "服务器"],
  phoneTitle: "still.fail 手机版",
  install: ["一条命令", "加入一台电脑"],
  installLede: "在那台电脑上运行。它已登录的账号和订阅，之后在每台设备上都能用",
  installSteps: ["→ 下载 still.fail station · 加入 workspace「Acme」", "→ 注册为登录启动的服务", "✓ station 已上线"],
  web: "网页版", terms: "服务条款", privacy: "隐私政策", trademark: "商标", legal: "",
  theme: { label: "主题", system: "跟随系统", light: "浅色", dark: "深色" },
};

const EN: typeof ZH = {
  download: "Download", open: "Open", appleSilicon: "Apple silicon", downloadGo: "Download →", androidQr: "A code to scan for the Android app", androidScan: "Scan for Android",
  other: "中文", otherHref: "/",
  title: ["Join your devices", "into one computer"],
  lede: "Your phone, laptops, desktops and servers connect directly. On any one of them, open another's files, use the subscriptions it's signed in to, and have it run tasks.",
  start: "Get started",
  steps: [
    { title: "Devices connect directly", text: "Not through a server; through an encrypted relay only when they can't" },
    { title: "Use them as one computer", text: "All of them in one still.fail: each one's files, subscriptions and tasks in one place" },
    { title: "The same on your phone", text: "Open it on your phone and see the same devices" },
  ],
  machines: ["Laptop", "Studio", "Mini", "Server"],
  phoneTitle: "still.fail on a phone",
  install: ["One command", "adds a computer"],
  installLede: "Run it on that computer. The accounts and subscriptions signed in there can then be used from all your devices.",
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
