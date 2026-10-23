// The demo's made-up data in English, for the site's English page (site/OneComputer.tsx): what a station says in
// Chinese (its figures, its accounts, the workspace's machines), said in English. The app's own words come from its
// catalog already; this is only what the demo makes up, read where the demo answers (mount.tsx).

/** Each a whole phrase or a pattern, the longer and more particular first. */
const SAID: [RegExp, string][] = [
  [/^Claude Code 已登录 (.+)（(.+)）$/, "Claude Code signed in as $1 ($2)"],
  [/^Codex 已登录 (.+)（(.+)）$/, "Codex signed in as $1 ($2)"],
  [/^(\d+) 个 agent 进程 (.+)$/, "$1 agent processes, $2"],
  [/^已启用 (\d+) \/ (\d+) 个模型$/, "$1 of $2 models on"],
  [/^(\d+) 小时 (\d+) 分钟后刷新$/, "Resets in $1 h $2 min"],
  [/^(\d+) 天 (\d+) 小时后刷新$/, "Resets in $1 d $2 h"],
  [/^(\d+) 天 (\d+) 小时$/, "$1 d $2 h"],
  [/^(\d+) 小时$/, "$1 hours"],
  [/^剩余 (.+) \/ (.+)$/, "$1 free of $2"],
  [/^进程占用 (.+)$/, "$1 for its processes"],
  [/^空闲 (\d+)%$/, "$1% idle"],
  [/^剩 (.+)$/, "$1 free"],
  [/^负载 (.+)$/, "load $1"],
  [/^共 (.+)$/, "of $1"],
  [/（本机）/g, " (this machine)"],
  [/(\d+) 个 agent 正在运行/g, "$1 agent running"],
  [/(\d+) 个任务正在运行/g, "$1 task running"],
  [/已运行 (\d+) 天/g, "up $1 days"],
  [/(\d+) 核/g, "$1 cores"],
  [/空闲/g, "idle"],
];

const WORDS: Record<string, string> = {
  每周: "Weekly", 已登录: "Signed in", 可用: "Available", 已停用: "Disabled", "CPU 负载": "CPU load", 内存: "Memory", 磁盘: "Disk",
  主机名: "Hostname", 芯片: "Chip", 已运行: "Uptime", "CPU 空闲": "CPU idle", 内存剩: "Memory free", 磁盘剩: "Disk free",
  直连: "Direct", 中继: "Relay", 笔记本: "Laptop", 服务器: "Server", 下载: "Downloads", 桌面: "Desktop",
};

const HAN = /[㐀-鿿（）]/;

/** A string in English, where the demo knows how to say it; else as it is. */
export function english(text: string): string {
  if (!HAN.test(text)) return text;
  const whole = WORDS[text];
  if (whole) return whole;
  let out = text;
  for (const [pattern, to] of SAID) out = out.replace(pattern, to);
  return out.replace(/[^\s·/()（）]+/g, (w) => WORDS[w] ?? w);
}

/** A value (a topic's answer) with every string in it in English; the rest as it is. */
export function inEnglish<T>(value: T): T {
  const turn = (v: unknown): unknown => {
    if (typeof v === "string") return english(v);
    if (Array.isArray(v)) return v.map(turn);
    if (v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, turn(x)]));
    return v;
  };
  return turn(value) as T;
}
