// The agents' `login` tool (docs/remote-login.md, agent 的 login 工具): a command failed for want of a login (gh, gcloud,
// npm, docker…), and the station logs itself in, a person finishing it from their still.fail client in their own
// browser. What it answers never holds the page or the code: an agent has no use for them, and so never posts them to
// Slack or a chat. The person is reached by a login card (chat_post card {"type": "login", "login": <id>}) or the link.
import type { Logins, Login, Starter } from "../logins/index.ts";
import type { Tool } from "./mcp.ts";

type Json = any;

export const LOGIN = {
  name: "login",
  description:
    "Log this station in to a command-line tool when a command fails because it is not logged in (gh, gcloud, npm, docker, aws, az, vercel, wrangler, firebase, fly, hf, or any tool's own login command, e.g. gh auth refresh -s workflow). The login is machine-wide: every chat's agent on this station uses it. A person finishes it from their still.fail client in their own browser; you never see the page or the code. action status: how each known service stands (or one: service). start: begin a login for a service or a command (one under way for the service is given rather than another); answers its id, state and link. Then chat_post with card {\"type\": \"login\", \"login\": \"<id>\"}, a sentence saying who should log in to what on which station and why, and the link; end need_human. When it ends you get a station notice and the card closes. get: how one stands. cancel: end one. describe: add or change a service (service: {id, name, bin, status: {command, in: {exit?, match?}, account?}, login: {command, flow, enter?, code?, answers?}, logout?, signedOut?, env?}) so it is listed with its status next time.",
  inputSchema: {
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["status", "start", "get", "cancel", "describe"],
        "description": "What to do (status by default)."
      },
      "service": {
        "anyOf": [{ "type": "string" }, { "type": "object" }],
        "description": "status/start: a known service's id (gh, gcloud, gcloud-adc, npm, docker, aws, az, vercel, wrangler, firebase, fly, huggingface, or one described). describe: the service's description object."
      },
      "command": {
        "description": "start: a login command of its own instead of a service, as a line (gh auth refresh -s workflow) or words.",
        "anyOf": [{ "type": "string" }, { "type": "array", "items": { "type": "string" } }]
      },
      "id": {
        "type": "string",
        "description": "get/cancel: the login's id (start answers it)."
      },
      "station": {
        "type": "string",
        "description": "Another station of the workspace to log in (not yet: log in on this station, or ask a person to log in on that one from its station page)."
      }
    },
    "additionalProperties": false
  },
};

export type LoginToolDeps = {
  logins: () => Logins | undefined;
  /// Who a session's login is for: its chat's starter and workspace.
  starter: (session: string) => Starter;
  /// The link that opens a login in a person's client (null outside a workspace with pages).
  link: (session: string, id: string) => string | null;
};

/// A login as an agent is told of it: how it stands, no page or code.
function told(login: Login, link: string | null): Json {
  return {
    id: login.id,
    ...(login.service ? { service: login.service } : {}),
    name: login.name,
    command: login.command.join(" "),
    state: login.state,
    ...(login.step ? { step: login.step } : {}),
    ...(login.waiting ? { waiting: true } : {}),
    ...(login.account ? { account: login.account } : {}),
    ...(login.error ? { error: login.error.replace(/https?:\/\/\S+/g, "<link>") } : {}),
    ...(link ? { link } : {}),
  };
}

export function loginTools(deps: LoginToolDeps): Tool[] {
  return [
    {
      ...LOGIN,
      run: async (session: string, args: Record<string, unknown>) => {
        const logins = deps.logins();
        if (logins === undefined) throw new Error("the station is starting: try again in a moment");
        const action = typeof args.action === "string" && args.action !== "" ? args.action : "status";
        if (typeof args.station === "string" && args.station.trim() !== "")
          throw new Error("logging in another station is not there yet: start the login on this station, or ask a person to log in on that one from its station page in still.fail");
        switch (action) {
          case "status": {
            await logins.refresh();
            const services = logins.services().filter((s) => typeof args.service !== "string" || s.id === args.service);
            if (typeof args.service === "string" && services.length === 0) throw new Error(`no service ${args.service}: start a login with its command instead, or describe it`);
            return JSON.stringify(services.map((s) => ({ id: s.id, name: s.name, installed: s.installed, state: s.state, ...(s.account ? { account: s.account } : {}), ...(s.login ? { login: s.login } : {}) })), null, 2);
          }
          case "start": {
            const service = typeof args.service === "string" ? args.service : null;
            const command = typeof args.command === "string" || Array.isArray(args.command) ? (args.command as string | string[]) : null;
            if (service === null && command === null) throw new Error("start takes service (a known service's id) or command (the login command)");
            const login = await logins.start({ service, command }, deps.starter(session));
            const link = deps.link(session, login.id);
            return `${JSON.stringify(told(login, link), null, 2)}\n\nNow chat_post with card {"type": "login", "login": "${login.id}"} (and card.assignee: who should log in), a sentence saying who should log in to ${login.name} on this station and why${link ? `, and the link ${link}` : ""}; end need_human. In Slack, post the link alone. You get a station notice when it ends.`;
          }
          case "get":
          case "cancel": {
            if (typeof args.id !== "string" || args.id === "") throw new Error(`${action} takes id (start answers it)`);
            const login = action === "get" ? logins.get(args.id) : logins.cancel(args.id);
            if (login === null) throw new Error(`no login ${args.id} (one ended over ten minutes ago is gone)`);
            return JSON.stringify(told(login, deps.link(session, login.id)), null, 2);
          }
          case "describe": {
            const service = logins.describe(args.service);
            return `${JSON.stringify(service, null, 2)}\n\nKept: it is listed on this station's page with its status, and login start takes service "${service.id}".`;
          }
          default:
            throw new Error("action is one of status, start, get, cancel, describe");
        }
      },
    },
  ];
}

/// What a session that started a login is told when it ends.
export function endedNotice(login: Login, link: string | null): string {
  const which = `${login.name} (${login.command.join(" ")}; login ${login.id})`;
  const how =
    login.state === "done" ? `is done${login.account ? `: logged in as ${login.account}` : ""}. Carry on with what needed it`
    : login.state === "cancelled" ? "was cancelled. Ask whether it is still wanted before starting another"
    : `failed${login.error ? `: ${login.error.split("\n").slice(-3).join(" / ").replace(/https?:\/\/\S+/g, "<link>")}` : ""}. Start it again if it is still needed`;
  return `The login you started on this station, ${which}, ${how}.${login.state === "done" ? "" : link ? ` (Its link was ${link}.)` : ""} Its card was closed.`;
}
