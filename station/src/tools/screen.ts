// screen (docs/remote-screens.md, "Asking a person to take over"): the screens of this station a person can see and
// drive from their still.fail app, who is on each now, and the link that opens one, for the agent to post when a
// person has to do something there (log in, solve a captcha).
import type { ScreenHub } from "../screens/hub.ts";
import type { Tool } from "./mcp.ts";

export const SCREEN = {
  name: "screen",
  description:
    "The screens of this station a person can see and drive from their still.fail app (this machine's display; tabs of the station's browser), each with who is viewing or controlling it now and the link that opens it there. When a person has to act on one (log in, solve a captcha, approve a prompt), post its link on a line of its own (people see the screen's card) with chat_post kind=need_human and end your turn; call this again to see whether someone is on it. To see and operate one yourself, use the computer tool with its id.",
  inputSchema: {
    "type": "object",
    "properties": {
      "id": { "type": "string", "description": "One screen's id (desktop, browser:<targetId>); default: all of them" }
    },
    "additionalProperties": false
  },
};

/// What the agent is told: the screens (one, with `id`), and how to hand one to a person. `base`: this station's place
/// in its control plane's pages (`<cloud>/w/<workspace>/s/<station>`), none when it has no pages.
export function described(hub: ScreenHub, base: string | null, id?: string): string {
  const all = hub.listed("en").screens;
  const shown = id === undefined ? all : all.filter((s) => s.id === id);
  if (id !== undefined && shown.length === 0) throw new Error(`no screen ${id} on this station (it has: ${all.map((s) => s.id).join(", ") || "none"})`);
  const screens = shown.map(({ access, ...s }: any) => ({
    ...s,
    link: base === null ? null : `${base}/screen/${encodeURIComponent(String(s.id))}`,
    ...(access ? { cannot: access.message } : {}),
  }));
  if (screens.length === 0) return "This station has no screen a person can open now.";
  let text = `${JSON.stringify(screens, null, 2)}\n\n`;
  text +=
    base === null
      ? "This station's control plane has no pages, so there is no link to give: a person opens its screens from the still.fail app."
      : "To have a person act on a screen, post its link on a line of its own in the conversation (chat_post kind=need_human, saying what to do there; the link alone shows as the screen's card) and end your turn; it opens the screen in their still.fail app. viewers: who has it open now; controlledBy: those of them driving it.";
  return text;
}

/// `base`: as `described` takes it.
export function screenTools(hub: ScreenHub, base: () => string | null): Tool[] {
  return [
    {
      ...SCREEN,
      run: async (_session, args) => {
        // The desktop's grants as macOS has them now.
        await hub.refresh();
        return described(hub, base(), typeof args.id === "string" && args.id !== "" ? args.id : undefined);
      },
    },
  ];
}
