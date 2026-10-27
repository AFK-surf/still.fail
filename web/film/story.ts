// The promo film's world, in place of the site demo's story (vite.film.config.ts swaps it in for src/demo/story.ts):
// one person's workspace of four machines. From the phone they ask the chat on the Mac at home to fix a button; its
// agent fixes it and opens a chat on each of the other three machines (Studio builds Android, the Windows desktop
// installs it, the cloud runs the tests); their answers come back to the first chat, which asks to merge; the person
// taps 合并 on the phone and it is merged.
//
// Every pane of the film (?pane=…) plays the same world on the same clock (the recorder's, from the moment the page
// opens) and shows its own chat; the phone's pane is the one the recorder types and taps in (record.mjs).
import { addItem, groupOf, marked, message, posted, received, said, step, type DemoChat, type Who } from "../src/demo/fixtures.ts";
import type { Attachment, HistoryStep, Person } from "../src/core/shapes.ts";
import { ASK, TIMES } from "./times.ts";

export interface Stage {
  chats: DemoChat[];
  publish(): void;
  open(key: string): void;
}

const ANTHROPIC = { id: "anthropic", name: "Anthropic" };
const OPENAI = { id: "openai", name: "OpenAI" };
const OPUS = { runtime: "claude" as const, model: "claude-opus-5-5", name: "Opus 5.5", effort: "medium", maker: ANTHROPIC };
const SONNET = { runtime: "claude" as const, model: "claude-sonnet-5-5", name: "Sonnet 5.5", effort: "medium", maker: ANTHROPIC };
const GPT = { runtime: "codex" as const, model: "gpt-5.5", name: "GPT-5.5", effort: "high", maker: OPENAI };

/** The chats, by key; the first is the one asked from the phone (the key the demo opens on). */
export const MAIN = "ember:c-demo-safari";
export const STUDIO = "ember:c-film-studio";
export const WIN = "ember:c-film-win";
export const CLOUD = "ember:c-film-cloud";

/** The machine each chat is on, as the app names it. */
export const MACHINE: Record<string, string> = {
  [MAIN]: "家里的 Mac", [STUDIO]: "Studio", [WIN]: "Win 台式机", [CLOUD]: "云主机",
  "ember:c-film-home": "家里的 Mac", "ember:c-film-blog": "云主机", "ember:c-film-week": "Studio",
};
export const MACHINES = ["家里的 Mac", "Studio", "Win 台式机", "云主机"];

/** Which chat a pane shows. */
export const PANE_CHAT: Record<string, string> = { phone: MAIN, home: MAIN, studio: STUDIO, win: WIN, cloud: CLOUD };

/** The pictures the agents took (made by record.mjs into shots/), as the chats attach them. */
export const SHOTS: Record<string, Attachment> = {
  android: { name: "android-登录页.png", path: "/Users/you/shots/android-登录页.png", size: 182_000, width: 720, height: 1480 },
  windows: { name: "windows-登录页.png", path: "/Users/you/shots/windows-登录页.png", size: 214_000, width: 1280, height: 860 },
  mac: { name: "mac-登录页.png", path: "/Users/you/shots/mac-登录页.png", size: 196_000, width: 1280, height: 860 },
  all: { name: "三端-登录页.png", path: "/Users/you/shots/三端-登录页.png", size: 420_000, width: 1800, height: 1000 },
};

const MINUTE = 60_000;
const ME: Who = "me";

function chatOf(key: string, thread: number, title: string, model: DemoChat["model"], extra: Partial<DemoChat> = {}): DemoChat {
  return { key, thread, title, model, people: [], messages: [], outbox: [], items: [], running: null, blocked: false, failed: false, unread: false, ...extra };
}

function history(chat: DemoChat, lines: [Who, string, number][]): DemoChat {
  for (const [by, text, minutes] of lines) {
    chat.messages = [...chat.messages, message(chat, by, text, Date.now() - minutes * MINUTE)];
    if (by === "agent") { addItem(chat, posted(chat, text)); addItem(chat, marked("完成", "done")); }
  }
  return chat;
}

/** The workspace as the film opens: the chat on the Mac at home with yesterday's work in it, and a few others. */
export function openingChats(): DemoChat[] {
  return [
    history(chatOf(MAIN, 9, "Acme App", OPUS), [
      [ME, "首页的加载动画换成骨架屏", 60 * 15],
      ["agent", "换好了：首页三块内容都先出骨架，数据到了再换上，已合进 main（`7c1e0a2`）。", 60 * 14.6],
    ]),
    history(chatOf("ember:c-film-week", 8, "每周依赖升级", SONNET), [
      [ME, "这周的依赖升级跑一下", 60 * 20],
      ["agent", "23 个包都升好了，测试通过，PR 在 `chore/deps-w43`。", 60 * 19.5],
    ]),
    history(chatOf("ember:c-film-blog", 7, "博客改版", GPT), [
      [ME, "博客列表页改成两列", 60 * 26],
      ["agent", "改好了，窄屏下自动变回一列。", 60 * 25.8],
    ]),
    history(chatOf("ember:c-film-home", 6, "整理照片备份", SONNET), [
      [ME, "把 NAS 上重复的照片找出来", 60 * 30],
      ["agent", "找到 1,284 张重复的，列表在 `dupes.csv`，没有删任何东西。", 60 * 29],
    ]),
  ];
}

// ---- What happens, by when (ms from the page opening) ----

/** One tool call: running from `at`, done `ms` later. */
interface Call { at: number; ms: number; activity: string; step: HistoryStep }
const call = (at: number, ms: number, activity: string, name: string, hint: string, input: object, result: string): Call => ({
  at, ms, activity, step: step(name, hint, input, result, ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`),
});


const SENT_AT = TIMES.send + 450;

const MAIN_CALLS: Call[] = [
  call(6100, 600, "搜索 LoginButton", "Grep", "LoginButton", { pattern: "LoginButton", path: "src" }, "src/auth/LoginForm.tsx:38:  <LoginButton />"),
  call(6900, 500, "读取 src/auth/login.css", "Read", "src/auth/login.css", { file_path: "src/auth/login.css" }, ".submit { color: #1a1a1a; background: #202124; }"),
  call(7600, 500, "编辑 src/auth/login.css", "Edit", "src/auth/login.css", { file_path: "src/auth/login.css", old_string: "color: #1a1a1a; background: #202124;", new_string: "color: var(--on-primary); background: var(--primary);" }, "The file has been updated."),
  call(8500, 700, "在 Studio 上开对话", "chat_create", "Studio · 安卓上验证登录按钮", { station: "Studio", title: "安卓上验证登录按钮" }, "已开对话「安卓上验证登录按钮」"),
  call(9400, 700, "在 Win 台式机上开对话", "chat_create", "Win 台式机 · Windows 上验证登录按钮", { station: "Win 台式机", title: "Windows 上验证登录按钮" }, "已开对话「Windows 上验证登录按钮」"),
  call(10300, 700, "在云主机上开对话", "chat_create", "云主机 · 跑全部测试", { station: "云主机", title: "跑全部测试" }, "已开对话「跑全部测试」"),
];

const OPENED: { key: string; at: number; thread: number; title: string; model: DemoChat["model"]; ask: string }[] = [
  { key: STUDIO, at: 9200, thread: 10, title: "安卓上验证登录按钮", model: SONNET, ask: "在安卓上编译 `fix/login-button`，装到模拟器上，浅色、深色各截一张登录页。" },
  { key: WIN, at: 10100, thread: 11, title: "Windows 上验证登录按钮", model: GPT, ask: "在 Windows 上编译 `fix/login-button`，装上新版，截一张登录页。" },
  { key: CLOUD, at: 11000, thread: 12, title: "跑全部测试", model: SONNET, ask: "在 `fix/login-button` 上跑全部单元测试和登录页的 e2e。" },
];

const WORK: Record<string, { calls: Call[]; answer: string; at: number; shot?: Attachment }> = {
  [STUDIO]: {
    calls: [
      call(10400, 900, "运行 git switch", "Bash", "git switch fix/login-button", { command: "git fetch && git switch fix/login-button" }, "Switched to branch 'fix/login-button'"),
      call(11500, 3600, "运行 gradlew assembleDebug", "Bash", "./gradlew assembleDebug", { command: "./gradlew assembleDebug" }, "BUILD SUCCESSFUL in 41s"),
      call(15300, 1200, "运行 adb install", "Bash", "adb install -r app-debug.apk", { command: "adb install -r app/build/outputs/apk/debug/app-debug.apk" }, "Success"),
      call(16700, 1500, "截图 登录页 浅色 / 深色", "Bash", "adb shell screencap", { command: "adb exec-out screencap -p > login-light.png && adb shell cmd uimode night yes && adb exec-out screencap -p > login-dark.png" }, "saved login-light.png, login-dark.png"),
    ],
    answer: "安卓上编好、装好了：浅色和深色下按钮都看得清，截图在这。", at: 19400, shot: SHOTS.android,
  },
  [WIN]: {
    calls: [
      call(11300, 900, "运行 git pull", "Bash", "git pull", { command: "git pull && git switch fix/login-button" }, "Already up to date."),
      call(12400, 3800, "运行 pnpm build:win", "Bash", "pnpm build:win", { command: "pnpm build:win" }, "dist\\Acme-Setup-2.4.0.exe"),
      call(16400, 1600, "安装 Acme-Setup-2.4.0.exe", "Bash", ".\\dist\\Acme-Setup-2.4.0.exe /S", { command: ".\\dist\\Acme-Setup-2.4.0.exe /S" }, "installed"),
      call(18200, 1300, "截图 登录页", "Bash", "screenshot --window Acme", { command: "screenshot --window Acme --out login.png" }, "saved login.png"),
    ],
    answer: "Windows 上装好新版了，登录按钮看得清，截图在这。", at: 21400, shot: SHOTS.windows,
  },
  [CLOUD]: {
    calls: [
      call(12100, 1100, "运行 pnpm install", "Bash", "pnpm install", { command: "pnpm install --frozen-lockfile" }, "Done in 6.2s"),
      call(13400, 3600, "运行 pnpm test", "Bash", "pnpm test", { command: "pnpm test" }, "Tests: 312 passed, 312 total"),
      call(17200, 1800, "运行 pnpm e2e login", "Bash", "pnpm e2e login", { command: "pnpm e2e login --browsers chromium,webkit" }, "24 passed (2 browsers)"),
    ],
    answer: "312 个单元测试和登录页的 24 个 e2e 全过。", at: 19800,
  },
};

const MAIN_THOUGHT = "按钮的字和底色都写死成深色，深色模式下整个按钮看不见。改成跟着主题走的颜色，再让三台机器分头验证。";
const MAIN_ANSWER = "三端都改好了：登录按钮改成跟着主题走的颜色。\n\n- 安卓（Studio）：浅色、深色都看得清\n- Windows（Win 台式机）：装好新版，看得清\n- 测试（云主机）：312 个单元测试、24 个 e2e 全过\n\n合进 main 吗？";
const MERGED = "已合进 main（`4f2a9c1`），测试版正在发。";

/** What a chat's turn shows while it runs its calls. */
function playCalls(at: (ms: number, f: () => void) => void, chat: () => DemoChat, calls: Call[], publish: () => void) {
  const done: HistoryStep[] = [];
  let slot = -1;
  for (const c of calls) {
    at(c.at, () => {
      const x = chat();
      x.running = { ...(x.running ?? { since: Date.now(), started: true }), activity: c.activity };
      const { result: _, ...pending } = c.step;
      const body = groupOf([...done, pending], 1);
      if (slot < 0) { slot = x.items.length; addItem(x, body); } else x.items = x.items.map((item, i) => (i === slot ? { ...item, body } : item));
      publish();
    });
    at(c.at + c.ms, () => {
      const x = chat();
      done.push(c.step);
      x.items = x.items.map((item, i) => (i === slot ? { ...item, body: groupOf(done, 0) } : item));
      publish();
    });
  }
}

/** The film's story: its world played from the page opening. `pane`: the chat this page shows. */
export function makeStory(stage: Stage) {
  const pane = new URLSearchParams(location.search).get("pane") ?? "home";
  const own = PANE_CHAT[pane] ?? MAIN;
  const at = (ms: number, f: () => void) => setTimeout(f, ms);
  const chat = (key: string) => stage.chats.find((c) => c.key === key)!;
  const main = () => chat(MAIN);
  const { publish } = stage;

  // The phone's message, there on every pane (the phone's own pane put it on its way as it was sent: film/main.tsx).
  at(SENT_AT, () => {
    const c = main();
    c.outbox = [];
    c.messages = [...c.messages, message(c, ME, ASK)];
    addItem(c, received(c, { id: "you", name: "你", via: "cloud", shown: { name: "你", display: "你", mine: true } } as Person, ASK));
    publish();
  });
  at(SENT_AT + 450, () => { main().running = { activity: "思考中", since: Date.now(), started: true }; publish(); });
  playCalls(at, main, MAIN_CALLS, publish);

  // The three chats it opens, each on its machine, its agent at work at once.
  for (const o of OPENED) {
    at(o.at, () => {
      const c = chatOf(o.key, o.thread, o.title, o.model);
      const m = message(c, "agent", o.ask);
      c.messages = [{ ...m, authorKind: "agent", author: MAIN, by: { name: "Acme App · 家里的 Mac", agent: MAIN, maker: ANTHROPIC, runtime: "claude", from: `https://still.fail/chats/${MAIN}` } }];
      addItem(c, received(c, { id: "home", name: "Acme App · 家里的 Mac", via: "cloud", shown: { name: "Acme App", display: "Acme App", mine: false } } as Person, o.ask.replace(/`/g, "")));
      c.running = { activity: "思考中", since: Date.now(), started: true };
      stage.chats.unshift(c);
      publish();
      if (own === o.key) stage.open(o.key);
    });
    const w = WORK[o.key]!;
    // Its turn ends a moment after its answer is out, as a station's does.
    at(w.at + 900, () => { const c = chat(o.key); addItem(c, marked("完成", "done")); c.running = null; publish(); });
    playCalls(at, () => chat(o.key), w.calls, publish);
    at(w.at - 900, () => { const c = chat(o.key); c.running = { ...c.running!, activity: "写回复" }; publish(); });
    at(w.at, () => {
      const c = chat(o.key);
      const m = message(c, "agent", w.answer);
      c.messages = [...c.messages, w.shot ? { ...m, attachments: [{ ...w.shot, owner: o.key }] } : m];
      addItem(c, posted(c, w.answer));
      publish();
      // Its answer back in the chat that asked, as a letter.
      const x = main();
      addItem(x, received(x, { id: o.key, name: `${o.title} · ${MACHINE[o.key]}`, via: "cloud", shown: { name: o.title, display: o.title, mine: false } } as Person, w.answer));
      x.running = { ...x.running!, activity: `${MACHINE[o.key]} 回来了` };
      publish();
    });
  }
  at(11300, () => { const x = main(); addItem(x, said(MAIN_THOUGHT)); x.running = { ...x.running!, activity: "等 3 台机器回来" }; publish(); });
  at(22400, () => { const x = main(); x.running = { ...x.running!, activity: "写回复" }; publish(); });
  at(23600, () => {
    const x = main();
    const options = [{ label: "合并", detail: "squash 合进 main，测试版自动发", recommended: true }];
    const m = message(x, "agent", MAIN_ANSWER);
    x.messages = [...x.messages, {
      ...m, attachments: [{ ...SHOTS.all!, owner: MAIN }], ending: "need_decision", options, asked: true,
      card: { type: "options", options, assignee: "you@acme.dev", assigneeText: "待你决定" }, decision: { resolved: false },
    }];
    addItem(x, posted(x, MAIN_ANSWER));
    publish();
  });
  at(24500, () => { const x = main(); addItem(x, marked("待你决定", "human")); x.running = null; x.blocked = true; publish(); });
  // 合并, tapped on the phone (its pane answered the card at once: main.tsx); everywhere the message from then.
  const ANSWERED_AT = TIMES.merge + 450;
  at(ANSWERED_AT, () => {
    const x = main();
    x.outbox = [];
    x.messages = x.messages.map((m) => (m.card && !m.decision?.resolved ? { ...m, asked: false, decision: { resolved: true, chosen: "合并", answeredBy: "你", text: "你 选了「合并」" } } : m));
    x.messages = [...x.messages, message(x, ME, "合并")];
    addItem(x, received(x, { id: "you", name: "你", via: "cloud", shown: { name: "你", display: "你", mine: true } } as Person, "合并"));
    x.blocked = false;
    x.running = { activity: "思考中", since: Date.now(), started: true };
    publish();
  });
  playCalls(at, main, [call(ANSWERED_AT + 700, 1300, "运行 gh pr merge", "Bash", "gh pr merge 2381 --squash", { command: "gh pr merge 2381 --squash" }, "✓ Squashed and merged pull request #2381")], publish);
  at(ANSWERED_AT + 2600, () => {
    const x = main();
    x.messages = [...x.messages, message(x, "agent", MERGED)];
    addItem(x, posted(x, MERGED));
    publish();
  });
  at(ANSWERED_AT + 3500, () => { const x = main(); addItem(x, marked("完成", "done")); x.running = null; publish(); });

  return { async play() {}, stop() {}, end() {} };
}
