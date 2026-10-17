// What the stories show that the site's demo has none of (src/demo/mount.tsx extendDemo): a novel and a note to read,
// a clip and a picture in a folder, the changelog's news. Made up here, the same every time.
import type { DriveEntry, DriveKind, HistoryItem, HistoryStep, HistoryView } from "../src/core/shapes.ts";
import { markdown } from "../../client/core-ts/src/markdown.ts";
import clipUrl from "./assets/story-clip.mp4?url";
import pictureUrl from "./assets/story-picture.png?url";

const SENTENCES = [
  "夜色压在城墙上，风从北边的山口吹过来，带着一股潮湿的土腥味。",
  "他把灯往前推了推，火苗晃了两下，照出桌上那封还没拆开的信。",
  "街上已经没有人了，只有更夫的梆子声隔着几条巷子传过来，一下，又一下。",
  "她没有回头，只是把手里的伞握得更紧了些，好像那是她在这座城里唯一能抓住的东西。",
  "“你还记得那年冬天吗？”他问。屋里很静，炉子里的炭偶尔噼啪响一声。",
];
const TITLES = ["雨夜", "旧信", "城门", "灯下", "北风", "故人", "长街", "渡口"];

/** A plain-text novel, hard-wrapped at 36 characters as an old TXT is: 40 chapters. */
export const NOVEL = Array.from({ length: 40 }, (_, c) => {
  const paras = Array.from({ length: 14 }, (_, p) => {
    let para = "";
    for (let k = 0; k < 3 + ((c * 7 + p) % 4); k++) para += SENTENCES[(c + p + k) % SENTENCES.length];
    return "　　" + (para.match(/.{1,36}/gu) ?? []).join("\n");
  });
  return `第${c + 1}章　${TITLES[(c + 1) % TITLES.length]}\n\n${paras.join("\n\n")}\n\n`;
}).join("");

/** A note in Markdown with each kind of block: headings, a list, code, a table, a quote. */
export const NOTE = `# orders 慢查询排查

上周三开始，\`GET /api/orders\` 的 p99 从 **180ms** 涨到了 **2.4s**。下面是排查过程和结论。

## 现象

- 只有带 \`status\` 筛选的请求变慢
- 高峰期（10:00–11:00）最明显
- 数据库 CPU 没有明显变化

## 原因

\`orders\` 表缺少 \`(user_id, created_at)\` 联合索引，筛选时走了全表扫描：

\`\`\`sql
EXPLAIN SELECT * FROM orders
WHERE user_id = 42 AND status = 'paid'
ORDER BY created_at DESC LIMIT 20;
\`\`\`

| 指标 | 修复前 | 修复后 |
|---|---|---|
| p50 | 95ms | 31ms |
| p99 | 2.4s | 140ms |

> 结论：加索引后恢复正常，已经在生产上观察了 24 小时。

### 后续

1. 给慢查询加告警
2. 每周看一次 \`pg_stat_statements\`
`;

const bytes = (text: string) => new TextEncoder().encode(text);
const NOVEL_BYTES = bytes(NOVEL);
const NOTE_BYTES = bytes(NOTE);
const MTIME = Date.UTC(2026, 9, 15, 8);

const entry = (name: string, kind: DriveKind, size: number, type: string): DriveEntry =>
  ({ name, dir: false, size, mtime: MTIME, type, kind, sizeText: "", timeText: "10/15" });

/** The folder the stories' files are in, as the drive lists it. */
export const AT = { station: "local", root: "/Users/lin/Downloads" } as const;
export const novel = entry("长夜行.txt", "text", NOVEL_BYTES.length, "text/plain");
export const note = entry("orders-慢查询.md", "markdown", NOTE_BYTES.length, "text/markdown");
const clipSize = 108045;
export const clips = ["发版录屏 1014.mp4", "发版录屏 1015.mp4", "发版录屏 1016.mp4", "周会 1013.mp4"].map((n) => entry(n, "video", clipSize, "video/mp4"));
export const picture = entry("login-375.png", "image", 19013, "image/png");
/** A file no viewer shows (its bytes are the picture's: not text). */
export const apk = entry("still.fail-beta-0.1.3021.apk", "other", 31_457_280, "application/vnd.android.package-archive");
export const folder: DriveEntry[] = [novel, note, ...clips, picture];

const fetched = new Map<string, Promise<Uint8Array>>();
const fetchBytes = (url: string) => {
  let got = fetched.get(url);
  if (!got) { got = fetch(url).then(async (r) => new Uint8Array(await r.arrayBuffer())); fetched.set(url, got); }
  return got;
};
const base64 = (part: Uint8Array) => {
  let bin = "";
  for (let i = 0; i < part.length; i += 8192) bin += String.fromCharCode(...part.subarray(i, i + 8192));
  return btoa(bin);
};

/** A file's bytes as the station reads them (`drive.read`: a part from `offset`, `length` long). */
export async function readFile(path: string, offset: number, length: number): Promise<{ type: string; total: number; bytes: string }> {
  const [all, type] = path.endsWith(".txt") ? [NOVEL_BYTES, "text/plain"]
    : path.endsWith(".md") ? [NOTE_BYTES, "text/markdown"]
    : path.endsWith(".mp4") ? [await fetchBytes(clipUrl), "video/mp4"]
    : [await fetchBytes(pictureUrl), "image/png"];
  return { type, total: all.length, bytes: base64(all.subarray(offset, offset + length)) };
}

/** What the update just installed brought (the changelog's news). */
export const CHANGELOG = {
  tabs: [],
  news: { build: "0.1.2925", entries: [{ version: 2925, versionName: "0.1.2925", text: ["阅读器支持深色主题，文件页侧栏直接列出文件夹"], lines: [], note: "" }] },
};

/** What the stories' chats send (stories.tsx `files`): a picture, and files of a few kinds, on a person's message and
 * an agent's. */
export const SENT = {
  picture: { name: "login-375.png", path: "/Users/lin/Downloads/login-375.png", size: 19013, width: 480, height: 320 },
  files: [
    { name: "orders-慢查询.md", path: "/Users/lin/Downloads/orders-慢查询.md", size: NOTE_BYTES.length },
    { name: "发版录屏 1016.mp4", path: "/Users/lin/Downloads/发版录屏 1016.mp4", size: clipSize },
  ],
};

/** A file a message names, as its card reads it (file.peek): a few of its lines. */
export const PEEK = {
  kind: "text", name: "login.css.ts", path: "web/src/login.css.ts", size: 1840, mtime: MTIME,
  lines: { start: 12, at: 14, text: ["export const form = style({", "  display: \"grid\", gap: 12,", "  padding: \"0 16px\",", "  maxWidth: 360,", "});"] },
};

// ── One station in several workspaces (docs/multi-workspace.md): what the core's `joinable` and `memberships` say ──

/** The stations of the viewer's other workspaces that could be added to this one, as the core lists them. */
export const JOINABLE = {
  offered: true,
  loading: false,
  items: [
    { station: "lab/mini1", id: "mini1", name: "Mini1", icon: "glyph:dice-1", workspace: "lab", workspaceName: "Lab", online: true, line: "Lab · 在线" },
    { station: "lab/gpu", id: "gpu", name: "GPU 主机", emoji: "🔥", workspace: "lab", workspaceName: "Lab", online: false, line: "Lab · 离线" },
    { station: "home/nas", id: "nas", name: "NAS", workspace: "home", workspaceName: "家里", online: true, line: "家里 · 在线" },
    // Its home in security mode, this workspace not: shown, not to be picked.
    { station: "safe/vault", id: "vault", name: "Vault", workspace: "safe", workspaceName: "保险库", online: true, line: "保险库 已开启安全模式，需在此 workspace 也开启安全模式后才能添加", needsLock: true },
  ],
};
/** None to add: the viewer manages another workspace, but its stations are all here already. */
/** What a station from before several workspaces answers, in the core's words. */
export const JOIN_REFUSED = "此 station 尚不支持加入多个 workspace，请先更新";

/** The demo's station in its home workspace (Acme) and in Lab, which it joined. */
export const MEMBERSHIPS = {
  manages: true,
  loading: false,
  canJoin: true,
  workspaces: [
    { workspace: "demo", name: "Acme", stationName: "Studio", home: true, here: true, line: "主 workspace" },
    { workspace: "lab", name: "Lab", stationName: "Studio", home: false, here: false, line: "加入的 workspace" },
  ],
};

// ── An agent's execution history in turns (History.tsx): a person's message answered and left to them, a reminder
// answered while it waits on work it started, and a sub-agent's end while it still waits. Its times as the core says them.

const call = (name: string, hint: string, meta: string): HistoryStep =>
  ({ name, hint, meta, failed: false, call: JSON.stringify({ hint }), result: "ok", entries: [], brief: false });
const posted = (text: string, ends?: string): HistoryItem["body"] =>
  ({ kind: "post", content: { text, md: markdown(text), place: { name: "看看我的 screencam 的 Windows 版本", surface: "stillfail" }, block: false, failed: false, ...(ends ? { ends } : {}) } });
const own = (text: string): HistoryItem["body"] => ({ kind: "text", content: { text, md: markdown(text), subagent: false } });
const WAITED_AT = Date.parse("2026-10-16T08:27:00Z");
const WAITING_SINCE = Date.now() - 23_000;
const HISTORY_ITEMS: { body: HistoryItem["body"]; turn?: HistoryItem["turn"] }[] = [
  { turn: { time: "16:12", text: "5 步 · 发出 1 条" }, body: { kind: "received", content: { tasks: [], messages: [{ key: "m1", from: { name: "林晓", bound: false }, text: "看看我的 screencam 的 Windows 版本，我感觉某些 UI 还是粗糙" }] } } },
  { body: { kind: "group", content: { summary: "读取 4 个文件 · 共 5 项", title: "读取 4 个文件、运行 1 条命令", failures: 0, pending: 0, rows: [
    { kind: "step", content: call("Read", "src/ui/Toolbar.tsx", "0.2 秒") }, { kind: "step", content: call("Read", "src/ui/Countdown.tsx", "0.1 秒") },
    { kind: "step", content: call("Read", "src/ui/Tray.tsx", "0.1 秒") }, { kind: "step", content: call("Read", "src/ui/Export.tsx", "0.1 秒") },
    { kind: "step", content: call("Bash", "pnpm shot --platform win", "12 秒") },
  ] } } },
  { body: posted("看了一圈，有三处确实粗糙：\n\n- 工具栏图标在 125% 缩放下发虚；\n- 倒计时的数字会跳宽度；\n- 托盘菜单还是系统默认样式。\n\n先改哪个？", "human") },
  { turn: { time: "16:29", text: "3 步 · 发出 1 条" }, body: { kind: "received", content: { note: "Your turn ended without a state. If you need a clarification, visibly ask for it; need alone is only a status summary. Cards are optional. Do not reopen a decision the user already made.", tasks: [], messages: [] } } },
  { body: { kind: "group", content: { summary: "SendMessage · 共 3 项", title: "其他 3 项", failures: 0, pending: 0, rows: [
    { kind: "step", content: call("TaskOutput", "摄像头 agent", "0.4 秒") }, { kind: "step", content: call("SendMessage", "摄像头 agent", "0.8 秒") },
    { kind: "step", content: call("SendMessage", "导出 agent", "0.9 秒") },
  ] } } },
  { body: posted("中途会话重启了一次，两路的工作都已提交保存，没丢，现在已经让它们接着做。\n\n**摄像头 + 打包**（4 个提交，基本做完，正在补跑测试）：\n\n- 原生端新增摄像头 H.264 写入器和 DirectShow 采集图；\n- 摄像头录制改用共享的 QPC 时钟，跟录屏时间轴对齐；\n- 安装包里不再带 ffmpeg。\n\n**导出**（还在做）：剩下 GIF 和混音两项。") },
  { body: { kind: "mark", content: { text: "去 ffmpeg 两路收尾（重启后续跑） · 等待了 1m 54s / 1h", wait: { since: WAITED_AT, until: WAITED_AT + 114_000, seconds: 3600, what: "去 ffmpeg 两路收尾（重启后续跑）" }, ends: "waiting" } } },
  { body: own("The session restarted partway through, but both parts had already committed their work, so nothing was lost and both are running again.") },
  { turn: { time: "16:30", text: "未发消息" }, body: { kind: "received", content: { tasks: [{ text: "任务已退出（退出码 1）：shot-win", agent: false, failed: true, result: "error: no display", md: markdown("```\nerror: no display\n```") }], messages: [
    { key: "m2", from: { name: "ci-time-watch", bound: false }, text: "OVER BUDGET: run 39026861305 (attempt 1, android, add-station-sheet-pinned 9791b9da) took 301 s of 240 s\nhttps://github.com/AFK-surf/still.fail/actions/runs/39026861305\n\njobs (start → seconds):\n  +   0 s    13 s  plan\n  +  16 s   285 s  check-android\n  +  16 s    26 s  check-linux\n  +  16 s    88 s  check-browser (stories 1/2)\n  +  16 s   152 s  check-browser (motion)", notice: "job" },
  ] } } },
  { turn: { time: "16:31", text: "未发消息" }, body: { kind: "received", content: { tasks: [{ text: "子 agent 完成：Camera recording without ffmpeg", agent: true, failed: false, result: "Waiting for the NativeEngine results before sending the final report.", md: markdown("Waiting for the NativeEngine results before sending the final report.") }], messages: [] } } },
  { body: { kind: "mark", content: { text: "去 ffmpeg 两路收尾 · 等待中，最长 1h", wait: { since: WAITING_SINCE, seconds: 3600, what: "去 ffmpeg 两路收尾" }, ends: "waiting" } } },
  { body: own("Both parts of the ffmpeg removal are still finishing. The camera part is waiting on its last test run before reporting, and the export part is working through its remaining items.") },
];
export const HISTORY: HistoryView = {
  items: HISTORY_ITEMS.map(({ body, turn }, n) => ({ key: `e${n}`, entries: [n, n], body, ...(turn ? { turn } : {}) })),
  live: [], edge: "已到会话开头", empty: false, loaded: true,
};
