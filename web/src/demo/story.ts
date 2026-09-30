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

// The main chat: a request that says nothing ("that thing, do that to it"), the agent working out what was meant and
// doing it, "still no good", and then "what the hell did you do": still.fail and youdid.wtf, played out.
const FIRST = {
  calls: [
    call("查看最近的讨论", "Bash", "git log --since=yesterday", { command: "git log --since=yesterday --oneline" }, "9d2e1f0 登录页：按钮样式调整\n41c7a2b 登录页：手机上的布局", 300),
    call("搜索 登录 按钮", "Grep", "LoginButton", { pattern: "LoginButton", path: "src" }, "src/auth/LoginForm.tsx:38:  <LoginButton width={320} />", 40),
    call("读取 src/auth/LoginForm.tsx", "Read", "src/auth/LoginForm.tsx", { file_path: "src/auth/LoginForm.tsx" }, "export function LoginForm() { … }", 10),
    call("编辑 src/auth/LoginForm.tsx", "Edit", "src/auth/LoginForm.tsx", { file_path: "src/auth/LoginForm.tsx", old_string: "width={320}", new_string: "block" }, "The file has been updated.", 10),
    call("截图 登录页 375px", "Bash", "pnpm shot /login --width 375", { command: "pnpm shot /login --width 375" }, "saved shots/login-375.png", 1600),
  ],
  thought: "昨天的提交都在动登录页，手机上按钮是写死的 320px 宽，最可能说的是这个。",
  answer: [
    "我猜你说的是登录页那个按钮：手机上它是写死的 320px，超出屏幕了。",
    "",
    "- 改成撑满容器，375px 宽下截图看过了，不再超出",
    "- 分支 `fix/login-button`",
    "",
    "如果你说的「那个」不是这个，告诉我是哪个页面就行。",
  ].join("\n"),
};
const FOLLOW_UP = "还是不行";
const SECOND = {
  calls: [
    call("截图 登录页 375px", "Bash", "pnpm shot /login --width 375", { command: "pnpm shot /login --width 375" }, "saved shots/login-375.png", 1500),
    call("读取 src/auth/login.css", "Read", "src/auth/login.css", { file_path: "src/auth/login.css" }, ".form { padding: 0 24px 0 8px; }", 10),
    call("编辑 src/auth/login.css", "Edit", "src/auth/login.css", { file_path: "src/auth/login.css", old_string: "padding: 0 24px 0 8px", new_string: "padding: 0 16px" }, "The file has been updated.", 10),
    call("运行 pnpm test login", "Bash", "pnpm test login", { command: "pnpm test login" }, "Tests: 18 passed, 18 total", 1900),
  ],
  thought: "按钮不超出了，但整个表单左右留白不对称，看着还是歪的。",
  answer: "再看了一遍 375px 的截图：表单左右留白是 8px 和 24px，所以按钮看着还是歪的。改成左右各 16px，现在居中了，测试都过了。",
};
const WTF = "你干的什么 JB？？我说的是深色模式！按钮都看不见了！";
const THIRD = {
  calls: [
    call("截图 登录页 深色", "Bash", "pnpm shot /login --theme dark", { command: "pnpm shot /login --theme dark" }, "saved shots/login-dark.png", 1500),
    call("搜索 #111", "Grep", "#111", { pattern: "#111", path: "src/auth" }, "src/auth/login.css:22:  .submit { color: #111; background: #111; }", 40),
    call("编辑 src/auth/login.css", "Edit", "src/auth/login.css", { file_path: "src/auth/login.css", old_string: "color: #111; background: #111;", new_string: "color: var(--on-primary); background: var(--primary);" }, "The file has been updated.", 10),
    call("截图 浅色 / 深色", "Bash", "pnpm shot /login --theme light,dark", { command: "pnpm shot /login --theme light,dark" }, "saved shots/login-light.png, shots/login-dark.png", 1700),
  ],
  thought: "深色模式下按钮的字和底色都写死成 #111，所以整个按钮看不见。",
  answer: "明白了，是深色模式：登录按钮的文字和背景都写死成 `#111`，深色下整个按钮都看不见。改成跟着主题走的颜色，浅色、深色都截图核对过了，两张图在 PR 里。之前那两处改动也保留着，一起在 `fix/login-button`。",
};
/** Where the opening frame stands in the second turn: at its tests. */
const OPENING_AT = 3;

/**
 * The chats as the demo opens (and as the site is built to HTML: the same frame): the main chat well under way —
 * asked, answered, "still no good", its agent at the tests of its second go. The story goes on from there.
 */
export function openingChats(): DemoChat[] {
  const chats = startingChats();
  const c = chats.find((x) => x.key === SAFARI_KEY)!;
  const said_ = (by: Who, text: string, minutes: number) => {
    c.messages = [...c.messages, message(c, by, text, Date.now() - minutes * 60_000)];
    if (typeof by === "object") addItem(c, received(c, by, text));
  };
  said_(LIN, SAFARI_ASK, 9);
  addItem(c, groupOf(FIRST.calls.map((x) => x.step), 0));
  addItem(c, said(FIRST.thought));
  c.messages = [...c.messages, message(c, "agent", FIRST.answer, Date.now() - 6 * 60_000)];
  addItem(c, posted(c, FIRST.answer));
  addItem(c, marked("完成"));
  said_(LIN, FOLLOW_UP, 1);
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
      c.running = { activity: "思考中", since: Date.now(), started: true };
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
    say(SAFARI_KEY, LIN, FOLLOW_UP);
    await wait(700);
    await turn(SAFARI_KEY, SECOND.calls, SECOND.thought, SECOND.answer);
    await wtf();
  }

  async function wtf() {
    await wait(2200);
    say(SAFARI_KEY, LIN, WTF);
    await wait(700);
    await turn(SAFARI_KEY, THIRD.calls, THIRD.thought, THIRD.answer);
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
        // First where the opening frame left off (openingChats): the second turn, at its tests.
        await wait(1200);
        await turn(SAFARI_KEY, SECOND.calls, SECOND.thought, SECOND.answer, { from: OPENING_AT });
        await wtf();
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
