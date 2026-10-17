// Seeds the dev environment's station (up.sh runs it) with chats as alice: each made and written in as her device does
// it (the station's admin API over iroh, as alice's member device), each answered by the scripted agent (agent.mjs)
// playing the scene its message matches (scenes.json, written here first). Then some chats are marked read and one is
// pinned. What it made is written to <state>/seeded.json; up.sh skips seeding while that is there.
//
//   node apps/mobile-rn/scripts/devenv/seed.ts <state dir>     (ORIGIN: the dev cloud; RELAY: the iroh relay)
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Connection, loadMesh } from "../../../../station/src/mesh/native.ts";
import { ALPN, Reader, writeLine } from "../../../../station/src/mesh/serve.ts";

const STATE = process.argv[2]!;
const ORIGIN = process.env.ORIGIN!;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const DATA = join(STATE, "station/data");
const ASSETS = join(STATE, "assets");
const SCENES = join(STATE, "scenes.json");
const DONE = `${SCENES}.done`;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── alice, her device, the station ──

type Account = { sub: string; email: string; access: string };
/// One sign-in for the whole seeding (the dev cloud allows an account 16 sessions, a few sign-ins a minute).
async function alice(): Promise<Account> {
  const saved = join(STATE, "alice.json");
  if (existsSync(saved)) {
    const a = JSON.parse(readFileSync(saved, "utf8"));
    if ((await fetch(`${ORIGIN}/v1/me`, { headers: { authorization: `Bearer ${a.access}` } })).ok) return a;
  }
  const a = await (await fetch(`${ORIGIN}/__dev/account?user=alice`)).json();
  writeFileSync(saved, JSON.stringify(a));
  return a as Account;
}
async function api(who: Account, method: string, path: string, body?: unknown): Promise<any> {
  const r = await fetch(`${ORIGIN}${path}`, { method, headers: { authorization: `Bearer ${who.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}
async function readLine(stream: { read(): Promise<Buffer | null> }): Promise<any> {
  let got = Buffer.alloc(0);
  for (;;) {
    const at = got.indexOf(10);
    if (at >= 0) return JSON.parse(got.subarray(0, at).toString());
    const more = await stream.read();
    if (!more) return null;
    got = Buffer.concat([got, more]);
  }
}
let conn: Connection;
/// One request of the station's admin API, as alice: its JSON answer (an error when it is not 2xx).
async function ask(method: string, path: string, body?: Buffer | unknown): Promise<any> {
  let timer: NodeJS.Timeout | undefined;
  const late = new Promise<never>((_, reject) => (timer = setTimeout(() => reject(new Error(`${method} ${path}: no answer in 30 s`)), 30_000)));
  try {
    return await Promise.race([asking(method, path, body), late]);
  } finally {
    clearTimeout(timer);
  }
}
async function asking(method: string, path: string, body?: Buffer | unknown): Promise<any> {
  const s = await conn.openBi();
  await writeLine(s, { method, path: `/admin/api${path}`, headers: { "stillfail-lang": "zh", "content-type": "application/json" } });
  if (body !== undefined) await s.write(Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body)));
  await s.finish();
  const r = new Reader(s);
  const head = await r.line();
  const rest = (await r.rest()).toString();
  if (head.status < 200 || head.status >= 300) throw new Error(`${method} ${path}: ${head.status} ${rest}`);
  return rest ? JSON.parse(rest) : null;
}

// ── what the agent says ──

const MARKDOWN_REPLY = `## 结论

首页列表滚动掉帧的主要原因是**每一行在滚动时都重新解析了 Markdown 摘要**，和图片解码无关。改成在 core 里缓存摘要后，滚动时重建的行从 312 降到 9。

### 查到的情况

1. \`ChatRow\` 的 \`summary\` 每次渲染都调用 \`render(markdown)\`，没有 memo
2. 列表的 key 用的是下标，顶部插入一行会让下面所有行重建
3. 头像图片已经有缓存，不是瓶颈
   - 冷启动时第一屏解码约 40 ms
   - 之后全部命中内存缓存

### 改前改后

| 指标 | 改前 | 改后 |
|---|---:|---:|
| 滚动时重建的行 | 312 | 9 |
| 掉帧（每 10 秒） | 47 | 3 |
| Markdown 解析次数 | 1,284 | 36 |
| 内存峰值 | 212 MB | 198 MB |

### 改动

\`\`\`ts
// client/core-ts/src/views/chats.ts
const summaries = new Map<string, Summary>();
export function summaryOf(entry: Entry): Summary {
  const hit = summaries.get(entry.id);
  if (hit && hit.rev === entry.rev) return hit;
  const made = { rev: entry.rev, text: plain(entry.markdown, 140) };
  summaries.set(entry.id, made);
  return made;
}
\`\`\`

列表的 key 改成 chat 的 \`id\`：

\`\`\`kotlin
items(chats, key = { it.id }) { chat -> ChatRow(chat) }
\`\`\`

> 注意：旧版 station 不带 \`rev\` 字段，这时按 \`ts\` 判断，兼容性见 [docs/core-ts.md](https://github.com/AFK-surf/still.fail/blob/main/docs/core-ts.md)。

验证用的是 \`node test/perf/chat.mjs --compare\`，三次结果都在上表范围内。PR：[#612](https://github.com/AFK-surf/still.fail/pull/612)`;

const MEMORY_REPLY = `## station 内存占用

跑了 24 小时，主进程 footprint 稳定在 **180 MB 左右**，没有持续上涨，不是泄漏。

| 部分 | 大小 | 说明 |
|---|---:|---|
| V8 堆（主线程） | 64 MB | 会话和订阅的状态 |
| 读取 worker | 3 × 22 MB | 每个 worker 一份 transcript 缓存 |
| \`MALLOC_LARGE\` | 31 MB | sqlite 的页缓存 |
| 其他 | 19 MB | 原生模块、代码 |

峰值出现在凌晨的归档：一次读了 40 个会话的 transcript。可以做的：

- 归档改成一次一个会话，峰值能降到 120 MB 以下
- 读取 worker 空闲 10 分钟后退出

\`\`\`sh
footprint -f bytes --noCategories -p $(pgrep -f "stillfail-station run")
\`\`\`

要我把这两条改了吗？`;

const NOTES_REPLY = `Here are the release notes for October, grouped by what people will notice:

### New
- **Files** — browse and preview the station's folders from any device
- **Vault** — keep API keys on the station; agents use them without seeing them
- A third runtime, **DeepSeek Harness**, next to Claude Code and Codex

### Improved
- The chat list opens about twice as fast on Android
- Decisions show who is asked to decide
- Reconnecting after sleep no longer reloads the whole chat

### Fixed
- Notifications on Android 15 now play their sound
- Long code blocks scroll horizontally instead of wrapping

Full list: [changelog](https://still.fail/changelog). Let me know if you want a shorter version for Slack.`;

const RELEASE_ASK = `测试版 **0.1.2450** 准备好了：

- 安卓：首页列表滚动优化（#612）、通知声音修复（#605）
- station：归档时的内存峰值降到 120 MB 以下（#608）
- CI：main 最近 30 次运行全绿，\`test-beam\` 的偶发失败已修

发到测试频道后，大约 40 个设备会在 1 小时内收到更新。要现在发吗？`;

/// The scenes the agent plays, each a chat: its title, what alice writes, the agent's steps; `read` marks it read after.
type Chat = { title: string; messages: { text: string; steps: any[]; attach?: string }[]; read?: boolean; pin?: boolean; busy?: boolean };
function chats(): Chat[] {
  const photo = join(ASSETS, "photo.jpg");
  const wide = join(ASSETS, "crop-after.png");
  const done = (text: string, why: string) => ({ post: { text, kind: "all_done", done: why } });
  return [
    {
      title: "Rename the drive's root folders",
      read: true,
      messages: [{ text: "Can the drive show the root folders by their own names instead of full paths?", steps: [
        { tool: "Grep", input: { pattern: "rootName", path: "station/src/drive" }, output: "station/src/drive/drive.ts:231:  const rootName = (path: string) => basename(path) || path;" },
        done("Yes: the drive already names each root by its last path segment (`rootName` in `station/src/drive/drive.ts`). Full paths only show when two roots share a name. Nothing to change.", "Answered: the drive already names roots by their last segment (rootName in station/src/drive/drive.ts), so nothing needs changing"),
      ] }],
    },
    {
      title: "安卓通知不响",
      read: true,
      messages: [{ text: "安卓 15 上收到通知但是没有声音，截图里是通知设置", attach: photo, steps: [
        { think: "看截图：通知渠道是「静默」。可能是建渠道时 importance 设成了 LOW。" },
        { tool: "Grep", input: { pattern: "NotificationChannel\\(", path: "apps/android" }, output: "apps/android/app/src/main/kotlin/fail/still/android/Notify.kt:48:        NotificationChannel(CHATS, name, NotificationManager.IMPORTANCE_LOW)" },
        { tool: "Read", input: { file_path: "apps/android/app/src/main/kotlin/fail/still/android/Notify.kt" }, output: "     44\t    fun channels(context: Context) {\n     45\t        val m = context.getSystemService(NotificationManager::class.java)\n     46\t        m.createNotificationChannel(\n     47\t            // the chats' channel\n     48\t        NotificationChannel(CHATS, name, NotificationManager.IMPORTANCE_LOW)" },
        done("找到原因了：chat 的通知渠道建成了 `IMPORTANCE_LOW`，安卓 15 对这个级别一律静音。\n\n已经改成 `IMPORTANCE_DEFAULT`，并给老用户换了一个新的渠道 id（渠道建好后 importance 改不了）。PR：[#605](https://github.com/AFK-surf/still.fail/pull/605)", "修复已合进 main（PR #605），在安卓 15 的模拟器上确认通知有声音"),
      ] }],
    },
    {
      title: "Write release notes for October",
      read: true,
      messages: [{ text: "Write release notes for October from the changelog", steps: [
        { tool: "Bash", input: { command: "node scripts/changelog.ts --since 2026-10-01 --json | jq length", description: "Count October changelog entries" }, output: "57" },
        done(NOTES_REPLY, "Release notes posted in this chat, written from the 57 October changelog entries"),
      ] }],
    },
    {
      title: "station 内存占用分析",
      read: true,
      messages: [{ text: "studio 上的 station 内存好像一直在涨，帮我看看是不是泄漏", steps: [
        { tool: "Bash", input: { command: "footprint -f bytes --noCategories -p $(pgrep -f 'stillfail-station run')", description: "Measure the station's memory footprint" }, output: "stillfail-station [41822]: 64-bit    Footprint: 188743680 B (16384 bytes per page)\n  phys_footprint: 188743680\n  phys_footprint_peak: 251658240" },
        { tool: "Bash", input: { command: "grep 'memory: now' ~/.stillfail/logs/station.log | tail -5", description: "Read the memory lines of the log" }, output: "10-17 22:10 memory: now 182M heap 61M external 9M readers 22M/21M/23M\n10-17 22:20 memory: now 179M heap 60M external 9M readers 22M/21M/22M\n10-18 03:00 memory: now 246M heap 88M external 14M readers 41M/39M/40M\n10-18 03:10 memory: now 185M heap 63M external 9M readers 22M/22M/22M\n10-18 03:20 memory: now 181M heap 61M external 9M readers 22M/21M/22M" },
        { post: { text: MEMORY_REPLY, kind: "need_human", need: "问要不要改归档和 worker" } },
      ] }],
    },
    {
      title: "预览服务：设置页改版",
      messages: [{ text: "把设置页改版的预览起一个服务给我看", steps: [
        { tool: "Bash", input: { command: "pnpm exec vite build --config web/vite.config.ts --outDir /tmp/settings-preview", description: "Build the web app for the preview" }, output: "vite v7.1.3 building for production...\n✓ 1843 modules transformed.\n✓ built in 9.42s" },
        { job: { name: "设置页预览", command: `exec python3 -m http.server 8937 --bind 127.0.0.1 --directory ${join(STATE, "assets/site")}`, port: 8937 } },
        done("预览起好了，在上面的服务里打开。改动：\n\n- 设置首页按 **账号 / Station / 外观 / 关于** 分组\n- 每一组的说明文字收短成一行\n- 深色模式下分隔线改成 `vars.line`", "预览服务已起在 8937 端口（上面的服务卡片），改动列在这条消息里"),
      ] }],
    },
    {
      title: "盯 main 的 CI",
      messages: [{ text: "盯一下 main 的 CI，挂了告诉我", steps: [
        { job: { name: "CI watch", command: `: devenv ${STATE}/; ` + "i=0; while true; do i=$((i+1)); echo \"$(date '+%H:%M:%S') run 18412 in progress ($i)\"; sleep 30; done", watch: true } },
        { post: { text: "在盯 main 最新一轮（run 18412），任一项失败会立刻告诉你。" } },
        { state: { kind: "waiting", for: "main 的 CI run 18412", seconds: 1800 } },
      ] }],
    },
    {
      title: "Profile 页的头像裁剪",
      messages: [{ text: "Profile 页的头像裁剪框太小了，改大一点", steps: [
        { tool: "Edit", input: { file_path: "apps/android/settings/src/main/kotlin/fail/still/android/screens/Profiles.kt", old_string: "size(64.dp)", new_string: "size(88.dp)" }, output: "The file has been updated." },
        { tool: "Bash", input: { command: "./gradlew :settings:compileDebugKotlin --console=plain -q", description: "Compile the settings module" }, output: "" },
        { post: { text: "改好了，裁剪框从 64 dp 改成 88 dp，下面是改后的样子（Pixel 7，浅色）：\n\n![](crop-after.png)\n\n原图也附上了，可以对比一下边缘。", files: [wide, photo], kind: "all_done", done: "裁剪框改成 88 dp，:settings 编译通过，改后截图发在这条消息里" } },
      ] }],
    },
    {
      title: "迁移旧的 Slack 连接",
      messages: [{ text: "把 bft 上旧的 Slack 连接迁到新的 station", steps: [
        { tool: "Bash", input: { command: "stillfail-station connects --data ~/.stillfail --json | jq '.[].slack.botName'", description: "List the Slack connects" }, output: "\"ember-bot\"\n\"ops-bot\"" },
        { post: { text: "两个连接里 `ops-bot` 的 token 已经过期，迁移需要新的 bot token（Slack 应用设置 → OAuth & Permissions）。请把它填在下面。", card: { type: "text", placeholder: "xoxb-…", assignee: "alice@example.test" }, kind: "need_human", need: "需要 ops-bot 的新 token" } },
      ] }],
    },
    {
      title: "修 CI 里 test-beam 偶发失败",
      busy: true,
      messages: [{ text: "test-beam 最近又偶发失败了，查一下根因", steps: [
        { tool: "Bash", input: { command: "gh run list -R AFK-surf/still.fail --branch main --limit 40 --json conclusion,databaseId", description: "List the last 40 runs on main" }, output: "[{\"conclusion\":\"success\",\"databaseId\":18411},{\"conclusion\":\"failure\",\"databaseId\":18398}]" },
        { post: { text: "最近 40 次里 test-beam 挂了 3 次，都是 `presence.test.ts` 等心跳超时。在本地用 `SIM_SEED` 重放这三次的种子。" } },
        { hold: { tool: "Bash", input: { command: "for s in 4127 9021 33310; do SIM_SEED=$s node --test test/presence.test.ts; done", description: "Replay the three failing seeds" } } },
      ] }],
    },
    {
      title: "station 内存 · 归档改成逐个",
      busy: true,
      messages: [{ text: "按你说的把归档改成一次一个会话", steps: [
        { think: "归档在 sessions/archive.ts 里一次 Promise.all 所有会话，改成顺序处理。" },
        { tool: "Read", input: { file_path: "station/src/sessions/archive.ts" }, output: "    88\t  await Promise.all(due.map((s) => pack(s)));" },
        { tool: "Edit", input: { file_path: "station/src/sessions/archive.ts", old_string: "await Promise.all(due.map((s) => pack(s)));", new_string: "for (const s of due) await pack(s);" }, output: "The file has been updated." },
        { hold: { tool: "Bash", input: { command: "cd station && node --test test/archive.test.ts", description: "Run the archive tests" } } },
      ] }],
    },
    {
      title: "首页列表滚动卡顿排查",
      read: true,
      pin: true,
      messages: [
        { text: "安卓首页 chat 列表滚动的时候明显卡，查一下原因", steps: [
          { think: "先量：滚动时哪些行重建了、Markdown 解析了几次。" },
          { tool: "Grep", input: { pattern: "render\\(", path: "client/core-ts/src/views" }, output: "client/core-ts/src/views/chats.ts:142:    summary: render(entry.markdown)," },
          { tool: "Read", input: { file_path: "client/core-ts/src/views/chats.ts" }, output: "   138\t  return rows.map((entry, i) => ({\n   139\t    key: i,\n   140\t    id: entry.id,\n   141\t    title: entry.title,\n   142\t    summary: render(entry.markdown)," },
          { tool: "Bash", input: { command: "node test/perf/chat.mjs --url http://127.0.0.1:8930 --scroll 10", description: "Measure scrolling the chat list" }, output: "replaced 312  dropped 47  markdown 1284  peak 212MB" },
          { post: { text: "量到了：滚动 10 秒重建了 312 行、解析了 1,284 次 Markdown。在查是哪一步触发的。" } },
          { tool: "Edit", input: { file_path: "client/core-ts/src/views/chats.ts", old_string: "summary: render(entry.markdown),", new_string: "summary: summaryOf(entry)," }, output: "The file has been updated." },
          { tool: "Bash", input: { command: "node test/perf/chat.mjs --url http://127.0.0.1:8930 --scroll 10", description: "Measure again after the change" }, output: "replaced 9  dropped 3  markdown 36  peak 198MB" },
          done(MARKDOWN_REPLY, "原因找到并修好：PR #612 已合进 main，改前改后三次 perf 测试的数据在表里"),
        ] },
        { text: "旧 station 不带 rev 的时候会不会显示旧摘要？", steps: [
          { tool: "Grep", input: { pattern: "rev \\?\\?", path: "client/core-ts/src/views/chats.ts" }, output: "client/core-ts/src/views/chats.ts:151:  const rev = entry.rev ?? entry.ts;" },
          done("不会。没有 `rev` 时用消息的 `ts` 代替：消息被编辑时 station 会换 `ts`，缓存跟着失效。\n\n测试里加了一条旧 station 的情形（`views.test.ts` 的 `summary without rev`），已经跑过。", "回答了问题：没有 rev 时按 ts 判断，views.test.ts 加了旧 station 的用例并跑过"),
        ] },
      ],
    },
    {
      title: "发布 0.1.2450 测试版",
      messages: [{ text: "准备发测试版", steps: [
        { tool: "Bash", input: { command: "gh run list -R AFK-surf/still.fail --branch main --limit 30 --json conclusion | jq -r '.[].conclusion' | sort | uniq -c", description: "Count the last 30 runs on main" }, output: "  30 success" },
        { tool: "Bash", input: { command: "node scripts/changelog.ts --since v0.1.2441", description: "List the changes since the last beta" }, output: "修复：安卓 15 的通知没有声音\n首页列表滚动更流畅\nstation 归档时占用的内存更少" },
        { post: { text: RELEASE_ASK, card: { type: "options", options: [{ label: "现在发布", detail: "发到测试频道，约 40 台设备", recommended: true }, { label: "等明天早上再发", detail: "明早 9 点自动发" }, { label: "先不发", action: "close" }], assignee: "alice@example.test" }, kind: "need_human", need: "要不要现在发测试版" } },
      ] }],
    },
  ];
}

async function main() {
  mkdirSync(ASSETS, { recursive: true });
  const all = chats();
  // The scenes, by what each message says.
  const scenes = all.flatMap((c) => c.messages.map((m) => ({ match: m.text, steps: m.steps })));
  writeFileSync(SCENES, JSON.stringify(scenes, null, 1));
  writeFileSync(DONE, "");
  writeFileSync(`${SCENES}.errors`, "");

  const who = await alice();
  const me = await api(who, "GET", "/v1/me");
  const dev = me.workspaces.find((w: any) => w.name === "Dev").id as string;
  const station = JSON.parse(readFileSync(join(DATA, "mesh/cloud.json"), "utf8")).station as string;
  process.env.STILLFAIL_MESH_NATIVE ??= execFileSync(process.execPath, [join(import.meta.dirname, "../../../../scripts/native.ts"), "file", "mesh"], { encoding: "utf8" }).trim();
  const device = await loadMesh().bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await device.online();
  const credential = (await api(who, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
  conn = await device.connect({ id: station, relays: [RELAY] }, ALPN);
  const first = await conn.openBi();
  await first.write(Buffer.from(JSON.stringify({ credential, protocol: 2 }) + "\n"));
  const hello = await readLine(first);
  if (!hello?.ok) throw new Error(`not admitted: ${JSON.stringify(hello)}`);

  const made: { title: string; key: string; thread: number }[] = [];
  for (const chat of all) {
    const m = await ask("POST", "/sessions", { runtime: "claude", profile: "claude", model: "claude-opus-4-7", title: chat.title, clientKey: `seed-${randomBytes(4).toString("hex")}` });
    const key = m.key as string;
    const thread = Number(m.thread.id ?? m.thread.thread?.id);
    for (const message of chat.messages) {
      const attachments: unknown[] = [];
      if (message.attach) {
        const up = await ask("POST", `/uploads?name=${encodeURIComponent("notification-settings.jpg")}`, readFileSync(message.attach));
        attachments.push({ path: up.path, name: "notification-settings.jpg", size: up.size, width: 960, height: 640 });
      }
      const before = readFileSync(DONE, "utf8").split("\n").length;
      await ask("POST", `/threads/${thread}/messages`, { text: message.text, attachments, client: "devenv seed" });
      // The turn's end (agent.mjs writes a line), or for a chat left busy, its call running.
      if (chat.busy) await sleep(3000);
      else for (let i = 0; readFileSync(DONE, "utf8").split("\n").length <= before; i++) {
        if (i > 300) throw new Error(`no answer in “${chat.title}”`);
        await sleep(200);
      }
    }
    if (chat.read) await ask("PUT", `/threads/${thread}/read`, { n: 1_000_000_000 });
    if (chat.pin) await ask("PUT", `/sessions/${encodeURIComponent(key)}/pin`, {});
    made.push({ title: chat.title, key, thread });
    console.log(`seeded “${chat.title}” (thread ${thread})`);
    await sleep(1200);
  }
  const failed = existsSync(`${SCENES}.errors`) ? readFileSync(`${SCENES}.errors`, "utf8").trim() : "";
  if (failed !== "") throw new Error(`the agent's calls failed:\n${failed}`);
  writeFileSync(join(STATE, "seeded.json"), JSON.stringify(made, null, 1));
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
