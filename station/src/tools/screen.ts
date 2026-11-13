// screen ("Asking a person to take over"): the screens of this station a person can see and
// drive from their still.fail app, who is on each now, and the link that opens one, for the agent to post when a
// person has to do something there (log in, solve a captcha).
import { tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { type ScreenHub, ScreenRefused, type ViewShown, viewOn } from "../screens/hub.ts";
import type { Tool } from "./mcp.ts";

export const SCREEN = {
  name: "screen",
  description:
    "The screens of this station a person can see and drive from their still.fail app (this machine's display; tabs of the station's browser; the iOS Simulators booted on this Mac), each with who is viewing or controlling it now and the link that opens it there. When a person has to act on one (log in, solve a captcha, approve a prompt), post its link on a line of its own (people see the screen's card) with chat_post kind=need_human and end your turn; call this again to see whether someone is on it. To see and operate one yourself, use the computer tool with its id.",
  inputSchema: {
    "type": "object",
    "properties": {
      "id": { "type": "string", "description": "One screen's id (desktop, browser:<targetId>, simulator:<udid>); default: all of them" },
      "action": { "type": "string", "enum": ["list", "take_control", "disconnect", "watch_only", "disconnect_all"], "description": "list (default). The others act on people's views of the screen `id`, and only when a person asked for it in this chat (\"you take control\"): never by your own choice to get past being refused input. take_control makes every person's view only look, its picture going on, so your input by coordinates goes through; they take it back with one tap. disconnect and watch_only act on one `view`; disconnect_all ends every person's view." },
      "view": { "type": "string", "description": "A view's id, from `on` in the list." }
    },
    "additionalProperties": false
  },
};

/// What the agent is told: the screens (one, with `id`), and how to hand one to a person. `base`: this station's place
/// in its control plane's pages (`<cloud>/w/<workspace>/s/<station>`), none when it has no pages.
export function described(hub: ScreenHub, base: string | null, id?: string): string {
  const all = hub.listed("en").screens.filter((s) => !s.userTab);
  const shown = id === undefined ? all : all.filter((s) => s.id === id);
  if (id !== undefined && shown.length === 0) {
    if (hub.get(id)?.userTab) throw new Error(tr("en", "station.screen.userOnly"));
    throw new Error(`no screen ${id} on this station (it has: ${all.map((s) => s.id).join(", ") || "none"})`);
  }
  const screens = shown.map(({ access, views, ...s }: any) => ({
    ...s,
    on: (views as ViewShown[]).map((v) => ({ view: v.id, who: v.name, ...(v.agent ? {} : { where: viewOn(v) }), controlling: v.control })),
    link: base === null ? null : `${base}/screen/${encodeURIComponent(String(s.id))}`,
    ...(access ? { cannot: access.message } : {}),
  }));
  if (screens.length === 0) return "This station has no screen a person can open now.";
  let text = `${JSON.stringify(screens, null, 2)}\n\n`;
  text +=
    base === null
      ? "This station's control plane has no pages, so there is no link to give: a person opens its screens from the still.fail app."
      : "To have a person act on a screen, post its link on a line of its own in the conversation (chat_post kind=need_human, saying what to do there; the link alone shows as the screen's card) and end your turn; it opens the screen in their still.fail app. viewers: who has it open now; controlledBy: those of them driving it; on: each of their views and the device it is on. A view you are held off by is let go of on that device, or disconnected or made watch-only under Screens on the station's page; or by you with action take_control, disconnect or watch_only, when a person asks you to in the chat.";
  return text;
}

/// A person's request carried out: `action` of the views of `id`, `by` the agent (as they are told who ended their view).
export function letGo(hub: ScreenHub, by: string, id: unknown, action: string, view: unknown): string {
  if (typeof id !== "string" || id === "") throw new Error(`${action} needs id, the screen`);
  if (hub.get(id)?.userTab) throw new Error(tr("en", "station.screen.userOnly"));
  const one = () => {
    if (typeof view !== "string" || view === "") throw new Error(`${action} needs view, a view's id from the list`);
    return view;
  };
  try {
    switch (action) {
      case "take_control":
        return `${hub.takeControl(id, by)} people's views of ${id} now only look; your input goes through until one of them takes it back. Tell them when you are done.`;
      case "disconnect":
        hub.endView(id, one(), by);
        return `View ${view} of ${id} disconnected; it is not opened again by itself.`;
      case "watch_only":
        hub.watchOnly(id, one());
        return `View ${view} of ${id} now only looks.`;
      case "disconnect_all":
        return `${hub.endViews(id, by)} people's views of ${id} disconnected.`;
      default:
        throw new Error(`no action ${action}: list, take_control, disconnect, watch_only or disconnect_all`);
    }
  } catch (e) {
    throw e instanceof ScreenRefused ? new Error(tr("en", e.key, e.args)) : e;
  }
}

/// `base`: as `described` takes it. `name`: a session's name among a screen's people ("agent: <its chat's title>").
export function screenTools(hub: ScreenHub, base: () => string | null, name: (session: string) => string = (session) => session): Tool[] {
  return [
    {
      ...SCREEN,
      run: async (session, args) => {
        if (typeof args.action === "string" && args.action !== "" && args.action !== "list") {
          const said = letGo(hub, name(session), args.id, args.action, args.view);
          log.info("screens", "an agent let go of a view", { session, screen: String(args.id), action: args.action, view: String(args.view ?? "") });
          return said;
        }
        // The desktop as it is now (its size; on macOS its grants).
        await hub.refresh();
        return described(hub, base(), typeof args.id === "string" && args.id !== "" ? args.id : undefined);
      },
    },
  ];
}
