// browser: the chat's own Chrome (src/browser/browsers.ts), for its agent to drive over its DevTools with its own
// client (chrome-devtools-mcp, Playwright). Its profile keeps the sign-ins made in it, this chat's alone: no other
// chat's agent reaches them, and they go when the chat is archived. A person can see and drive its tabs from their app
// (the `screen` tool gives the link), which is how an agent asks for a sign-in or a captcha. The session reaches it at
// its own address on the door (browser/proxy.ts).
import type { BrowserStatus } from "./browser.ts";
import { sessionPath } from "./proxy.ts";
import type { TabInfo } from "./tabs.ts";
import type { Tool } from "../tools/mcp.ts";

export const BROWSER = {
  name: "browser",
  description:
    "This chat's own browser: a real Google Chrome with a profile of this chat's, so sign-ins made in it stay for this chat (no other chat sees them; they go when the chat is archived). action endpoint (default) starts it if needed and gives its DevTools endpoint and how to connect (chrome-devtools-mcp --wsEndpoint, Playwright connectOverCDP); tabs lists its tabs; status says whether it runs; stop closes it (its sign-ins stay). Use it for web work that needs a login or should look like a person's browser; when a page needs a person (sign-in, captcha, 2FA), give them the tab with the `screen` tool.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["endpoint", "tabs", "status", "stop"], description: "endpoint (default), tabs, status or stop" },
    },
    additionalProperties: false,
  },
};

/// This session's address of the browser (browser/proxy.ts), from the door's MCP URL; null without one (Chrome's own).
export function sessionWs(doorUrl: string | null, session: string): string | null {
  return doorUrl === null ? null : `${doorUrl.replace(/^http:/, "ws:").replace(/\/mcp$/, "")}${sessionPath(session)}`;
}

/// What `endpoint` tells the agent: where (`ws`, this session's address), how to connect, and how to share it.
export function howTo(s: BrowserStatus, ws: string | null): string {
  const at = ws ?? s.http;
  return [
    `This chat's browser runs (${s.binary || "Chrome"}${s.headless ? ", headless" : ""}).`,
    `DevTools for this chat: ${at}`,
    "",
    "Connect with your own client at this address:",
    ws !== null
      ? `- chrome-devtools-mcp: \`npx -y chrome-devtools-mcp@latest --wsEndpoint ${ws}\``
      : `- chrome-devtools-mcp: \`npx -y chrome-devtools-mcp@latest --browserUrl ${s.http}\``,
    `- Playwright: \`const browser = await chromium.connectOverCDP("${at}"); const page = await browser.contexts()[0].newPage();\` — the default context holds the sign-ins; a new context has none.`,
    "",
    "It is this chat's alone: its sign-ins are the ones made in it (none of another chat's). Close the tabs you are done with.",
    "Never launch another Chrome for work that needs a login: this one keeps them.",
    "When a page needs a person (sign-in, captcha, 2FA, a consent), give them that tab with the `screen` tool (a link to see and drive it from their app), ask in the chat (need_human), and end your turn; carry on when they say it is done.",
    ws !== null
      ? "If the connection drops (the browser was restarted or closed after a long idle, the station restarted), connect again to the same address: it starts the browser if needed."
      : "If the connection drops (the browser was restarted or closed after a long idle), call browser again: the address usually stays the same.",
  ].join("\n");
}

const tabsText = (tabs: TabInfo[]): string =>
  tabs.length === 0 ? "No tabs open (or the browser is not running)." : tabs.map((t) => `- ${t.id} ${t.title ? `${JSON.stringify(t.title)} ` : ""}${t.url}${t.attached ? " (a client is attached)" : ""}`).join("\n");

/// What the tool asks of the browsers (browsers.ts Browsers): each session's chat's.
export type ToolBrowsers = {
  endpoint(session: string): Promise<BrowserStatus>;
  tabs(session: string): TabInfo[];
  status(session: string): BrowserStatus;
  stop(session: string): Promise<void>;
};

/// `doorUrl`: the agents' door's MCP URL once it is open (parts.ts `doorUrl`), where each session is given its address.
export function browserTools(browser: ToolBrowsers, doorUrl: () => string | null = () => null): Tool[] {
  return [
    {
      ...BROWSER,
      async run(session, args) {
        const action = typeof args.action === "string" ? args.action : "endpoint";
        switch (action) {
          case "endpoint":
            return howTo(await browser.endpoint(session), sessionWs(doorUrl(), session));
          case "tabs":
            return tabsText(browser.tabs(session));
          case "status": {
            const s = browser.status(session);
            return s.running
              ? `Running: ${sessionWs(doorUrl(), session) ?? s.http}, ${s.tabs} tab(s), ${s.viewing} view(s) by people${s.headless ? ", headless" : ""}.`
              : "Not running: `browser` (action endpoint) starts it.";
          }
          case "stop":
            await browser.stop(session);
            return "This chat's browser is closed (its profile and sign-ins stay).";
          default:
            throw new Error(`unknown action ${action}: endpoint, tabs, status or stop`);
        }
      },
    },
  ];
}
