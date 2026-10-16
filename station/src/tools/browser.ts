// browser: the station's own Chrome (src/browser/), for the agents to drive over its DevTools with their own client
// (chrome-devtools-mcp, Playwright). Its profile keeps sign-ins, shared by every session on the station; a person can
// see and drive its tabs from their app (the `screen` tool gives the link), which is how an agent asks for a sign-in
// or a captcha.
import type { BrowserStatus, StationBrowser } from "../browser/browser.ts";
import type { TabInfo } from "../browser/tabs.ts";
import type { Tool } from "./mcp.ts";

export const BROWSER = {
  name: "browser",
  description:
    "The station's own browser: a real Google Chrome with a persistent profile, so sign-ins made in it stay (shared by every session on this station). action endpoint (default) starts it if needed and gives its DevTools endpoint and how to connect (chrome-devtools-mcp --browserUrl, Playwright connectOverCDP); tabs lists its tabs; status says whether it runs; stop closes it (every session's tabs). Use it for web work that needs a login or should look like a person's browser; when a page needs a person (sign-in, captcha, 2FA), give them the tab with the `screen` tool.",
  inputSchema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ["endpoint", "tabs", "status", "stop"], description: "endpoint (default), tabs, status or stop" },
    },
    additionalProperties: false,
  },
};

/// What `endpoint` tells the agent: where, how to connect, and how to share it.
export function howTo(s: BrowserStatus): string {
  return [
    `The station's browser runs (${s.binary || "Chrome"}${s.headless ? ", headless" : ""}).`,
    `DevTools: ${s.http} (WebSocket ${s.ws})`,
    "",
    "Connect with your own client:",
    `- chrome-devtools-mcp: \`npx -y chrome-devtools-mcp@latest --browserUrl ${s.http}\` (or \`--wsEndpoint ${s.ws}\`)`,
    `- Playwright: \`const browser = await chromium.connectOverCDP("${s.http}"); const page = await browser.contexts()[0].newPage();\` — the default context holds the sign-ins; a new context has none.`,
    "",
    "It is shared: open a tab of your own and close it when done; leave other tabs (other sessions', people's) alone, and do not close the browser.",
    "Never launch another Chrome for work that needs a login: this one keeps them.",
    "When a page needs a person (sign-in, captcha, 2FA, a consent), give them that tab with the `screen` tool (a link to see and drive it from their app), ask in the chat (need_human), and end your turn; carry on when they say it is done.",
    "If the connection drops (the browser was restarted or closed after a long idle), call browser again: the address usually stays the same.",
  ].join("\n");
}

const tabsText = (tabs: TabInfo[]): string =>
  tabs.length === 0 ? "No tabs open (or the browser is not running)." : tabs.map((t) => `- ${t.id} ${t.title ? `${JSON.stringify(t.title)} ` : ""}${t.url}${t.attached ? " (a client is attached)" : ""}`).join("\n");

export function browserTools(browser: StationBrowser): Tool[] {
  return [
    {
      ...BROWSER,
      async run(_session, args) {
        const action = typeof args.action === "string" ? args.action : "endpoint";
        switch (action) {
          case "endpoint":
            return howTo(await browser.endpoint());
          case "tabs":
            return tabsText(browser.tabs());
          case "status": {
            const s = browser.status();
            return s.running
              ? `Running: ${s.http} (WebSocket ${s.ws}), ${s.tabs} tab(s), ${s.viewing} view(s) by people${s.headless ? ", headless" : ""}.`
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
