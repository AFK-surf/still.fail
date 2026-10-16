// The agents' `login` tool (docs/remote-login.md, agent 的 login 工具): a command failed for want of a login, or a person
// asked for one, and the agent runs the tool's own login command on this station. The agent drives the command's
// terminal (用户定: CLI 的交互由 agent 操作): it reads the screen and answers its prompts (Y/n, menus, a host to pick) itself;
// a person does only the step that needs them, in their own browser (a code to enter, a page to sign in on), reached by a
// login card or the link. What the agent is told never holds the page's address or the code (each shown as <link>, <code>):
// it has no use for them, and so never posts them to Slack or a chat. Nothing types a secret: a prompt read without echo is
// refused.
import type { Logins, Login, Starter } from "../logins/index.ts";
import type { Screen } from "../logins/run.ts";
import type { Tool } from "./mcp.ts";


/// How long a call waits for the command to settle (go quiet: what it waits on is then known), at most.
const START_WAIT_MS = 15_000;
const INPUT_WAIT_MS = 5_000;
/// The keys the agent may send, as it names them, and as the terminal does.
const KEYS: Record<string, "Enter" | "Backspace" | "Up" | "Down" | "Left" | "Right" | "Tab" | "Ctrl-C"> = {
  enter: "Enter", backspace: "Backspace", up: "Up", down: "Down", left: "Left", right: "Right", tab: "Tab", "ctrl-c": "Ctrl-C",
};

export const LOGIN = {
  name: "login",
  description:
    "Log this station in to a command-line tool, when a command fails because it is not logged in (not logged in, 401, an expired token) or a person asks for it. command: the tool's own login command (gh auth login, gcloud auth login, npm login, az login --use-device-code, gh auth refresh -s workflow…), with its browser or device-code option where it has one. You drive the command: the answer shows its screen (the page and code hidden) and what it waits for; answer its prompts yourself with id and input (text) or key (enter, up, down, tab, ctrl-c…), taking the tool's defaults or what the task needs; if you truly cannot decide, ask the person in the chat as a normal question. Never type a password or token: a prompt that asks for one is refused; use the tool's browser or device-code login instead, or tell the person it cannot be done this way. Once the answer says the person's browser step is ready (a code or a page), chat_post with card {\"type\": \"login\", \"login\": \"<id>\"}, a sentence saying who should log in to what on this station and why, and the link; end need_human. Nobody is ever asked to run a command. The login is machine-wide: every chat's agent on this station uses it. When it ends you get a station notice and the card closes. id alone: how it stands now; id with cancel: true: end it.",
  inputSchema: {
    "type": "object",
    "properties": {
      "command": {
        "description": "Start: the tool's own login command, as a line (gh auth login) or words.",
        "anyOf": [{ "type": "string" }, { "type": "array", "items": { "type": "string" } }]
      },
      "id": {
        "type": "string",
        "description": "A login's id (start answers it): how it stands, its screen; with input, key or cancel, act on it."
      },
      "input": {
        "type": "string",
        "description": "With id: text typed at its prompt (a key, e.g. enter, follows only if given)."
      },
      "key": {
        "type": "string",
        "enum": ["enter", "up", "down", "left", "right", "tab", "backspace", "ctrl-c"],
        "description": "With id: a key pressed (after input, if both)."
      },
      "cancel": {
        "type": "boolean",
        "description": "With id: end that login."
      },
      "station": {
        "type": "string",
        "description": "Another station of the workspace to log in (not yet: log in on this station)."
      }
    },
    "additionalProperties": false
  },
};

export type LoginToolDeps = {
  logins: () => Logins | undefined;
  /// Who a session's login is for: its chat's starter and workspace, its chat and title.
  starter: (session: string) => Starter;
  /// The link that opens a login in a person's client (null outside a workspace with pages).
  link: (session: string, id: string) => string | null;
};

/// The screen as its agent reads it: the lines with something on them (the last 30), the page's address and the code
/// hidden, the line the cursor is on marked.
export function screenFor(screen: Screen | null, login: Login): string {
  if (screen === null) return "";
  const hide = (line: string) => {
    let out = line.replace(/https?:\/\/\S+/g, "<link>");
    if (login.code) out = out.split(login.code).join("<code>");
    return out.trimEnd();
  };
  const lines = screen.rows.map((row, y) => (y === screen.cursor.y && screen.live ? `${hide(row)}▏` : hide(row)));
  let end = lines.length;
  while (end > 0 && lines[end - 1]!.trim() === "") end--;
  const shown = lines.slice(0, end).filter((l, i, all) => l.trim() !== "" || (i > 0 && all[i - 1]!.trim() !== ""));
  return shown.slice(-30).join("\n");
}

/// What the agent is told of a login: how it stands, its screen, and what to do next.
function told(logins: Logins, login: Login, link: string | null): string {
  const state = {
    id: login.id,
    command: login.command.join(" "),
    state: login.state,
    ...(login.step ? { step: login.step } : {}),
    ...(login.waiting ? { waiting: true } : {}),
    ...(link ? { link } : {}),
  };
  const screen = screenFor(logins.screen(login.id), login);
  const active = login.endedAt === undefined;
  const next = !active
    ? login.state === "done" ? "It finished (its command exited 0)." : login.state === "cancelled" ? "It was cancelled." : `It failed${login.timedOut ? " (out of time)" : ""}.`
    : logins.screen(login.id)?.echo === false && login.waiting
      ? "It asks for a secret (read without echo): do not type it, nothing is sent to such a prompt. Cancel it, and use the tool's browser or device-code login, or tell the person it cannot be logged in this way."
      : login.waiting
        ? "It waits on the prompt above: answer it with login {id, input and/or key} (the tool's default, usually key enter, or what the task needs). If you truly cannot decide, ask the person in the chat."
        : login.step === "device" || login.step === "loopback" || login.step === "open"
          ? `The person's browser step is ready: chat_post with card {"type": "login", "login": "${login.id}"} (card.assignee: who should log in), a sentence saying who should log in to what on this station and why${link ? `, and the link ${link}` : ""}; end need_human. In Slack, post the link alone. You get a station notice when it ends.`
          : "It is still working: look again with login {id}.";
  return `${JSON.stringify(state, null, 2)}\n\nScreen:\n${screen === "" ? "(nothing yet)" : screen}\n\n${next}`;
}

export function loginTools(deps: LoginToolDeps): Tool[] {
  return [
    {
      ...LOGIN,
      run: async (session: string, args: Record<string, unknown>) => {
        const logins = deps.logins();
        if (logins === undefined) throw new Error("the station is starting: try again in a moment");
        if (typeof args.station === "string" && args.station.trim() !== "") throw new Error("logging in another station is not there yet: log in on this station");
        if (typeof args.id === "string" && args.id !== "") {
          const id = args.id;
          if (logins.get(id) === null) throw new Error(`no login ${id}`);
          if (args.cancel === true) logins.cancel(id);
          else if (typeof args.input === "string" || typeof args.key === "string") {
            const key = typeof args.key === "string" ? KEYS[args.key.toLowerCase()] : undefined;
            if (typeof args.key === "string" && key === undefined) throw new Error(`key: one of ${Object.keys(KEYS).join(", ")}`);
            const waits = logins.settle(id, INPUT_WAIT_MS);
            if (typeof args.input === "string" && args.input !== "") logins.input(id, { text: args.input });
            if (key !== undefined) logins.input(id, { key });
            await waits;
          }
          const login = logins.get(id)!;
          return told(logins, login, deps.link(session, id));
        }
        const command = typeof args.command === "string" || Array.isArray(args.command) ? (args.command as string | string[]) : null;
        if (command === null) throw new Error("command: the tool's own login command (e.g. gh auth login); or id to see or act on one");
        const started = await logins.start(command, deps.starter(session));
        const login = (await logins.settle(started.id, START_WAIT_MS)) ?? started;
        return told(logins, login, deps.link(session, login.id));
      },
    },
  ];
}

/// What a session that started a login, or posted its card, is told when it ends.
export function endedNotice(login: Login, link: string | null): string {
  const which = `${login.command.join(" ")} (login ${login.id})`;
  const how =
    login.state === "done" ? "finished (its command exited 0). Carry on with what needed it, and check it works"
    : login.state === "cancelled" ? "was cancelled. Ask whether it is still wanted before starting another"
    : `failed${login.error ? `: ${login.error.split("\n").slice(-3).join(" / ").replace(/https?:\/\/\S+/g, "<link>")}` : ""}. Start it again if it is still needed`;
  return `The login on this station you started or posted a card for, ${which}, ${how}.${login.state === "done" ? "" : link ? ` (Its link was ${link}.)` : ""} Its card was closed.`;
}

/// What its agent is told when, after its person's browser step, the command asks something again.
export function promptNotice(logins: Logins, login: Login, link: string | null): string {
  return `The login on this station you started, ${login.command.join(" ")} (login ${login.id}), asks something again:\n\n${told(logins, login, link)}`;
}

