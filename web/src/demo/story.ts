// What the demo plays, over and over: someone asks in a chat, its agent works through it step by step (the execution
// panel filling in as it goes) and answers; then on to another chat. Once the visitor takes over (clicks or types in
// the demo) it stops moving between chats, and what is under way finishes where it is.
import {
  addItem, CHEN, DEPS_KEY, groupOf, LIN, marked, message, posted, received, SAFARI_ASK, SAFARI_KEY, said, startingChats, step,
  type DemoChat, type Who,
} from "./fixtures.ts";
import type { HistoryStep } from "../core/shapes.ts";

export interface Stage {
  chats: DemoChat[];
  /** Tells the page what changed. */
  publish(): void;
  /** Opens a chat, unless the visitor has taken over. */
  open(key: string): void;
}


/** One tool call: shown running with `activity`, then with its result. */
interface Call {
  activity: string;
  step: HistoryStep;
  ms: number;
}
const call = (activity: string, name: string, hint: string, input: object, result: string, ms: number, failed = false): Call => ({
  activity, ms, step: step(name, hint, input, result, ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`, failed),
});

const FIRST = {
  calls: [
    call("搜索 (?<=", "Grep", "(?<=", { pattern: "\\(\\?<=", path: "src" }, "src/auth/validate.ts:14:  const EMAIL = /^[^@\\s]+(?<=@)[^@\\s]+\\.[a-z]{2,}$/i;", 40),
    call("读取 src/auth/validate.ts", "Read", "src/auth/validate.ts", { file_path: "src/auth/validate.ts" }, "export function isEmail(value: string) { … }", 10),
    call("编辑 src/auth/validate.ts", "Edit", "src/auth/validate.ts", { file_path: "src/auth/validate.ts", old_string: "(?<=@)", new_string: "@" }, "The file has been updated.", 10),
    call("运行 pnpm test auth", "Bash", "pnpm test auth", { command: "pnpm test auth" }, "FAIL  src/auth/validate.test.ts\n  ✕ accepts plus addressing\n\nTests: 1 failed, 11 passed, 12 total", 2100, true),
    call("编辑 src/auth/validate.ts", "Edit", "src/auth/validate.ts", { file_path: "src/auth/validate.ts", old_string: "[^@\\s]+@", new_string: "[^@\\s+]+(\\+[^@\\s]+)?@" }, "The file has been updated.", 10),
    call("运行 pnpm test auth", "Bash", "pnpm test auth", { command: "pnpm test auth" }, "PASS  src/auth/validate.test.ts\n\nTests: 12 passed, 12 total\nTime:  0.84 s", 1900),
  ],
  thought: "Safari 16.4 之前不支持后行断言，换成普通写法后行为一致，测试都过了。",
  answer: [
    "找到原因了：`src/auth/validate.ts` 校验邮箱的正则用了后行断言 `(?<=@)`，Safari 16.4 之前不支持，整个 bundle 解析失败，所以直接白屏。",
    "",
    "- 换成不用断言的写法，匹配结果不变",
    "- 补了 12 个用例，`pnpm test auth` 全部通过",
    "",
    "分支是 `fix/safari-login-regex`，可以的话我就合进 main。",
  ].join("\n"),
};
const FOLLOW_UP = "看过了没问题 👍 顺手在 browserslist 里把 Safari 15 也加上吧，免得以后再踩";
const SECOND = {
  calls: [
    call("读取 package.json", "Read", "package.json", { file_path: "package.json" }, "\"browserslist\": [\"defaults\"]", 10),
    call("编辑 package.json", "Edit", "package.json", { file_path: "package.json", old_string: "[\"defaults\"]", new_string: "[\"defaults\", \"safari >= 15\"]" }, "The file has been updated.", 10),
    call("运行 pnpm build", "Bash", "pnpm build", { command: "pnpm build" }, "✓ built in 6.42s", 2200),
    call("运行 git push", "Bash", "git push origin HEAD:main", { command: "git push origin HEAD:main" }, "a3f9c21..7c1e2d4  HEAD -> main", 900),
  ],
  thought: "build 通过，产物里没有后行断言了，合进 main。",
  answer: "加好了：`browserslist` 里加上 `safari >= 15`，`pnpm build` 通过。已合进 main（`7c1e2d4`）。",
};
/** Where the opening frame stands in the second turn: at its build. */
const OPENING_AT = 2;

/**
 * The chats as the demo opens (and as the site is built to HTML: the same frame): the Safari chat well under way —
 * asked, answered, asked again, its agent at the build of that second request. The story goes on from there.
 */
export function openingChats(): DemoChat[] {
  const chats = startingChats();
  const c = chats.find((x) => x.key === SAFARI_KEY)!;
  const said_ = (by: Who, text: string, minutes: number) => {
    c.messages = [...c.messages, message(c, by, text, Date.now() - minutes * 60_000)];
    if (typeof by === "object") addItem(c, received(c, by, text));
  };
  said_(LIN, SAFARI_ASK, 12);
  addItem(c, groupOf(FIRST.calls.map((x) => x.step), 0));
  addItem(c, said(FIRST.thought));
  c.messages = [...c.messages, message(c, "agent", FIRST.answer, Date.now() - 8 * 60_000)];
  addItem(c, posted(c, FIRST.answer));
  addItem(c, marked("完成"));
  said_(CHEN, FOLLOW_UP, 1);
  const { result: _, ...building } = SECOND.calls[OPENING_AT]!.step;
  addItem(c, groupOf([...SECOND.calls.slice(0, OPENING_AT).map((x) => x.step), building], 1));
  c.running = { activity: SECOND.calls[OPENING_AT]!.activity, since: Date.now() - 20_000 };
  return chats;
}

export function makeStory(stage: Stage) {
  let stopped = false;
  let ended = false;
  // Every step waits here: once the story is ended, what it was in the middle of goes no further.
  const wait = (ms: number) => new Promise<void>((resolve, reject) => setTimeout(() => (ended ? reject(new Error("ended")) : resolve()), ms));
  const chat = (key: string) => stage.chats.find((c) => c.key === key)!;

  function say(key: string, by: Who, text: string) {
    const c = chat(key);
    c.messages = [...c.messages, message(c, by, text)];
    if (typeof by === "object") addItem(c, received(c, by, text));
    stage.publish();
  }

  /**
   * The agent's turn: its calls one by one, then a line of its own, then its answer in the chat. `resume`: a turn
   * already under way (the opening frame), from its call `from` on.
   */
  async function turn(key: string, calls: Call[], thought: string, answer: string, resume?: { from: number }) {
    const c = chat(key);
    c.blocked = false;
    const done: HistoryStep[] = resume ? calls.slice(0, resume.from).map((x) => x.step) : [];
    const at = resume ? c.items.length - 1 : c.items.length;
    if (!resume) {
      c.running = { activity: "思考中", since: Date.now() };
      stage.publish();
      await wait(1100);
    }
    for (const next of calls.slice(resume?.from ?? 0)) {
      c.running = { ...c.running!, activity: next.activity };
      const { result: _, ...pending } = next.step;
      const body = groupOf([...done, pending], 1);
      if (c.items.length === at) addItem(c, body);
      else c.items = c.items.map((item, i) => (i === at ? { ...item, body } : item));
      stage.publish();
      await wait(next.ms < 400 ? 700 : Math.min(next.ms, 2200));
      done.push(next.step);
      c.items = c.items.map((item, i) => (i === at ? { ...item, body: groupOf(done, 0) } : item));
      stage.publish();
      await wait(250);
    }
    c.running = { ...c.running!, activity: "写回复" };
    addItem(c, said(thought));
    stage.publish();
    await wait(1200);
    // Its answer arrives while its turn still runs (it posts, then ends the turn), as a station's does: the chat shows
    // its activity becoming the message.
    c.messages = [...c.messages, message(c, "agent", answer)];
    addItem(c, posted(c, answer));
    stage.publish();
    await wait(900);
    addItem(c, marked("完成"));
    c.running = null;
    stage.publish();
  }

  async function safari() {
    stage.open(SAFARI_KEY);
    await wait(1500);
    say(SAFARI_KEY, LIN, SAFARI_ASK);
    await wait(900);
    await turn(SAFARI_KEY, FIRST.calls, FIRST.thought, FIRST.answer);
    await wait(2600);
    say(SAFARI_KEY, CHEN, FOLLOW_UP);
    await wait(700);
    await turn(SAFARI_KEY, SECOND.calls, SECOND.thought, SECOND.answer);
  }

  async function deps() {
    await wait(2500);
    stage.open(DEPS_KEY);
    await wait(2200);
    say(DEPS_KEY, CHEN, "一起升吧，路由文件你直接改");
    await wait(700);
    await turn(DEPS_KEY, [
      call("运行 pnpm up react-router@8", "Bash", "pnpm up react-router@8", { command: "pnpm up react-router@8" }, "+ react-router 8.0.2", 1600),
      call("运行 codemod", "Bash", "npx @react-router/codemod v8 src/routes", { command: "npx @react-router/codemod v8 src/routes" }, "14 files changed", 1800),
      call("运行 pnpm test", "Bash", "pnpm test", { command: "pnpm test" }, "Tests: 312 passed, 312 total", 2200),
    ], "codemod 改完 14 个路由文件，全部测试通过。", "React Router 8 也升好了：codemod 改了 14 个路由文件，312 个测试全过。PR 在 `chore/deps-2026-w40`。");
  }

  return {
    async play() {
      try {
        // First where the opening frame left off (openingChats): the second turn, at its build.
        await wait(1200);
        await turn(SAFARI_KEY, SECOND.calls, SECOND.thought, SECOND.answer, { from: OPENING_AT });
        await deps();
        await wait(4000);
        if (stopped) return;
        stage.chats.splice(0, stage.chats.length, ...startingChats());
        stage.publish();
        while (!stopped) {
          await safari();
          await deps();
          await wait(4000);
          if (stopped) return;
          stage.chats.splice(0, stage.chats.length, ...startingChats());
          stage.publish();
        }
      } catch {
        // ended
      }
    },
    /** The visitor took over: this round is the last. */
    stop() {
      stopped = true;
    },
    /** The visitor sent a message: the story ends where it is; no agent of it is at work any more but the one in `except` (the visitor's chat), which takes the message into its turn. */
    end(except?: string) {
      stopped = true;
      ended = true;
      for (const c of stage.chats) {
        if (c.key !== except) c.running = null;
        // A step it was in the middle of stops there: its group no longer says one runs.
        c.items = c.items.map((item) => (item.body.kind === "group" && item.body.content.pending ? { ...item, body: { ...item.body, content: { ...item.body.content, pending: 0 } } } : item));
      }
      stage.publish();
    },
  };
}
