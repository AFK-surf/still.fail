// A workspace at the size of a real one, for what the core sends of it to be measured (topic-bytes.test.ts): the
// owner's workspace as his phone reported it, 2026-11-10. Five stations (four up, one down), whose `stations` came to
// 463,533 bytes: each station's models 295,504 in all (the accounts that run them 252,287), its overview 153,336 (its
// profiles 97,199, their checks 23,601, its automatic decisions 28,262). Eight profiles a station bring those within a
// little of the phone's (topic-bytes.test.ts prints the two side by side), over the account kinds people have:
// Claude's and ChatGPT's subscriptions with their allowances and a done check, Devin, DeepSeek, and in turn
// OpenRouter, an Anthropic key, OpenCode Go, SuperGrok, Cursor. With them connects, Slack apps, automatic decisions
// with a policy, the machine's own logins and a host reading; some 400 chats across the stations with their titles,
// last lines and people; one chat of 300 messages of every length (six pages: it opens on the last, `PAGE`), another
// of four weeks held whole on the device (`OUTLINED`); a week of usage, the jobs at work, the archive; and what the
// pages of one thing read (`more`, `records`): the account's workspaces, the lock and the vault, a drive's folder, a
// job's log, the chat's letters, screens, the cards of what messages name. Every family of
// fields is filled as a station fills it, none made larger than a station makes it. Made of the test's clock and
// indexes alone: the same every run.
import { workerData } from "node:worker_threads";
import { activity } from "../src/history.ts";
import { PENDING_MOST, type Pending } from "../src/lock-pending.ts";
import type { Topic } from "../src/protocol.ts";
import { PAGE } from "../src/station/channel-kinds.ts";
import { localDay } from "../src/views/usage.ts";
import { hostOf, link, overview, rows, sessions, threads, workspace } from "./views-rig.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The workspace's size: k times each of what it has (its chats a station, the messages of the chat opened and of the
/// chat held whole, the profiles a station, its people, its stations, as `Size` says), 1 each by default: the workspace
/// as above, byte for byte. A size other than 1 is given only to a worker thread of its own (topic-work.test.ts), as its
/// `workerData.realSize`: the module's exports are made of it as it loads.
export type Size = { chats: number; messages: number; profiles: number; people: number; stations: number };
const asked = (workerData as { realSize?: Partial<Size> } | null)?.realSize ?? {};
const knob = (v: number | undefined): number => (v !== undefined && Number.isInteger(v) && v >= 1 ? v : 1);
export const SIZE: Size = { chats: knob(asked.chats), messages: knob(asked.messages), profiles: knob(asked.profiles), people: knob(asked.people), stations: knob(asked.stations) };

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/// The workspace's stations: the last one down (its overview from before kept, its chats out of the lists).
const STATIONS_BASE = [
  { id: "maple", name: "Maple", host: "maple", cpu: "Apple M4 Max", cpus: 16, memGb: 128, emoji: "🍁" },
  { id: "willow", name: "Willow", host: "willow-mini", cpu: "Apple M4 Pro", cpus: 14, memGb: 64, emoji: "🌳" },
  { id: "studio", name: "Studio", host: "studio", cpu: "Apple M3 Ultra", cpus: 28, memGb: 192, emoji: "🎛️" },
  { id: "cedar", name: "Cedar", host: "CEDAR-WIN", cpu: "Intel Core Ultra 9 285K", cpus: 24, memGb: 64, emoji: null },
  { id: "ash", name: "Ash", host: "ash-old-mbp", cpu: "Apple M1 Pro", cpus: 10, memGb: 32, emoji: null },
] as const;
type StationOf = { id: string; name: string; host: string; cpu: string; cpus: number; memGb: number; emoji: string | null };
const copyOf = (s: StationOf, j: number): StationOf => (j === 0 ? s : { ...s, id: `${s.id}${j + 1}`, name: `${s.name} ${j + 1}`, host: `${s.host}-${j + 1}` });
/// (the four up ones k times, then the down one k times: the down ones last)
export const STATIONS: readonly StationOf[] = [
  ...Array.from({ length: SIZE.stations }, (_, j) => STATIONS_BASE.slice(0, 4).map((s) => copyOf(s, j))).flat(),
  ...Array.from({ length: SIZE.stations }, (_, j) => copyOf(STATIONS_BASE[4], j)),
];
/// How many of them are up: the first ones.
const UP_COUNT = 4 * SIZE.stations;
export const UP = STATIONS.slice(0, UP_COUNT).map((s) => `ws/${s.id}`);
export const DOWN = `ws/${STATIONS[UP_COUNT]!.id}`;
export const address = (i: number) => `ws/${STATIONS[i]!.id}`;

/// The chat of 300 messages: its station, its thread, its two agents.
export const CHAT = { station: "ws/maple", thread: 1001, keys: ["k-maple-0", "k-maple-0b"] } as const;
/// A chat of each up station's sidebar: their rows, then the archive's, by station.
const ROWS_UP = 100 * SIZE.chats;
const ROWS_DOWN = 20 * SIZE.chats;
const ARCHIVED = 60 * SIZE.chats;

const pick = <T>(pool: readonly T[], i: number): T => pool[((i % pool.length) + pool.length) % pool.length]!;

// ── people ──

const PEOPLE_BASE = [
  { sub: "s1", email: "me@x.com", name: "左子健" },
  { sub: "s2", email: "lina@acme.dev", name: "Lina Park" },
  { sub: "s3", email: "wang.lei@acme.dev", name: "王磊" },
  { sub: "s4", email: "chen.yu@acme.dev", name: "陈雨" },
  { sub: "s5", email: "marco@acme.dev", name: "Marco Rossi" },
  { sub: "s6", email: "zhao.min@acme.dev", name: "赵敏" },
  { sub: "s7", email: "sam.k@acme.dev", name: "Sam Kowalski" },
  { sub: "s8", email: "liu.yang@acme.dev", name: "刘洋" },
  { sub: "s9", email: "aiko@acme.dev", name: "Aiko Tanaka" },
  { sub: "s10", email: "he.jing@acme.dev", name: "何静" },
  { sub: "s11", email: "dev.ops@acme.dev", name: "Ops Bot" },
  { sub: "s12", email: "sun.fei@acme.dev", name: "孙飞" },
] as const;
export const PEOPLE: readonly { sub: string; email: string; name: string }[] = [
  ...PEOPLE_BASE,
  ...Array.from({ length: PEOPLE_BASE.length * (SIZE.people - 1) }, (_, i) => ({ sub: `s${13 + i}`, email: `member${13 + i}@acme.dev`, name: `成员 ${13 + i}` })),
];
const SLACK_USERS = ["U04A1B2C3D4", "U04E5F6G7H8", "U05J9K0L1M2", "U05N3P4Q5R6", "U06S7T8U9V0", "U06W1X2Y3Z4"];
const SLACK_NAMES = ["lina", "marco.rossi", "aiko.t", "sam", "wanglei", "chenyu"];
const slackPicture = (i: number) => `https://avatars.slack-edge.com/2026-03-1${i % 10}/71${i}20${i}83${i}_8f3c${i}a2b9d1e4f07c6a5_192.jpg`;

const person = (i: number): J => {
  const p = pick(PEOPLE, i);
  return { id: p.email, name: p.name, email: p.email, via: "cloud" };
};
const slackPerson = (i: number): J => ({ id: `slack:c-slack-1:${pick(SLACK_USERS, i)}`, name: pick(SLACK_NAMES, i), via: "slack", picture: slackPicture(i % 6) });

// ── words ──

const TITLES = [
  "修复 Android 上聊天列表滚动掉帧",
  "把 station 的日志轮转改成按天切",
  "Slack 连接断开后不会自动重连",
  "升级 Effect 到 4.0 并跑完全部测试",
  "首页加载时骨架屏闪一下",
  "用量页按模型拆分，加周对比",
  "Windows 安装包签名失败（signtool 0x800b0109）",
  "iOS 锁屏推送不显示正文",
  "Review #5231：归档策略的默认值",
  "写本周周报：发布、事故、下周计划",
  "订单列表慢查询，explain 看一下",
  "CI 迁到自建 runner，缓存命中率",
  "整理新人 onboarding 文档",
  "新的模型选择器的交互稿",
  "Fix flaky e2e on the mac runners",
  "Investigate memory growth in the station worker",
  "Bump iroh to 0.95 and test the relays",
  "Add a retry budget to cloud sync",
  "Landing page copy for the launch",
  "Triage FB-1832: 打开图片偶尔黑屏",
  "数据看板：日活和留存的口径对齐",
  "给 drive 加拖拽上传进度",
  "Postgres 15 → 17 升级演练",
  "清理 S3 上过期的构建产物",
  "Feishu 群里 @ 机器人没有反应",
  "README 里的安装步骤过时了",
  "Profile 页面在小屏上按钮挤在一起",
  "调研：把 markdown 渲染挪到 worker",
  "Release 0.1.7020 的发布说明",
  "Refactor the composer's draft store",
  "压测 relay：1k 并发连接",
  "把 chat 的图片缩略图改成 thumbhash",
] as const;

const LINES = [
  "已经修好了：列表项的高度现在在第一次布局时就算好，不再在滚动中重新测量。我在 Pixel 8 上录了前后对比，掉帧从 23% 降到 1% 以下，PR #5244 等 CI。",
  "日志轮转改成按天切了，保留 14 天，旧的压缩成 .gz。重启 station 之后看了一下 ~/.stillfail/logs，文件名是 station-2026-11-10.log，没问题。",
  "原因是 Socket Mode 的 ping 超时后我们只关了连接没有重新打开。改成按 backoff 重连（1s 起，最多 60s），本地断网 10 分钟再恢复，3 秒内连上。",
  "Effect 4.0 的升级跑完了：类型错误 112 处都改了，测试 2,431 个全部通过。有两处 Stream API 的语义变了，我写在 PR 描述里，需要你看一下是否接受。",
  "闪烁是因为第一帧拿不到缓存的列表，骨架和真实内容之间切了一次。改成先读设备上的缓存再决定画什么，录屏里已经看不到闪了。",
  "需要你决定：按模型拆分时，同一个模型在不同 runtime 上（Claude Code 和 OpenRouter）要合并成一行还是分开显示？两种我都做了截图。",
  "签名失败是证书链缺了中间证书。我把 DigiCert 的中间证书加进了 CI 的 keychain，重新打包签名通过，signtool verify /pa 也过了。",
  "锁屏推送不显示正文是因为通知的 mutable-content 没设，扩展没被调用。修了之后在 iPhone 16 上测过，锁屏能看到消息前两行。",
  "看完了 #5231，整体没问题。两个小建议：默认天数 7 天对 Slack 的对话太短；另外 reviewed 模式下没有说明为什么没归档。已在 PR 上留言。",
  "周报草稿写好了，放在 docs/weekly/2026-W45.md：本周发了 3 个 beta、1 个正式版，一次事故（relay 证书过期 22 分钟），下周重点是 iOS 上架。",
  "慢查询的原因是 orders(created_at) 上没有和 tenant_id 组合的索引，全表扫了 1200 万行。加了组合索引后从 2.3s 降到 18ms，迁移脚本在 PR 里。",
  "自建 runner 上缓存命中率现在 87%，平均 CI 时间从 14 分钟降到 6 分 40 秒。还有 arm64 的 Android 构建没迁，等新机器到。",
  "好的",
  "在看了，大概 20 分钟。",
  "Tests pass locally and on CI. The flake was a race between the window becoming key and the first click; waiting for the named event fixed it in 200 runs.",
  "Heap snapshots show the growth is the markdown cache: entries are never evicted for archived chats. Capped it at 500 and added an LRU; RSS is flat over 6 hours now.",
  "iroh 0.95 is in. Relays reconnect fine; direct connections take ~40 ms longer to be chosen on Wi-Fi. I left a note in the PR with the numbers from three networks.",
  "需要人工确认：生产库迁移要停写大约 4 分钟，什么时候可以做？我建议周六上午 9 点。",
] as const;

const SHORT = ["好的", "收到", "在看了", "可以，按这个来", "等一下，我先跑一遍测试", "👍", "谢谢！", "这个先不改", "合吧", "看起来没问题"] as const;
const MEDIUM = [
  "我把这个问题拆成了三步：先复现，再写一个能稳定失败的测试，最后修。现在复现了，在 Pixel 8 上滑动 30 秒左右会出现，录屏在附件里。",
  "Could you check whether the beta channel is on for your phone? The fix shipped in 0.1.7018 and your logs say 0.1.7012.",
  "这里的 timeout 我改成了按 Clock 的 sleep，测试里用 TestClock 推进，不再有真实等待。顺便删掉了两个只为了等时间的 retry。",
  "这个方向可以，但请先别动 data.ts 的 schema，改了要写迁移，我们下周统一做。",
  "Done: the migration ran on staging in 3 min 41 s with writes paused; no errors, row counts match. Production is ready when you are.",
  "PR 已经开了：https://github.com/acme/app/pull/5244 ，CI 在跑，大概 12 分钟。",
] as const;
const LONG = [
  [
    "## 结论",
    "",
    "列表掉帧的根因是**每一帧都在重新测量行高**：`measure_row` 在滚动时被调用了 1,800 次/秒。",
    "",
    "### 做了什么",
    "",
    "1. 行高在第一次布局时算好并缓存，键是行的 id 和宽度；",
    "2. 宽度变化（旋转、分屏）时整表失效一次，而不是逐行；",
    "3. 头像图片解码挪到后台线程，主线程只拿结果。",
    "",
    "```kotlin",
    "val height = heights.getOrPut(row.id to width) { measure(row, width) }",
    "```",
    "",
    "### 结果",
    "",
    "| 设备 | 之前掉帧 | 之后 |",
    "| --- | --- | --- |",
    "| Pixel 8 | 23.1% | 0.6% |",
    "| Galaxy S24 | 17.4% | 0.9% |",
    "| Redmi Note 13 | 41.0% | 3.2% |",
    "",
    "录屏和 trace 在附件里。还有一个问题需要你决定：低端机上要不要把头像的圆角改成预先裁好的位图？能再省 1.5 ms/帧，但内存多 4 MB。",
  ].join("\n"),
  [
    "Here's what I found in the station worker's memory growth:",
    "",
    "- RSS grows ~38 MB/hour with 6 chats open, and never comes back down;",
    "- heap snapshots at 0 h, 2 h and 6 h show `MdCache` holding 41k entries at the end, 93% of them for archived chats;",
    "- nothing evicts them: `forget()` is only called when a chat is deleted, never when it is archived.",
    "",
    "The fix (PR #5251):",
    "",
    "```ts",
    "const cache = new Lru<string, Md>(500, (key) => kept.delete(key));",
    "data.onArchived((station, key) => cache.dropWhere((k) => k.startsWith(`${station}\\u0001${key}`)));",
    "```",
    "",
    "After it, RSS is flat at 212 MB over 6 hours with the same load. I also added a test that archives 1,000 chats and checks the cache stays at 500.",
    "",
    "One question: should the cap be per workspace or for the whole device? Per device is simpler, but a big workspace could push a small one's chats out.",
  ].join("\n"),
  [
    "迁移演练的完整记录：",
    "",
    "1. `pg_dump --format=directory -j 8` 导出 412 GB，用时 38 分钟；",
    "2. 新实例 Postgres 17，`pg_restore -j 16`，用时 1 小时 12 分钟；",
    "3. 逻辑复制追平增量，延迟稳定在 200 ms 以内；",
    "4. 切换：停写 → 等复制追平 → 改连接串 → 恢复写，**停写 3 分 41 秒**；",
    "5. 校验：每张表行数一致，抽样 10 万行逐列比对无差异。",
    "",
    "发现的问题：",
    "",
    "- `orders` 上有一个函数索引用了 `to_char`，17 里被标成了不安全，需要改成 immutable 的包装函数；",
    "- 连接池 pgbouncer 1.21 和 17 的 SCRAM 有兼容问题，升到 1.23 解决。",
    "",
    "正式迁移建议放在周六上午，预计停写 4 分钟以内。需要你确认时间，我来发公告。",
  ].join("\n"),
] as const;

/// A message's words, by its place in the chat: most short or a few lines, every fifth a page.
function words(i: number): string {
  if (i % 5 === 4) return pick(LONG, i);
  if (i % 3 === 0) return pick(SHORT, i);
  return pick(MEDIUM, i) + (i % 7 === 0 ? `\n\n${pick(LINES, i)}` : "");
}

// ── models and profiles ──

const CLAUDE_MODELS = ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5", "claude-sonnet-4-5", "claude-haiku-4-5", "claude-fable-1"];
const CODEX_MODELS = ["gpt-6-astra", "gpt-6", "gpt-6-mini", "gpt-6-codex", "gpt-5.5-codex", "gpt-5.5-pro", "gpt-5.5", "gpt-5.5-mini"];
const DEVIN_MODELS = ["swe-1.6", "swe-1.6-fast", "claude-opus-5-5", "claude-sonnet-5", "gpt-6", "gpt-6-codex"];
const DSH_MODELS = ["deepseek-v4", "deepseek-v4-1", "deepseek-v4-1-flash", "deepseek-v4-reasoner", "deepseek-v3.2"];
const ROUTER_MODELS = ["anthropic/claude-opus-5-5", "openai/gpt-6", "google/gemini-4-pro", "google/gemini-4-flash", "moonshotai/kimi-k3", "z-ai/glm-5", "qwen/qwen4-coder", "x-ai/grok-5"];
const OPENCODE_MODELS = ["kimi-k3", "glm-5", "qwen4-coder", "minimax-m3"];
const GROK_MODELS = ["grok-5", "grok-5-code"];
const CURSOR_MODELS = ["composer-2", "claude-sonnet-5", "gpt-6"];
const CLAUDE_EFFORTS = ["low", "medium", "high", "xhigh", "max"];
const CODEX_EFFORTS = ["minimal", "low", "medium", "high", "xhigh"];

const efforts = (runtime: string, models: string[], levels: string[]) => ({ [runtime]: Object.fromEntries(models.map((m) => [m, levels])) });

function check(now: number, models: string[], detail: string, patch: J = {}): J {
  return { state: "ok", detail, models, checkedAt: now - 37 * MIN, ...patch };
}

/// A window of an allowance as the station reads it: how much of it is used, when it refills.
const window = (label: string, used: number, resetsAt: number | null, scope?: string): J => ({ label, usedPercent: used, resetsAt, ...(scope ? { scope } : {}) });

function claudeQuota(now: number, i: number): J {
  return {
    state: "ok",
    plan: i % 2 === 0 ? "max_20x" : "max_5x",
    windows: [window("5 小时", (i * 17) % 90, now + (2 + (i % 3)) * HOUR + 14 * MIN), window("每周", (i * 23) % 80 + 10, now + (3 + (i % 4)) * DAY + 5 * HOUR)],
    scoped: [window("每周 · Opus", (i * 29) % 70 + 20, now + (3 + (i % 4)) * DAY + 5 * HOUR, "opus"), window("每周 · Fable", (i * 31) % 60, now + (3 + (i % 4)) * DAY + 5 * HOUR, "fable")],
    // (every other one holds resets, a kind each as the station tells them: accounts/claude-reset.ts claudeResets, quota.ts withResets)
    ...(i % 2 === 0
      ? { resets: [{ id: "session", kind: "session", left: 1, usable: true }, { id: "weekly", kind: "weekly", left: 2, expiries: [now + 3 * DAY, now + 9 * DAY], usable: false }], resetCount: 3, resetExpiries: [now + 3 * DAY, now + 9 * DAY] }
      : {}),
    detail: null,
    checkedAt: now - 4 * MIN,
  };
}

function codexQuota(now: number, i: number): J {
  return {
    state: "ok",
    plan: i % 3 === 0 ? "pro" : "plus",
    credits: { hasCredits: i % 2 === 0, unlimited: false, balance: i % 2 === 0 ? String(120 - i * 7) : "0" },
    // (the chat's second agent's account, codex-maple-1, near the end of its five hours: what its card warns of)
    windows: [window("5 小时", i === 1 ? 86 : (i * 19) % 95, now + (1 + (i % 4)) * HOUR + 33 * MIN), window("每周", (i * 13) % 85 + 5, now + (2 + (i % 5)) * DAY + 11 * HOUR)],
    // (a count and when each ends, no kinds: what a station tells of Codex, accounts/quota.ts withCodexCredits)
    resetCount: i % 3,
    ...(i % 3 === 0 ? {} : { resetExpiries: Array.from({ length: i % 3 }, (_, k) => now + (5 + k) * DAY) }),
    detail: null,
    checkedAt: now - 6 * MIN,
  };
}

/// A profile as a station lists it (its overview's `profiles`).
function profileOf(now: number, station: number, n: number, kind: string, k: number): J {
  const owner = pick(PEOPLE, station * 3 + k);
  const id = `${kind}-${STATIONS[station]!.id}-${k}`;
  const home = `/Users/${owner.email.split("@")[0]}/.stillfail/profiles/${id}`;
  const used = Array.from({ length: (n * 3) % 5 }, (_, j) => `k-${STATIONS[station]!.id}-${(n * 7 + j * 11) % ROWS_UP}`);
  const base = {
    id, home, homeExists: true, named: [] as string[], env: [] as J[], usedBy: used, machine: false, enabled: n !== 19, fast: false, backgroundOnMessage: true, login: null,
    workspaces: [] as string[], serves: true,
  };
  // (one Claude subscription of the workspace's signed out: its check says so, it has no allowance)
  const expired = kind === "claude" && station === 1 && k === 2;
  // (each lent to the next stations; the first of each station's kept to those it is lent to, as a manager narrows it: share/index.ts `allow`)
  const shared = (users: number): J => {
    const to = Array.from({ length: users }, (_, j) => pick(STATIONS, station + j + 1).id);
    return { share: { id: `share-${id}`, role: "host", host: STATIONS[station]!.id, users: to, ...(k === 0 ? { allow: [STATIONS[station]!.id, ...to] } : {}) } };
  };
  switch (kind) {
    case "claude":
      return {
        ...base, name: k === 0 ? `${owner.name} 的 Max` : `团队 Max ${k + 1}`, email: owner.email, runtime: "claude", runtimes: ["claude"], access: { kind: "subscription", key: "", login: false },
        model: "claude-opus-5-5", models: CLAUDE_MODELS, loginCommand: "claude /login", machine: k === 0,
        check: expired
          ? { state: "login", detail: "登录已过期：请重新登录 Claude", checkedAt: now - 2 * HOUR }
          : check(now, CLAUDE_MODELS, `可用 · Claude ${k % 2 === 0 ? "Max 20x" : "Max 5x"} · ${owner.email}`, {
            plan: k % 2 === 0 ? "max_20x" : "max_5x", modelEfforts: efforts("claude", CLAUDE_MODELS, CLAUDE_EFFORTS),
            decision: { state: "ok", detail: "可用于自动决策：claude-haiku-4-5", model: "claude-haiku-4-5", provider: "anthropic" },
          }),
        quota: expired ? null : claudeQuota(now, station * 5 + k), ...(k < 2 ? shared(2) : {}),
      };
    case "codex":
      return {
        ...base, name: k === 0 ? `${owner.name} 的 ChatGPT Pro` : `ChatGPT ${k % 3 === 0 ? "Pro" : "Plus"} ${k + 1}`, email: owner.email, runtime: "codex", runtimes: ["codex"],
        access: { kind: "subscription", key: "", login: false }, model: "gpt-6-astra", models: CODEX_MODELS, loginCommand: "codex login",
        check: check(now, CODEX_MODELS, `可用 · ChatGPT ${k % 3 === 0 ? "Pro" : "Plus"} · ${owner.email}`, {
          plan: k % 3 === 0 ? "pro" : "plus", modelEfforts: efforts("codex", CODEX_MODELS, CODEX_EFFORTS),
          modelEffortDefaults: { codex: Object.fromEntries(CODEX_MODELS.map((m) => [m, "medium"])) },
          decision: { state: "ok", detail: "可用于自动决策：gpt-6-mini", model: "gpt-6-mini", provider: "openai" },
        }),
        quota: codexQuota(now, station * 5 + k), ...(k === 0 ? shared(3) : {}),
      };
    case "devin":
      return {
        ...base, name: k === 0 ? "Devin Team" : `Devin · ${owner.name}`, email: owner.email, runtime: "devin", runtimes: ["devin"], access: { kind: "subscription", key: "", login: false },
        model: "swe-1.6", models: DEVIN_MODELS, loginCommand: "devin auth login",
        check: check(now, DEVIN_MODELS, `可用 · Devin Team · ${owner.email}`, { plan: "team", modelEfforts: efforts("devin", DEVIN_MODELS, ["low", "high"]) }),
        quota: { state: "ok", plan: "team", windows: [window("每月", (station * 11 + k * 7) % 70, now + 17 * DAY)], detail: "ACU 余额 412 / 1,000", checkedAt: now - 9 * MIN },
      };
    case "dsh":
      return {
        ...base, name: k === 0 ? "DeepSeek" : "DeepSeek（备用）", runtime: "dsh", runtimes: ["dsh", "claude"], access: { kind: "env", key: "" }, model: "deepseek-v4", models: DSH_MODELS,
        env: [{ key: "DEEPSEEK_API_KEY", secret: true, value: "sk-…a3f2" }, { key: "DEEPSEEK_BASE_URL", secret: false, value: "https://api.deepseek.com" }], loginCommand: "",
        check: check(now, DSH_MODELS, "可用 · 余额 ¥ 214.30", { modelEfforts: { ...efforts("dsh", DSH_MODELS, ["low", "medium", "high", "max"]), ...efforts("claude", DSH_MODELS, ["low", "high"]) } }),
        quota: { state: "ok", windows: [], detail: "余额 ¥ 214.30", checkedAt: now - 12 * MIN },
      };
    case "openrouter":
      return {
        ...base, name: k === 0 ? "OpenRouter" : "OpenRouter · 实验", runtime: "claude", runtimes: ["claude", "codex"], access: { kind: "api-provider", key: "sk-or-v1-…9e1c", provider: "openrouter" },
        // (one named by hand that OpenRouter does not list: what can be taken off)
        model: "anthropic/claude-sonnet-5", models: [...ROUTER_MODELS, "deepseek/deepseek-v4-1"], named: [...ROUTER_MODELS.slice(0, 4), "deepseek/deepseek-v4-1"], loginCommand: "",
        check: check(now, ROUTER_MODELS, "可用 · 列出了 312 个模型", { decision: { state: "ok", detail: "可用于自动决策：google/gemini-4-flash", model: "google/gemini-4-flash", provider: "openrouter" } }),
        quota: { state: "ok", credits: { hasCredits: true, unlimited: false, balance: "$41.18" }, windows: [], checkedAt: now - 15 * MIN },
      };
    case "anthropic":
      return {
        ...base, name: "Anthropic API", runtime: "claude", runtimes: ["claude"], access: { kind: "anthropic-api", key: "sk-ant-api03-…Qx7A" }, model: "claude-sonnet-5", models: CLAUDE_MODELS.slice(0, 3), loginCommand: "",
        check: check(now, CLAUDE_MODELS.slice(0, 3), "可用 · API key", { modelEfforts: efforts("claude", CLAUDE_MODELS.slice(0, 3), CLAUDE_EFFORTS) }), quota: { state: "unsupported", windows: [], checkedAt: now - 15 * MIN },
      };
    case "opencode":
      return {
        ...base, name: "OpenCode Go", email: owner.email, runtime: "claude", runtimes: ["claude", "dsh"], access: { kind: "opencode-go", key: "", login: true }, model: "kimi-k3", models: OPENCODE_MODELS, loginCommand: "",
        check: check(now, OPENCODE_MODELS, `可用 · OpenCode Go · ${owner.email}`), quota: { state: "ok", plan: "go", windows: [window("每月", 34, now + 12 * DAY)], checkedAt: now - 20 * MIN },
      };
    case "grok":
      return {
        ...base, name: "SuperGrok", email: owner.email, runtime: "grok", runtimes: ["grok"], access: { kind: "subscription", key: "", login: false }, model: "grok-5", models: GROK_MODELS, loginCommand: "grok login",
        check: check(now, GROK_MODELS, `可用 · SuperGrok · ${owner.email}`, { plan: "supergrok" }), quota: { state: "ok", plan: "supergrok", windows: [window("2 小时", 12, now + HOUR)], checkedAt: now - 8 * MIN },
      };
    default:
      return {
        ...base, name: "Cursor Pro", email: owner.email, runtime: "cursor", runtimes: ["cursor"], access: { kind: "subscription", key: "", login: false }, model: "composer-2", models: CURSOR_MODELS, loginCommand: "cursor-agent login",
        check: check(now, CURSOR_MODELS, `可用 · Cursor Pro · ${owner.email}`, { plan: "pro" }), quota: { state: "ok", plan: "pro", windows: [window("每月", 58, now + 9 * DAY)], checkedAt: now - 30 * MIN },
      };
  }
}

/// A station's eight profiles, by kind: Claude's and ChatGPT's subscriptions, Devin, DeepSeek, and one of the rest in
/// turn (OpenRouter, an Anthropic key, OpenCode Go, SuperGrok, Cursor), so the workspace has every kind.
const KINDS: [string, number][] = [["claude", 3 * SIZE.profiles], ["codex", 2 * SIZE.profiles], ["devin", SIZE.profiles], ["dsh", SIZE.profiles]];
const OTHERS = ["openrouter", "anthropic", "opencode", "grok", "cursor"];
export function profilesOf(now: number, station: number): J[] {
  const out: J[] = [];
  const kinds: [string, number][] = [...KINDS, [pick(OTHERS, station), SIZE.profiles]];
  for (const [kind, count] of kinds) for (let k = 0; k < count; k++) out.push(profileOf(now, station, out.length, kind, k));
  return out;
}

// ── a station's overview ──

function connectsOf(station: number): J[] {
  const s = STATIONS[station]!;
  const slack = (n: number): J => ({
    id: `c-slack-${n}`, name: n === 1 ? "still.fail" : `${s.name} Bot ${n}`, team: "T04ACME0001", botImage: `https://avatars.slack-edge.com/2026-02-0${n}/bot${n}_512.png`, enabled: true,
    kind: "slack", mode: n === 2 ? "single-session" : "multi-session", requireMention: n !== 3, bind: { runtime: n === 2 ? "codex" : "claude", model: n === 2 ? "gpt-6-astra" : "claude-opus-5-5", effort: "high", profile: null },
    slack: { appToken: "xapp-1-…f3e9", botToken: "xoxb-…71ac" },
    connection: { state: "connected", botUserId: `U0BOT${n}${station}`, workspace: { team: "Acme", teamId: "T04ACME0001", url: "https://acme-dev.slack.com/", botUserId: `U0BOT${n}${station}`, botName: n === 1 ? "still.fail" : `${s.name.toLowerCase()}-bot-${n}`, botImage: `https://avatars.slack-edge.com/2026-02-0${n}/bot${n}_192.png` } },
    // (the first of each station's made by the viewer, the workspace's owner, who set up its Slack: `connects mine`)
    createdBy: n === 1 ? { id: PEOPLE[0].email, name: PEOPLE[0].name } : { id: pick(PEOPLE, station + n).email, name: pick(PEOPLE, station + n).name }, sessions: 30 + station * 7 + n * 3, session: n === 2 ? `k-${s.id}-3` : null,
  });
  const feishu: J = {
    id: "c-feishu-1", name: "飞书助手", team: null, enabled: true, kind: "feishu", mode: "multi-session", requireMention: true, bind: { runtime: "claude", model: null, effort: null, profile: null },
    slack: { appToken: "", botToken: "" }, feishu: { appId: "cli_a7f3e9b2c41d500e", appSecret: "…9c2b", domain: "feishu", threads: true },
    connection: { state: "connected" }, createdBy: { id: pick(PEOPLE, station + 4).email, name: pick(PEOPLE, station + 4).name }, sessions: 12 + station, session: null,
  };
  return station % 2 === 0 ? [slack(1), slack(2), slack(3), feishu] : [slack(1), slack(2), feishu];
}

function decisionsOf(now: number, station: number, profiles: J[]): J {
  const s = STATIONS[station]!;
  const ids = (runtime: string) => profiles.filter((p) => p.runtime === runtime && p.access.kind === "subscription").map((p) => p.id);
  const options = [
    ["done", "已完成", "agent 说完成了，最后一条消息之后没有人再提新的要求，也没有未合并的 PR 或未回答的问题。", true],
    ["waiting", "等人回复", "agent 在等某个人的回答或决定，而这个人还没有回复；或者对话里有人说了“等我看看”。", false],
    ["followup", "还有后续", "对话里约好了之后再做的事（下周、明天、等 CI），或者 agent 起了长期任务还在跑。", false],
    ["abandoned", "已放弃", "对话停在中途超过三天，没有人再提起，也没有任务在跑；常见于试一试就放下的问题。", true],
  ] as const;
  return {
    canEdit: station !== 3,
    canReview: true,
    settings: { completion: { enabled: true, model: "claude-haiku-4-5" } },
    models: [
      { id: "claude-haiku-4-5", name: "Haiku 4.5", profiles: ids("claude") },
      { id: "gpt-6-mini", name: "GPT-6 mini", profiles: ids("codex") },
      { id: "google/gemini-4-flash", name: "Gemini 4 Flash", profiles: profiles.filter((p) => p.access.provider === "openrouter").map((p) => p.id) },
    ],
    recent: Array.from({ length: 10 }, (_, i) => ({
      id: 9000 + i, session: `k-${s.id}-${i}`, title: pick(TITLES, station * 7 + i), at: now - (i * 47 + 3) * MIN, label: pick(options, i)[1], accepted: i % 6 !== 5,
      model: "claude-haiku-4-5", profile: ids("claude")[0], elapsedMs: 2400 + ((i * 731) % 6000), ...(i === 11 ? { error: "超时：模型 30 秒内没有回答" } : {}),
    })),
    policy: {
      text: "判断一个对话是否可以归档：看最后一条 agent 消息之后有没有人提出新的要求；有没有未合并的 PR、未回答的卡片或还在跑的任务；对话里是否约定了之后要做的事。拿不准时不要归档。Slack 来的对话以 Slack 线程里最后一条消息为准。",
      options: options.map(([id, name, rubric, archive], j) => ({
        id, name, rubric, archive, count: 12 - j * 3,
        chats: Array.from({ length: 5 }, (_, c) => ({ session: `k-${s.id}-${j * 5 + c}`, title: pick(TITLES, j * 5 + c + station), at: now - (j * 5 + c) * 3 * HOUR, recommended: archive })),
      })),
      days: 7, checked: 42, failed: 1, edited: true,
      change: { at: now - 3 * DAY, summary: "加了「已放弃」：三天没人提起的对话也可以归档", by: { kind: "person", email: PEOPLE[1].email, name: PEOPLE[1].name } },
    },
  };
}

const VERSION = (id: string, name: string, version: string | null, latest: string | null, extra: J = {}): J => ({
  id, name, installed: version !== null, version, latest, newer: version !== null && latest !== null && version !== latest, updatable: true, state: "idle", checkedAt: 0, ...extra,
});

export function overviewOf(now: number, station: number): J {
  const s = STATIONS[station]!;
  const profiles = profilesOf(now, station);
  const mac = s.cpu.startsWith("Apple");
  const running = (station * 3) % 7;
  return {
    viewer: { via: "mesh", email: PEOPLE[0].email, name: PEOPLE[0].name, sub: "s1", role: "owner", workspace: "ws", device: "d-phone-1" },
    connects: connectsOf(station),
    profiles,
    processes: Array.from({ length: running + 2 }, (_, i) => ({
      pgid: 41000 + station * 100 + i, startedAt: now - (i + 1) * 23 * MIN, runtime: i % 3 === 0 ? "codex" : "claude", label: pick(TITLES, station * 5 + i), rssMb: 180 + i * 37.5,
    })),
    counts: { sessions: 160 + station * 13, running, warm: 4 + station },
    mesh: { state: "running", origin: "https://still.fail", station: s.id, workspace: "Acme", workspaceId: "ws", name: s.name, reached: true },
    slackUsers: SLACK_USERS,
    slackTeams: [{ teamId: "T04ACME0001", name: "Acme", owner: { team: "T04ACME0001", teamDomain: "acme-dev", teamIcon: "https://avatars.slack-edge.com/2025-11-02/team_icon_132.png", user: "lina", email: PEOPLE[1].email, image: slackPicture(1) } }],
    slackApps: [
      { appId: `A07${s.id.toUpperCase()}01`, name: `${s.name} agent`, teamId: "T04ACME0001", team: "Acme", created: now - 40 * DAY, links: { settings: `https://api.slack.com/apps/A07${s.id.toUpperCase()}01/general`, install: `https://api.slack.com/apps/A07${s.id.toUpperCase()}01/install-on-team`, appToken: `https://api.slack.com/apps/A07${s.id.toUpperCase()}01/general#app-level-tokens`, oauth: `https://api.slack.com/apps/A07${s.id.toUpperCase()}01/oauth` }, install: `https://slack.com/oauth/v2/authorize?client_id=4815162342.${station}&scope=app_mentions:read,channels:history,chat:write&state=st-${s.id}`, state: `st-${s.id}`, installed: false },
    ],
    comma: station === 0,
    feishuRegistrations: [],
    disk: { freeBytes: (180 + station * 40) * 1e9, totalBytes: 1000e9 },
    logins: station === 1 ? [{ id: "login-1", runtime: "codex", job: { profile: "codex-new", runtime: "codex", state: "needs_approval", url: "https://auth.openai.com/codex/device", userCode: "QH7K-2M9P", startedAt: now - 2 * MIN, expiresAt: now + 13 * MIN, browser: true } }] : [],
    machineLogins: [
      { runtime: "claude", installed: true, loggedIn: true, email: pick(PEOPLE, station).email, plan: "max_20x", usable: true, quota: claudeQuota(now, station + 30), text: `Claude Code 已登录：${pick(PEOPLE, station).email}（Max 20x）` },
      station !== 2
        ? { runtime: "codex", installed: true, loggedIn: true, email: pick(PEOPLE, station + 1).email, plan: "pro", usable: true, quota: codexQuota(now, station + 30), text: `Codex 已登录：${pick(PEOPLE, station + 1).email}（Pro）` }
        : { runtime: "codex", installed: true, loggedIn: false, usable: true, text: "Codex 未登录" },
    ],
    sharing: true,
    consoleSignIn: true,
    accountSubsets: true,
    updates: [
      VERSION("station", "still.fail", "0.1.7018", "0.1.7020", { channel: "beta", auto: true, idleOnly: true }),
      VERSION("claude", "Claude Code", "2.4.12", "2.4.14"),
      VERSION("codex", "Codex", "0.98.0", "0.98.0"),
      VERSION("dsh", "DeepSeek Harness", "1.3.2", "1.3.2"),
      VERSION("grok", "Grok Build", "0.7.1", "0.8.0"),
      VERSION("cursor", "Cursor", null, "2026.11.03"),
      VERSION("devin", "Devin", "1.12.0", "1.12.0"),
    ],
    agentEnv: [
      { key: "GITHUB_TOKEN", secret: true, value: "ghp_…Q2xz" },
      { key: "NPM_CONFIG_REGISTRY", secret: false, value: "https://registry.npmmirror.com" },
      { key: "HTTPS_PROXY", secret: false, value: "http://127.0.0.1:7890" },
      { key: "SENTRY_AUTH_TOKEN", secret: true, value: "sntrys_…8f1a" },
    ],
    drive: {
      roots: [
        { path: `/Users/${s.host}/Documents`, name: "文稿", state: "ok" },
        { path: `/Users/${s.host}/Downloads`, name: "下载", state: "ok" },
        { path: `/Users/${s.host}/src`, name: "src", state: "ok" },
        { path: "/Volumes/Backup", name: "Backup", state: station === 2 ? "missing" : "ok" },
      ],
      anywhere: true, home: `/Users/${s.host}`, trash: true, watch: true, zip: true, transfers: true,
    },
    search: { files: mac ? "spotlight" : "walk", personal: mac },
    network: { congestion: "cubic" },
    context: { afreshWhenCold: true, afreshAbove: 0.5 },
    diagnostics: { logs: true },
    // (as a station says them, station/src/helper/grants.ts GrantsView and api/routes/permissions.ts: the core words them)
    ...(mac ? { permissions: { grants: ["capture", "control", "documents", "desktop", "downloads", "localNetwork"].map((grant, j) => ({ grant, state: j === 3 ? "unknown" : "granted" })), asking: [], screen: true, request: true, localNetworkName: "still.fail" } } : {}),
    // Its chats copied off it to two others (station/src/replica/copies.ts): the next two up.
    copies: {
      to: 412 + station, chats: 160 + station * 13, stopped: null, restored: null, empty: false, restoring: null, restorable: null, manage: true, formerly: [],
      keepers: [1, 2].map((d) => ({ station: pick(STATIONS, station + d).id, name: pick(STATIONS, station + d).name, to: 412 + station, at: now - (3 + d) * MIN, error: null, reason: null })),
    },
    // What a chat can be kept to less context on (station/src/api/overview.ts, sessions/context-cap.ts): each model's window.
    contextCaps: { runtimes: ["claude", "codex"], least: 100_000, windows: Object.fromEntries([...new Set(profiles.flatMap((p: J) => p.models as string[]))].map((m) => [m, /haiku|4-5|mini|flash|v3/.test(m) ? 200_000 : /gpt|codex|grok/.test(m) ? 400_000 : 1_000_000])) },
    archiving: { days: 7, slackDays: 14, reviewed: true, canEdit: true },
    automaticDecisions: decisionsOf(now, station, profiles),
  };
}

// ── what a station's machine says ──

export function hostReading(now: number, station: number, load = 0.21 + station * 0.07): J {
  const s = STATIONS[station]!;
  const gb = 1024 ** 3;
  return {
    hostname: s.host, os: s.cpu.startsWith("Apple") ? "macOS 26.1" : s.cpu.startsWith("AMD") ? "Ubuntu 24.04" : "Windows 11 Pro 24H2", arch: s.cpu.startsWith("Apple") ? "arm64" : "x64",
    cpus: s.cpus, cpuModel: s.cpu, load, cpuBusy: load * 0.8, uptimeSec: 86400 * (3 + station) + 4211,
    memory: { totalBytes: s.memGb * gb, usedBytes: Math.round(s.memGb * gb * (0.42 + station * 0.05)), swapUsedBytes: 512 * 1024 ** 2 },
    disk: { path: "/", totalBytes: 1000e9, freeBytes: (180 + station * 40) * 1e9 }, stationRssBytes: 212 * 1024 ** 2 + station * 1e6, checkedAt: now,
    // (as station/src/jobs/gpu.ts reads them: a Mac's its chip's, the PC's its card's)
    gpus: s.cpu.startsWith("Apple")
      ? [{ name: s.cpu, cores: pick([40, 20, 80, 0, 16], station), busy: 0.12 + station * 0.05 }]
      : [{ name: "NVIDIA GeForce RTX 4090", memoryTotalBytes: 24_564 * 1024 ** 2, memoryUsedBytes: 3_100 * 1024 ** 2, busy: 0.07 }],
  };
}

// ── the chats ──

/// An agent as a sidebar's row has it.
function agentOf(now: number, key: string, i: number): J {
  const codex = i % 3 === 1;
  return {
    key, runtime: codex ? "codex" : "claude", model: codex ? "gpt-6-astra" : "claude-opus-5-5", effort: codex ? "high" : "xhigh", process: i % 9 === 0 ? "running" : i % 4 === 0 ? "warm" : "cold",
    pending: 0,
    lastTurn: {
      id: `turn-${key}-${i}`, kind: "chat", outcome: "done", declared: i % 5 === 3 ? "block" : "final", ending: i % 5 === 3 ? "need_help" : "all_done",
      ...(i % 5 === 3 ? { need: "需要你决定：周六上午 9 点做生产库迁移可以吗？" } : {}), detail: null, startedAt: now - (i * 37 + 9) * MIN, endedAt: now - (i * 37 + 2) * MIN,
    },
  };
}

const keyOf = (station: number, i: number) => `k-${STATIONS[station]!.id}-${i}`;

/// An agent's options card, as `chat_post` posts one.
const optionsCard = (): J => ({ type: "options", options: [{ label: "可以，周六 9 点", detail: "按计划停写 4 分钟", recommended: true }, { label: "改到周日上午" }, { label: "先不做" }], assignee: PEOPLE[0].email });
/// An agent's request for a vault item, as the station posts it (station/src/vault/secrets.ts: its scopes, then 拒绝).
const vaultCard = (i: number): J => ({
  type: "options", options: [{ label: "允许这一次" }, { label: "允许一小时", recommended: true }, { label: "拒绝", detail: "通知 agent 已拒绝" }], assignee: PEOPLE[0].email,
  vault: { request: `vr-${i}`, name: "GitHub token", reason: "推送 PR #5244 并打开 review", command: "gh pr create --fill", mode: "proxy", hosts: ["api.github.com", "github.com"], timeout: { kind: "idle", seconds: 3600 } },
});
/// What a chat's row says of the card it waits on (station/src/read/views.ts cardView): the card, its post, an options
/// card its `decision` too.
function waiting(seq: number, author: string, text: string, at: number, card: J): J {
  const message = { seq, authorKind: "agent", author, authorName: null, text, attachments: [], quotes: [], declared: "block", createdAt: at, options: card.options, card };
  return { card: { seq, card, message, before: [] }, decision: { seq, message, before: [], options: card.options } };
}
const threadIdOf = (station: number, i: number) => (i === 0 && station === 0 ? CHAT.thread : 2000 + station * 1000 + i);

/// A chat row as a station lists it (its `GET /chats`).
function rowOf(now: number, station: number, i: number, archived = false): J {
  const key = archived ? `a-${STATIONS[station]!.id}-${i}` : keyOf(station, i);
  const th = threadIdOf(station, i) + (archived ? 500 : 0);
  const slack = i % 4 === 1;
  const at = now - (i * 41 + station * 13 + 1) * MIN - (archived ? 9 * DAY : 0);
  const starter = slack ? slackPerson(i) : person(i + station);
  const people = [starter, person(i + 2), ...(i % 3 === 0 ? [person(i + 5)] : [])];
  const agents = [agentOf(now, key, i), ...(i === 0 && station === 0 ? [agentOf(now, CHAT.keys[1], 1)] : [])];
  const titled = i % 10 !== 7;
  const row: J = {
    id: key, session: key, thread: th, title: "", agents,
    last: { seq: 40 + i, authorKind: i % 3 === 2 ? "person" : "agent", author: i % 3 === 2 ? pick(PEOPLE, i).email : key, authorName: i % 3 === 2 ? pick(PEOPLE, i).name : null, text: pick(LINES, i + station).slice(0, 200), createdAt: at },
    unread: i % 6 === 0, mine: i % 3 === 0, lastActiveAt: at,
    connect: slack ? "c-slack-1" : null,
    origin: slack ? { teamName: "Acme", channel: "C05ENG0001", channelName: pick(["eng", "android", "infra", "design"], i), threadTs: `1794${i}0${station}.00${i}`, surface: "slack:T04ACME0001" } : null,
    creator: starter, people, ws: "ws",
    named: titled
      ? { thread: { id: th, surface: slack ? "slack:T04ACME0001" : "ember", channel: slack ? "C05ENG0001" : "EMBER", threadTs: `${th}.0`, title: pick(TITLES, i + station * 3), createdAt: at - HOUR }, firstText: null, channelName: null }
      : { thread: { id: th, surface: "ember", channel: "EMBER", threadTs: `${th}.0`, title: null, createdAt: at - HOUR }, firstText: pick(MEDIUM, i), channelName: null },
    mineOf: people.slice(0, 2), said: null, archiveReminderDismissed: false, archiveRecommended: i % 11 === 5, archiveReviewed: true, pinned: i % 37 === 3 ? now - i * HOUR : null,
  };
  if (archived) row.archived = { at: at + DAY, by: "auto", alone: true };
  // (those whose agent asks a person wait on its card, every other one a vault item's request; the chat's its last)
  else if (i % 5 === 3 || (station === 0 && i === 0)) {
    const seq = station === 0 && i === 0 ? CHAT_MESSAGES : row.last.seq;
    const text = i % 10 === 3 ? "需要你决定：周六上午 9 点做生产库迁移可以吗？" : "需要用 GitHub token 推送 PR，请批准。";
    Object.assign(row, waiting(seq, key, text, at, i % 10 === 3 ? optionsCard() : vaultCard(i)));
  }
  // (some shared with the owner's other workspace, as its station says it: read/views.ts `xshare`)
  if (!archived && i % 13 === 4) row.xshare = { to: [OTHER_WORKSPACE.id], write: false };
  // (the chats the chat's agent opened, `chat_create`: read/views.ts `opened`)
  if (!archived && station === 0 && i === 0) row.opened = [{ session: keyOf(0, 40), title: pick(TITLES, 40) }, { session: keyOf(0, 41), title: pick(TITLES, 41) }];
  return row;
}

const member = (thread: number, key: string, connect: string, at: number): J => ({ thread, session: key, connect, joinedAt: at });

/// A chat's thread as a station lists it (its `GET /threads`).
function threadOf(now: number, station: number, i: number): J {
  const r = rowOf(now, station, i);
  return {
    id: r.thread, surface: r.named.thread.surface, channel: r.named.thread.channel, channelName: r.origin?.channelName ?? null, threadTs: r.named.thread.threadTs, title: r.named.thread.title,
    createdBy: r.creator.id, creator: r.creator, createdAt: r.lastActiveAt - HOUR,
    sessions: r.agents.map((a: J) => member(r.thread, a.key, r.connect ?? "ember", r.lastActiveAt - HOUR)), last: r.last.seq,
    lastMessage: { seq: r.last.seq, thread: r.thread, ts: `${r.thread}.${r.last.seq}`, authorKind: r.last.authorKind, author: r.last.author, authorName: r.last.authorName, text: r.last.text, attachments: [], quotes: [], declared: null, createdAt: r.last.createdAt, editedAt: null },
    read: i % 6 === 0 ? r.last.seq - 2 : r.last.seq, unread: i % 6 === 0 ? 2 : 0, people: r.people, firstText: r.named.firstText,
    // (the chat's agent is in a Slack thread too, what is said here can be copied to: station/src/read/sessions.ts `cc`;
    // and it is shared with the owner's other workspace)
    ...(station === 0 && i === 0
      ? {
        cc: [{ thread: threadIdOf(0, 1), surface: "slack:T04ACME0001", channel: "C05ENG0001", threadTs: `${threadIdOf(0, 1)}.0`, channelName: "android" }],
        xshare: { to: [{ workspace: OTHER_WORKSPACE.id, name: OTHER_WORKSPACE.name }], write: false },
      }
      : {}),
  };
}

/// The job a session watches, of `jobsOf`'s.
const watched = (now: number, station: number, key: string): J | undefined => jobsOf(now, station).find((j) => j.watch && j.session === key);

/// A session as a station lists it (its `GET /sessions`).
function sessionOf(now: number, station: number, key: string, i: number): J {
  const a = agentOf(now, key, i);
  return {
    key, connect: i % 4 === 1 ? "c-slack-1" : "ember", scope: "thread", title: null, createdBy: person(i + station).id, boundTo: [], creator: person(i + station), participants: [person(i + 2)],
    runtime: a.runtime, profile: a.runtime === "codex" ? `codex-${STATIONS[station]!.id}-${i % 3}` : `claude-${STATIONS[station]!.id}-${i % 3}`, profilePinned: false, model: a.model, effort: a.effort, fast: false,
    runtimeSessionId: `rs-${key}`, contextActions: ["compact", "clear"], workspace: `/Users/${STATIONS[station]!.host}/.stillfail/sessions/chat/${key}/workspace`, running: a.process === "running",
    createdAt: now - (i * 41 + 70) * MIN, lastActiveAt: now - (i * 41 + 1) * MIN, archivedAt: null, process: a.process, turns: 3 + (i % 17), pending: 0, firstText: pick(MEDIUM, i), lastTurn: a.lastTurn,
    // (what it watches, as station/src/read/sessions.ts says it of its jobs `watch`ing: jobsOf's)
    ...(watched(now, station, key) ? { watch: { names: [watched(now, station, key)!.name], since: watched(now, station, key)!.startedAt, at: now - 20 * MIN } } : {}),
  };
}

const rowsCount = (station: number) => (station < UP_COUNT ? ROWS_UP : ROWS_DOWN);

// ── the chat of 300 messages ──

/// All of its messages, six of the pages a chat is read in (`PAGE`): as many as a chat with all six loaded holds. One
/// opened holds the last page alone (`OPENS`).
export const CHAT_MESSAGES = 6 * PAGE * SIZE.messages;
/// What the chat holds as it opens: its last page.
export const OPENS = PAGE;

/// Where in the chat its run changed (the station's notice, station/src/sessions/actor.ts).
const RUN_CHANGED = 151;

const tsOf = (n: number) => `${CHAT.thread}.${String(n).padStart(6, "0")}`;
const keyAt = (n: number) => (n % 10 === 4 ? CHAT.keys[1] : CHAT.keys[0]);

function entryOf(now: number, n: number): J {
  const agent = n % 2 === 0;
  const key = keyAt(n);
  const by = pick(PEOPLE, n % 4 === 1 ? 1 : 0);
  const at = now - (CHAT_MESSAGES - n + 1) * 7 * MIN;
  // (the station's notice that the chat's second agent was moved to another account: run-change.ts words it)
  if (n === RUN_CHANGED) {
    const run = (runtime: string, model: string, effort: string, profile: string, account: string) => ({ runtime, model, effort, fast: false, profile, account, pinned: false, context: null });
    return {
      thread: CHAT.thread, n, kind: "message", ts: tsOf(n), authorKind: "ember", author: "ember", authorName: null, text: "已换成 Codex · GPT-6 Astra", at,
      change: { was: run("claude", "claude-opus-5-5", "xhigh", "claude-maple-1", "团队 Max 2"), now: run("codex", "gpt-6-astra", "high", "codex-maple-1", "ChatGPT Plus 2") },
    };
  }
  const attached = n % 23 === 0;
  // (an agent's text places the picture it attached where it names it, placed.ts; now and then links an earlier chat)
  const text = words(n) + (agent && attached ? `\n\n![](screenshot-${n}.png)` : "") + (agent && n % 50 === 10 ? `\n\n和[上次的讨论](https://still.fail/o/ws/maple/${keyOf(0, 12)})是同一个问题。` : "");
  // (now and then an agent's options card, every third of them a vault item's request; the last message asks for one, waiting)
  const card = agent && (n === CHAT_MESSAGES || n % 60 === 20) ? (n === CHAT_MESSAGES || n % 180 === 20 ? vaultCard(n) : optionsCard()) : undefined;
  return {
    thread: CHAT.thread, n, kind: "message", ts: tsOf(n), authorKind: agent ? "agent" : "person", author: agent ? key : by.email, authorName: agent ? null : by.name,
    text, at,
    ...(attached ? { attachments: [{ name: `screenshot-${n}.png`, path: `.stillfail/uploads/${n}-screenshot.png`, size: 248_113 + n, width: 1170, height: 2532, thumbhash: "3OcRJYB4d3h/iIeHeEh3eIhw+j3A" }] } : {}),
    // (now and then a file that is no picture: a trace, a report)
    ...(!attached && n % 37 === 0 ? { attachments: [{ name: n % 74 === 0 ? `trace-${n}.json` : `report-${n}.pdf`, path: `.stillfail/uploads/${n}-${n % 74 === 0 ? "trace.json" : "report.pdf"}`, size: 1_204_331 + n }] } : {}),
    // (a person replying to the agent's message before quotes some of it, as store/rows.ts Quote)
    ...(!agent && n % 11 === 1 ? { quotes: [{ author: keyAt(n - 1), text: words(n - 1).slice(0, 120), comment: "", ts: tsOf(n - 1), role: "agent" }] } : {}),
    ...(card ? { card, options: card.options } : {}),
  };
}

/// The chat's thread as its station's page of the last `count` of its messages has it (older ones before, `first`).
export function chatPage(now: number, count = CHAT_MESSAGES): J {
  const first = CHAT_MESSAGES - count + 1;
  return { first, last: CHAT_MESSAGES, entries: Array.from({ length: count }, (_, i) => entryOf(now, first + i)), end: true, thread: null };
}

// ── a chat of four weeks, held whole ──

/// A chat of four weeks held whole on the device, as the sync puts what it reads in its log (`outlinedLog`), for what
/// is made of all of a chat held (its outline, `chatOutline`): 1,600 entries a message 25 minutes apart, every third a
/// person's (533 of them: the viewer, three others and one from Slack with its picture; most a long line, some a few
/// words, a page or only a picture), the rest its agent's.
export const OUTLINED = { station: "ws/maple", thread: threadIdOf(0, 2), key: keyOf(0, 2) } as const;
export const OUTLINED_ENTRIES = 1600 * SIZE.messages;
const OUTLINED_EVERY = 25 * MIN;
/// One of Slack who is not the viewer (whose Slack ids are the overview's `slackUsers`).
const SLACK_OTHER = { id: "U07Z1X2Y3W4", name: "aiko.t", picture: slackPicture(2) };

/// The long chat's entry `n` (said at `at`).
function outlinedEntry(now: number, n: number, at = now - (OUTLINED_ENTRIES - n + 1) * OUTLINED_EVERY): J {
  const head = { thread: OUTLINED.thread, n, kind: "message", ts: `${OUTLINED.thread}.${String(n).padStart(6, "0")}`, at };
  if (n % 3 !== 0) return { ...head, authorKind: "agent", author: OUTLINED.key, authorName: null, text: words(n) };
  const k = n / 3;
  const who = k % 4 === 3
    ? { author: SLACK_OTHER.id, authorName: SLACK_OTHER.name, authorPicture: SLACK_OTHER.picture }
    : { author: pick(PEOPLE, k % 4).email, authorName: pick(PEOPLE, k % 4).name };
  if (k % 19 === 0) return { ...head, authorKind: "person", ...who, text: "", attachments: [{ name: `photo-${n}.jpg`, path: `.stillfail/uploads/${n}-photo.jpg`, size: 812_331 + n, width: 3024, height: 4032 }] };
  const text = k % 6 === 0 ? pick(SHORT, k) : k % 6 === 1 ? pick(MEDIUM, k) : k % 6 === 5 ? pick(LONG, k) : pick(LINES, k);
  return { ...head, authorKind: "person", ...who, text };
}

/// What the device holds of the long chat (made at `now`): its entries by number.
export function outlinedLog(now: number): [number, J][] {
  return Array.from({ length: OUTLINED_ENTRIES }, (_, i) => [i + 1, outlinedEntry(now, i + 1)]);
}

/// The long chat's next entry, a person's long line said at `at` (the chat made at `base`).
export function outlinedSaid(base: number, at: number): [number, J] {
  const n = OUTLINED_ENTRIES + 2;
  return [n, { ...outlinedEntry(base, n, at), text: pick(LINES, 0) }];
}

/// The long chat's newest entry, its agent's, as it goes on writing it (`more` words more of it).
export function outlinedWorking(base: number, more: number): [number, J] {
  const entry = outlinedEntry(base, OUTLINED_ENTRIES);
  return [OUTLINED_ENTRIES, { ...entry, text: `${entry.text}\n\n${pick(LINES, more).slice(0, 20 * more)}` }];
}

/// A person's message of the long chat (the newest of the viewer's) with its words edited at `at`.
export function outlinedEdit(base: number, at: number): [number, J] {
  const n = OUTLINED_ENTRIES + 1;
  const target = OUTLINED_ENTRIES - (OUTLINED_ENTRIES % 12);
  return [n, { thread: OUTLINED.thread, n, kind: "edit", target, ts: `${OUTLINED.thread}.${String(n).padStart(6, "0")}`, authorKind: "person", author: PEOPLE[0].email, text: "改一下：这一条说错了，按下面那条来", at }];
}

function detailOf(now: number, key: string, i: number): J {
  return {
    session: sessionOf(now, 0, key, i),
    threads: [threadOf(now, 0, 0)],
    // (its jobs, as station/src/read/sessions.ts gives them with the session)
    jobs: jobsOf(now, 0).filter((j) => j.session === key),
    turns: Array.from({ length: 40 }, (_, t) => ({ id: `turn-${key}-${t}`, kind: "chat", outcome: "done", declared: "final", ending: "all_done", detail: null, startedAt: now - (40 - t) * 30 * MIN, endedAt: now - (40 - t) * 30 * MIN + 9 * MIN })),
  };
}

export function liveOf(now: number): J {
  const tools = ["Bash", "Read", "Edit", "Grep", "mcp__stillfail__chat_post"];
  const timeline: J[] = [];
  for (let i = 0; i < 160; i++) {
    const at = new Date(now - (160 - i) * MIN).toISOString();
    // (what it was given: a person's message as still.fail hands it over, station/src/agents/instructions.ts, now and then
    // a background command's end told it)
    if (i % 4 === 0) {
      const p = pick(PEOPLE, i % 8 === 0 ? 0 : 1);
      timeline.push({
        at, kind: "user", text: i % 16 === 8
          ? `<task-notification>\n<task-id>bg-${i}</task-id>\n<status>completed</status>\n<summary>Background command "pnpm test --filter core" completed (exit code 0)</summary>\n</task-notification>`
          : `<message via="web" connect="ember" thread="EMBER/${CHAT.thread}.0" from="${p.name} (${p.email})" ts="${tsOf(i + 100)}">\n${words(i)}\n</message>`,
      });
    }
    else if (i % 4 === 1) timeline.push({ at, kind: "thinking", text: pick(MEDIUM, i) });
    else if (i % 4 === 2) timeline.push({ at, kind: "tool_call", text: i % 8 === 2 ? "pnpm exec tsgo --noEmit && node --test test/views.test.ts" : `src/views/views.ts`, tool: pick(tools, i), callId: `call-${i}` });
    else timeline.push({ at, kind: "tool_result", text: i % 8 === 3 ? "✔ 311 tests passed (14.2s)" : pick(LINES, i).slice(0, 160), tool: pick(tools, i - 1), ok: true, callId: `call-${i - 1}` });
  }
  return {
    // (as it runs: thinking now, what it has going past its turn and its checklist, station/src/sessions/live.ts)
    loaded: true, first: 1, timeline, steps: [{ id: "st-1", step: "thinking", input: "", startedAt: now - 20_000 }], phase: { phase: "working", since: now - 40_000 },
    tasks: [
      { id: "t1", kind: "command", description: "pnpm test --watch", elapsedMs: 600_000, since: now - 600_000 },
      { id: "t2", kind: "agent", description: "Review the migration script", elapsedMs: 120_000, since: now - 120_000 },
    ],
    plan: [{ text: "复现掉帧", status: "completed" }, { text: "缓存行高", status: "completed" }, { text: "录前后对比", status: "in_progress" }, { text: "开 PR 等 CI", status: "pending" }],
    usage: { modelCalls: 412, inputTokens: 8_412_330, cachedTokens: 7_901_002, outputTokens: 211_430, model: "claude-opus-5-5", contextTokens: 143_211, contextWindow: 1_000_000, cost: 31.42, lastCallAt: now - 3 * MIN, cacheMs: 300_000, rereadCost: 2.7 },
  };
}

/// What the chat's agent's transcript holds that the sync reads of Slack (elsewhere.ts readItem): two posts to the Slack
/// thread of the chat it is in too, and their answers; as `data.putItems("transcript", …)` takes them.
export function transcriptOf(now: number): [number, J][] {
  const to = `C05ENG0001/${rowOf(now, 0, 1).origin.threadTs}`;
  const said = ["CI 绿了，PR #5244 可以合了。", "已经合进 main，beta 今晚出。Pixel 8 上的掉帧录屏在 PR 里。"];
  return said.flatMap((text, k): [number, J][] => [
    [k * 2 + 1, { at: new Date(now - (90 - k * 40) * MIN).toISOString(), kind: "tool_call", tool: "mcp__stillfail__chat_post", callId: `post-${k}`, text: JSON.stringify({ to, text }) }],
    [k * 2 + 2, { at: new Date(now - (90 - k * 40) * MIN + 2000).toISOString(), kind: "tool_result", tool: "mcp__stillfail__chat_post", callId: `post-${k}`, ok: true, text: JSON.stringify({ ok: true, ts: `17941${k}00.0042` }) }],
  ]);
}

// ── usage, jobs, resources ──

function usageOf(now: number, station: number): J {
  const rows: J[] = [];
  for (let d = 0; d < 7; d++) {
    const day = localDay(now - d * DAY, 0);
    for (let r = 0; r < 24; r++) {
      const i = d * 24 + r;
      const codex = r % 3 === 1;
      rows.push({
        day, session: keyOf(station, i % ROWS_UP), thread: threadIdOf(station, i % ROWS_UP), person: pick(PEOPLE, i + station).email,
        profile: codex ? `codex-${STATIONS[station]!.id}-${r % 3}` : `claude-${STATIONS[station]!.id}-${r % 3}`, model: codex ? pick(CODEX_MODELS, r) : pick(CLAUDE_MODELS, r),
        calls: 12 + ((i * 37) % 300), cost: Math.round((0.4 + ((i * 53) % 900) / 37) * 100) / 100,
        // (its tokens, as station/src/read/store.ts counts them)
        runtime: codex ? "codex" : "claude", input: 20_000 + ((i * 911) % 90_000), cacheRead: 400_000 + ((i * 7717) % 2_000_000), cacheWrite: codex ? 0 : 30_000 + ((i * 313) % 60_000),
        cacheWriteLong: 0, output: 4_000 + ((i * 131) % 30_000),
      });
    }
  }
  // Its history (station/src/read/usage.ts usageHistory): the tokens of each day it has been used, half a year of them;
  // its chats by place, those archived, the decision cards and those picked, the tasks other stations' chats ran here.
  const history = {
    days: Array.from({ length: 180 }, (_, d) => ({ day: localDay(now - (179 - d) * DAY, 0), runtime: "", model: null, tokens: 40_000_000 + (((d * 7919 + station * 31) % 60) * 1_000_000), calls: 300 + ((d * 13) % 90) })),
    cards: 48 + station, picked: 31 + station, places: { ember: 70 + station * 9, slack: 30 + station * 4 }, archived: 60 + station * 7, remoteRuns: 9 + station,
  };
  return { rows, since: now - 30 * DAY, reading: false, history };
}

/// A station's jobs (its `GET /jobs`): the chat's agent's dev server and its watch of the PR's CI, a Slack chat's agent's
/// watch of a deploy, and the rest a chat each; a soak that has run a day telling how it goes (`stillfail-job notify`).
function jobsOf(now: number, station: number): J[] {
  const sessions = [0, 0, 6, 9, 12, 15, 1];
  return Array.from({ length: 7 }, (_, j) => ({
    id: `job-${STATIONS[station]!.id}-${j}`, session: keyOf(station, sessions[j]!), name: pick(["dev server", "watch CI #5244", "storybook", "e2e soak", "tail prod logs", "benchmark", "watch deploy #812"], j),
    state: j === 5 ? "exited" : "running", port: j === 0 ? 5173 : j === 2 ? 6006 : null, exitCode: j === 5 ? 0 : null, startedAt: now - (j + 1) * 5 * HOUR, endedAt: j === 5 ? now - HOUR : null,
    command: pick(["pnpm dev --host 127.0.0.1", "gh run watch 11234567 --exit-status", "pnpm storybook -p 6006", "./e2e/run.sh mac --loop", "kubectl logs -f deploy/api", "node bench/scroll.ts", "gh run watch 11234590 --exit-status"], j),
    restarts: j === 2 ? 1 : 0,
    // (the soak tells each round, `stillfail-job notify`: as many as the station shows, station/src/jobs/jobs.ts NOTICES_SHOWN)
    notices: j === 1
      ? [{ at: now - 20 * MIN, text: "CI 绿了：check-mbui native 5 分 12 秒" }]
      : j === 3
      ? Array.from({ length: 20 }, (_, r) => ({ at: now - (20 - r) * 45 * MIN, text: r % 6 === 5 ? `第 ${393 + r} 轮：1 个失败，chat-scroll 第 3 次重试后通过` : `第 ${393 + r} 轮：全部通过（平均 3 分 ${String(8 + (r % 5)).padStart(2, "0")} 秒）` }))
      : [],
    watch: j === 1 || j === 6, outputAt: now - (j + 1) * MIN,
  }));
}

/// What still.fail uses of station `st`'s machine as the station tells it (`more`: that many samples on, each as before,
/// the oldest gone).
export function resourcesOf(now: number, station: number, more = 0): J {
  const use = (cpu: number, mem: number) => ({ cpu, memory: mem, netIn: 1200 * cpu, netOut: 300 * cpu, diskRead: 4096 * cpu, diskWrite: 2048 * cpu });
  const sample = (k: number) => use(60 + (k % 7) * 4, 5.8 * 1024 ** 3);
  const at = now + more * 5000;
  return {
    at, counted: true, net: true, disk: true, everyMs: 5000, machine: { cores: STATIONS[station]!.cpus, memory: STATIONS[station]!.memGb * 1024 ** 3 },
    total: more === 0 ? use(84.2, 6.1 * 1024 ** 3) : sample(35 + more),
    history: Array.from({ length: 36 }, (_, i) => ({ at: at - (36 - i) * 5000, ...sample(i + more) })),
    chats: Object.fromEntries(Array.from({ length: 6 }, (_, i) => [keyOf(station, i), { thread: threadIdOf(station, i), title: pick(TITLES, i + station) }])),
    groups: Array.from({ length: 8 }, (_, g) => ({
      key: g < 6 ? `chat:${keyOf(station, g)}` : g === 6 ? "station" : "agents", ...(g < 6 ? { session: keyOf(station, g) } : {}),
      processes: Array.from({ length: 3 }, (_, p) => ({ pid: 50000 + station * 1000 + g * 10 + p, name: pick(["node", "claude", "codex", "esbuild", "tsgo", "git"], g + p), endable: g < 6, ...use(3 + g + p, (200 + g * 40) * 1024 ** 2) })),
    })),
  };
}

// ── all of it, as the stations' topics hold it ──

/// Each topic of the workspace with what it holds: what `set` puts in the rig, in an order a core could have it come;
/// the chat with the last `chat` of its messages read.
/// The workspace as still.fail cloud lists it (`/v1/workspaces/:id`): its stations and members.
function workspaceOf(now: number): J {
  return {
    id: "ws", name: "Acme", role: "owner",
    stations: STATIONS.map((s, i) => ({ id: s.id, name: s.name, last_seen: Math.trunc(now / 1000) - (i < UP_COUNT ? 5 : 3 * 86400), version: "0.1.7018", ...(s.emoji ? { emoji: s.emoji } : {}) })),
    members: PEOPLE.map((p, i) => ({ sub: p.sub, email: p.email, name: p.name, role: i === 0 ? "owner" : i < 3 ? "admin" : "member", picture: i % 2 === 0 ? slackPicture(i) : "" })),
  };
}

export function fixture(now: number, chat = CHAT_MESSAGES): [Topic, unknown][] {
  const out: [Topic, unknown][] = [];
  out.push([workspace(), workspaceOf(now)]);
  for (let st = 0; st < STATIONS.length; st++) {
    const at = address(st);
    const up = st < UP_COUNT;
    out.push([link(at), up ? { state: "online" } : { state: "offline", message: "连不上这台 station：它可能关机了", last: "offline" }]);
    out.push([overview(at), overviewOf(now - (up ? 0 : 3 * DAY), st)]);
    if (up) out.push([hostOf(at), hostReading(now, st)], [{ topic: "way", station: at }, { via: st % 2 === 0 ? "direct" : "relay", rttMs: 18 + st * 9 }]);
    out.push([sessions(at), sessionsAt(now, st)]);
    out.push([threads(at), threadsAt(now, st)]);
    out.push([rows(at), rowsWith(now, st, (r) => r)]);
    out.push([{ topic: "archivedRows", station: at }, Array.from({ length: ARCHIVED }, (_, i) => rowOf(now, st, i, true))]);
    if (up) {
      out.push([{ topic: "stationUsage", station: at }, usageOf(now, st)]);
      out.push([{ topic: "jobs", station: at }, jobsOf(now, st)]);
      out.push([{ topic: "stationResources", station: at }, resourcesOf(now, st)]);
    }
  }
  out.push([{ topic: "thread", station: CHAT.station, thread: CHAT.thread }, chatPage(now, chat)]);
  for (const [i, key] of CHAT.keys.entries()) {
    out.push([{ topic: "session", station: CHAT.station, key }, detailOf(now, key, i)]);
    // (with what the chat's line shows of it, as station/topics.ts `#live` puts it)
    const live = liveOf(now);
    out.push([{ topic: "live", station: CHAT.station, key }, { ...live, activity: activity(live) }]);
  }
  return out;
}

// ── the changelog ──
//
// still.fail cloud's beta feed as it was read on 2026-11-11 (`GET /v1/changelog`, `x-stillfail-channel: beta`: 2546
// entries), at its size and shape and made up: of its newest 200 (what the topic shows, changelog.ts `SHOWN`) the days
// held 43, 79, 12, 11, 29 and 26, a line was about 50 Chinese characters, an entry 1.06 lines; its parts android, desktop
// and web 53%, the station's 21%, all four 4%, desktop and web 3.5%, the desktop's 3%, Android's 2.5%, Android and
// desktop 2.5%, Android, desktop and the station 2.5%, none 2%, a few others; Android's tab 137 of them, by day 37, 62,
// 9, 4, 11 and 14. Sixty more after them, as `SHOWN` cuts the feed; the newest few not out yet.

/// How many entries the feed holds, and of its newest 200 each day's, newest first, and how many of a day's are Android's.
export const CHANGELOG_ENTRIES = 260;
const CHANGELOG_DAYS = [43, 79, 12, 11, 29, 26, 20, 20, 20];
const CHANGELOG_ANDROID = [37, 62, 9, 4, 11, 14, 15, 15, 15];
/// The parts of Android's changes, and of the others, as many of each in the newest 200 as the feed had.
const ANDROID_PARTS: [string[], number][] = [
  [["android", "desktop", "web"], 106], [["android", "desktop", "station", "web"], 8], [["android"], 5], [["android", "desktop"], 5],
  [["android", "desktop", "station"], 5], [["android", "web"], 4], [["android", "station"], 4],
];
const OTHER_PARTS: [string[], number][] = [[["station"], 42], [["desktop", "web"], 7], [["desktop"], 6], [[], 4], [["web"], 4]];
/// The newest version in the feed.
const CHANGELOG_NEWEST = 8400;

/// `pool`'s kinds spread over `n` (each as many times as it says, in turn).
function spread(pool: [string[], number][], n: number): string[][] {
  const all = pool.reduce((a, [, k]) => a + k, 0);
  const out: string[][] = [];
  const used = pool.map(() => 0);
  for (let i = 0; i < n; i++) {
    // (the kind furthest behind its share)
    let best = 0;
    for (let k = 1; k < pool.length; k++) if (used[k]! - ((i + 1) * pool[k]![1]) / all < used[best]! - ((i + 1) * pool[best]![1]) / all) best = k;
    used[best]!++;
    out.push(pool[best]![0]);
  }
  return out;
}

const CL_KINDS = ["修复：", "改进：", "新增：", "修复：", "改进："];
const CL_WHERE = ["对话列表", "Station 页面", "更新日志", "设置里的账号", "聊天输入框", "图片预览", "文件面板", "Profile 页面", "通知", "手机上的侧边栏", "命令面板", "终端", "搜索结果", "归档"];
const CL_WHAT = [
  "在网络断开又恢复后不再一直显示正在连接，切回前台时也会立刻读到最新的消息",
  "滚动到很长的对话中间时不再跳回底部，新消息到来时只在已经看到最后一条的时候才跟随",
  "打开时先显示设备上已经有的内容，再在后台读取更新，不再先闪一下空白的骨架",
  "字号调大以后文字不再被截断，按钮在窄屏上换行排列，长名字在中间省略",
  "里显示每台机器的版本和是否需要更新，点一下就能更新，更新完成后自动刷新",
  "在键盘弹出时不再被挡住，输入多行文字时高度跟着增长，发送后回到一行",
];

/// The made-up line `i` of the feed, about 50 characters as the feed's are.
function changelogLine(i: number): string {
  return `${pick(CL_KINDS, i)}${pick(CL_WHERE, i * 7 + 3)}${pick(CL_WHAT, i * 5 + i % 3)}`;
}

/// The feed as the cloud answers it (`{entries, released}`), its newest made a few minutes before `now`; each day of it
/// one day before the next, in the day's middle hours where the device is (UTC, or within a few hours of it; `now` past
/// three in the morning).
export function changelogFeed(now: number): J {
  const android = spread(ANDROID_PARTS, CHANGELOG_ANDROID.reduce((a, b) => a + b, 0));
  const others = spread(OTHER_PARTS, CHANGELOG_DAYS.reduce((a, b) => a + b, 0) - android.length);
  const today = Math.floor(now / DAY) * DAY;
  const entries: J[] = [];
  let [a, o] = [0, 0];
  for (const [d, n] of CHANGELOG_DAYS.entries()) {
    const mine = CHANGELOG_ANDROID[d]!;
    for (let k = 0; k < n; k++) {
      const i = entries.length;
      // (Android's spread through the day as many as it had)
      const isAndroid = Math.floor(((k + 1) * mine) / n) > Math.floor((k * mine) / n);
      const parts = isAndroid ? android[a++]! : others[o++]!;
      // (the day's from its newest, a few minutes apart, in the day's middle hours; today's up to a few minutes ago)
      const at = d === 0 ? now - (k + 1) * 4 * MIN : today - d * DAY + 15 * HOUR - (k * 8 * HOUR) / n;
      const text = i % 17 === 5 ? [changelogLine(i), changelogLine(i + 1000)] : [changelogLine(i)];
      entries.push({ version: CHANGELOG_NEWEST - i * 2, commit: (BigInt(i + 1) * 0x9e3779b97f4a7c15n % (1n << 160n)).toString(16).padStart(40, "0"), at: Math.trunc(at / 1000), text, fixes: [], parts });
    }
  }
  const version = (i: number) => CHANGELOG_NEWEST - i * 2;
  return { entries, released: { station: version(9), android: version(4), desktop: version(4), web: version(1) } };
}

/// What the device says it is (`client.device`): Android, a build some forty changes into the feed, the build seen before
/// it some ten further, so what it has, what an update brings and what it got since are all said.
export const CHANGELOG_DEVICE = { app: "android", build: `0.1.${CHANGELOG_NEWEST - 40 * 2}` };
export const CHANGELOG_SEEN = CHANGELOG_NEWEST - 52 * 2;

// ── devices ──

/// What up station `st` says of the devices attached to it and the phones lent to it (its `GET /devices`, the `devices`
/// event): three devices a member over the up stations, each as a station keeps it (`station/src/devices/registry.ts`
/// Kept, with where), and some members' phones lent to every up station, each with a grant or two of a chat's (as
/// `station/src/adb/module.ts` `shown` says them).
export function devicesSaid(now: number, st: number): J {
  const at = STATIONS[st]!;
  const kinds = [
    { kind: "adb", name: "Pixel 8 测试机", target: "192.168.1.%d:5555" },
    { kind: "tcp", name: "打印服务器", target: "10.0.0.%d:9100" },
    { kind: "serial", name: "ESP32 开发板", target: "/dev/tty.usbserial-14%d0", baud: 115200 },
  ];
  const devices = PEOPLE.flatMap((p, i) => kinds.map((k, j) => ({ p, i, j, k })))
    .filter(({ i, j }) => (i * 3 + j) % UP_COUNT === st)
    .map(({ p, i, j, k }) => ({
      id: ((i * 3 + j) * 2654435761 >>> 0).toString(16).padStart(16, "0").slice(-16), name: `${k.name} ${i + 1}`, kind: k.kind,
      target: k.target.replace("%d", String(20 + i * 3 + j)), ...(k.baud !== undefined ? { baud: k.baud } : {}),
      ws: "ws", owner: p.sub, owner_email: p.email, owner_name: p.name, at: now - (i * 3 + j) * HOUR, station: at.id, stationName: at.name,
    }));
  const phones = PEOPLE.filter((_, i) => i % 3 === 0).map((p, i) => ({
    id: `phone-${p.sub}`, name: `${p.name} 的 Pixel 8`, target: `R5CW${40000 + i}`,
    ownerEmail: p.email, ownerName: p.name, online: i % 2 === 0, open: i === 0,
    grants: Array.from({ length: 1 + (i % 2) }, (_, g) => ({
      request: `req-${p.sub}-${g}`, session: keyOf(st, g + i), chat: `chat-${st}-${g + i}`, title: `修 ${p.name} 那台手机上的登录页`, by: p.email,
      timeoutKind: g === 0 ? "idle" : "fixed", timeoutSeconds: 3600, exp: Math.trunc(now / 1000) + (g + 1) * 3600, until: Math.trunc(now / 1000) + 3600,
    })),
  }));
  return { workspace: "ws", station: at.id, devices, phones };
}

// ── what changes ──

/// The overview of station `st` (made at `base`, as `fixture` made it) with one profile's allowance read again at `at`
/// (its five hours' window used more).
export function quotaChanged(base: number, at: number, st: number): J {
  const o = overviewOf(base, st);
  const p = o.profiles.find((x: J) => x.runtime === "codex");
  p.quota = { ...p.quota, windows: [{ ...p.quota.windows[0], usedPercent: p.quota.windows[0].usedPercent + 4 }, ...p.quota.windows.slice(1)], checkedAt: at };
  return o;
}

/// What the chat's station tells as one more message comes at `at` (the workspace made at `base`, the chat with the last
/// `chat` of its messages read): its page, its thread and its row.
/// (`said`: what the message is, its words and what comes with them)
export function messageAdded(base: number, at: number, chat = CHAT_MESSAGES, said: J = { text: "好的，我先跑一遍测试再合。" }): [Topic, unknown][] {
  const page = chatPage(base, chat);
  const n = CHAT_MESSAGES + 1;
  const entry = { ...entryOf(base, n), at, ...said };
  const t0 = threadOf(base, 0, 0);
  const r0 = rowOf(base, 0, 0);
  const last = { seq: n, authorKind: "agent", author: CHAT.keys[0], authorName: null, text: entry.text, createdAt: at };
  const thread = { ...t0, last: n, read: n, lastMessage: { ...t0.lastMessage, seq: n, ts: entry.ts, authorKind: "agent", author: CHAT.keys[0], authorName: null, text: entry.text, createdAt: at } };
  return [
    [{ topic: "thread", station: CHAT.station, thread: CHAT.thread }, { ...page, last: n, entries: [...page.entries, entry] }],
    [threads(CHAT.station), [thread, ...Array.from({ length: ROWS_UP - 1 }, (_, i) => threadOf(base, 0, i + 1))]],
    [rows(CHAT.station), [{ ...r0, last, lastActiveAt: at }, ...Array.from({ length: ROWS_UP - 1 }, (_, i) => rowOf(base, 0, i + 1))]],
  ];
}

/// What the chat's agent says next with what it shows (made at `at`): a picture it attached and a pull request it links,
/// as `messageAdded`'s `said`.
export function thingSaid(at: number): J {
  const n = CHAT_MESSAGES + 1;
  return {
    text: `截图和新的 PR：https://github.com/acme/app/pull/5250\n\n![](screenshot-${n}.png)`, at,
    attachments: [{ name: `screenshot-${n}.png`, path: `.stillfail/uploads/${n}-screenshot.png`, size: 251_002, width: 1170, height: 2532, thumbhash: "3OcRJYB4d3h/iIeHeEh3eIhw+j3A" }],
  };
}

/// Station `st`'s chat rows (made at `base`), each as `f` makes it of the fixture's (null: gone from the list).
function rowsWith(base: number, st: number, f: (row: J, i: number) => J | null): J[] {
  return Array.from({ length: rowsCount(st) }, (_, i) => f(rowOf(base, st, i), i)).filter((r) => r !== null);
}

/// Station `st`'s sessions and threads as it lists them (made at `now`).
function sessionsAt(now: number, st: number): J[] {
  const keys = Array.from({ length: rowsCount(st) }, (_, i) => keyOf(st, i));
  if (st === 0) keys.push(CHAT.keys[1]);
  return keys.map((k, i) => sessionOf(now, st, k, i));
}
function threadsAt(now: number, st: number): J[] {
  return Array.from({ length: rowsCount(st) }, (_, i) => threadOf(now, st, i));
}

/// What the station at `station` lists as the workspace was made at `base` (the fixture's): its chat rows, threads and
/// sessions, by the topic of each.
export function listedOf(base: number, station: string, topic: "chatRows" | "threads" | "sessions"): J[] {
  const st = STATIONS.findIndex((s) => `ws/${s.id}` === station);
  return topic === "chatRows" ? rowsWith(base, st, (r) => r) : topic === "threads" ? threadsAt(base, st) : sessionsAt(base, st);
}

/// A chat of the viewer's on Maple (not the open one) whose agent came to wait on a card at `at`: its rows, and the row
/// before and after (what attention.ts tells notices.ts of).
export const CARD_ROW = 6;
export function cardCame(base: number, at: number): { rows: J[]; before: J; after: J } {
  const before = rowOf(base, 0, CARD_ROW);
  const seq = before.last.seq + 1;
  const text = "需要你决定：周六上午 9 点做生产库迁移可以吗？";
  const after = { ...before, last: { seq, authorKind: "agent", author: before.id, authorName: null, text, createdAt: at }, lastActiveAt: at, ...waiting(seq, before.id, text, at, optionsCard()) };
  return { rows: rowsWith(base, 0, (r, i) => (i === CARD_ROW ? after : r)), before, after };
}

/// A chat of Maple's archived at `at` by its station's archiving: its rows without it, its archived rows with it
/// first. One among the first rows its lists show (their first window, real-size-asked.ts `WINDOWS`), so the lists a
/// device holds lose a row and take the next in.
export const ARCHIVED_ROW = 2;
export function chatArchived(base: number, at: number): { rows: J[]; archived: J[] } {
  const row = { ...rowOf(base, 0, ARCHIVED_ROW), archived: { at, by: "auto", alone: true } };
  return { rows: rowsWith(base, 0, (r, i) => (i === ARCHIVED_ROW ? null : r)), archived: [row, ...Array.from({ length: ARCHIVED }, (_, i) => rowOf(base, 0, i, true))] };
}

/// A chat of Maple's with no title yet named by its agent (`chat_title`) with the words the search looks for: a pinned
/// one, among the first rows its lists show (their first window), so the row a device holds is told its title.
export const RENAMED_ROW = 77;
export function chatRenamed(base: number): J[] {
  return rowsWith(base, 0, (r, i) => (i === RENAMED_ROW ? { ...r, named: { ...r.named, thread: { ...r.named.thread, title: "迁移演练：Postgres 15 → 17 切换" }, firstText: null } } : r));
}

/// What Maple tells of three of its jobs at `at` (its `job` event, each): the chat's dev server crashed; the chat's watch
/// of its PR's CI ended, the CI red; the soak a round more told (`stillfail-job notify`), the oldest of the notices it shows gone.
export function jobsMoved(base: number, at: number): J[] {
  const all = jobsOf(base, 0);
  const [dev, ci, , soak] = all as [J, J, J, J];
  return [
    { ...dev, state: "failed", exitCode: 1, endedAt: at, outputAt: at },
    { ...ci, state: "exited", exitCode: 1, endedAt: at, outputAt: at, notices: [...ci.notices, { at, text: "CI 失败：check-mbui native，2 个测试没过" }] },
    { ...soak, outputAt: at, notices: [...soak.notices.slice(1), { at, text: "第 413 轮：全部通过（平均 3 分 09 秒）" }] },
  ];
}

/// Maple's usage read again (its `usage` event): today's calls of a chat a few more.
export function usageRead(base: number): J {
  const u = usageOf(base, 0);
  const [first, ...rest] = u.rows as J[];
  return { ...u, rows: [{ ...first, calls: first.calls + 3, cost: Math.round((first.cost + 0.42) * 100) / 100, input: first.input + 2_100, cacheRead: first.cacheRead + 61_000, output: first.output + 900 }, ...rest], history: { ...u.history, days: u.history.days.map((d: J, i: number) => (i === u.history.days.length - 1 ? { ...d, tokens: d.tokens + 64_000, calls: d.calls + 3 } : d)) } };
}

/// The folder of Maple's drive shown with a file more at `at`: a screenshot saved into it.
export function driveAdded(base: number, at: number): J {
  const d = driveOf(base);
  return { ...d, entries: [{ name: "Screenshot 2026-11-11 at 14.02.11.png", dir: false, size: 2_412_331, mtime: at, type: "file" }, ...d.entries] };
}

/// The chat's letters (its `letters` as the device holds it: all its entries, its letters) with `letters` letters, and
/// entries `more` after its 300.
export function lettersHeld(base: number, letters = LETTERS_COUNT, more: J[] = []): J {
  return { entries: [...chatPage(base).entries, ...more], letters: lettersOf(base, letters), whole: true, thread: { ...threadOf(base, 0, 0), lettersLast: letters } };
}

/// Maple's screens as it tells them at `at` (its `screens` event): the chat's agent's browser tab moved to the PR's
/// checks, the person looking at it gone.
export function screensMoved(base: number, at: number): J {
  const s = screensOf(base);
  return { ...s, screens: s.screens.map((x: J) => (x.id === "browser:T1" ? { ...x, title: "Checks · Pull request #5244 · acme/app", viewers: x.viewers.slice(0, 1), views: x.views.slice(0, 1).map((v: J) => ({ ...v, at })) } : x)) };
}

/// What Maple says of its devices at `at`, a member's test phone attached to it more.
export function devicesAdded(base: number, at: number): J {
  const d = devicesSaid(base, 0);
  const p = PEOPLE[1];
  return { ...d, devices: [...d.devices, { id: "00000000c0ffee01", name: "Pixel 9 测试机", kind: "adb", target: "192.168.1.60:5555", ws: "ws", owner: p.sub, owner_email: p.email, owner_name: p.name, at, station: STATIONS[0].id, stationName: STATIONS[0].name }] };
}

/// The workspace's lock as its stations keep it once a member's new device was approved at `at` (an entry more, and
/// what the device told of itself).
export function lockApproved(base: number, at: number): J {
  const l = lockOf(base);
  const secs = Math.floor(at / 1000);
  const p = PEOPLE[1];
  const device = { id: `dev-${p.sub}-tablet`, sub: p.sub, kind: "app", label: `ios still.fail · ${p.name} 的 iPad Pro`, sign_key: `sk-${p.sub}-tablet` };
  return {
    head: { seq: 2, hash: "h-2", genesis: "h-genesis" }, entries: [...l.entries, { seq: 2, prev: "h-genesis", at: secs, by: "dev-s1-mac", kind: "device", body: device, sig: "" }],
    seen: [...l.seen, { base: device.id, last_seen: secs, label: device.label }],
  };
}

/// The workspace's plain library as held once Maple told its uses again at `at`: the most used item used once more,
/// the oldest of the 500 it keeps gone.
export function vaultUsed(base: number, at: number): J {
  const v = vaultOf(base);
  const key = `${STATIONS[0].id}/plain`;
  const use = { item: VAULT_ITEM, at: Math.floor(at / 1000), session: `ember:${CHAT.keys[0]}`, chatTitle: pick(TITLES, 0), mode: "proxy", command: "gh pr merge 5244 --squash", hosts: ["api.github.com", "github.com", "uploads.github.com"], denied: false };
  return { ...v, uses: { ...v.uses, [key]: [use, ...v.uses[key].slice(0, -1)] } };
}

/// The workspace's plain library with an item added at `at`.
export function vaultAdded(base: number, at: number): J {
  const v = vaultOf(base);
  const id = `item-${VAULT_ITEMS}`;
  const name = "Linear API key";
  return { ...v, plain: { ...v.plain, [id]: { id, owner: "s1", version: 1, kind: "token", name, notes: "", listing: { name, kind: "token", modes: ["proxy"], hosts: ["api.linear.app"], env: null, lasts: "chat" }, at, station: STATIONS[0].id } } };
}

/// The workspace as the cloud lists it once a member more joined.
export function memberJoined(base: number): J {
  const w = workspaceOf(base);
  return { ...w, members: [...w.members, { sub: "s13", email: "lin.xiao@acme.dev", name: "林晓", role: "member", picture: "" }] };
}

/// Maple at `at` with a session more, a Slack thread's of its first connect: its sessions, and its overview counting it.
export function sessionMade(base: number, at: number): [Topic, unknown][] {
  const keys = [...Array.from({ length: ROWS_UP }, (_, i) => keyOf(0, i)), CHAT.keys[1]];
  const made = { ...sessionOf(base, 0, keyOf(0, ROWS_UP + 1), ROWS_UP + 1), createdAt: at, lastActiveAt: at };
  const o = overviewOf(base, 0);
  return [
    [sessions(address(0)), [...keys.map((k, i) => sessionOf(base, 0, k, i)), made]],
    [overview(address(0)), { ...o, connects: o.connects.map((c: J) => (c.id === "c-slack-1" ? { ...c, sessions: c.sessions + 1 } : c)) }],
  ];
}

/// Maple's overview once something of it changed at `at` (its `overview` event): `decided`, an automatic decision more
/// (the newest of the ten it shows first); `updating`, Claude Code being updated; `machine`, the machine's own Claude
/// login's allowance read again; `login`, a sign-in of a Codex account under way, begun on another device;
/// `archiving`, its archiving's review turned off on another device (`archiving.save`); `off`, its automatic decisions
/// on whether a chat is done turned off there (`automaticDecisions.save`).
export function overviewMoved(base: number, at: number, what: "decided" | "updating" | "machine" | "login" | "archiving" | "off"): J {
  const o = overviewOf(base, 0);
  if (what === "off") return { ...o, automaticDecisions: { ...o.automaticDecisions, settings: { completion: { ...o.automaticDecisions.settings.completion, enabled: false } } } };
  if (what === "login") return { ...o, logins: overviewOf(base, 1).logins.map((l: J) => ({ ...l, job: { ...l.job, startedAt: at - 2 * MIN, expiresAt: at + 13 * MIN } })) };
  if (what === "archiving") return { ...o, archiving: { ...o.archiving, reviewed: false } };
  if (what === "updating") return { ...o, updates: o.updates.map((u: J) => (u.id === "claude" ? { ...u, state: "updating" } : u)) };
  if (what === "machine") {
    return { ...o, machineLogins: o.machineLogins.map((m: J, i: number) => (i === 0 ? { ...m, quota: { ...m.quota, windows: [{ ...m.quota.windows[0], usedPercent: m.quota.windows[0].usedPercent + 3 }, ...m.quota.windows.slice(1)], checkedAt: at } } : m)) };
  }
  const ad = o.automaticDecisions;
  const made = { ...ad.recent[0], id: 9010, session: keyOf(0, 11), title: pick(TITLES, 11), at, label: "已完成", accepted: true, elapsedMs: 3100 };
  return { ...o, automaticDecisions: { ...ad, recent: [made, ...ad.recent.slice(0, -1)], policy: { ...ad.policy, checked: ad.policy.checked + 1 } } };
}

/// The person's presets as the device carries them (src/presets-kept.ts): Maple's two and one made on Willow, one of
/// theirs deleted; none of a station from before.
function presetRecordsOf(now: number): J {
  const maple = presetsOf(now, 0).presets as J[];
  const rec = (p: J, home: string, rev: number) => ({
    ...p, dirs: p.dirs.map((d: J) => ({ path: d.path, repo: d.repo, station: `ws/${home}` })), createdBy: PEOPLE[0]!.email, owner: "s1", rev, home,
  });
  const records: J = {
    "p-app": rec(maple[0], "maple", 3),
    "p-infra": rec(maple[1], "maple", 2),
    "p-web": rec({ id: "p-web", name: "官网", dirs: [{ path: "/Users/willow/src/website", repo: "github.com/acme/website" }], instructions: "改文案前先看 i18n 的五种语言是否都要改。", createdAt: now - 12 * DAY, updatedAt: now - DAY }, "willow", 1),
    "p-old": { id: "p-old", owner: "s1", rev: 4, gone: true, updatedAt: now - 30 * DAY },
  };
  return { records, before: [] };
}

/// What the device holds once one of the person's presets was changed on another device of theirs at `at` (carried to
/// it as a station told `presets`).
export function presetRecordsChanged(base: number, at: number): J {
  const held = presetRecordsOf(base);
  const was = held.records["p-web"];
  return { ...held, records: { ...held.records, "p-web": { ...was, name: "官网 · 文案", updatedAt: at, rev: was.rev + 1 } } };
}

/// Others' presets as Maple gives them at a press (GET /presets/others): each of a member's, as many as a team of real
/// size has (two a member of the first dozen).
export function othersPresetsOf(now: number): J[] {
  return PEOPLE.slice(1, 12).flatMap((p, i) => [0, 1].map((j) => ({
    id: `p-${p.sub}-${j}`, name: j === 0 ? `${p.name} 的代码审查` : `${pick(TITLES, i * 2 + j)}`.slice(0, 40), dirs: [{ path: `/Users/maple/src/${["app", "station", "infra"][(i + j) % 3]}`, repo: `github.com/acme/${["app", "station", "infra"][(i + j) % 3]}`, station: "ws/maple" }],
    instructions: "先跑测试再提交；改动大的先在 thread 里说一声。", createdBy: p.email, createdAt: now - (40 - i) * DAY - j * HOUR, updatedAt: now - i * HOUR, owner: p.sub, rev: 1 + j, home: "maple",
  })));
}

/// Others' presets as Maple gives them read again once one of them changed one at `at`.
export function othersPresetsChanged(base: number, at: number): J[] {
  return othersPresetsOf(base).map((r: J, i: number) => (i === 0 ? { ...r, name: `${r.name}（新）`, updatedAt: at, rev: r.rev + 1 } : r));
}

/// Maple's presets once one was changed on another device at `at`.
export function presetsChanged(base: number, at: number): J {
  const p = presetsOf(base, 0);
  return { ...p, presets: p.presets.map((x: J) => (x.id === "p-infra" ? { ...x, instructions: `${x.instructions}改完在 #infra 贴 diff。`, updatedAt: at } : x)) };
}

/// The changelog's feed as the cloud answers it once a build more is out at `at`: an entry more, the newest.
export function changelogReleased(base: number, at: number): J {
  const f = changelogFeed(base);
  const version = CHANGELOG_NEWEST + 2;
  const entry = { version, commit: "f".repeat(40), at: Math.trunc(at / 1000), text: [changelogLine(9999)], fixes: [], parts: ["android", "desktop", "station", "web"] };
  return { entries: [entry, ...f.entries], released: { ...f.released, android: version, station: version } };
}

/// The chat's agent's live state at `at` as it goes on working (station/topics.ts `#live`, with its line): a call more
/// in its transcript, its step now that call.
export function liveStepped(base: number, at: number): J {
  const live = liveOf(base);
  const iso = new Date(at).toISOString();
  const call = "pnpm exec tsgo --noEmit && node --test test/topic-bytes.test.ts";
  const now = {
    ...live,
    timeline: [...live.timeline, { at: iso, kind: "tool_call", text: call, tool: "Bash", callId: "call-160" }],
    steps: [{ id: "st-2", step: "tool", tool: "Bash", input: JSON.stringify({ command: call }), startedAt: at }],
    usage: { ...live.usage, modelCalls: live.usage.modelCalls + 1, outputTokens: live.usage.outputTokens + 120, contextTokens: live.usage.contextTokens + 900, lastCallAt: at },
  };
  return { ...now, activity: activity(now) };
}

// ── the account's own, and what else the pages read ──

/// The owner's other workspace, where some chats are shared and whose stations a station here could join.
export const OTHER_WORKSPACE = { id: "ws-labs", name: "Acme Labs" } as const;
const OTHER_STATIONS = [{ id: "lab-1", name: "Lab GPU", version: "0.1.7018" }, { id: "lab-2", name: "Lab Mini", version: "0.1.7018" }];
/// The relays still.fail cloud offers (`/v1/me` relay_urls), and the workspace's own one (cloud/src/relays.ts).
const RELAYS = ["https://relay.still.fail", "https://relay-bj.still.fail", "https://relay-sg.still.fail"];
const OWN_RELAY = "https://relay.acme.dev";
/// The workspaces the account is in, as its `/v1/me` lists them: this one, another of the owner's, a friend's.
const ACCOUNT_WORKSPACES = [
  { id: "ws", name: "Acme", role: "owner", relays: [OWN_RELAY], ways_off: ["tailnet"] },
  { id: OTHER_WORKSPACE.id, name: OTHER_WORKSPACE.name, role: "owner", relays: [], ways_off: [] },
  { id: "ws-friends", name: "周末项目", role: "member", relays: [], ways_off: [] },
];

/// The records of the account a core keeps as it is told (by table and key, as `data.put` takes them): its `/v1/me`
/// (its workspaces, the relays), a new chat's picks as the device remembers them (choose.ts: the configurations it
/// started on most, the preset picked), what each station said of the workspaces it is in (views/memberships.ts), the
/// workspace's lock as its stations keep it (views/lock.ts), and its plain library of secrets with their uses
/// (views/vault.ts).
export function records(now: number): [string, string, unknown][] {
  const me = {
    user: { sub: "s1", email: PEOPLE[0].email, name: PEOPLE[0].name, beta: true }, workspaces: ACCOUNT_WORKSPACES,
    relay_url: RELAYS[0], relay_urls: RELAYS, relay_names: { [RELAYS[1]!]: "北京", [RELAYS[2]!]: "新加坡" },
  };
  // (the configurations new chats here started on most, choose.ts recordCombo: four at most are shown)
  const frequent = [
    ["claude-opus-5-5", "claude", "xhigh", 41], ["gpt-6-astra", "codex", "high", 23], ["claude-sonnet-5", "claude", "high", 12], ["swe-1.6", "devin", "high", 6], ["deepseek-v4", "dsh", "high", 3],
  ].map(([model, runtime, effort, count], i) => ({ model, runtime, effort, fast: null, context: null, count, last: now - (i + 1) * 3 * HOUR }));
  return [
    ["me", "s1", me],
    ["choice", "ws:ws:frequent", frequent],
    ["choice", "ws:ws:preset", { id: "p-app", station: "ws/maple" }],
    ["presetRecords", "ws", presetRecordsOf(now)],
    ...UP.map((at, st): [string, string, unknown] => ["memberships", at, { workspaces: [{ workspace: "ws", workspaceName: "Acme", name: STATIONS[st]!.name, home: true }], canJoin: true }]),
    ["lock", "ws", lockOf(now)],
    ["lockPending", "ws", pendingOf(now)],
    ["vault", "ws", vaultOf(now)],
  ];
}

/// What the workspace's stations say of its presets (their `presets` topic): two of the owner's, and the folders offered.
function presetsOf(now: number, station: number): J {
  const s = STATIONS[station]!;
  const repos = ["app", "station", "website", "infra", "design-system", "mobile"];
  return {
    presets: station === 0
      ? [
        { id: "p-app", name: "still.fail App", dirs: [{ path: `/Users/${s.host}/src/app`, repo: "github.com/acme/app" }, { path: `/Users/${s.host}/src/design-system`, repo: "github.com/acme/design-system" }], instructions: "改 UI 前先在 Pixel 8 和 iPhone 16 上各录一段前后对比；提交前跑 `pnpm test` 和 `pnpm exec tsgo --noEmit`。", createdBy: PEOPLE[0].email, createdAt: now - 20 * DAY, updatedAt: now - 2 * DAY },
        { id: "p-infra", name: "Infra", dirs: [{ path: `/Users/${s.host}/src/infra`, repo: "github.com/acme/infra" }], instructions: "生产环境的改动先在 staging 跑一遍，改动前在 #infra 说一声。", stations: ["maple", "willow"], model: { model: "claude-opus-5-5", runtime: "claude", effort: "high", profiles: ["claude-maple-0", "claude-maple-1"] }, createdBy: PEOPLE[1].email, createdAt: now - 41 * DAY, updatedAt: now - 9 * DAY },
      ]
      : [],
    candidates: repos.map((r, i) => ({ path: `/Users/${s.host}/src/${r}`, name: r, repo: `github.com/acme/${r}`, chats: 40 - i * 6, lastAt: now - (i + 1) * 5 * HOUR, where: `~/src/${r}` })),
    // (one being cloned, one that failed: a repository of the organisation's the person is not let into)
    clones: station === 0
      ? [
        { id: "c-docs", url: "https://github.com/acme/docs.git", repo: "github.com/acme/docs", name: "docs", state: "cloning", error: "", by: PEOPLE[0].email, startedAt: now - 40 * 1000 },
        { id: "c-billing", url: "git@github.com:acme/billing.git", repo: "github.com/acme/billing", name: "billing", state: "failed", error: "ERROR: Repository not found.\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.", by: PEOPLE[1].email, startedAt: now - 2 * HOUR },
      ]
      : [],
  };
}

/// The workspace's lock as its stations keep it (views/lock.ts `Held`): its genesis naming its members, their devices
/// (each a phone and a computer or two, a web page for some) and its stations, and when each device was last seen. Its
/// entries are not signed (the lock's view folds them as they are; views/vault.ts checks them, and keeps to its plain
/// library, unchecked).
/// What this device signed in the workspace's lock that no station took yet (src/lock-pending.ts), as many as are kept:
/// PENDING_MOST waiting (the bound on signing more) and as many failed (the bound on those kept), by the longest names.
function pendingOf(now: number): J {
  const at = Math.floor(now / 1000);
  const item = (i: number, state: "waiting" | "failed") => {
    const p = PEOPLE[i % PEOPLE.length]!;
    const name = `macos still.fail 桌面版 · ${p.name} 的 MacBook Pro`;
    const entry = { v: 1, ws: "ws", seq: 40, prev: `${i}`.padStart(64, "a"), at: at - i * 60, kind: "device.remove", body: { id: `dev-${p.sub}-mac` }, sig: { key: `sk-${PEOPLE[0].sub}-mac`, alg: "Ed25519", sig: "ab".repeat(64) } };
    const failed = state === "failed" ? (i % 2 === 0 ? { what: name } : { why: "the entry disagrees with this station's lock (a fork)" }) : {};
    return { id: `${state}${i}`.padEnd(64, "0"), entry, act: "removeDevice", name, at: now - i * 60_000, state, ...failed };
  };
  return { items: [...Array.from({ length: PENDING_MOST }, (_, i) => item(i, "waiting")), ...Array.from({ length: PENDING_MOST }, (_, i) => item(i + PENDING_MOST, "failed"))] };
}

/// What this device signed in its person's own lock that no station of theirs took yet, as many as are kept (as
/// `pendingOf`), each about a device none of the workspace's pending ones is about: the workspace's `lock` topic says
/// them after its own (views/lock.ts `ownPendingRows`).
export function ownPendingOf(now: number): Pending[] {
  const at = Math.floor(now / 1000);
  const item = (i: number, state: "waiting" | "failed"): Pending => {
    const p = PEOPLE[i % PEOPLE.length]!;
    const name = `android still.fail 手机版 · ${p.name} 的 Pixel 9 Pro XL`;
    const entry = { v: 1 as const, ws: "person:s1", seq: 12, prev: `${i}`.padStart(64, "b"), at: at - i * 60, kind: "device.remove", body: { key: `ed25519:${`${i}`.padStart(64, "c")}` }, sig: { key: `ed25519:${"d".repeat(64)}`, alg: "Ed25519" as const, sig: "ab".repeat(64) } };
    const failed = state === "failed" ? (i % 2 === 0 ? { what: name } : { why: "the entry disagrees with this station's lock (a fork)" }) : {};
    return { id: `${state}${i}`.padEnd(64, "1"), entry, act: "removeDevice", name, at: now - i * 60_000, state, ...failed };
  };
  return [...Array.from({ length: PENDING_MOST }, (_, i) => item(i, "waiting")), ...Array.from({ length: PENDING_MOST }, (_, i) => item(i + PENDING_MOST, "failed"))];
}

function lockOf(now: number): J {
  const secs = Math.floor(now / 1000);
  const devices = PEOPLE.flatMap((p, i) => [
    { id: `dev-${p.sub}-mac`, sub: p.sub, kind: "app", label: `macos still.fail 桌面版 · ${p.name} 的 MacBook Pro`, sign_key: `sk-${p.sub}-mac` },
    { id: `dev-${p.sub}-phone`, sub: p.sub, kind: "app", label: `${i % 2 === 0 ? "ios" : "android"} still.fail · ${p.name} 的${i % 2 === 0 ? " iPhone 16" : " Pixel 8"}`, sign_key: `sk-${p.sub}-phone` },
    ...(i % 3 === 0 ? [{ id: `dev-${p.sub}-web`, sub: p.sub, kind: "web", label: `web still.fail 网页版 · Chrome on ${p.name} 的台式机`, exp: secs + (i + 2) * 86400 }] : []),
  ]);
  const genesis = {
    seq: 1, prev: null, at: secs - 30 * 86400, by: "dev-s1-mac", kind: "genesis",
    body: {
      owner: "s1", origins: ["https://still.fail"], rp_id: "still.fail", cloud_keys: [],
      members: PEOPLE.map((p, i) => ({ sub: p.sub, email: p.email, role: i === 0 ? "owner" : i < 3 ? "admin" : "member" })),
      devices, passkeys: [], stations: STATIONS.map((s) => ({ key: s.id, name: s.name })), gateways: [],
    },
    sig: "",
  };
  return {
    head: { seq: 1, hash: "h-genesis", genesis: "h-genesis" }, entries: [genesis],
    seen: devices.map((d, j) => ({ base: d.id, last_seen: secs - (j * 7919) % (9 * 86400), label: d.label })),
  };
}

/// The workspace's plain library (views/vault.ts `Held`): some dozens of secrets on Maple, the agents' requests waiting,
/// and the uses of each as the stations said them (station/src/vault/secrets.ts `uses`, 500 at most a vault a station).
const SECRETS = ["GitHub token", "npm publish token", "Sentry auth token", "AWS staging", "AWS production (只读)", "Cloudflare API", "Slack bot token", "OpenAI key", "Apple App Store Connect", "Google Play 服务账号", "PostgreSQL staging", "PostgreSQL production", "Redis", "Stripe test key", "Feishu app secret", "Docker Hub", "1Password Connect", "Vercel", "Fastly purge", "Twilio"];
export const VAULT_ITEMS = 36;
export const VAULT_ITEM = "item-0";
function vaultOf(now: number): J {
  const secs = Math.floor(now / 1000);
  const hostsOf = (i: number) => [["api.github.com", "github.com", "uploads.github.com"], ["registry.npmjs.org"], ["sentry.io"], ["*.amazonaws.com"], ["api.cloudflare.com"], ["slack.com"]][i % 6]!;
  const plain = Object.fromEntries(Array.from({ length: VAULT_ITEMS }, (_, i) => {
    const name = i < SECRETS.length ? SECRETS[i]! : `${pick(SECRETS, i)} · ${pick(["备用", "CI", "个人"], i)}`;
    return [`item-${i}`, {
      id: `item-${i}`, owner: "s1", version: 1 + (i % 4), kind: i % 7 === 3 ? "file" : i % 5 === 1 ? "login" : "token", name, notes: i % 3 === 0 ? "轮换周期 90 天，过期前在 #infra 提醒" : "",
      listing: { name, kind: "token", modes: i % 4 === 0 ? ["proxy", "env"] : ["proxy"], hosts: hostsOf(i), env: i % 4 === 0 ? `${name.toUpperCase().replace(/[^A-Z]+/g, "_")}TOKEN` : null, lasts: pick(["once", "hour", "chat"], i) },
      at: now - (i + 1) * 2 * DAY, station: "maple",
    }];
  }));
  // (each of its most used items used by the agents many times, most of the rest now and then: 500 a station at most)
  const uses = (st: number): J[] => Array.from({ length: st === 0 ? 500 : 120 }, (_, u) => {
    const item = u % 3 === 0 ? 0 : u % 7;
    return {
      item: `item-${item}`, at: secs - u * 1800 - st * 600, session: `ember:${keyOf(st, u % ROWS_UP)}`, chatTitle: pick(TITLES, u + st),
      mode: item % 4 === 0 && u % 5 === 0 ? "env" : "proxy", command: u % 4 === 0 ? pick(["gh pr create --fill", "gh run watch", "npm publish", "aws s3 ls"], u) : null,
      hosts: u % 4 === 0 ? [] : hostsOf(item), denied: u % 41 === 7,
    };
  });
  const request = (i: number): J => ({
    id: `vr-${i}`, vault: "plain", item: `item-${i}`, session: keyOf(i % 4, i * 5 + 3), chat: pick(TITLES, i * 5 + 3), mode: "proxy", reason: "推送 PR 并打开 review", command: "gh pr create --fill",
    hosts: ["api.github.com", "github.com"], at: now - (i + 1) * 9 * MIN, status: "pending", timeout: { kind: "idle", seconds: 3600 },
  });
  return {
    vaults: {}, at: {}, boxes: {}, requests: Object.fromEntries([0, 1, 2].map((i) => [`vr-${i}`, request(i)])), asked: { "vr-0": "maple", "vr-1": "willow", "vr-2": "studio" }, refused: {},
    on: {}, keeps: [], hidden: {}, plain, plainOn: ["maple"], plainLasts: { lasts: "chat", at: now - 5 * DAY },
    uses: Object.fromEntries(UP.map((_, st) => [`${STATIONS[st]!.id}/plain`, uses(st)])),
  };
}

/// What the chat's agents and three other chats wrote each other (its `letters`, station/src/sessions/messages.ts): forty
/// letters, each way, as its own log keeps them.
export const LETTERS_COUNT = 40;
function lettersOf(now: number, count = LETTERS_COUNT): J[] {
  return Array.from({ length: count }, (_, k) => {
    const other = [12, 20, 33][k % 3]!;
    const title = pick(TITLES, other);
    const link = `https://still.fail/o/ws/maple/${keyOf(0, other)}`;
    const way = k % 2 === 0 ? "in" : "out";
    const body = words(k * 3 + 1);
    // (now and then one coming with a file, which its words place)
    const file = way === "in" && k % 8 === 0 ? `bench-${k}.png` : null;
    return {
      thread: CHAT.thread, n: k + 1, kind: "message", ts: `${CHAT.thread}.L${String(k + 1).padStart(5, "0")}`, authorKind: "agent", author: way === "in" ? keyOf(0, other) : CHAT.keys[0], authorName: null,
      text: `${way === "in" ? "来自" : "写给"} [${title}](${link})：\n\n${body}${file ? `\n\n![](${file})` : ""}`, at: now - (LETTERS_COUNT - k) * 40 * MIN, letter: { way, title, link },
      ...(file ? { attachments: [{ name: file, path: `.stillfail/uploads/L${k}-${file}`, size: 182_331 + k, width: 1600, height: 1000 }] } : {}),
    };
  });
}

/// The chat's station's connection as the device samples it (station/topics.ts `#sampleNet`): its last `NET_KEPT` samples
/// (`more`: that many samples on, each as before, the oldest gone).
export function netOf(now: number, more = 0): J {
  const at = now + more * 2000;
  const sample = (k: number) => ({ rttMs: 18 + ((k * 7) % 13) + 0.4, rxBps: 12_000 + ((k * 3331) % 90_000), txBps: 2_000 + ((k * 911) % 9_000), sent: 40, lost: k === 17 ? 1 : 0 });
  // (what the samples after the first counted, two seconds each)
  const rx = Array.from({ length: more }, (_, k) => 2 * sample(30 + k).rxBps).reduce((a, b) => a + b, 0);
  const tx = Array.from({ length: more }, (_, k) => 2 * sample(30 + k).txBps).reduce((a, b) => a + b, 0);
  return {
    path: "direct", relay: RELAYS[1], rttMs: more === 0 ? 23.4 : sample(29 + more).rttMs, rxBytes: 412_331_004 + rx, txBytes: 38_120_551 + tx,
    samples: Array.from({ length: 30 }, (_, i) => ({ at: at - (30 - i) * 2000, ...sample(i + more) })),
    measured: { measuring: false, relays: [{ relay: "direct", rttMs: 23 }, { relay: RELAYS[0], rttMs: 61 }, { relay: RELAYS[1], rttMs: 38 }, { relay: RELAYS[2], rttMs: 84 }, { relay: OWN_RELAY, rttMs: 47 }], moved: null },
    todayRxBytes: 1_204_331_004 + rx, todayTxBytes: 98_120_551 + tx, lan: ["192.168.1.20:52001", "10.8.0.3:52001", "[fe80::1c2a:3bff:fe4d:9a01]:52001"],
  };
}

/// The longest a job's log comes: what the station reads of its end (station/src/read/jobs.ts LOG_BYTES).
const LOG_BYTES = 64 * 1024;
/// The last `lines` lines of the chat's dev server's log, as `GET /jobs/:id/log` gives them (its colours kept): a test
/// runner's lines with their paths, so 400 of them reach the 64 KB the station reads. `more`: as it is that many lines
/// on, each line the same as before (its time too), those it printed after them under them, its first ones gone where
/// the station reads no more of it.
export function jobLogOf(now: number, lines: number, more = 0): J {
  const line = (k: number) => {
    const ok = k % 17 !== 5;
    const path = `src/${pick(["views", "station", "sync", "db", "shapes"], k)}/${pick(["views", "chat-tabs", "collections", "scheduler", "account", "conform"], k * 3)}.test.ts`;
    return `\u001b[2m${new Date(now - (lines - k) * 900).toISOString()}\u001b[22m ${ok ? "\u001b[32m✔" : "\u001b[33m↻"}\u001b[39m ${path} › ${pick(TITLES, k)} \u001b[2m(${(k * 37) % 900} ms, ${(k * 13) % 40} assertions)\u001b[22m`;
  };
  let text = Array.from({ length: lines }, (_, k) => line(k + more)).join("\n");
  while (new TextEncoder().encode(text).length > LOG_BYTES) text = text.slice(text.indexOf("\n") + 1);
  return { text, outputAt: now - 2000 + more * 900 };
}

/// A folder of the station's drive (its `/drive/list`): the Downloads of a machine used a year, a few hundred files.
export const DRIVE = { station: "ws/maple", root: "/Users/maple/Downloads", path: "" } as const;
export const DRIVE_ENTRIES = 420;
function driveOf(now: number): J {
  const kinds = ["pdf", "png", "zip", "dmg", "mov", "csv", "md", "jpg", "xlsx", "json"];
  const entries = Array.from({ length: DRIVE_ENTRIES }, (_, i) => {
    const dir = i < 24;
    const ext = pick(kinds, i * 7);
    const name = dir ? `${pick(["2026 Q3 报告", "screenshots", "build-artifacts", "设计稿", "invoice"], i)} ${i}` : `${pick(["Screenshot 2026-11-0", "release-notes-0.1.70", "监控截图 ", "export-", "IMG_"], i)}${(i * 7919) % 10_000}.${ext}`;
    return { name, dir, size: dir ? 0 : ((i * 104_729) % 80_000_000) + 1024, mtime: now - i * 37 * MIN, type: dir ? "dir" : "file" };
  });
  return { path: DRIVE.path, entries, truncated: false };
}

/// What the chat's station says of its screens (its `GET /screens`, station/src/screens/hub.ts `listed`): its display,
/// a tab of its browser the chat's agent opened and one of another chat's, who is on them.
export function screensOf(now: number): J {
  const views = (who: [string, string, string][]) => who.map(([name, device, app], i) => ({ id: `v-${name}-${i}`, name, device, app, at: now - (i + 1) * 4 * MIN, control: i === 0, ...(app === "agent" ? { agent: true } : {}) }));
  return {
    screens: [
      { id: "desktop", kind: "desktop", title: "Maple", width: 3456, height: 2234, viewers: ["左子健"], controlledBy: ["左子健"], views: views([["左子健", "still.fail 桌面版 · MacBook Pro", "desktop"]]), clipboard: ["text", "png"], drop: { folder: "/Users/maple/Downloads", reveal: true } },
      { id: "browser:T1", kind: "browser", title: "Pull request #5244 · acme/app", width: 1280, height: 800, viewers: ["修复 Android 上聊天列表滚动掉帧", "Lina Park"], controlledBy: ["修复 Android 上聊天列表滚动掉帧"], views: views([["修复 Android 上聊天列表滚动掉帧", "agent", "agent"], ["Lina Park", "still.fail · Pixel 8", "android"]]), clipboard: ["text"], peek: true, closable: true, openedBy: CHAT.keys[0], drop: { folder: "/Users/maple/Downloads", reveal: false } },
      { id: "browser:T2", kind: "browser", title: "Grafana · relay 1k 并发", width: 1440, height: 900, viewers: [], controlledBy: [], views: [], clipboard: ["text"], peek: true, closable: true, openedBy: keyOf(0, 30) },
    ],
    outdated: false,
  };
}

/// What else of the stations the pages read, by topic, at `now`: their presets, the device's list of its accounts'
/// workspaces, the chat's letters and its station's connection, its dev server's log as the app asks it, a folder of
/// its drive, a search's answers of each up station, the chat's tabs kept on this device.
export function more(now: number): [Topic, unknown][] {
  const out: [Topic, unknown][] = [];
  for (const [st, at] of UP.entries()) out.push([{ topic: "presets", station: at }, presetsOf(now, st)]);
  out.push([{ topic: "workspaces" }, [{ account: { sub: "s1", email: PEOPLE[0].email }, workspaces: ACCOUNT_WORKSPACES, invitations: [], relay_url: RELAYS[0], loaded: true }]]);
  out.push([{ topic: "workspace", workspace: OTHER_WORKSPACE.id }, { id: OTHER_WORKSPACE.id, name: OTHER_WORKSPACE.name, role: "owner", stations: OTHER_STATIONS.map((s) => ({ ...s, last_seen: Math.trunc(now / 1000) - 9 })), members: [{ sub: "s1", email: PEOPLE[0].email, name: PEOPLE[0].name, role: "owner" }] }]);
  out.push([{ topic: "letters", station: CHAT.station, thread: CHAT.thread }, { entries: chatPage(now).entries, letters: lettersOf(now), whole: true, thread: { ...threadOf(now, 0, 0), lettersLast: LETTERS_COUNT } }]);
  out.push([{ topic: "net", station: CHAT.station }, netOf(now)]);
  for (const lines of JOB_LOG_LINES) out.push([{ topic: "jobLog", station: CHAT.station, job: JOB, lines }, jobLogOf(now, lines)]);
  out.push([{ topic: "drive", ...DRIVE }, driveOf(now)]);
  out.push([{ topic: "prefs" }, { chatTabs: { [`${CHAT.station}:${CHAT.keys[0]}`]: { tabs: [CHAT.keys[0], "files", "letters", `service:job-maple-0`], active: CHAT.keys[0] } } }]);
  // (the pull request its agent's words link, as the station's preview of it says it)
  out.push([{ topic: "linkPreview", station: CHAT.station, url: "https://github.com/acme/app/pull/5244" }, { kind: "github_pull_request", url: "https://github.com/acme/app/pull/5244", repository: "acme/app", number: 5244, title: "Android：列表行高首帧算好，滚动不再重新测量", state: "open", author: { login: "lina-park" }, additions: 412, deletions: 187, changedFiles: 14, comments: 6, labels: ["android", "performance", "needs-review"], updatedAt: now - HOUR, checks: { passed: 23, failed: 0, pending: 2 } }]);
  for (const [st, at] of UP.entries()) out.push([{ topic: "stationSearch", station: at, q: SEARCH, limit: 6 }, searchOf(now, st)]);
  for (const [topic, value] of peeks(now)) out.push([topic, value]);
  return out;
}

/// Bytes made of `seed` alone, as base64: a picture's that is not one.
const noise = (n: number, seed: number) => {
  const b = new Uint8Array(n);
  let x = seed;
  for (let i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) >>> 0;
    b[i] = x >>> 24;
  }
  return Buffer.from(b).toString("base64");
};

/// The cards of what a message names, at the most their station sends: a page's preview with its icon and its picture
/// inline (station/src/links/preview.ts ICON_BYTES 48 KB, PICTURE_INLINE 192 KB: a picture under it as itself, a
/// plausible one of 160 KB), a picture a message names as the peek gives it (station/src/api/routes/sessions.ts
/// PEEK_IMAGE: itself up to 256 KB, the most), a text file's lines (PEEK_LINES of PEEK_LINE characters), a message of
/// another chat a link names (the core sends its words whole: a page of them).
export const PEEKS = {
  page: "https://www.anthropic.com/news/claude-opus-5-5",
  pull: "https://github.com/acme/app/pull/5244",
  picture: ".stillfail/uploads/bench-full.png",
  text: "src/views/views.ts",
  message: { thread: threadIdOf(0, 12), seq: 41 },
} as const;
function peeks(now: number): [Topic, unknown][] {
  const at = CHAT.station;
  const key = CHAT.keys[0];
  return [
    [{ topic: "linkPreview", station: at, url: PEEKS.page }, { kind: "page", url: PEEKS.page, title: "Introducing Claude Opus 5.5", description: "Our most capable model yet for coding, agents and long-running work, with a context window of a million tokens and better judgment about when to ask.", site: "Anthropic", icon: `data:image/png;base64,${noise(6 * 1024, 1)}`, image: `data:image/jpeg;base64,${noise(160 * 1024, 2)}` }],
    [{ topic: "filePeek", station: at, key, path: PEEKS.picture }, { path: `/Users/maple/.stillfail/sessions/chat/${key}/workspace/${PEEKS.picture}`, name: "bench-full.png", size: 256 * 1024, mtime: now - HOUR, type: "image/png", kind: "image", image: { type: "image/png", data: noise(256 * 1024, 3) } }],
    [{ topic: "filePeek", station: at, key, path: PEEKS.text }, { path: `/Users/maple/src/app/${PEEKS.text}`, name: "views.ts", size: 212_331, mtime: now - 2 * HOUR, type: "text/plain", kind: "text", lines: { start: 1, text: Array.from({ length: 12 }, (_, i) => `${"  ".repeat(i % 4)}${pick(LINES, i)}`.slice(0, 240) + (i % 3 === 0 ? "…" : "")) } }],
    [{ topic: "messagePeek", station: at, thread: PEEKS.message.thread, seq: PEEKS.message.seq }, { entries: [{ thread: PEEKS.message.thread, n: PEEKS.message.seq, kind: "message", ts: `${PEEKS.message.thread}.${PEEKS.message.seq}`, authorKind: "agent", author: keyOf(0, 12), authorName: null, text: LONG.join("\n\n"), at: now - 5 * HOUR }], end: true }],
  ];
}

/// The job whose log the app shows (the chat's dev server), and the ways it asks it: its last line (the job's row), the
/// sheet's 300 (`job_output_most`), the desktop's 400 (`job_output_lines`).
export const JOB = "job-maple-0";
export const JOB_LOG_LINES = [1, 300, 400];
/// What the search asks.
export const SEARCH = "迁移";

/// What up station `st` answers a search for `SEARCH` (its `GET /search`, station/src/search/sources.ts): a chat and a
/// message that have the words, a job.
function searchOf(now: number, st: number): J {
  const chat = 10;
  const message = 17;
  return {
    building: false,
    groups: [
      { kind: "chat", more: false, hits: [{ kind: "chat", key: `c:${threadIdOf(st, chat)}`, title: pick(TITLES, chat + st * 3), text: "…加了组合索引后从 2.3s 降到 18ms，迁移脚本在 PR 里。", at: now - HOUR, thread: threadIdOf(st, chat), chat: keyOf(st, chat), chatTitle: pick(TITLES, chat + st * 3), surface: "ember", archived: false }] },
      { kind: "message", more: false, hits: [{ kind: "message", key: `m:${threadIdOf(st, message)}:57`, title: "", text: "需要人工确认：生产库迁移要停写大约 4 分钟，什么时候可以做？", at: now - 2 * HOUR, thread: threadIdOf(st, message), seq: 57, chat: keyOf(st, message), chatTitle: pick(TITLES, message + st * 3), surface: "ember", archived: false, authorKind: "agent", author: keyOf(st, message) }] },
      { kind: "job", more: false, hits: [{ kind: "job", key: `j:job-${STATIONS[st]!.id}-mig`, title: "迁移演练 dry-run", text: "迁移演练：./scripts/migrate.sh --dry-run --from pg15", at: now - 3 * HOUR, job: `job-${STATIONS[st]!.id}-mig`, session: keyOf(st, 0), chat: keyOf(st, 0), state: "running" }] },
    ],
  };
}
