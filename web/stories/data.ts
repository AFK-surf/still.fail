// What the stories show that the site's demo has none of (src/demo/mount.tsx extendDemo): a novel and a note to read,
// a clip and a picture in a folder, the changelog's news. Made up here, the same every time.
import type { DriveEntry, DriveKind } from "../src/core/shapes.ts";
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
  ],
};
/** None to add: the viewer manages another workspace, but its stations are all here already. */
/** What a station from before several workspaces answers, in the core's words. */
export const JOIN_REFUSED = "这台 station 还不能在多个 workspace 里，先更新它";

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
