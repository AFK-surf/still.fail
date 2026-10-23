// What the site says, in Chinese (its page at /) and in English (its page at /en/: site/en/index.html). The page is
// built to HTML in each (prerender.tsx); the browser takes over the one it is on (main.tsx, by the root's lang).
import { createContext, useContext } from "react";

export type SiteLang = "zh" | "en";

const ZH = {
  download: "下载", open: "打开", appleSilicon: "Apple 芯片", downloadGo: "下载 →", androidQr: "下载 Android 版的二维码", androidScan: "Android 扫码下载",
  other: "English", otherHref: "/en/",
  title: "One devices.",
  lede: "在任何一台上，用所有设备。",
  start: "开始使用",
  steps: ["设备直连", "像一台电脑", "手机上也一样"],
  /** The demo's machines as it names them (demo/station.ts; demo/english.ts in English). */
  machines: ["笔记本", "Studio", "Mini", "服务器"],
  phoneTitle: "still.fail 手机版",
  install: ["一条命令", "加入一台电脑"],
  installSteps: ["→ 下载 still.fail station · 加入 workspace「Acme」", "→ 注册为登录启动的服务", "✓ station 已上线"],
  web: "网页版", terms: "服务条款", privacy: "隐私政策", trademark: "商标", legal: "",
  theme: { label: "主题", system: "跟随系统", light: "浅色", dark: "深色" },
};

const EN: typeof ZH = {
  download: "Download", open: "Open", appleSilicon: "Apple silicon", downloadGo: "Download →", androidQr: "A code to scan for the Android app", androidScan: "Scan for Android",
  other: "中文", otherHref: "/",
  title: "One devices.",
  lede: "Use all of them from any one.",
  start: "Get started",
  steps: ["Connected directly", "Like one computer", "The same on your phone"],
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
