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
  [/^(\d+) 分钟前$/, "$1 min ago"],
  [/^(\d+) 小时前$/, "$1 h ago"],
  [/^(\d+) 天前$/, "$1 d ago"],
  [/^(\d+) 分钟后$/, "in $1 min"],
  [/^(\d+) 小时后$/, "in $1 h"],
  [/^1 分钟内$/, "within a minute"],
  [/^(\d+) 个待批准$/, "$1 to approve"],
  [/^代理 · (.+) · (\d+) 小时前用于「(.+)」$/, "Proxy · $1 · used $2 h ago in “$3”"],
  [/^代理 · (.+) · 昨天用于「(.+)」$/, "Proxy · $1 · used yesterday in “$2”"],
  [/^代理 · (.+) · 尚未使用$/, "Proxy · $1 · not used yet"],
  [/^允许 agent 申请 · 代理 · (.+)$/, "Agents may ask · proxy · $1"],
  [/^代理 · 限 (.+)$/, "Proxy · only $1"],
  [/^推送 (.+) 分支并开 PR$/, "Push the $1 branch and open a PR"],
  [/(\d+) 个 agent 正在运行/g, "$1 agent running"],
  [/(\d+) 个任务正在运行/g, "$1 task running"],
  [/已运行 (\d+) 天/g, "up $1 days"],
  [/(\d+) 核/g, "$1 cores"],
  [/空闲/g, "idle"],
];

const WORDS: Record<string, string> = {
  每周: "Weekly", 已登录: "Signed in", 可用: "Available", 已停用: "Disabled", "CPU 负载": "CPU load", 内存: "Memory", 磁盘: "Disk",
  主机名: "Hostname", 芯片: "Chip", 已运行: "Uptime", "CPU 空闲": "CPU idle", 内存剩: "Memory free", 磁盘剩: "Disk free",
  我的密钥: "My keys", Stripe测试密钥: "Stripe test key", "Stripe 测试密钥": "Stripe test key", 登录页手机适配: "Login page on phones", 订单导出支持CSV: "CSV export for orders", "跟随默认 · 本对话内": "Default · for this chat", 值: "Value", 林晓: "Lin Xiao",
    直连: "Direct", 中继: "Relay", 笔记本: "Laptop", 服务器: "Server", 下载: "Downloads", 桌面: "Desktop",
};

/** The chats' words, whole: what the people ask and the agents answer (fixtures.ts, story.ts), and what they are doing. */
const LINES: Record<string, string> = {
  // The chat the story plays in.
  "登录页在手机上显示不对，帮我修一下": "The login page looks wrong on phones, can you fix it?",
  "昨天的提交都在动登录页，手机上按钮是写死的 320px 宽，会超出屏幕。": "Yesterday's commits all touched the login page; on phones its button is fixed at 320px wide, wider than the screen.",
  "登录按钮在手机上写死了 320px 宽，超出了屏幕。\n\n- 改成撑满容器，375px 宽下截图看过了，不再超出\n- 分支 `fix/login-button`":
    "The login button was fixed at 320px wide on phones, wider than the screen.\n\n- It now fills its container; checked in a screenshot at 375px, it fits\n- Branch `fix/login-button`",
  "表单看着还是有点偏": "The form still looks a bit off-centre",
  "按钮不超出了，但整个表单左右留白不对称，看着还是歪的。": "The button fits now, but the form's margins differ left and right, so it still looks lopsided.",
  "再看了一遍 375px 的截图：表单左右留白是 8px 和 24px，所以按钮看着还是歪的。改成左右各 16px，现在居中了，测试都过了。":
    "Looked at the 375px screenshot again: the form had 8px on the left and 24px on the right, so the button looked lopsided. Now 16px each side, centred, and the tests pass.",
  "深色模式下登录按钮也看不见": "In dark mode the login button can't be seen either",
  "深色模式下按钮的字和底色都写死成 #111，所以整个按钮看不见。": "In dark mode the button's text and background are both fixed at #111, so the whole button disappears.",
  "深色模式下登录按钮的文字和背景都写死成 `#111`，深色下整个按钮都看不见。改成跟着主题走的颜色，浅色、深色都截图核对过了，两张图在 PR 里。之前那两处改动也保留着，一起在 `fix/login-button`。":
    "The login button's text and background were both fixed at `#111`, so in dark mode the whole button vanished. They now follow the theme; checked in light and dark screenshots, both in the PR. The two earlier changes are kept too, all on `fix/login-button`.",
  "查看最近的讨论": "Reading recent history", "搜索 登录 按钮": "Searching for the login button", "截图 登录页 375px": "Screenshot of /login at 375px",
  "截图 登录页 深色": "Screenshot of /login in dark", "截图 浅色 / 深色": "Screenshots in light / dark", "搜索 #111": "Searching for #111",
  "运行 pnpm test login": "Running pnpm test login", "运行 pnpm test": "Running pnpm test", "运行 codemod": "Running the codemod", "运行 pnpm up react-router@8": "Running pnpm up react-router@8",
  "思考中": "Thinking", "写回复": "Writing a reply", "完成": "Done", "待你决定": "Waiting on you", "正在执行工具": "Running a tool",
  "9d2e1f0 登录页：按钮样式调整\n41c7a2b 登录页：手机上的布局": "9d2e1f0 login: button styles\n41c7a2b login: layout on phones",
  // The other chats.
  "每周依赖升级": "Weekly dependency updates", "订单导出支持 CSV": "CSV export for orders", "排查 API p99 变慢": "Why API p99 got slow", "补一下部署文档": "Write the deploy docs", "新对话": "New chat",
  "这周的依赖升级跑一下": "Run this week's dependency updates",
  "其余 23 个包都升好了，测试通过。只剩 React Router 8：它改了 loader 的写法，要动 14 个路由文件。这周要一起升吗？":
    "The other 23 packages are updated and the tests pass. Only React Router 8 is left: it changes how loaders are written, touching 14 route files. Update it this week too?",
  "一起升吧，路由文件你直接改": "Yes, go ahead and change the route files",
  "codemod 改完 14 个路由文件，全部测试通过。": "The codemod changed 14 route files; all tests pass.",
  "React Router 8 也升好了：codemod 改了 14 个路由文件，312 个测试全过。PR 在 `chore/deps-2026-w40`。": "React Router 8 is updated too: the codemod changed 14 route files and all 312 tests pass. The PR is on `chore/deps-2026-w40`.",
  "订单列表加一个导出 CSV，筛选条件要带上": "Add a CSV export to the orders list, keeping the filters",
  "做好了：导出按当前筛选条件走流式写出，10 万行大约 2.3 秒，已合进 main（`a3f9c21`）。": "Done: the export streams out with the current filters, about 2.3 s for 100,000 rows, merged into main (`a3f9c21`).",
  "昨天开始 /api/orders 的 p99 从 150ms 涨到快 2 秒了": "Since yesterday /api/orders p99 went from 150ms to almost 2 s",
  "把 station 的部署步骤写进 docs/deploy.md": "Write the station's deploy steps into docs/deploy.md",
  "写好了，按 macOS 和 Linux 分开，附了 launchd / systemd 的排错办法。": "Done, split by macOS and Linux, with troubleshooting for launchd / systemd.",
  "谢谢，文档看过了": "Thanks, I've read the docs",
  "林晓": "Lin Xiao", "陈默": "Chen Mo", "周宁": "Zhou Ning", "你": "You", "刚刚": "just now", "昨天": "Yesterday",
};

const HAN = /[㐀-鿿（）]/;

/** A string in English, where the demo knows how to say it; else as it is. */
export function english(text: string): string {
  if (!HAN.test(text)) return text;
  const whole = LINES[text] ?? WORDS[text];
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
