// browser: the station's own Chrome (src/browser/), for the agents to drive over its DevTools with their own client
// (chrome-devtools-mcp, Playwright). Its profile keeps sign-ins, shared by every session on the station; a person can
// see and drive its tabs from their app (the `screen` tool gives the link), which is how an agent asks for a sign-in
// or a captcha. Each session is given its own address of it (browser/proxy.ts), so the tabs it opens are known as its
// chat's: people see which chat opened a tab, and they close with it.
import type { BrowserStatus, StationBrowser } from "./browser.ts";
import { sessionPath } from "./proxy.ts";
import type { TabInfo } from "./tabs.ts";
import type { Tool } from "../tools/mcp.ts";

export const BROWSER = {
  name: "browser",
  description:
    "The station's own browser: a real Google Chrome with a persistent profile, so sign-ins made in it stay (shared by every session on this station). action endpoint (default) starts it if needed and gives this chat's DevTools endpoint and how to connect (chrome-devtools-mcp --wsEndpoint, Playwright connectOverCDP); tabs opened through it are this chat's (people see which chat opened a tab, may close it, and it closes when the chat is archived); tabs lists its tabs; status says whether it runs; stop closes it (every session's tabs). Use it for web work that needs a login or should look like a person's browser; when a page needs a person (sign-in, captcha, 2FA), give them the tab with the `screen` tool.",
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
    `The station's browser runs (${s.binary || "Chrome"}${s.headless ? ", headless" : ""}).`,
    `DevTools for this chat: ${at}`,
    "",
    ws !== null
      ? "Connect with your own client at this address, not at Chrome's own port: the tabs you open through it are known as this chat's (people see which chat opened a tab and may close it) and close when this chat is archived."
      : "Connect with your own client:",
    ws !== null
      ? `- chrome-devtools-mcp: \`npx -y chrome-devtools-mcp@latest --wsEndpoint ${ws}\``
      : `- chrome-devtools-mcp: \`npx -y chrome-devtools-mcp@latest --browserUrl ${s.http}\``,
    `- Playwright: \`const browser = await chromium.connectOverCDP("${at}"); const page = await browser.contexts()[0].newPage();\` — the default context holds the sign-ins; a new context has none.`,
    "",
    "It is shared: open a tab of your own and close it when done; leave other tabs (other sessions', people's) alone, and do not close the browser.",
    "Never launch another Chrome for work that needs a login: this one keeps them.",
    "When a page needs a person (sign-in, captcha, 2FA, a consent), give them that tab with the `screen` tool (a link to see and drive it from their app), ask in the chat (need_human), and end your turn; carry on when they say it is done.",
    ws !== null
      ? "If the connection drops (the browser was restarted or closed after a long idle, the station restarted), connect again to the same address: it starts the browser if needed."
      : "If the connection drops (the browser was restarted or closed after a long idle), call browser again: the address usually stays the same.",
  ].join("\n");
}

const tabsText = (tabs: TabInfo[], session: string): string =>
  tabs.length === 0 ? "No tabs open (or the browser is not running)." : tabs.map((t) => `- ${t.id} ${t.title ? `${JSON.stringify(t.title)} ` : ""}${t.url}${t.session === session ? " (this chat's)" : t.session ? " (another chat's)" : ""}${t.attached ? " (a client is attached)" : ""}`).join("\n");

/// `doorUrl`: the agents' door's MCP URL once it is open (parts.ts `doorUrl`), where each session is given its address.
export function browserTools(browser: StationBrowser, doorUrl: () => string | null = () => null): Tool[] {
  return [
    {
      ...BROWSER,
      async run(session, args) {
        const action = typeof args.action === "string" ? args.action : "endpoint";
        switch (action) {
          case "endpoint":
            return howTo(await browser.endpoint(), sessionWs(doorUrl(), session));
          case "tabs":
            return tabsText(browser.tabs(), session);
          case "status": {
            const s = browser.status();
            return s.running
              ? `Running: ${sessionWs(doorUrl(), session) ?? s.http}, ${s.tabs} tab(s), ${s.viewing} view(s) by people${s.headless ? ", headless" : ""}.`
              : "Not running: `browser` (action endpoint) starts it.";
          }
          case "stop":
            await browser.stop();
            return "The station's browser is closed (its profile and sign-ins stay).";
          default:
            throw new Error(`unknown action ${action}: endpoint, tabs, status or stop`);
        }
      },
    },
  ];
}
