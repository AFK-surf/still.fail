// A workspace at the size of a real one, for what the core sends of it to be measured (topic-bytes.test.ts): the
// owner's workspace as his phone reported it, 2026-11-10. Five stations (four up, one down), whose `stations` came to
// 463,533 bytes: each station's models 295,504 in all (the accounts that run them 252,287), its overview 153,336 (its
// profiles 97,199, their checks 23,601, its automatic decisions 28,262). Eight profiles a station bring those within a
// little of the phone's (topic-bytes.test.ts prints the two side by side), over the account kinds people have:
// Claude's and ChatGPT's subscriptions with their allowances and a done check, Devin, DeepSeek, and in turn
// OpenRouter, an Anthropic key, OpenCode Go, SuperGrok, Cursor. With them connects, Slack apps, automatic decisions
// with a policy, the machine's own logins and a host reading; some 400 chats across the stations with their titles,
// last lines and people; one chat of 300 messages of every length; a week of usage, the jobs at work, the archive.
// Every family of fields is filled as a station fills it, none made larger than a station makes it. Made of the
// test's clock and indexes alone: the same every run.
import type { Topic } from "../src/protocol.ts";
import { localDay } from "../src/views/usage.ts";
import { hostOf, link, overview, rows, sessions, threads, workspace } from "./views-rig.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

/// The workspace's stations: the last one down (its overview from before kept, its chats out of the lists).
export const STATIONS = [
  { id: "maple", name: "Maple", host: "maple", cpu: "Apple M4 Max", cpus: 16, memGb: 128, emoji: "🍁" },
  { id: "willow", name: "Willow", host: "willow-mini", cpu: "Apple M4 Pro", cpus: 14, memGb: 64, emoji: "🌳" },
  { id: "studio", name: "Studio", host: "studio", cpu: "Apple M3 Ultra", cpus: 28, memGb: 192, emoji: "🎛️" },
  { id: "cedar", name: "Cedar", host: "CEDAR-WIN", cpu: "Intel Core Ultra 9 285K", cpus: 24, memGb: 64, emoji: null },
  { id: "ash", name: "Ash", host: "ash-old-mbp", cpu: "Apple M1 Pro", cpus: 10, memGb: 32, emoji: null },
] as const;
/// How many of them are up: the first ones.
const UP_COUNT = 4;
export const UP = STATIONS.slice(0, UP_COUNT).map((s) => `ws/${s.id}`);
export const DOWN = `ws/${STATIONS[UP_COUNT].id}`;
export const address = (i: number) => `ws/${STATIONS[i]!.id}`;

/// The chat of 300 messages: its station, its thread, its two agents.
export const CHAT = { station: "ws/maple", thread: 1001, keys: ["k-maple-0", "k-maple-0b"] } as const;
/// A chat of each up station's sidebar: their rows, then the archive's, by station.
const ROWS_UP = 100;
const ROWS_DOWN = 20;
const ARCHIVED = 60;

const pick = <T>(pool: readonly T[], i: number): T => pool[((i % pool.length) + pool.length) % pool.length]!;

// ── people ──

export const PEOPLE = [
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
    detail: null,
    checkedAt: now - 4 * MIN,
  };
}

function codexQuota(now: number, i: number): J {
  return {
    state: "ok",
    plan: i % 3 === 0 ? "pro" : "plus",
    credits: { hasCredits: i % 2 === 0, unlimited: false, balance: i % 2 === 0 ? String(120 - i * 7) : "0" },
    windows: [window("5 小时", i === 3 ? 100 : (i * 19) % 95, now + (1 + (i % 4)) * HOUR + 33 * MIN), window("每周", (i * 13) % 85 + 5, now + (2 + (i % 5)) * DAY + 11 * HOUR)],
    resetCount: i % 3,
    resetExpiries: Array.from({ length: i % 3 }, (_, k) => now + (5 + k) * DAY),
    resets: i % 3 === 0 ? [] : [{ id: `r-${i}-s`, kind: "session", left: 1, usable: true }, { id: `r-${i}-w`, kind: "weekly", left: (i % 3) - 1, usable: false }],
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
  const shared = (users: number): J => ({ share: { id: `share-${id}`, role: "host", host: STATIONS[station]!.id, users: Array.from({ length: users }, (_, j) => pick(STATIONS, station + j + 1).id) } });
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
        model: "anthropic/claude-sonnet-5", models: ROUTER_MODELS, named: ROUTER_MODELS.slice(0, 4), loginCommand: "",
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
const KINDS: [string, number][] = [["claude", 3], ["codex", 2], ["devin", 1], ["dsh", 1]];
const OTHERS = ["openrouter", "anthropic", "opencode", "grok", "cursor"];
export function profilesOf(now: number, station: number): J[] {
  const out: J[] = [];
  const kinds: [string, number][] = [...KINDS, [pick(OTHERS, station), 1]];
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
    createdBy: { id: pick(PEOPLE, station + n).email, name: pick(PEOPLE, station + n).name }, sessions: 30 + station * 7 + n * 3, session: n === 2 ? `k-${s.id}-3` : null,
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
      { runtime: "claude", installed: true, loggedIn: true, email: PEOPLE[station].email, plan: "max_20x", usable: true, quota: claudeQuota(now, station + 30), text: `Claude Code 已登录：${PEOPLE[station].email}（Max 20x）` },
      station !== 2
        ? { runtime: "codex", installed: true, loggedIn: true, email: PEOPLE[station + 1].email, plan: "pro", usable: true, quota: codexQuota(now, station + 30), text: `Codex 已登录：${PEOPLE[station + 1].email}（Pro）` }
        : { runtime: "codex", installed: true, loggedIn: false, usable: true, text: "Codex 未登录" },
    ],
    sharing: true,
    consoleSignIn: true,
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
    ...(mac ? { permissions: { grants: [["capture", "屏幕录制"], ["control", "辅助功能"], ["documents", "文稿"], ["desktop", "桌面"], ["downloads", "下载"], ["localNetwork", "本地网络"]].map(([id, name], j) => ({ id, name, line: `允许 still.fail Helper 使用${name}`, granted: j !== 3, asking: false })), canRequest: true } } : {}),
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
  };
}

/// A session as a station lists it (its `GET /sessions`).
function sessionOf(now: number, station: number, key: string, i: number): J {
  const a = agentOf(now, key, i);
  return {
    key, connect: i % 4 === 1 ? "c-slack-1" : "ember", scope: "thread", title: null, createdBy: person(i + station).id, boundTo: [], creator: person(i + station), participants: [person(i + 2)],
    runtime: a.runtime, profile: a.runtime === "codex" ? `codex-${STATIONS[station]!.id}-${i % 3}` : `claude-${STATIONS[station]!.id}-${i % 3}`, profilePinned: false, model: a.model, effort: a.effort, fast: false,
    runtimeSessionId: `rs-${key}`, contextActions: ["compact", "clear"], workspace: `/Users/${STATIONS[station]!.host}/.stillfail/sessions/chat/${key}/workspace`, running: a.process === "running",
    createdAt: now - (i * 41 + 70) * MIN, lastActiveAt: now - (i * 41 + 1) * MIN, archivedAt: null, process: a.process, turns: 3 + (i % 17), pending: 0, firstText: pick(MEDIUM, i), lastTurn: a.lastTurn,
  };
}

const rowsCount = (station: number) => (station < UP_COUNT ? ROWS_UP : ROWS_DOWN);

// ── the chat of 300 messages ──

const CHAT_MESSAGES = 300;

function entryOf(now: number, n: number): J {
  const agent = n % 2 === 0;
  const key = n % 10 === 4 ? CHAT.keys[1] : CHAT.keys[0];
  const by = pick(PEOPLE, n % 4 === 1 ? 1 : 0);
  return {
    thread: CHAT.thread, n, kind: "message", ts: `${CHAT.thread}.${String(n).padStart(6, "0")}`, authorKind: agent ? "agent" : "person", author: agent ? key : by.email, authorName: agent ? null : by.name,
    text: words(n), at: now - (CHAT_MESSAGES - n + 1) * 7 * MIN,
    ...(n % 23 === 0 ? { attachments: [{ name: `screenshot-${n}.png`, path: `.stillfail/uploads/${n}-screenshot.png`, size: 248_113 + n, width: 1170, height: 2532, thumbhash: "3OcRJYB4d3h/iIeHeEh3eIhw+j3A" }] } : {}),
  };
}

export function chatPage(now: number, count = CHAT_MESSAGES): J {
  return { first: 1, last: count, entries: Array.from({ length: count }, (_, i) => entryOf(now, i + 1)), end: true, thread: null };
}

function detailOf(now: number, key: string, i: number): J {
  return {
    session: sessionOf(now, 0, key, i),
    threads: [threadOf(now, 0, 0)],
    turns: Array.from({ length: 40 }, (_, t) => ({ id: `turn-${key}-${t}`, kind: "chat", outcome: "done", declared: "final", ending: "all_done", detail: null, startedAt: now - (40 - t) * 30 * MIN, endedAt: now - (40 - t) * 30 * MIN + 9 * MIN })),
  };
}

function liveOf(now: number): J {
  const tools = ["Bash", "Read", "Edit", "Grep", "mcp__stillfail__chat_post"];
  const timeline: J[] = [];
  for (let i = 0; i < 160; i++) {
    const at = new Date(now - (160 - i) * MIN).toISOString();
    if (i % 4 === 0) timeline.push({ at, kind: "user", text: words(i) });
    else if (i % 4 === 1) timeline.push({ at, kind: "thinking", text: pick(MEDIUM, i) });
    else if (i % 4 === 2) timeline.push({ at, kind: "tool_call", text: i % 8 === 2 ? "pnpm exec tsgo --noEmit && node --test test/views.test.ts" : `src/views/views.ts`, tool: pick(tools, i), callId: `call-${i}` });
    else timeline.push({ at, kind: "tool_result", text: i % 8 === 3 ? "✔ 311 tests passed (14.2s)" : pick(LINES, i).slice(0, 160), tool: pick(tools, i - 1), ok: true, callId: `call-${i - 1}` });
  }
  return {
    loaded: true, first: 1, timeline, steps: [],
    usage: { modelCalls: 412, inputTokens: 8_412_330, cachedTokens: 7_901_002, outputTokens: 211_430, model: "claude-opus-5-5", contextTokens: 143_211, contextWindow: 1_000_000, cost: 31.42, lastCallAt: now - 3 * MIN, cacheMs: 300_000, rereadCost: 2.7 },
  };
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
      });
    }
  }
  return { rows, since: now - 30 * DAY, reading: false };
}

function jobsOf(now: number, station: number): J[] {
  return Array.from({ length: 6 }, (_, j) => ({
    id: `job-${STATIONS[station]!.id}-${j}`, session: keyOf(station, j * 3), name: pick(["dev server", "watch CI #5244", "storybook", "e2e soak", "tail prod logs", "benchmark"], j),
    state: j === 5 ? "exited" : "running", port: j === 0 ? 5173 : j === 2 ? 6006 : null, exitCode: j === 5 ? 0 : null, startedAt: now - (j + 1) * 5 * HOUR, endedAt: j === 5 ? now - HOUR : null,
    command: pick(["pnpm dev --host 127.0.0.1", "gh run watch 11234567 --exit-status", "pnpm storybook -p 6006", "./e2e/run.sh mac --loop", "kubectl logs -f deploy/api", "node bench/scroll.ts"], j),
    restarts: j === 2 ? 1 : 0, notices: j === 1 ? [{ at: now - 20 * MIN, text: "CI 绿了：check-mbui native 5 分 12 秒" }] : [], watch: j === 1, outputAt: now - (j + 1) * MIN,
  }));
}

function resourcesOf(now: number, station: number): J {
  const use = (cpu: number, mem: number) => ({ cpu, memory: mem, netIn: 1200 * cpu, netOut: 300 * cpu, diskRead: 4096 * cpu, diskWrite: 2048 * cpu });
  return {
    at: now, counted: true, net: true, disk: true, everyMs: 5000, machine: { cores: STATIONS[station]!.cpus, memory: STATIONS[station]!.memGb * 1024 ** 3 },
    total: use(84.2, 6.1 * 1024 ** 3),
    history: Array.from({ length: 36 }, (_, i) => ({ at: now - (36 - i) * 5000, ...use(60 + (i % 7) * 4, 5.8 * 1024 ** 3) })),
    chats: Object.fromEntries(Array.from({ length: 6 }, (_, i) => [keyOf(station, i), { thread: threadIdOf(station, i), title: pick(TITLES, i + station) }])),
    groups: Array.from({ length: 8 }, (_, g) => ({
      key: g < 6 ? `chat:${keyOf(station, g)}` : g === 6 ? "station" : "agents", ...(g < 6 ? { session: keyOf(station, g) } : {}),
      processes: Array.from({ length: 3 }, (_, p) => ({ pid: 50000 + station * 1000 + g * 10 + p, name: pick(["node", "claude", "codex", "esbuild", "tsgo", "git"], g + p), endable: g < 6, ...use(3 + g + p, (200 + g * 40) * 1024 ** 2) })),
    })),
  };
}

// ── all of it, as the stations' topics hold it ──

/// Each topic of the workspace with what it holds: what `set` puts in the rig, in an order a core could have it come.
export function fixture(now: number): [Topic, unknown][] {
  const out: [Topic, unknown][] = [];
  out.push([workspace(), {
    id: "ws", name: "Acme", role: "owner",
    stations: STATIONS.map((s, i) => ({ id: s.id, name: s.name, last_seen: Math.trunc(now / 1000) - (i < UP_COUNT ? 5 : 3 * 86400), version: "0.1.7018", ...(s.emoji ? { emoji: s.emoji } : {}) })),
    members: PEOPLE.map((p, i) => ({ sub: p.sub, email: p.email, name: p.name, role: i === 0 ? "owner" : i < 3 ? "admin" : "member", picture: i % 2 === 0 ? slackPicture(i) : "" })),
  }]);
  for (let st = 0; st < STATIONS.length; st++) {
    const at = address(st);
    const up = st < UP_COUNT;
    out.push([link(at), up ? { state: "online" } : { state: "offline", message: "连不上这台 station：它可能关机了", last: "offline" }]);
    out.push([overview(at), overviewOf(now - (up ? 0 : 3 * DAY), st)]);
    if (up) out.push([hostOf(at), hostReading(now, st)], [{ topic: "way", station: at }, { via: st % 2 === 0 ? "direct" : "relay", rttMs: 18 + st * 9 }]);
    const n = rowsCount(st);
    const keys = Array.from({ length: n }, (_, i) => keyOf(st, i));
    if (st === 0) keys.push(CHAT.keys[1]);
    out.push([sessions(at), keys.map((k, i) => sessionOf(now, st, k, i))]);
    out.push([threads(at), Array.from({ length: n }, (_, i) => threadOf(now, st, i))]);
    out.push([rows(at), Array.from({ length: n }, (_, i) => rowOf(now, st, i))]);
    out.push([{ topic: "archivedRows", station: at }, Array.from({ length: ARCHIVED }, (_, i) => rowOf(now, st, i, true))]);
    if (up) {
      out.push([{ topic: "stationUsage", station: at }, usageOf(now, st)]);
      out.push([{ topic: "jobs", station: at }, jobsOf(now, st)]);
      out.push([{ topic: "stationResources", station: at }, resourcesOf(now, st)]);
    }
  }
  out.push([{ topic: "thread", station: CHAT.station, thread: CHAT.thread }, chatPage(now)]);
  for (const [i, key] of CHAT.keys.entries()) {
    out.push([{ topic: "session", station: CHAT.station, key }, detailOf(now, key, i)]);
    out.push([{ topic: "live", station: CHAT.station, key }, liveOf(now)]);
  }
  return out;
}

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

/// What the chat's station tells as one more message comes at `at` (the workspace made at `base`): its page, its
/// thread and its row.
export function messageAdded(base: number, at: number): [Topic, unknown][] {
  const page = chatPage(base);
  const n = CHAT_MESSAGES + 1;
  const entry = { ...entryOf(base, n), text: "好的，我先跑一遍测试再合。", at };
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
